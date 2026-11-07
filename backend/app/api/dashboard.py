from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.ambulance import Ambulance
from app.models.emergency import Emergency, EmergencyEvent
from app.models.hospital import Hospital
from app.models.patient import Patient

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])

@router.get("/summary")
def summary(db=Depends(get_db), current_user=Depends(get_current_user)):
    ambulance = db.scalar(select(Ambulance).where(Ambulance.paramedic_id == current_user.id).limit(1))
    total = db.scalar(select(func.count(Emergency.id)).where(Emergency.created_by == current_user.id)) or 0
    active = db.scalar(select(func.count(Emergency.id)).where(Emergency.created_by == current_user.id, Emergency.status.notin_(["COMPLETED","CANCELLED"]))) or 0
    return {"total_responses": int(total), "active_emergencies": int(active), "pending": 0, "ambulance": None if not ambulance else {"id": str(ambulance.id), "vehicle_number": ambulance.vehicle_number, "status": ambulance.status, "latitude": ambulance.current_latitude, "longitude": ambulance.current_longitude}}

def _format_emergency(db, x: Emergency) -> dict:
    hosp = db.get(Hospital, x.hospital_id) if x.hospital_id else None
    amb = db.get(Ambulance, x.ambulance_id) if x.ambulance_id else None
    patient = db.get(Patient, x.patient_id) if x.patient_id else None
    ev = db.scalar(
        select(EmergencyEvent)
        .where(EmergencyEvent.emergency_id == x.id, EmergencyEvent.event_type.in_(["EMERGENCY_CREATED", "CONDITION_RECORDED"]))
        .order_by(EmergencyEvent.created_at.desc())
        .limit(1)
    )
    condition = (ev.payload or {}).get("condition", "Medical Emergency") if ev else "Medical Emergency"
    dest_name = hosp.name if hosp else "Selected Hospital"
    pickup_label = (ev.payload or {}).get("pickup_name") if ev else None
    if not pickup_label:
        pickup_label = "Pickup Scene"
    route_label = f"{pickup_label} → {dest_name}"

    return {
        "id": str(x.id),
        "severity": x.severity,
        "status": x.status,
        "condition": condition,
        "hospital_name": dest_name,
        "route_label": route_label,
        "pickup_label": pickup_label,
        "destination_name": dest_name,
        "ambulance_number": amb.vehicle_number if amb else None,
        "patient_name": patient.full_name if patient else "Emergency Patient",
        "pickup_latitude": x.pickup_latitude,
        "pickup_longitude": x.pickup_longitude,
        "destination_latitude": x.destination_latitude,
        "destination_longitude": x.destination_longitude,
        "created_at": x.created_at.isoformat(),
    }

@router.get("/emergencies")
def history(db=Depends(get_db), current_user=Depends(get_current_user)):
    rows = db.scalars(select(Emergency).where(Emergency.created_by == current_user.id).order_by(Emergency.created_at.desc()).limit(100)).all()
    return [_format_emergency(db, x) for x in rows]
