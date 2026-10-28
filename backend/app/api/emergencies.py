import uuid
from datetime import datetime

from fastapi import APIRouter, Body, Depends, HTTPException, Query, status
from sqlalchemy import select

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.ambulance import Ambulance
from app.models.emergency import Emergency, EmergencyEvent
from app.models.hospital import Hospital
from app.models.hospital_availability_request import HospitalAvailabilityRequest
from app.models.patient import Patient
from app.schemas.emergency import (
    AssignHospitalRequest,
    EmergencyCreate,
    EmergencyResponse,
    HospitalArrivalNotificationRequest,
    LocationUpdate,
    PoliceNotificationRequest,
    StatusUpdateRequest,
)
from app.services.events import record_event
from app.services.hospital_selection import find_candidates, get_emergency_condition, normalize_condition
from app.services.rough_road import get_rough_road_points
from app.services.routing import get_routing_provider, route_points

router = APIRouter(prefix="/emergencies", tags=["Emergencies"])

VALID_STATUSES = {
    "CREATED", "DISPATCHED", "EN_ROUTE", "HOSPITAL_ASSIGNED", "HOSPITAL_ALERTED",
    "ARRIVED", "COMPLETED", "CANCELLED",
}


def _get_owned_emergency(db, emergency_id, current_user):
    emergency = db.get(Emergency, emergency_id)
    if not emergency:
        raise HTTPException(status_code=404, detail="Emergency not found")
    if emergency.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Emergency access denied")
    return emergency


def _get_live_origin(db, emergency):
    latitude = emergency.pickup_latitude
    longitude = emergency.pickup_longitude
    if emergency.ambulance_id:
        ambulance = db.get(Ambulance, emergency.ambulance_id)
        if ambulance and ambulance.current_latitude is not None and ambulance.current_longitude is not None:
            latitude = ambulance.current_latitude
            longitude = ambulance.current_longitude
    return latitude, longitude


def _assign_hospital_record(db, emergency, hospital, event_type="HOSPITAL_ASSIGNED", payload=None):
    emergency.hospital_id = hospital.id
    emergency.status = "HOSPITAL_ASSIGNED"
    emergency.destination_latitude = hospital.latitude
    emergency.destination_longitude = hospital.longitude
    record_event(db, emergency.id, event_type, payload or {"hospital_id": str(hospital.id), "hospital_name": hospital.name})


def _latest_event(db, emergency_id: uuid.UUID, event_type: str) -> EmergencyEvent | None:
    """Return the newest matching event for idempotent agency notifications."""
    return db.scalar(
        select(EmergencyEvent)
        .where(
            EmergencyEvent.emergency_id == emergency_id,
            EmergencyEvent.event_type == event_type,
        )
        .order_by(EmergencyEvent.created_at.desc())
        .limit(1)
    )


@router.post("/", response_model=EmergencyResponse, status_code=status.HTTP_201_CREATED)
def create_emergency(data: EmergencyCreate, db=Depends(get_db), current_user=Depends(get_current_user)):
    severity = data.severity.upper().strip()
    if severity not in {"LOW", "MEDIUM", "HIGH"}:
        raise HTTPException(status_code=400, detail="Invalid severity")

    patient = Patient(**data.patient.model_dump())
    db.add(patient)
    db.flush()

    ambulance = None
    if data.ambulance_id:
        ambulance = db.get(Ambulance, data.ambulance_id)
        if not ambulance:
            raise HTTPException(status_code=404, detail="Ambulance not found")
        if ambulance.paramedic_id != current_user.id:
            raise HTTPException(status_code=403, detail="Ambulance is not assigned to this paramedic")
    else:
        ambulance = db.scalar(select(Ambulance).where(Ambulance.paramedic_id == current_user.id).limit(1))

    if not ambulance:
        raise HTTPException(status_code=409, detail="No ambulance is linked to this paramedic")
    if ambulance.status not in {"AVAILABLE", "READY", "ON_EMERGENCY"}:
        raise HTTPException(status_code=409, detail=f"Ambulance is not available (status={ambulance.status})")

    condition = data.condition.strip().upper()
    emergency = Emergency(
        patient_id=patient.id,
        ambulance_id=ambulance.id,
        created_by=current_user.id,
        severity=severity,
        pickup_latitude=data.pickup_latitude,
        pickup_longitude=data.pickup_longitude,
        status="DISPATCHED",
    )
    db.add(emergency)
    db.flush()

    ambulance.status = "ON_EMERGENCY"
    ambulance.current_latitude = data.pickup_latitude
    ambulance.current_longitude = data.pickup_longitude

    record_event(db, emergency.id, "PATIENT_CREATED", {"patient_id": str(patient.id)})
    record_event(db, emergency.id, "EMERGENCY_CREATED", {"created_by": str(current_user.id), "ambulance_id": str(ambulance.id), "severity": severity})
    record_event(db, emergency.id, "EMERGENCY_DISPATCHED", {"ambulance_id": str(ambulance.id)})
    record_event(db, emergency.id, "PATIENT_CONDITION_REPORTED", {"condition": condition})

    db.commit()
    db.refresh(emergency)
    return emergency


@router.get("/{emergency_id}", response_model=EmergencyResponse)
def get_emergency(emergency_id: uuid.UUID, db=Depends(get_db), current_user=Depends(get_current_user)):
    return _get_owned_emergency(db, emergency_id, current_user)


@router.get("/{emergency_id}/events")
def get_emergency_events(emergency_id: uuid.UUID, db=Depends(get_db), current_user=Depends(get_current_user)):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    events = db.scalars(select(EmergencyEvent).where(EmergencyEvent.emergency_id == emergency.id).order_by(EmergencyEvent.created_at.asc())).all()
    return [{"id": str(e.id), "event_type": e.event_type, "payload": e.payload or {}, "created_at": e.created_at.isoformat()} for e in events]


@router.get("/{emergency_id}/hospital-recommendations")
async def hospital_recommendations(
    emergency_id: uuid.UUID,
    radius_km: float = Query(10, gt=0, le=30),
    db=Depends(get_db),
    current_user=Depends(get_current_user),
):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    latitude, longitude = _get_live_origin(db, emergency)
    condition = get_emergency_condition(db, emergency.id)
    candidates = await find_candidates(db, latitude, longitude, radius_km, condition, emergency.severity)
    return candidates


@router.post("/{emergency_id}/hospital-recommendations/auto-assign", response_model=EmergencyResponse)
async def auto_assign_best_hospital(
    emergency_id: uuid.UUID,
    radius_km: float = Query(10, gt=0, le=30),
    db=Depends(get_db),
    current_user=Depends(get_current_user),
):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    if emergency.status in {"COMPLETED", "CANCELLED"}:
        raise HTTPException(status_code=409, detail="Emergency is already closed")
    if emergency.hospital_id:
        return emergency

    latitude, longitude = _get_live_origin(db, emergency)
    condition = get_emergency_condition(db, emergency.id)
    candidates = await find_candidates(db, latitude, longitude, radius_km, condition, emergency.severity)
    if not candidates:
        raise HTTPException(status_code=404, detail="No real emergency-capable hospital was returned for the current live location")

    best = candidates[0]
    hospital = db.get(Hospital, best["hospital_id"])
    if not hospital:
        raise HTTPException(status_code=404, detail="Recommended hospital disappeared")

    _assign_hospital_record(
        db,
        emergency,
        hospital,
        "HOSPITAL_AUTO_ASSIGNED_AI",
        {
            "hospital_id": str(hospital.id),
            "hospital_name": hospital.name,
            "rank": best["rank"],
            "model_score": best["model_score"],
            "model_version": best["model_version"],
            "condition": best["condition"],
            "distance_km": best["distance_km"],
            "duration_seconds": best["duration_seconds"],
        },
    )
    db.commit()
    db.refresh(emergency)
    return emergency


@router.post("/{emergency_id}/assign-hospital", response_model=EmergencyResponse)
def assign_hospital(emergency_id: uuid.UUID, data: AssignHospitalRequest, db=Depends(get_db), current_user=Depends(get_current_user)):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    hospital = db.get(Hospital, data.hospital_id)
    if not hospital:
        raise HTTPException(status_code=404, detail="Hospital not found")
    if hospital.status != "ACTIVE":
        raise HTTPException(status_code=409, detail="Hospital is not active")
    if not hospital.is_emergency_available:
        raise HTTPException(status_code=409, detail="Hospital is not marked emergency-capable")
    _assign_hospital_record(db, emergency, hospital)
    db.commit()
    db.refresh(emergency)
    return emergency


@router.post("/{emergency_id}/notify-hospital")
def notify_hospital(emergency_id: uuid.UUID, data: HospitalArrivalNotificationRequest, db=Depends(get_db), current_user=Depends(get_current_user)):
    """Create/refresh a hospital availability request for the selected facility.

    Police dispatch is intentionally a separate action: it is created only when
    the paramedic presses Inform police.
    """
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    hospital = db.get(Hospital, data.hospital_id)
    if not hospital:
        raise HTTPException(status_code=404, detail="Hospital not found")
    if emergency.status in {"COMPLETED", "CANCELLED", "ARRIVED"}:
        raise HTTPException(status_code=409, detail="Emergency is already closed")

    condition = get_emergency_condition(db, emergency.id)
    live_latitude, live_longitude = _get_live_origin(db, emergency)
    emergency.hospital_id = hospital.id
    emergency.destination_latitude = hospital.latitude
    emergency.destination_longitude = hospital.longitude
    emergency.status = "HOSPITAL_ALERTED"

    payload = {
        "hospital_id": str(hospital.id),
        "hospital_name": hospital.name,
        "condition": condition,
        "severity": emergency.severity,
        "eta_seconds": data.eta_seconds,
        "ambulance_latitude": live_latitude,
        "ambulance_longitude": live_longitude,
        "contact_phone": data.phone,
        "note": data.note,
        "sent_by": str(current_user.id),
    }
    availability_request = db.scalar(
        select(HospitalAvailabilityRequest).where(
            HospitalAvailabilityRequest.emergency_id == emergency.id,
            HospitalAvailabilityRequest.hospital_id == hospital.id,
        )
    )
    created_new_request = availability_request is None
    if availability_request is None:
        availability_request = HospitalAvailabilityRequest(
            emergency_id=emergency.id,
            hospital_id=hospital.id,
            requested_by=current_user.id,
            status="REQUESTED",
            requested_eta_seconds=data.eta_seconds,
            ambulance_latitude=live_latitude,
            ambulance_longitude=live_longitude,
            message=data.note or "Please confirm emergency department availability.",
        )
        db.add(availability_request)
        db.flush()
    elif availability_request.status == "REQUESTED":
        # Refresh the live values without erasing an existing hospital response.
        availability_request.requested_eta_seconds = data.eta_seconds
        availability_request.ambulance_latitude = live_latitude
        availability_request.ambulance_longitude = live_longitude
        availability_request.message = data.note or availability_request.message

    # Keep an auditable event trail, without creating duplicate request rows.
    latest_request_event = _latest_event(db, emergency.id, "HOSPITAL_AVAILABILITY_REQUESTED")
    if created_new_request or latest_request_event is None:
        record_event(db, emergency.id, "HOSPITAL_ARRIVAL_NOTIFICATION_REQUESTED", payload)
        record_event(db, emergency.id, "HOSPITAL_AVAILABILITY_REQUESTED", {
            "hospital_id": str(hospital.id),
            "hospital_name": hospital.name,
            "request_id": str(availability_request.id),
            "eta_seconds": data.eta_seconds,
            "ambulance_latitude": live_latitude,
            "ambulance_longitude": live_longitude,
            "condition": condition,
            "severity": emergency.severity,
        })
    else:
        # Refresh event metadata while keeping the history durable.
        latest_request_event.payload = {
            **(latest_request_event.payload or {}),
            **payload,
            "request_id": str(availability_request.id),
        }

    record_event(db, emergency.id, "STATUS_CHANGED", {
        "to": "HOSPITAL_ALERTED",
        "reason": "hospital availability requested",
    })
    db.commit()
    db.refresh(availability_request)
    return {
        "status": "queued",
        "delivery": "hospital_dashboard_poll",
        "request_id": str(availability_request.id),
        "request_status": availability_request.status,
        "hospital_id": str(hospital.id),
        "hospital_name": hospital.name,
        "eta_seconds": data.eta_seconds,
        "message": "Hospital availability request is visible on the hospital dashboard.",
    }


@router.get("/{emergency_id}/route")
async def route(emergency_id: uuid.UUID, db=Depends(get_db), current_user=Depends(get_current_user)):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    if emergency.destination_latitude is None or emergency.destination_longitude is None:
        return {
            "origin_latitude": emergency.pickup_latitude,
            "origin_longitude": emergency.pickup_longitude,
            "destination_latitude": None,
            "destination_longitude": None,
            "distance_meters": None,
            "duration_seconds": None,
            "encoded_polyline": None,
            "polyline_points": [],
            "steps": [],
            "provider": "none",
            "traffic_aware": False,
            "route_profile": "none",
            "comfort_applied": False,
            "comfort_score": None,
            "rough_road_exposure": None,
            "alternatives_considered": 0,
            "route_label": None,
            "next_action": "Select a hospital first.",
        }

    origin_latitude, origin_longitude = _get_live_origin(db, emergency)
    condition = normalize_condition(get_emergency_condition(db, emergency.id))
    rough_points = []
    if condition == "BROKEN_RIBS":
        try:
            rough_points = await get_rough_road_points(
                origin_latitude,
                origin_longitude,
                radius_km=15.0,
            )
        except Exception:
            rough_points = []

    provider = get_routing_provider()
    result = await provider.route_for_condition(
        origin_latitude,
        origin_longitude,
        emergency.destination_latitude,
        emergency.destination_longitude,
        condition,
        rough_points,
    )

    return {
        "origin_latitude": origin_latitude,
        "origin_longitude": origin_longitude,
        "destination_latitude": emergency.destination_latitude,
        "destination_longitude": emergency.destination_longitude,
        "distance_meters": result.distance_meters,
        "duration_seconds": result.duration_seconds,
        "encoded_polyline": result.encoded_polyline,
        "polyline_points": route_points(result),
        "steps": result.steps or [],
        "provider": result.provider,
        "traffic_aware": result.traffic_aware,
        "route_profile": result.route_profile,
        "comfort_applied": result.comfort_applied,
        "comfort_score": result.comfort_score,
        "rough_road_exposure": result.rough_road_exposure,
        "alternatives_considered": result.alternatives_considered,
        "route_label": result.route_label,
        "next_action": (
            "Traffic-priority route selected for cardiac emergency."
            if condition == "CARDIAC"
            else "Comfort-priority route selected using mapped road-quality data."
            if condition == "BROKEN_RIBS"
            else "Fastest available route selected."
        ),
    }


@router.post("/{emergency_id}/notify-police")
def notify_police(
    emergency_id: uuid.UUID,
    data: PoliceNotificationRequest | None = Body(default=None),
    db=Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Dispatch a traffic-clearance alert with the latest ambulance position."""
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    if emergency.status in {"COMPLETED", "CANCELLED", "ARRIVED"}:
        raise HTTPException(status_code=409, detail="Emergency is already closed")

    data = data or PoliceNotificationRequest()
    latitude, longitude = _get_live_origin(db, emergency)
    condition = get_emergency_condition(db, emergency.id)
    latest_location = _latest_event(db, emergency.id, "AMBULANCE_LOCATION_UPDATED")
    latest_location_payload = latest_location.payload or {} if latest_location else {}
    route_eta_seconds = data.eta_seconds if data.eta_seconds is not None else latest_location_payload.get("eta_seconds")

    payload = {
        "emergency_id": str(emergency.id),
        "ambulance_id": str(emergency.ambulance_id) if emergency.ambulance_id else None,
        "hospital_id": str(emergency.hospital_id) if emergency.hospital_id else None,
        "hospital_name": None,
        "condition": condition,
        "severity": emergency.severity,
        "latitude": latitude,
        "longitude": longitude,
        "ambulance_latitude": latitude,
        "ambulance_longitude": longitude,
        "destination_latitude": emergency.destination_latitude,
        "destination_longitude": emergency.destination_longitude,
        "eta_seconds": route_eta_seconds,
        "eta_basis": "latest route ETA sent by paramedic" if route_eta_seconds is not None else "route ETA not yet available",
        "location_updated_at": latest_location.created_at.isoformat() if latest_location else None,
        "message": "Ambulance approaching. Please prepare to clear traffic at your assigned junction.",
        "sent_by": str(current_user.id),
    }

    if emergency.hospital_id:
        hospital = db.get(Hospital, emergency.hospital_id)
        if hospital:
            payload["hospital_name"] = hospital.name

    existing_request = _latest_event(
        db, emergency.id, "POLICE_TRAFFIC_CLEARANCE_REQUESTED"
    )
    if existing_request is None:
        record_event(
            db,
            emergency.id,
            "POLICE_TRAFFIC_CLEARANCE_REQUESTED",
            payload,
        )
    else:
        # Idempotent repeated button presses: update the alert with current GPS/ETA.
        merged = dict(existing_request.payload or {})
        merged.update(payload)
        existing_request.payload = merged
    db.commit()

    return {
        "status": "queued",
        "delivery": "police_dashboard_poll",
        "already_requested": existing_request is not None,
        "message": "Police traffic-clearance alert is recorded with the latest ambulance location.",
        "emergency_id": str(emergency.id),
        "latitude": latitude,
        "longitude": longitude,
        "eta_seconds": route_eta_seconds,
    }


@router.post("/{emergency_id}/location")
def update_location(emergency_id: uuid.UUID, data: LocationUpdate, db=Depends(get_db), current_user=Depends(get_current_user)):
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    if not emergency.ambulance_id:
        raise HTTPException(status_code=409, detail="Emergency has no ambulance linked")
    ambulance = db.get(Ambulance, emergency.ambulance_id)
    if not ambulance:
        raise HTTPException(status_code=404, detail="Ambulance not found")
    if ambulance.paramedic_id != current_user.id:
        raise HTTPException(status_code=403, detail="You cannot update another ambulance's location")
    ambulance.current_latitude = data.latitude
    ambulance.current_longitude = data.longitude
    ambulance.status = "ON_EMERGENCY"
    location_payload = data.model_dump()
    location_payload["recorded_at"] = datetime.utcnow().isoformat()
    record_event(db, emergency.id, "AMBULANCE_LOCATION_UPDATED", location_payload)
    requests = db.scalars(
        select(HospitalAvailabilityRequest).where(
            HospitalAvailabilityRequest.emergency_id == emergency.id,
            HospitalAvailabilityRequest.status.in_(["REQUESTED", "ACCEPTED"]),
        )
    ).all()
    for availability_request in requests:
        availability_request.ambulance_latitude = data.latitude
        availability_request.ambulance_longitude = data.longitude
        if data.eta_seconds is not None:
            availability_request.requested_eta_seconds = data.eta_seconds

    # Keep the dispatch event in sync with the newest GPS and route ETA. Police
    # boards also read the live Ambulance row, but this makes the event auditable.
    police_request = _latest_event(db, emergency.id, "POLICE_TRAFFIC_CLEARANCE_REQUESTED")
    if police_request is not None:
        merged_payload = dict(police_request.payload or {})
        merged_payload.update({
            "latitude": data.latitude,
            "longitude": data.longitude,
            "ambulance_latitude": data.latitude,
            "ambulance_longitude": data.longitude,
            "eta_seconds": data.eta_seconds if data.eta_seconds is not None else merged_payload.get("eta_seconds"),
            "location_updated_at": location_payload["recorded_at"],
            "speed_mps": data.speed_mps,
            "heading_degrees": data.heading_degrees,
            "accuracy_meters": data.accuracy_meters,
        })
        merged_payload["eta_basis"] = "latest route ETA sent by paramedic" if merged_payload.get("eta_seconds") is not None else "route ETA not yet available"
        police_request.payload = merged_payload
    db.commit()
    return {"status": "ok", "latitude": data.latitude, "longitude": data.longitude, "ambulance_id": str(ambulance.id)}


@router.post("/{emergency_id}/status")
def update_status(emergency_id: uuid.UUID, data: StatusUpdateRequest, db=Depends(get_db), current_user=Depends(get_current_user)):
    if data.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid emergency status")
    emergency = _get_owned_emergency(db, emergency_id, current_user)
    if emergency.ambulance_id:
        ambulance = db.get(Ambulance, emergency.ambulance_id)
        if ambulance and ambulance.paramedic_id != current_user.id:
            raise HTTPException(status_code=403, detail="You cannot update another paramedic's emergency")
        if ambulance:
            ambulance.status = "AVAILABLE" if data.status in {"COMPLETED", "CANCELLED", "ARRIVED"} else "ON_EMERGENCY"
    emergency.status = data.status
    if data.status in {"ARRIVED", "COMPLETED", "CANCELLED"}:
        for request in db.scalars(
            select(HospitalAvailabilityRequest).where(
                HospitalAvailabilityRequest.emergency_id == emergency.id,
                HospitalAvailabilityRequest.status == "REQUESTED",
            )
        ).all():
            request.status = "CLOSED"
    record_event(db, emergency.id, "STATUS_CHANGED", {"status": data.status, "updated_by": str(current_user.id)})
    db.commit()
    return {"status": data.status, "emergency_id": str(emergency.id)}
