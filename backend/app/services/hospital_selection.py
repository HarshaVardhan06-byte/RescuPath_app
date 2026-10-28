from __future__ import annotations

import asyncio
from math import atan2, cos, exp, radians, sin, sqrt

from sqlalchemy import select

from app.models.emergency import EmergencyEvent
from app.models.hospital import Hospital
from app.services.hospital_ai import HospitalFeatures, MODEL
from app.services.real_hospitals import LiveHospital, fetch_real_hospitals
from app.services.rough_road import get_rough_road_points
from app.services.routing import get_routing_provider


CONDITION_ALIASES = {
    "CARDIAC": "CARDIAC",
    "CHEST PAIN": "CARDIAC",
    "HEART ATTACK": "CARDIAC",
    "STROKE": "STROKE",
    "NEUROLOGICAL": "STROKE",
    "TRAUMA": "TRAUMA",
    "BROKEN RIBS": "BROKEN_RIBS",
    "RIB FRACTURE": "BROKEN_RIBS",
    "BROKEN_RIB": "BROKEN_RIBS",
    "SPINAL INJURY": "SPINAL_INJURY",
    "ACCIDENT": "TRAUMA",
    "MAJOR TRAUMA": "TRAUMA",
    "RESPIRATORY": "RESPIRATORY",
    "BREATHING": "RESPIRATORY",
    "BURNS": "BURNS",
    "BURN": "BURNS",
    "OTHER": "OTHER",
}


def normalize_condition(condition: str | None) -> str:
    if not condition:
        return "OTHER"
    return CONDITION_ALIASES.get(condition.strip().upper(), "OTHER")


def haversine_km(lat1, lon1, lat2, lon2):
    earth_radius_km = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = (
        sin(dlat / 2) ** 2
        + cos(radians(lat1))
        * cos(radians(lat2))
        * sin(dlon / 2) ** 2
    )
    return 2 * earth_radius_km * atan2(sqrt(a), sqrt(1 - a))


def _urgency(severity: str | None) -> float:
    return {
        "LOW": 0.25,
        "MEDIUM": 0.60,
        "HIGH": 1.0,
    }.get((severity or "HIGH").upper(), 1.0)


def _specialities(hospital: LiveHospital) -> str:
    return " ".join(
        [
            hospital.tags.get("healthcare:speciality", ""),
            hospital.tags.get("healthcare", ""),
            hospital.tags.get("medical_system", ""),
            hospital.name,
        ]
    ).lower()


def _condition_fit(
    condition: str,
    hospital: LiveHospital,
) -> tuple[float, list[str]]:
    text = _specialities(hospital)
    reasons: list[str] = []

    if hospital.emergency_status == "VERIFIED_EMERGENCY":
        reasons.append("emergency service listed")

    keyword_sets = {
        "CARDIAC": ("cardiology", "cardiac", "coronary", "heart"),
        "STROKE": ("neurology", "neurosurgery", "stroke", "neuro"),
        "BROKEN_RIBS": (
            "trauma",
            "orthopedic",
            "orthopaedic",
            "emergency",
            "rib",
        ),
        "SPINAL_INJURY": (
            "spine",
            "spinal",
            "neurosurgery",
            "orthopedic",
            "orthopaedic",
            "trauma",
        ),
        "TRAUMA": (
            "trauma",
            "orthopedic",
            "orthopaedic",
            "surgery",
            "emergency",
        ),
        "RESPIRATORY": (
            "pulmonology",
            "pulmonary",
            "respiratory",
            "critical care",
        ),
        "BURNS": ("burn", "plastic surgery"),
        "OTHER": ("general", "emergency", "medical", "multispeciality"),
    }

    matches = keyword_sets[condition]
    match_count = sum(1 for word in matches if word in text)

    if match_count:
        fit = min(1.0, 0.50 + 0.14 * match_count)
        reasons.append(f"{condition.lower()} capability signal")
    else:
        fit = 0.50
        reasons.append("no condition-specific OSM specialty tag")

    if hospital.beds_total is not None and hospital.beds_total > 0:
        reasons.append(f"{hospital.beds_total} total beds listed")

    if hospital.emergency_status == "NOT_EMERGENCY":
        return 0.0, ["emergency service marked unavailable"]

    return fit, reasons


def _eta_score(duration_seconds: int | None, distance_km: float) -> float:
    if duration_seconds is None:
        return round(exp(-max(distance_km, 0.0) / 10.0), 4)
    return round(exp(-max(duration_seconds / 60.0, 0.0) / 25.0), 4)


def _distance_score(distance_km: float) -> float:
    return round(exp(-max(distance_km, 0.0) / 10.0), 4)


def _sync_hospital(db, live: LiveHospital) -> Hospital:
    hospital = db.get(Hospital, live.hospital_id)

    if not hospital:
        hospital = Hospital(
            id=live.hospital_id,
            name=live.name,
            latitude=live.latitude,
            longitude=live.longitude,
            status="ACTIVE",
            is_emergency_available=live.emergency_status != "NOT_EMERGENCY",
        )
        db.add(hospital)
        db.flush()
    else:
        hospital.name = live.name
        hospital.latitude = live.latitude
        hospital.longitude = live.longitude
        hospital.status = "ACTIVE"
        hospital.is_emergency_available = live.emergency_status != "NOT_EMERGENCY"

    return hospital


def get_emergency_condition(db, emergency_id):
    event = db.scalar(
        select(EmergencyEvent)
        .where(
            EmergencyEvent.emergency_id == emergency_id,
            EmergencyEvent.event_type == "PATIENT_CONDITION_REPORTED",
        )
        .order_by(EmergencyEvent.created_at.desc())
    )

    if not event or not event.payload:
        return "OTHER"

    return normalize_condition(event.payload.get("condition"))


async def _safe_route(provider, latitude, longitude, hospital, condition, rough_points=None):
    try:
        # Individual route timeout prevents one slow provider from blocking
        # the entire hospital recommendation request.
        return await asyncio.wait_for(
            provider.route_for_condition(
                latitude,
                longitude,
                hospital.latitude,
                hospital.longitude,
                condition,
                rough_points,
            ),
            timeout=4.5,
        )
    except Exception:
        return None


async def _cached_hospital_candidates(
    db,
    latitude: float,
    longitude: float,
    radius_km: float,
    condition: str,
    severity: str | None,
) -> list[dict]:
    """Return previously saved nearby hospitals when live OSM is unavailable.

    Cached records are explicitly marked unverified. The demo seed records are
    excluded so this fallback does not display fictional RescuPath hospitals.
    """
    demo_names = {
        "rescupath central medical center",
        "rescupath emergency institute",
        "rescupath trauma & cardiac",
    }
    saved = db.scalars(
        select(Hospital).where(
            Hospital.status == "ACTIVE",
            Hospital.is_emergency_available.is_(True),
        )
    ).all()

    nearby: list[tuple[Hospital, float]] = []
    for hospital in saved:
        # Hospitals discovered by real_hospitals.py are stored with deterministic
        # UUID5 IDs. Exclude UUID4 demo/seed rows so the outage fallback never
        # presents the sample dataset as real nearby hospitals.
        try:
            is_saved_osm_hospital = hospital.id.version == 5
        except AttributeError:
            is_saved_osm_hospital = False
        if not is_saved_osm_hospital:
            continue
        if hospital.name.strip().lower() in demo_names:
            continue
        if hospital.latitude is None or hospital.longitude is None:
            continue
        distance = haversine_km(
            latitude,
            longitude,
            float(hospital.latitude),
            float(hospital.longitude),
        )
        if distance <= float(radius_km):
            nearby.append((hospital, distance))

    nearby.sort(key=lambda item: item[1])
    nearby = nearby[:25]
    if not nearby:
        print(
            "[RescuPath] Live hospital lookup failed and no saved real-hospital "
            "records are available inside the requested radius."
        )
        return []

    provider = get_routing_provider()
    route_targets = nearby[:10]
    route_results = await asyncio.gather(
        *(
            _safe_route(provider, latitude, longitude, hospital, condition, [])
            for hospital, _ in route_targets
        ),
        return_exceptions=False,
    )
    routes_by_id = {
        str(hospital.id): route
        for (hospital, _), route in zip(route_targets, route_results)
    }

    route_profile_default = (
        "comfort_priority" if condition == "BROKEN_RIBS"
        else "traffic_priority" if condition == "CARDIAC"
        else "fastest"
    )
    candidates: list[dict] = []
    for hospital, distance in nearby:
        route = routes_by_id.get(str(hospital.id))
        duration_seconds = route.duration_seconds if route else None
        if duration_seconds is not None:
            minutes = max(0.0, duration_seconds / 60.0)
            score = round(100.0 / (1.0 + minutes / 20.0), 2)
            reason = (
                f"{round(minutes)} min road ETA; saved hospital record; "
                "live hospital lookup unavailable"
            )
        else:
            score = round(100.0 / (1.0 + distance), 2)
            reason = (
                f"{round(distance, 2)} km straight-line; road ETA unavailable; "
                "saved hospital record; live lookup unavailable"
            )

        candidates.append({
            "hospital_id": hospital.id,
            "hospital_name": hospital.name,
            "rank_score": score,
            "model_score": None,
            "model_version": "cached-distance-route-fallback",
            "recommended": False,
            "rank": 0,
            "condition": condition,
            "condition_score": None,
            "distance_km": round(distance, 2),
            "duration_seconds": duration_seconds,
            "route_provider": route.provider if route else "unavailable",
            "traffic_aware": bool(route.traffic_aware) if route else False,
            "route_profile": route.route_profile if route else route_profile_default,
            "comfort_score": route.comfort_score if route else None,
            "rough_road_exposure": route.rough_road_exposure if route else None,
            "alternatives_considered": route.alternatives_considered if route else 0,
            "route_policy_score": None,
            "emergency_service_status": "UNVERIFIED",
            "availability_confidence": "unverified",
            "beds_total_listed": None,
            "phone": None,
            "website": None,
            "opening_hours": None,
            "address": None,
            "latitude": float(hospital.latitude),
            "longitude": float(hospital.longitude),
            "source": "Saved hospital database cache",
            "source_timestamp": None,
            "source_endpoint": "database-cache",
            "availability_note": (
                "Saved hospital record only. Live hospital lookup failed; "
                "current emergency acceptance and capacity are unverified. "
                "Call the hospital to confirm before dispatch."
            ),
            "reason": reason,
        })

    candidates.sort(key=lambda item: (
        -item["rank_score"],
        item["duration_seconds"] is None,
        item["duration_seconds"] if item["duration_seconds"] is not None else item["distance_km"],
        item["distance_km"],
    ))
    for index, candidate in enumerate(candidates, start=1):
        candidate["rank"] = index
        candidate["recommended"] = index == 1
    return candidates


async def find_candidates(
    db,
    latitude: float,
    longitude: float,
    radius_km: float = 15.0,
    condition: str | None = None,
    severity: str | None = None,
):
    """Discover real nearby hospitals and rank them using the RescuPath model."""

    condition = normalize_condition(condition)
    urgency = _urgency(severity)

    try:
        live_hospitals, source_endpoint, source_timestamp = await fetch_real_hospitals(
            latitude,
            longitude,
            min(float(radius_km), 30.0),
        )
    except Exception as exc:
        print(
            f"[RescuPath] Live hospital discovery failed: "
            f"{type(exc).__name__}: {exc}"
        )
        return await _cached_hospital_candidates(
            db, latitude, longitude, radius_km, condition, severity
        )

    # Real hospitals only. Never substitute the demo hospital dataset.
    eligible = [
        hospital
        for hospital in live_hospitals
        if hospital.emergency_status != "NOT_EMERGENCY"
    ]

    if not eligible:
        print("[RescuPath] Live source returned no eligible hospital records; trying saved records.")
        return await _cached_hospital_candidates(
            db, latitude, longitude, radius_km, condition, severity
        )

    # De-duplicate by OSM ID and rank the whole nearby set by the AI model.
    pool_with_distance = [
        (
            hospital,
            haversine_km(
                latitude,
                longitude,
                hospital.latitude,
                hospital.longitude,
            ),
        )
        for hospital in eligible
    ]
    pool_with_distance.sort(key=lambda item: item[1])

    # The free public map can contain many hospitals. Evaluate up to 25 real
    # hospitals, which is enough to cover the meaningful nearby options while
    # keeping the response fast.
    pool_with_distance = pool_with_distance[:25]

    db_hospitals = {
        str(hospital.hospital_id): _sync_hospital(db, hospital)
        for hospital, _ in pool_with_distance
    }
    db.commit()

    # Route only the nearest 10 by straight-line distance, concurrently.
    # Remaining hospitals still participate in model ranking using their
    # distance score, with route ETA unavailable.
    route_targets = pool_with_distance[:10]
    provider = get_routing_provider()

    rough_points: list[dict[str, float]] = []
    if condition == "BROKEN_RIBS":
        try:
            rough_points = await get_rough_road_points(
                latitude,
                longitude,
                radius_km=min(max(radius_km, 8.0), 15.0),
            )
        except Exception:
            rough_points = []

    route_results = await asyncio.gather(
        *(
            _safe_route(
                provider,
                latitude,
                longitude,
                hospital,
                condition,
                rough_points,
            )
            for hospital, _ in route_targets
        ),
        return_exceptions=False,
    )

    routes_by_osm = {
        (hospital.osm_type, hospital.osm_id): route
        for (hospital, _), route in zip(route_targets, route_results)
    }

    candidates: list[dict] = []

    for live, distance in pool_with_distance:
        route = routes_by_osm.get((live.osm_type, live.osm_id))

        duration_seconds = route.duration_seconds if route else None
        route_provider = route.provider if route else "distance-estimate"
        traffic_aware = route.traffic_aware if route else False
        route_profile = route.route_profile if route else (
            "comfort_priority" if condition == "BROKEN_RIBS"
            else "traffic_priority" if condition == "CARDIAC"
            else "fastest"
        )
        comfort_score = route.comfort_score if route else None
        rough_exposure = route.rough_road_exposure if route else None

        condition_fit, condition_reasons = _condition_fit(condition, live)
        specialty_fit = condition_fit
        emergency_service = (
            1.0
            if live.emergency_status == "VERIFIED_EMERGENCY"
            else 0.45
        )
        bed_metadata = min((live.beds_total or 0) / 500.0, 1.0)
        eta_score = _eta_score(duration_seconds, distance)
        distance_score = _distance_score(distance)
        data_confidence = (
            1.0
            if live.emergency_status == "VERIFIED_EMERGENCY"
            else 0.45
        )

        features = HospitalFeatures(
            condition_fit=condition_fit,
            emergency_service=emergency_service,
            bed_metadata=bed_metadata,
            specialty_fit=specialty_fit,
            eta_score=eta_score,
            distance_score=distance_score,
            data_confidence=data_confidence,
            urgency=urgency,
        )

        model_score = MODEL.predict(features)
        db_hospital = db_hospitals[str(live.hospital_id)]

        route_policy_score = 50.0
        if condition == "CARDIAC":
            if traffic_aware:
                route_policy_score = max(0.0, 100.0 - (duration_seconds or 0) / 60.0)
            else:
                route_policy_score = max(0.0, 90.0 - (duration_seconds or 0) / 60.0)
        elif condition == "BROKEN_RIBS":
            route_policy_score = (comfort_score * 100.0) if comfort_score is not None else 50.0

        # Hospital suitability remains the primary ranking signal. The route
        # policy supplies an explicit condition-aware operational adjustment.
        final_score = round(
            0.78 * model_score
            + 0.12 * route_policy_score
            + 0.10 * (100.0 * eta_score),
            2,
        )

        reasons = list(condition_reasons)
        if duration_seconds is not None:
            reasons.append(f"{round(duration_seconds / 60)} min road ETA")
        else:
            reasons.append(f"{round(distance, 1)} km straight-line")
        if traffic_aware:
            reasons.append("traffic-aware ETA")
        if condition == "CARDIAC":
            reasons.append("traffic-priority route policy")
        elif condition == "BROKEN_RIBS":
            if rough_exposure is not None:
                reasons.append(
                    f"comfort-priority route; mapped rough-road exposure {round(rough_exposure * 100)}%"
                )
            else:
                reasons.append("comfort-priority route; rough-road map data unavailable")

        candidates.append(
            {
                "hospital_id": db_hospital.id,
                "hospital_name": live.name,
                "rank_score": final_score,
                "model_score": model_score,
                "model_version": MODEL.VERSION,
                "recommended": False,
                "rank": 0,
                "condition": condition,
                "condition_score": round(condition_fit * 100.0, 2),
                "distance_km": round(distance, 2),
                "duration_seconds": duration_seconds,
                "route_provider": route_provider,
                "traffic_aware": traffic_aware,
                "route_profile": route_profile,
                "comfort_score": comfort_score,
                "rough_road_exposure": rough_exposure,
                "alternatives_considered": route.alternatives_considered if route else 0,
                "route_policy_score": round(route_policy_score, 2),
                "emergency_service_status": live.emergency_status,
                "availability_confidence": (
                    "verified"
                    if live.emergency_status == "VERIFIED_EMERGENCY"
                    else "unverified"
                ),
                "beds_total_listed": live.beds_total,
                "phone": live.tags.get("phone")
                or live.tags.get("contact:phone"),
                "website": live.tags.get("website")
                or live.tags.get("contact:website"),
                "opening_hours": live.tags.get("opening_hours"),
                "address": ", ".join(
                    part
                    for part in (
                        live.tags.get("addr:housenumber"),
                        live.tags.get("addr:street"),
                        live.tags.get("addr:city"),
                    )
                    if part
                )
                or None,
                "latitude": live.latitude,
                "longitude": live.longitude,
                "source": "OpenStreetMap Overpass",
                "source_timestamp": source_timestamp.isoformat(),
                "source_endpoint": source_endpoint,
                "availability_note": (
                    "Emergency service is explicitly listed in OSM. "
                    "Free public OSM data does not provide live bed occupancy."
                    if live.emergency_status == "VERIFIED_EMERGENCY"
                    else "Real nearby hospital. Emergency service is not explicitly tagged in OSM."
                ),
                "reason": "; ".join(reasons),
            }
        )

    candidates.sort(
        key=lambda item: (
            -item["rank_score"],
            item["duration_seconds"] is None,
            item["duration_seconds"]
            if item["duration_seconds"] is not None
            else item["distance_km"],
            item["distance_km"],
        )
    )

    for index, candidate in enumerate(candidates, start=1):
        candidate["rank"] = index
        candidate["recommended"] = index == 1

    return candidates
