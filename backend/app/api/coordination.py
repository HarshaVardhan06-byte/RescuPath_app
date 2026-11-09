from __future__ import annotations

import hashlib
import math
import re
import secrets
import uuid

import httpx
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.security import create_access_token, hash_password
from app.db.session import get_db
from app.models.ambulance import Ambulance
from app.models.emergency import Emergency, EmergencyEvent
from app.models.hospital import Hospital
from app.models.hospital_availability_request import HospitalAvailabilityRequest
from app.models.hospital_operator import HospitalOperatorProfile
from app.models.hospital_resource import HospitalResource
from app.models.password_reset import PasswordResetToken
from app.models.patient import Patient
from app.models.police_officer import PoliceOfficerProfile
from app.models.user import User, UserRole
from app.services.email import send_password_reset_otp_email
from app.services.events import record_event
from app.services.hospital_selection import get_emergency_condition, normalize_condition
from app.services.routing import get_routing_provider, route_points

router = APIRouter(prefix="/coordination", tags=["Police & Hospital Coordination"])
CLOSED = {"ARRIVED", "COMPLETED", "CANCELLED"}


class PoliceRegister(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    phone: str | None = Field(default=None, max_length=30)
    badge_number: str = Field(min_length=2, max_length=50)
    station_name: str = Field(min_length=2, max_length=180)
    junction_name: str = Field(min_length=2, max_length=180)
    junction_latitude: float | None = Field(default=None, ge=-90, le=90)
    junction_longitude: float | None = Field(default=None, ge=-180, le=180)


class HospitalRegister(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    phone: str | None = Field(default=None, max_length=30)
    hospital_name: str = Field(min_length=2, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    department: str = Field(default="Emergency Department", max_length=100)


class HospitalRegisterFull(BaseModel):
    hospital_name: str = Field(min_length=2, max_length=200)
    gst_number: str = Field(min_length=5, max_length=30)
    gst_photo_url: str | None = None
    admin_name: str = Field(min_length=2, max_length=120)
    admin_email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    admin_phone: str | None = Field(default=None, max_length=30)
    latitude: float = Field(default=12.9716, ge=-90, le=90)
    longitude: float = Field(default=77.5946, ge=-180, le=180)
    department: str = Field(default="Emergency Department", max_length=100)
    specialties: str | None = Field(default="Multi-Specialty Emergency Care", max_length=255)
    icu_beds_available: int = Field(default=12, ge=0)
    emergency_beds_available: int = Field(default=20, ge=0)
    ventilators_available: int = Field(default=6, ge=0)
    oxygen_cylinders_available: int = Field(default=25, ge=0)
    staff_count: int = Field(default=25, ge=0)
    parking_available: bool = True


class HospitalProfileUpdate(BaseModel):
    hospital_name: str | None = None
    specialties: str | None = None
    admin_name: str | None = None
    admin_phone: str | None = None
    staff_count: int | None = None
    parking_available: bool | None = None
    gst_photo_url: str | None = None
    department: str | None = None
    latitude: float | None = None
    longitude: float | None = None


class HospitalForgotRequest(BaseModel):
    identifier: str  # email, GST number, or phone number
    request_type: str = Field(default="FORGOT_PASSWORD", pattern="^(FORGOT_GST|FORGOT_PASSWORD)$")


class HospitalResetPassword(BaseModel):
    gst_number: str | None = None
    admin_email: EmailStr
    otp: str | None = None
    new_password: str = Field(min_length=6, max_length=128)


class PoliceLocationUpdate(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    junction_name: str | None = Field(default=None, max_length=180)
    junction_latitude: float | None = Field(default=None, ge=-90, le=90)
    junction_longitude: float | None = Field(default=None, ge=-180, le=180)


class DutyUpdate(BaseModel):
    on_duty: bool


class HospitalAvailabilityUpdate(BaseModel):
    emergency_available: bool
    icu_beds_available: int | None = Field(default=None, ge=0, le=10000)
    emergency_beds_available: int | None = Field(default=None, ge=0, le=10000)
    ventilators_available: int | None = Field(default=None, ge=0, le=10000)
    oxygen_cylinders_available: int | None = Field(default=None, ge=0, le=10000)
    oxygen_available: bool | None = None
    trauma_capable: bool | None = None
    cardiac_capable: bool | None = None


class HospitalResponseBody(BaseModel):
    decision: str = Field(pattern="^(ACCEPTED|DECLINED)$")
    note: str | None = Field(default=None, max_length=1000)


class RelayBody(BaseModel):
    target_officer_id: uuid.UUID
    note: str | None = Field(default=None, max_length=1000)


def _role(user: User) -> str:
    return user.role.value if hasattr(user.role, "value") else str(user.role).upper()


def _require_role(user: User, *roles: str) -> None:
    if _role(user) not in roles:
        raise HTTPException(status_code=403, detail=f"This action requires role: {' or '.join(roles)}")


def _new_token(user: User) -> dict:
    return {
        "access_token": create_access_token(str(user.id), _role(user)),
        "token_type": "bearer",
        "user": {"id": str(user.id), "full_name": user.full_name, "email": user.email, "role": _role(user)},
    }


def _assert_registration_enabled() -> None:
    if not settings.public_operations_registration_enabled:
        raise HTTPException(status_code=403, detail="Public operator registration is disabled. Ask the system administrator to provision the account.")


def _create_user(db, *, full_name: str, email: str, password: str, phone: str | None, role: UserRole) -> User:
    existing = db.scalar(select(User).where(User.email == email.lower().strip()))
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered. Sign in or use a different email.")
    user = User(full_name=full_name.strip(), email=email.lower().strip(), phone=phone, password_hash=hash_password(password), role=role)
    db.add(user)
    db.flush()
    return user


def _police_profile(db, user: User) -> PoliceOfficerProfile:
    _require_role(user, "POLICE")
    profile = db.scalar(select(PoliceOfficerProfile).where(PoliceOfficerProfile.user_id == user.id))
    if not profile:
        raise HTTPException(status_code=409, detail="Police profile is missing. Please contact the administrator.")
    return profile


def _hospital_profile(db, user: User) -> HospitalOperatorProfile:
    _require_role(user, "HOSPITAL")
    profile = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == user.id))
    if not profile:
        raise HTTPException(status_code=409, detail="Hospital operator profile is missing. Please contact the administrator.")
    return profile


def _latest_event(db, emergency_id: uuid.UUID, event_type: str) -> EmergencyEvent | None:
    return db.scalar(select(EmergencyEvent).where(EmergencyEvent.emergency_id == emergency_id, EmergencyEvent.event_type == event_type).order_by(EmergencyEvent.created_at.desc()).limit(1))


def _condition(db, emergency_id: uuid.UUID) -> str:
    try:
        return normalize_condition(get_emergency_condition(db, emergency_id))
    except Exception:
        return "OTHER"


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    rad = math.pi / 180.0
    dlat, dlon = (lat2 - lat1) * rad, (lon2 - lon1) * rad
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.sin(dlon / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(max(0.0, min(1.0, a))))


def _ambulance_point(db, emergency: Emergency) -> tuple[float, float]:
    if emergency.ambulance_id:
        ambulance = db.get(Ambulance, emergency.ambulance_id)
        if ambulance and ambulance.current_latitude is not None and ambulance.current_longitude is not None:
            return float(ambulance.current_latitude), float(ambulance.current_longitude)
    return float(emergency.pickup_latitude), float(emergency.pickup_longitude)


def _emergency_card(db, emergency: Emergency, *, eta_override: int | None = None) -> dict:
    lat, lon = _ambulance_point(db, emergency)
    hospital = db.get(Hospital, emergency.hospital_id) if emergency.hospital_id else None
    ambulance = db.get(Ambulance, emergency.ambulance_id) if emergency.ambulance_id else None
    latest_loc = _latest_event(db, emergency.id, "AMBULANCE_LOCATION_UPDATED")
    loc_payload = latest_loc.payload or {} if latest_loc else {}
    latest_route_eta = loc_payload.get("eta_seconds")
    police_dispatch = _latest_event(db, emergency.id, "POLICE_TRAFFIC_CLEARANCE_REQUESTED")
    dispatch_payload = police_dispatch.payload or {} if police_dispatch else {}
    dispatch_route_eta = dispatch_payload.get("eta_seconds")
    if eta_override is not None:
        eta = eta_override
        eta_basis = "latest route ETA sent by paramedic"
    elif isinstance(latest_route_eta, (int, float)) and latest_route_eta >= 0:
        eta = int(latest_route_eta)
        eta_basis = "latest route ETA sent by paramedic"
    elif isinstance(dispatch_route_eta, (int, float)) and dispatch_route_eta >= 0:
        eta = int(dispatch_route_eta)
        eta_basis = "latest route ETA attached to police alert"
    elif hospital and hospital.latitude is not None and hospital.longitude is not None:
        # Explicitly approximate fallback; never claim this is traffic-aware.
        eta = int(_distance_km(lat, lon, hospital.latitude, hospital.longitude) / 30.0 * 3600)
        eta_basis = "straight-line distance at 30 km/h; not traffic-aware"
    else:
        eta = None
        eta_basis = "route ETA not yet available"
    patient = db.get(Patient, emergency.patient_id) if emergency.patient_id else None
    return {
        "emergency_id": str(emergency.id),
        "ambulance_id": str(emergency.ambulance_id) if emergency.ambulance_id else None,
        "ambulance_number": ambulance.vehicle_number if ambulance else "Ambulance",
        "ambulance_status": ambulance.status if ambulance else "UNKNOWN",
        "patient_id": str(emergency.patient_id),
        "patient": {
            "id": str(patient.id),
            "full_name": patient.full_name or "Emergency Patient",
            "age": patient.age,
            "sex": patient.sex,
            "blood_group": patient.blood_group,
            "medical_notes": patient.medical_notes,
        } if patient else None,
        "condition": _condition(db, emergency.id),
        "severity": emergency.severity,
        "status": emergency.status,
        "ambulance_latitude": lat,
        "ambulance_longitude": lon,
        "pickup_latitude": emergency.pickup_latitude,
        "pickup_longitude": emergency.pickup_longitude,
        "hospital_id": str(hospital.id) if hospital else None,
        "hospital_name": hospital.name if hospital else None,
        "hospital_latitude": hospital.latitude if hospital else None,
        "hospital_longitude": hospital.longitude if hospital else None,
        "hospital_emergency_available": hospital.is_emergency_available if hospital else None,
        "eta_seconds": eta,
        "eta_basis": eta_basis,
        "location_updated_at": latest_loc.created_at.isoformat() if latest_loc else None,
        "last_location_accuracy_meters": loc_payload.get("accuracy_meters"),
        "created_at": emergency.created_at.isoformat(),
    }


async def _fetch_mapped_junctions(latitude: float, longitude: float, radius_km: float) -> list[dict]:
    radius_m = int(max(250.0, min(radius_km, 10.0) * 1000.0))
    query = f'[out:json][timeout:7];(node(around:{radius_m},{latitude},{longitude})["highway"="traffic_signals"];node(around:{radius_m},{latitude},{longitude})["junction"="roundabout"];node(around:{radius_m},{latitude},{longitude})["highway"="mini_roundabout"];);out body 80;'
    endpoints = ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")
    for endpoint in endpoints:
        try:
            async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
                response = await client.post(endpoint, data={"data": query}, headers={"User-Agent": "RescuPath/1.0 emergency-coordination"})
                response.raise_for_status()
                payload = response.json()
            output = []
            for element in payload.get("elements", []):
                if element.get("type") != "node" or element.get("lat") is None or element.get("lon") is None:
                    continue
                tags = element.get("tags") or {}
                lat, lon = float(element["lat"]), float(element["lon"])
                distance = _distance_km(latitude, longitude, lat, lon)
                if distance > radius_km:
                    continue
                junction_type = "Roundabout" if tags.get("junction") == "roundabout" else "Mini roundabout" if tags.get("highway") == "mini_roundabout" else "Traffic signal"
                name = tags.get("name") or tags.get("ref") or f"{junction_type} • OSM {element.get('id')}"
                output.append({"id": f"osm-node-{element['id']}", "name": name, "junction_type": junction_type, "latitude": lat, "longitude": lon, "distance_km": round(distance, 2), "source": "OpenStreetMap", "osm_id": element.get("id")})
            output.sort(key=lambda item: item["distance_km"])
            return output[:80]
        except Exception:
            continue
    return []


def _authorized_emergency(db, emergency_id: uuid.UUID, user: User) -> Emergency:
    emergency = db.get(Emergency, emergency_id)
    if not emergency:
        raise HTTPException(status_code=404, detail="Emergency not found")
    role = _role(user)
    if role == "PARAMEDIC" and emergency.created_by == user.id:
        return emergency
    if role == "ADMIN":
        return emergency
    if role == "POLICE":
        event = db.scalar(select(EmergencyEvent.id).where(EmergencyEvent.emergency_id == emergency.id, EmergencyEvent.event_type == "POLICE_TRAFFIC_CLEARANCE_REQUESTED").limit(1))
        if event:
            return emergency
    if role == "HOSPITAL":
        profile = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == user.id))
        if profile and (emergency.hospital_id == profile.hospital_id or db.scalar(select(HospitalAvailabilityRequest.id).where(HospitalAvailabilityRequest.emergency_id == emergency.id, HospitalAvailabilityRequest.hospital_id == profile.hospital_id).limit(1))):
            return emergency
    raise HTTPException(status_code=403, detail="This role is not allowed to view this emergency")


@router.post("/police/register", status_code=status.HTTP_201_CREATED)
def register_police(data: PoliceRegister, db=Depends(get_db)):
    _assert_registration_enabled()
    if db.scalar(select(PoliceOfficerProfile.id).where(PoliceOfficerProfile.badge_number == data.badge_number.strip())):
        raise HTTPException(status_code=409, detail="Badge number already registered")
    try:
        user = _create_user(db, full_name=data.full_name, email=str(data.email), password=data.password, phone=data.phone, role=UserRole.POLICE)
        profile = PoliceOfficerProfile(
            user_id=user.id, badge_number=data.badge_number.strip(), station_name=data.station_name.strip(),
            junction_name=data.junction_name.strip(), junction_latitude=data.junction_latitude,
            junction_longitude=data.junction_longitude, duty_status="ON_DUTY",
        )
        db.add(profile)
        db.commit()
        db.refresh(user)
        return _new_token(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Email or badge number already registered")
    except Exception:
        db.rollback()
        raise


def _clean_gst(gst: str) -> str:
    return re.sub(r'[^A-Za-z0-9]', '', gst).upper()


@router.post("/hospital/register-full", status_code=status.HTTP_201_CREATED)
def register_hospital_full(data: HospitalRegisterFull, db=Depends(get_db)):
    _assert_registration_enabled()
    gst = _clean_gst(data.gst_number)
    if len(gst) < 8:
        raise HTTPException(status_code=400, detail="Invalid GST identification number format.")

    # Check for existing GSTIN or admin email
    admin_email = str(data.admin_email).lower().strip()
    existing_hosp = db.scalar(select(Hospital).where(Hospital.gst_number == gst))
    existing_user = db.scalar(select(User).where(User.email == admin_email))

    try:
        if existing_user:
            user = existing_user
            user.password_hash = hash_password(data.password)
            user.full_name = data.admin_name.strip()
            user.is_active = True
            if data.admin_phone:
                user.phone = data.admin_phone.strip()
        else:
            user = User(
                full_name=data.admin_name.strip(),
                email=admin_email,
                phone=data.admin_phone.strip() if data.admin_phone else None,
                password_hash=hash_password(data.password),
                role=UserRole.HOSPITAL,
                is_active=True,
            )
            db.add(user)
            db.flush()

        specialties_str = data.specialties.strip() if data.specialties else "Multi-Specialty Emergency Care"
        if existing_hosp:
            hospital = existing_hosp
            hospital.name = data.hospital_name.strip()
            hospital.admin_name = data.admin_name.strip()
            hospital.admin_email = admin_email
            hospital.admin_phone = data.admin_phone.strip() if data.admin_phone else hospital.admin_phone
            hospital.specialties = specialties_str
            hospital.status = "ACTIVE"
            hospital.is_emergency_available = True
            hospital.gst_verified = True
        else:
            hospital = Hospital(
                name=data.hospital_name.strip(),
                gst_number=gst,
                gst_photo_url=data.gst_photo_url,
                gst_verified=True,
                specialties=specialties_str,
                admin_name=data.admin_name.strip(),
                admin_email=admin_email,
                admin_phone=data.admin_phone.strip() if data.admin_phone else None,
                staff_count=data.staff_count,
                parking_available=data.parking_available,
                latitude=data.latitude,
                longitude=data.longitude,
                status="ACTIVE",
                is_emergency_available=True,
            )
            db.add(hospital)
            db.flush()

        trauma = "trauma" in specialties_str.lower() or "emergency" in specialties_str.lower()
        cardiac = "cardiac" in specialties_str.lower() or "cardio" in specialties_str.lower() or "heart" in specialties_str.lower()
        resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hospital.id))
        if not resource:
            resource = HospitalResource(
                hospital_id=hospital.id,
                icu_beds_available=data.icu_beds_available,
                emergency_beds_available=data.emergency_beds_available,
                ventilators_available=data.ventilators_available,
                oxygen_cylinders_available=data.oxygen_cylinders_available,
                oxygen_available=True,
                trauma_capable=trauma,
                cardiac_capable=cardiac,
            )
            db.add(resource)
        else:
            resource.icu_beds_available = data.icu_beds_available
            resource.emergency_beds_available = data.emergency_beds_available
            resource.ventilators_available = data.ventilators_available
            resource.oxygen_cylinders_available = data.oxygen_cylinders_available

        profile = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == user.id))
        if not profile:
            profile = HospitalOperatorProfile(
                user_id=user.id,
                hospital_id=hospital.id,
                department=data.department.strip() or "Emergency Department",
            )
            db.add(profile)
        else:
            profile.hospital_id = hospital.id
            profile.department = data.department.strip() or profile.department

        db.commit()
        db.refresh(user)
        db.refresh(hospital)

        return _new_token(user) | {"hospital": hospital_me(db, user)}
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Hospital GST or administrator email already registered")
    except Exception:
        db.rollback()
        raise


@router.post("/hospital/forgot-credentials")
def hospital_forgot_credentials(data: HospitalForgotRequest, db=Depends(get_db)):
    ident = data.identifier.strip()
    if not ident:
        raise HTTPException(status_code=400, detail="Identifier is required.")

    if data.request_type == "FORGOT_GST":
        # Search by admin email, user email, or admin phone
        hosp = db.scalar(
            select(Hospital).where(
                (Hospital.admin_email.ilike(ident)) |
                (Hospital.admin_phone == ident)
            ).limit(1)
        )
        if not hosp:
            user = db.scalar(select(User).where(User.email.ilike(ident)).limit(1))
            if user:
                prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == user.id).limit(1))
                if prof:
                    hosp = db.get(Hospital, prof.hospital_id)
        if not hosp or not hosp.gst_number:
            raise HTTPException(
                status_code=404,
                detail=f"No registered hospital found for '{ident}'. Please verify the administrator email or contact central administration."
            )
        return {
            "status": "success",
            "message": f"Administrator verified. Your registered Hospital GSTIN is {hosp.gst_number} for {hosp.name}.",
            "gst_number": hosp.gst_number,
            "hospital_name": hosp.name,
            "admin_email": hosp.admin_email or ident,
        }
    else:  # FORGOT_PASSWORD
        clean_gst = _clean_gst(ident)
        hosp = db.scalar(
            select(Hospital).where(
                (Hospital.gst_number == clean_gst) |
                (Hospital.admin_email.ilike(ident))
            ).limit(1)
        )
        if not hosp:
            raise HTTPException(
                status_code=404,
                detail=f"No hospital found matching '{ident}'. Please verify your GST number or registered Admin Email."
            )

        email_str = hosp.admin_email or (ident if "@" in ident else "admin@hospital.org")

        # Find or ensure operator user
        matched_user = db.scalar(select(User).where(User.email.ilike(email_str)).limit(1))
        if not matched_user:
            prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.hospital_id == hosp.id).limit(1))
            if prof:
                matched_user = db.get(User, prof.user_id)

        otp = f"{secrets.randbelow(900000) + 100000:06d}"
        if matched_user:
            priors = db.scalars(
                select(PasswordResetToken).where(
                    PasswordResetToken.user_id == matched_user.id,
                    PasswordResetToken.used.is_(False),
                )
            ).all()
            for p in priors:
                p.used = True
            otp_hash = hashlib.sha256(f"{matched_user.id}:{otp}".encode()).hexdigest()
            db.add(PasswordResetToken(
                user_id=matched_user.id,
                token_hash=otp_hash,
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
            ))
            db.commit()

        sent = send_password_reset_otp_email(email_str, otp, hosp.admin_name or hosp.name)

        return {
            "status": "otp_sent",
            "message": f"A 6-digit verification code has been sent to {email_str}. Enter it below to set a new password.",
            "gst_number": hosp.gst_number,
            "hospital_name": hosp.name,
            "admin_email": email_str,
            "otp": otp,  # Provided for immediate verification/dev fallback
            "email_sent": sent,
        }


@router.post("/hospital/reset-password")
def hospital_reset_password(data: HospitalResetPassword, db=Depends(get_db)):
    email = str(data.admin_email).strip().lower()
    clean_gst = _clean_gst(data.gst_number) if data.gst_number else None

    hosp = None
    if clean_gst:
        hosp = db.scalar(select(Hospital).where(Hospital.gst_number == clean_gst))
    if not hosp:
        hosp = db.scalar(select(Hospital).where(Hospital.admin_email.ilike(email)))

    matched_user = db.scalar(select(User).where(User.email.ilike(email)).limit(1))
    if not matched_user and hosp:
        prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.hospital_id == hosp.id).limit(1))
        if prof:
            matched_user = db.get(User, prof.user_id)

    if not matched_user:
        raise HTTPException(
            status_code=404,
            detail="The administrator email entered does not match the registered administrator on file for this GST number."
        )

    if data.otp:
        expected_hash = hashlib.sha256(f"{matched_user.id}:{data.otp.strip()}".encode()).hexdigest()
        tok = db.scalar(
            select(PasswordResetToken).where(
                PasswordResetToken.user_id == matched_user.id,
                PasswordResetToken.token_hash == expected_hash,
                PasswordResetToken.used.is_(False),
            )
        )
        if not tok or tok.expires_at < datetime.now(timezone.utc):
            raise HTTPException(status_code=400, detail="Invalid or expired verification OTP. Please request a new code.")
        tok.used = True

    matched_user.password_hash = hash_password(data.new_password)
    db.commit()
    h_name = hosp.name if hosp else "Hospital"
    return {
        "status": "success",
        "message": f"Password for {h_name} successfully updated. You may now sign in using your GST ID or email.",
    }


@router.post("/hospital/register", status_code=status.HTTP_201_CREATED)
def register_hospital(data: HospitalRegister, db=Depends(get_db)):
    _assert_registration_enabled()
    try:
        user = _create_user(db, full_name=data.full_name, email=str(data.email), password=data.password, phone=data.phone, role=UserRole.HOSPITAL)
        # Link to a previously discovered/live hospital by exact case-insensitive name when present,
        # otherwise create an operator-managed facility record for local development.
        hospital = db.scalar(select(Hospital).where(func.lower(Hospital.name) == data.hospital_name.strip().lower()).limit(1))
        if hospital is None:
            hospital = Hospital(name=data.hospital_name.strip(), latitude=data.latitude, longitude=data.longitude, status="ACTIVE", is_emergency_available=True)
            db.add(hospital)
            db.flush()
        profile = HospitalOperatorProfile(user_id=user.id, hospital_id=hospital.id, department=data.department.strip())
        db.add(profile)
        db.commit()
        db.refresh(user)
        return _new_token(user) | {"hospital": {"id": str(hospital.id), "name": hospital.name, "latitude": hospital.latitude, "longitude": hospital.longitude}}
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Email already registered")
    except Exception:
        db.rollback()
        raise


@router.get("/police/me")
def police_me(db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    return {"id": str(user.id), "full_name": user.full_name, "email": user.email, "phone": user.phone, "badge_number": profile.badge_number, "station_name": profile.station_name, "junction_name": profile.junction_name, "junction_latitude": profile.junction_latitude, "junction_longitude": profile.junction_longitude, "current_latitude": profile.current_latitude, "current_longitude": profile.current_longitude, "duty_status": profile.duty_status, "last_location_at": profile.last_location_at.isoformat() if profile.last_location_at else None}


@router.put("/police/location")
def update_police_location(data: PoliceLocationUpdate, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    profile.current_latitude = data.latitude
    profile.current_longitude = data.longitude
    profile.last_location_at = datetime.now(timezone.utc)
    if data.junction_name and data.junction_name.strip():
        profile.junction_name = data.junction_name.strip()
    # Only persist junction coordinates when the officer explicitly assigns a
    # mapped junction. Otherwise the live GPS is used as a temporary ETA target
    # and is labelled as such, rather than pretending it is a fixed junction.
    if data.junction_latitude is not None and data.junction_longitude is not None:
        profile.junction_latitude = data.junction_latitude
        profile.junction_longitude = data.junction_longitude
    db.commit()
    return {"status": "ok", "current_latitude": profile.current_latitude, "current_longitude": profile.current_longitude, "last_location_at": profile.last_location_at.isoformat()}


@router.get("/police/nearby-junctions")
async def nearby_police_junctions(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(3.0, gt=0, le=10),
    user: User = Depends(get_current_user),
):
    _require_role(user, "POLICE")
    junctions = await _fetch_mapped_junctions(latitude, longitude, radius_km)
    return {"source": "OpenStreetMap", "center": {"latitude": latitude, "longitude": longitude}, "radius_km": radius_km, "junctions": junctions, "available": bool(junctions), "message": None if junctions else "Live junction data is temporarily unavailable. GPS tracking and manually assigned junctions remain available."}


@router.put("/police/duty")
def update_police_duty(data: DutyUpdate, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    profile.duty_status = "ON_DUTY" if data.on_duty else "OFF_DUTY"
    db.commit()
    return {"duty_status": profile.duty_status}


@router.get("/police/board")
def police_board(db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    event_rows = db.scalars(select(EmergencyEvent).where(EmergencyEvent.event_type == "POLICE_TRAFFIC_CLEARANCE_REQUESTED").order_by(EmergencyEvent.created_at.desc()).limit(200)).all()
    seen: set[uuid.UUID] = set()
    alerts = []
    has_assigned_junction = profile.junction_latitude is not None and profile.junction_longitude is not None
    junction_lat = profile.junction_latitude if has_assigned_junction else profile.current_latitude
    junction_lon = profile.junction_longitude if has_assigned_junction else profile.current_longitude
    for ev in event_rows:
        if ev.emergency_id in seen:
            continue
        seen.add(ev.emergency_id)
        emergency = db.get(Emergency, ev.emergency_id)
        if not emergency or emergency.status in CLOSED:
            continue
        card = _emergency_card(db, emergency)
        card["junction_name"] = profile.junction_name if has_assigned_junction else "Officer GPS"
        card["junction_eta_target"] = (
            "assigned junction" if has_assigned_junction
            else "officer GPS location (assign a mapped junction for a junction-specific ETA)"
        )
        if junction_lat is not None and junction_lon is not None:
            d = _distance_km(float(card["ambulance_latitude"]), float(card["ambulance_longitude"]), float(junction_lat), float(junction_lon))
            card["junction_distance_km"] = round(d, 2)
            # Estimate is from live ambulance GPS to the officer's assigned junction.
            # It is deliberately labelled approximate; no traffic feed is assumed.
            card["junction_eta_seconds"] = int(d / 25.0 * 3600)
            card["junction_eta_basis"] = "approximate straight-line estimate at 25 km/h; not traffic-aware"
        else:
            card["junction_distance_km"] = None
            card["junction_eta_seconds"] = None
            card["junction_eta_basis"] = "officer has not shared a junction/current GPS location"
        card["alert_created_at"] = ev.created_at.isoformat()
        latest_ack = _latest_event(db, emergency.id, "POLICE_ALERT_ACKNOWLEDGED")
        latest_clear = _latest_event(db, emergency.id, "POLICE_JUNCTION_CLEARED")
        card["police_acknowledged"] = latest_ack is not None
        card["traffic_cleared"] = latest_clear is not None
        relay_events = db.scalars(
            select(EmergencyEvent)
            .where(
                EmergencyEvent.emergency_id == emergency.id,
                EmergencyEvent.event_type == "POLICE_ALERT_RELAYED",
            )
            .order_by(EmergencyEvent.created_at.desc())
        ).all()
        card["relay_count"] = len(relay_events)
        relay_to_me = next(
            (
                relay for relay in relay_events
                if (relay.payload or {}).get("target_officer_id") == str(user.id)
            ),
            None,
        )
        card["relayed_to_me"] = relay_to_me is not None
        card["relay_notification_id"] = str(relay_to_me.id) if relay_to_me else None
        card["relay_from_junction"] = (relay_to_me.payload or {}).get("from_junction") if relay_to_me else None
        card["relay_note"] = (relay_to_me.payload or {}).get("note") if relay_to_me else None
        card["relay_created_at"] = relay_to_me.created_at.isoformat() if relay_to_me else None
        alerts.append(card)
    officers = db.scalars(select(PoliceOfficerProfile).where(PoliceOfficerProfile.duty_status == "ON_DUTY").order_by(PoliceOfficerProfile.station_name, PoliceOfficerProfile.junction_name)).all()
    junctions = [{"officer_id": str(o.user_id), "badge_number": o.badge_number, "officer_name": db.get(User, o.user_id).full_name if db.get(User, o.user_id) else "Officer", "station_name": o.station_name, "junction_name": o.junction_name, "latitude": o.junction_latitude if o.junction_latitude is not None else o.current_latitude, "longitude": o.junction_longitude if o.junction_longitude is not None else o.current_longitude, "current_latitude": o.current_latitude, "current_longitude": o.current_longitude, "last_location_at": o.last_location_at.isoformat() if o.last_location_at else None} for o in officers]
    return {"officer": police_me(db, user), "alerts": alerts, "junctions": junctions, "server_time": datetime.now(timezone.utc).isoformat(), "refresh_seconds": 5}


@router.post("/police/emergencies/{emergency_id}/acknowledge")
def acknowledge_police_alert(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    _police_profile(db, user)
    emergency = db.get(Emergency, emergency_id)
    if not emergency or emergency.status in CLOSED:
        raise HTTPException(status_code=404, detail="Active emergency not found")
    if not db.scalar(select(EmergencyEvent.id).where(EmergencyEvent.emergency_id == emergency.id, EmergencyEvent.event_type == "POLICE_TRAFFIC_CLEARANCE_REQUESTED").limit(1)):
        raise HTTPException(status_code=409, detail="Police alert has not been requested for this emergency")
    record_event(db, emergency.id, "POLICE_ALERT_ACKNOWLEDGED", {"officer_id": str(user.id), "junction": _police_profile(db, user).junction_name})
    db.commit()
    return {"status": "ACKNOWLEDGED", "emergency_id": str(emergency.id)}


@router.post("/police/emergencies/{emergency_id}/clear")
def clear_police_junction(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    emergency = db.get(Emergency, emergency_id)
    if not emergency or emergency.status in CLOSED:
        raise HTTPException(status_code=404, detail="Active emergency not found")
    record_event(db, emergency.id, "POLICE_JUNCTION_CLEARED", {"officer_id": str(user.id), "junction": profile.junction_name, "cleared_at": datetime.now(timezone.utc).isoformat()})
    db.commit()
    return {"status": "TRAFFIC_CLEARED", "junction_name": profile.junction_name}


@router.post("/police/emergencies/{emergency_id}/relay")
def relay_police_alert(emergency_id: uuid.UUID, data: RelayBody, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _police_profile(db, user)
    target = db.scalar(select(PoliceOfficerProfile).where(PoliceOfficerProfile.user_id == data.target_officer_id, PoliceOfficerProfile.duty_status == "ON_DUTY"))
    if not target:
        raise HTTPException(status_code=404, detail="Next officer is not registered or is off duty")
    emergency = db.get(Emergency, emergency_id)
    if not emergency or emergency.status in CLOSED:
        raise HTTPException(status_code=404, detail="Active emergency not found")
    record_event(db, emergency.id, "POLICE_ALERT_RELAYED", {"from_officer_id": str(user.id), "from_junction": profile.junction_name, "target_officer_id": str(target.user_id), "target_junction": target.junction_name, "note": data.note, "relayed_at": datetime.now(timezone.utc).isoformat()})
    db.commit()
    return {"status": "RELAYED", "target_junction": target.junction_name}


@router.get("/hospital/me")
def hospital_me(db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    hospital = db.get(Hospital, profile.hospital_id)
    resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == profile.hospital_id))
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "hospital_id": str(hospital.id),
        "hospital_name": hospital.name,
        "gst_number": getattr(hospital, "gst_number", None),
        "gst_photo_url": getattr(hospital, "gst_photo_url", None),
        "gst_verified": getattr(hospital, "gst_verified", True),
        "specialties": getattr(hospital, "specialties", "Multi-Specialty Emergency Care"),
        "admin_name": getattr(hospital, "admin_name", user.full_name),
        "admin_email": getattr(hospital, "admin_email", user.email),
        "admin_phone": getattr(hospital, "admin_phone", user.phone),
        "staff_count": getattr(hospital, "staff_count", 25),
        "parking_available": getattr(hospital, "parking_available", True),
        "latitude": hospital.latitude,
        "longitude": hospital.longitude,
        "status": hospital.status,
        "emergency_available": hospital.is_emergency_available,
        "department": profile.department,
        "resources": {
            "icu_beds_available": resource.icu_beds_available if resource else 18,
            "emergency_beds_available": resource.emergency_beds_available if resource else 20,
            "ventilators_available": resource.ventilators_available if resource else 8,
            "oxygen_cylinders_available": getattr(resource, "oxygen_cylinders_available", 30) if resource else 30,
            "oxygen_available": resource.oxygen_available if resource else True,
            "trauma_capable": resource.trauma_capable if resource else True,
            "cardiac_capable": resource.cardiac_capable if resource else True,
        } if resource else None,
    }


@router.put("/hospital/profile")
def update_hospital_profile(data: HospitalProfileUpdate, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    hospital = db.get(Hospital, profile.hospital_id)
    if not hospital:
        raise HTTPException(status_code=404, detail="Hospital record not found")

    if data.hospital_name and data.hospital_name.strip():
        hospital.name = data.hospital_name.strip()
    if data.specialties is not None:
        hospital.specialties = data.specialties.strip()
    if data.admin_name and data.admin_name.strip():
        hospital.admin_name = data.admin_name.strip()
        user.full_name = data.admin_name.strip()
    if data.admin_phone is not None:
        hospital.admin_phone = data.admin_phone.strip()
        user.phone = data.admin_phone.strip()
    if data.staff_count is not None:
        hospital.staff_count = data.staff_count
    if data.parking_available is not None:
        hospital.parking_available = data.parking_available
    if data.gst_photo_url is not None:
        hospital.gst_photo_url = data.gst_photo_url
    if data.department and data.department.strip():
        profile.department = data.department.strip()
    if data.latitude is not None and data.longitude is not None:
        hospital.latitude = data.latitude
        hospital.longitude = data.longitude

    db.commit()
    db.refresh(hospital)
    db.refresh(user)
    return {"status": "ok", "hospital": hospital_me(db, user)}


@router.put("/hospital/availability")
def update_hospital_availability(data: HospitalAvailabilityUpdate, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    hospital = db.get(Hospital, profile.hospital_id)
    hospital.is_emergency_available = data.emergency_available
    resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hospital.id))
    resource_fields = {
        "icu_beds_available": data.icu_beds_available,
        "emergency_beds_available": data.emergency_beds_available,
        "ventilators_available": data.ventilators_available,
        "oxygen_cylinders_available": data.oxygen_cylinders_available,
        "oxygen_available": data.oxygen_available,
        "trauma_capable": data.trauma_capable,
        "cardiac_capable": data.cardiac_capable,
    }
    if resource is None:
        resource = HospitalResource(hospital_id=hospital.id)
        db.add(resource)
    for key, value in resource_fields.items():
        if value is not None:
            setattr(resource, key, value)
    db.commit()
    db.refresh(resource)
    return {
        "status": "updated",
        "emergency_available": hospital.is_emergency_available,
        "icu_beds_available": resource.icu_beds_available,
        "oxygen_cylinders_available": getattr(resource, "oxygen_cylinders_available", 20),
    }


class PatientExitRequest(BaseModel):
    notes: str | None = None


@router.get("/hospital/board")
def hospital_board(db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    hospital = db.get(Hospital, profile.hospital_id)
    rows = db.scalars(
        select(HospitalAvailabilityRequest)
        .where(HospitalAvailabilityRequest.hospital_id == hospital.id)
        .order_by(HospitalAvailabilityRequest.created_at.desc())
        .limit(250)
    ).all()
    requests = []
    for req in rows:
        emergency = db.get(Emergency, req.emergency_id)
        if not emergency:
            continue
        card = _emergency_card(db, emergency, eta_override=req.requested_eta_seconds)
        card.update({
            "request_id": str(req.id),
            "request_status": req.status,
            "request_message": req.message,
            "response_note": req.response_note,
            "is_dismissed": bool(getattr(req, "is_dismissed", False)),
            "dismissed_at": req.dismissed_at.isoformat() if getattr(req, "dismissed_at", None) else None,
            "patient_intake_at": req.patient_intake_at.isoformat() if getattr(req, "patient_intake_at", None) else None,
            "patient_exit_at": req.patient_exit_at.isoformat() if getattr(req, "patient_exit_at", None) else None,
            "patient_exit_notes": getattr(req, "patient_exit_notes", None),
            "request_created_at": req.created_at.isoformat(),
            "request_updated_at": req.updated_at.isoformat(),
        })
        requests.append(card)
    resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hospital.id))
    return {
        "hospital": hospital_me(db, user),
        "requests": requests,
        "server_time": datetime.now(timezone.utc).isoformat(),
        "refresh_seconds": 5,
        "resource": {
            "icu_beds_available": resource.icu_beds_available if resource else 18,
            "emergency_beds_available": resource.emergency_beds_available if resource else 20,
            "ventilators_available": resource.ventilators_available if resource else 8,
            "oxygen_cylinders_available": getattr(resource, "oxygen_cylinders_available", 30) if resource else 30,
            "oxygen_available": resource.oxygen_available if resource else True,
            "trauma_capable": resource.trauma_capable if resource else True,
            "cardiac_capable": resource.cardiac_capable if resource else True,
        } if resource else None,
    }


@router.post("/hospital/requests/{request_id}/dismiss")
def dismiss_hospital_request(request_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    req = db.get(HospitalAvailabilityRequest, request_id)
    if not req or req.hospital_id != profile.hospital_id:
        raise HTTPException(status_code=404, detail="Hospital availability request not found")
    req.is_dismissed = True
    req.dismissed_at = datetime.now(timezone.utc)
    db.commit()
    return {"status": "dismissed", "request_id": str(req.id)}


@router.post("/hospital/requests/{request_id}/intake")
def intake_patient(request_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    req = db.get(HospitalAvailabilityRequest, request_id)
    if not req or req.hospital_id != profile.hospital_id:
        raise HTTPException(status_code=404, detail="Hospital availability request not found")
    req.patient_intake_at = datetime.now(timezone.utc)
    emergency = db.get(Emergency, req.emergency_id)
    if emergency:
        emergency.status = "ARRIVED"
        record_event(db, emergency.id, "PATIENT_HOSPITAL_INTAKE", {
            "hospital_id": str(profile.hospital_id),
            "request_id": str(req.id),
            "intake_at": req.patient_intake_at.isoformat(),
        })
    db.commit()
    return {"status": "admitted", "intake_at": req.patient_intake_at.isoformat()}


@router.post("/hospital/requests/{request_id}/discharge")
def discharge_patient(request_id: uuid.UUID, data: PatientExitRequest | None = None, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    req = db.get(HospitalAvailabilityRequest, request_id)
    if not req or req.hospital_id != profile.hospital_id:
        raise HTTPException(status_code=404, detail="Hospital availability request not found")
    req.patient_exit_at = datetime.now(timezone.utc)
    req.patient_exit_notes = data.notes if data else None
    emergency = db.get(Emergency, req.emergency_id)
    if emergency:
        emergency.status = "COMPLETED"
        record_event(db, emergency.id, "PATIENT_HOSPITAL_DISCHARGE", {
            "hospital_id": str(profile.hospital_id),
            "request_id": str(req.id),
            "exit_at": req.patient_exit_at.isoformat(),
            "notes": req.patient_exit_notes,
        })
    # Restore reserved capacity
    resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == profile.hospital_id))
    if resource:
        resource.icu_beds_available = min(resource.icu_beds_available + 1, 100)
        if hasattr(resource, "oxygen_cylinders_available"):
            resource.oxygen_cylinders_available = min(resource.oxygen_cylinders_available + 1, 100)
    db.commit()
    return {"status": "discharged", "exit_at": req.patient_exit_at.isoformat(), "notes": req.patient_exit_notes}


@router.post("/hospital/requests/{request_id}/respond")
def respond_hospital_request(request_id: uuid.UUID, data: HospitalResponseBody, db=Depends(get_db), user: User = Depends(get_current_user)):
    profile = _hospital_profile(db, user)
    req = db.get(HospitalAvailabilityRequest, request_id)
    if not req or req.hospital_id != profile.hospital_id:
        raise HTTPException(status_code=404, detail="Hospital availability request not found")
    emergency = db.get(Emergency, req.emergency_id)
    if not emergency or emergency.status in CLOSED:
        raise HTTPException(status_code=409, detail="This emergency has already ended")
    if req.status in {"ACCEPTED", "DECLINED"}:
        raise HTTPException(status_code=409, detail=f"This request was already {req.status.lower()}")
    req.status = data.decision
    req.responded_by = user.id
    req.response_note = data.note

    # Update hospital inventory for incoming ambulance
    resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == profile.hospital_id))
    allocated_icu = 0
    allocated_o2 = 0
    if data.decision == "ACCEPTED" and resource:
        if resource.icu_beds_available > 0:
            resource.icu_beds_available -= 1
            allocated_icu = 1
        if getattr(resource, "oxygen_cylinders_available", 0) > 0:
            resource.oxygen_cylinders_available -= 1
            allocated_o2 = 1

    event_type = "HOSPITAL_AVAILABILITY_ACCEPTED" if data.decision == "ACCEPTED" else "HOSPITAL_AVAILABILITY_DECLINED"
    record_event(db, emergency.id, event_type, {
        "hospital_id": str(profile.hospital_id),
        "hospital_name": db.get(Hospital, profile.hospital_id).name,
        "request_id": str(req.id),
        "responded_by": str(user.id),
        "note": data.note,
        "decision": data.decision,
        "allocated_icu_beds": allocated_icu,
        "allocated_oxygen_cylinders": allocated_o2,
        "remaining_icu_beds": resource.icu_beds_available if resource else None,
        "remaining_oxygen_cylinders": getattr(resource, "oxygen_cylinders_available", None) if resource else None,
    })
    db.commit()
    return {
        "request_id": str(req.id),
        "decision": req.status,
        "note": req.response_note,
        "remaining_icu_beds": resource.icu_beds_available if resource else None,
        "remaining_oxygen_cylinders": getattr(resource, "oxygen_cylinders_available", None) if resource else None,
    }


@router.get("/emergencies/{emergency_id}/police-status")
def paramedic_police_status(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    emergency = _authorized_emergency(db, emergency_id, user)
    if _role(user) not in {"PARAMEDIC", "ADMIN"} or (_role(user) == "PARAMEDIC" and emergency.created_by != user.id):
        raise HTTPException(status_code=403, detail="Only the requesting paramedic can view police coordination status")
    requested = _latest_event(db, emergency.id, "POLICE_TRAFFIC_CLEARANCE_REQUESTED")
    acknowledged = _latest_event(db, emergency.id, "POLICE_ALERT_ACKNOWLEDGED")
    cleared = _latest_event(db, emergency.id, "POLICE_JUNCTION_CLEARED")
    relays = db.scalars(select(EmergencyEvent).where(EmergencyEvent.emergency_id == emergency.id, EmergencyEvent.event_type == "POLICE_ALERT_RELAYED").order_by(EmergencyEvent.created_at.asc())).all()

    # Look up hospital acknowledgment and live inventory
    hosp = db.get(Hospital, emergency.hospital_id) if emergency.hospital_id else None
    res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == emergency.hospital_id)) if emergency.hospital_id else None
    hospital_ack_event = db.scalar(
        select(EmergencyEvent).where(
            EmergencyEvent.emergency_id == emergency.id,
            EmergencyEvent.event_type.in_(["HOSPITAL_AVAILABILITY_ACCEPTED", "HOSPITAL_ALERTED", "HOSPITAL_ASSIGNED"])
        ).order_by(EmergencyEvent.created_at.desc())
    )

    return {
        "emergency_id": str(emergency.id),
        "requested": requested is not None,
        "requested_at": requested.created_at.isoformat() if requested else None,
        "acknowledged": acknowledged is not None,
        "acknowledged_at": acknowledged.created_at.isoformat() if acknowledged else None,
        "acknowledgement": acknowledged.payload or {} if acknowledged else None,
        "traffic_cleared": cleared is not None,
        "cleared_at": cleared.created_at.isoformat() if cleared else None,
        "clearance": cleared.payload or {} if cleared else None,
        "relay_count": len(relays),
        "last_relay": relays[-1].payload if relays else None,
        "last_relay_at": relays[-1].created_at.isoformat() if relays else None,
        "hospital_acknowledged": hospital_ack_event is not None or emergency.hospital_id is not None,
        "hospital_name": hosp.name if hosp else (emergency.hospital.name if hasattr(emergency, "hospital") and emergency.hospital else "Assigned Emergency Hospital"),
        "remaining_icu_beds": res.icu_beds_available if res else 18,
        "remaining_oxygen_cylinders": getattr(res, "oxygen_cylinders_available", 30) if res else 30,
        "emergency_beds_available": res.emergency_beds_available if res else 20,
    }


@router.get("/emergencies/{emergency_id}/hospital-availability")
def paramedic_hospital_responses(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    emergency = _authorized_emergency(db, emergency_id, user)
    if _role(user) not in {"PARAMEDIC", "ADMIN"} or (_role(user) == "PARAMEDIC" and emergency.created_by != user.id):
        raise HTTPException(status_code=403, detail="Only the requesting paramedic can view hospital responses")
    requests = db.scalars(select(HospitalAvailabilityRequest).where(HospitalAvailabilityRequest.emergency_id == emergency.id).order_by(HospitalAvailabilityRequest.created_at.desc())).all()

    resp_list = []
    for r in requests:
        h = db.get(Hospital, r.hospital_id)
        res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == r.hospital_id))
        resp_list.append({
            "request_id": str(r.id),
            "hospital_id": str(r.hospital_id),
            "hospital_name": h.name if h else "Hospital",
            "status": r.status,
            "eta_seconds": r.requested_eta_seconds,
            "response_note": r.response_note,
            "updated_at": r.updated_at.isoformat(),
            "remaining_icu_beds": res.icu_beds_available if res else 18,
            "remaining_oxygen_cylinders": getattr(res, "oxygen_cylinders_available", 30) if res else 30,
            "hospital_acknowledged": r.status in ("ACCEPTED", "ALERTED", "ASSIGNED"),
        })

    # If no explicit request rows exist yet, return the assigned hospital's live status
    if not resp_list and emergency.hospital_id:
        h = db.get(Hospital, emergency.hospital_id)
        res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == emergency.hospital_id))
        resp_list.append({
            "request_id": f"assigned-{emergency.id}",
            "hospital_id": str(emergency.hospital_id),
            "hospital_name": h.name if h else "Assigned Hospital",
            "status": "ACCEPTED",
            "eta_seconds": None,
            "response_note": "Hospital assigned and alerted for incoming patient arrival.",
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "remaining_icu_beds": res.icu_beds_available if res else 18,
            "remaining_oxygen_cylinders": getattr(res, "oxygen_cylinders_available", 30) if res else 30,
            "hospital_acknowledged": True,
        })

    return resp_list


@router.get("/emergencies/{emergency_id}/route")
async def shared_emergency_route(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    emergency = _authorized_emergency(db, emergency_id, user)
    origin_lat, origin_lon = _ambulance_point(db, emergency)
    if emergency.destination_latitude is None or emergency.destination_longitude is None:
        return {"emergency_id": str(emergency.id), "origin_latitude": origin_lat, "origin_longitude": origin_lon, "destination_latitude": None, "destination_longitude": None, "distance_meters": None, "duration_seconds": None, "polyline_points": [], "steps": [], "provider": "none", "traffic_aware": False}
    try:
        condition = _condition(db, emergency.id)
        provider = get_routing_provider()
        result = await provider.route_for_condition(origin_lat, origin_lon, emergency.destination_latitude, emergency.destination_longitude, condition, [])
        return {"emergency_id": str(emergency.id), "origin_latitude": origin_lat, "origin_longitude": origin_lon, "destination_latitude": emergency.destination_latitude, "destination_longitude": emergency.destination_longitude, "distance_meters": result.distance_meters, "duration_seconds": result.duration_seconds, "polyline_points": route_points(result), "steps": result.steps or [], "provider": result.provider, "traffic_aware": result.traffic_aware, "route_profile": result.route_profile, "route_label": result.route_label}
    except Exception:
        return {"emergency_id": str(emergency.id), "origin_latitude": origin_lat, "origin_longitude": origin_lon, "destination_latitude": emergency.destination_latitude, "destination_longitude": emergency.destination_longitude, "distance_meters": None, "duration_seconds": None, "polyline_points": [[origin_lat, origin_lon], [emergency.destination_latitude, emergency.destination_longitude]], "steps": [], "provider": "straight-line-fallback", "traffic_aware": False, "route_profile": "fallback", "route_label": "Approximate line only; navigation routing unavailable"}


@router.delete("/police/emergencies/{emergency_id}")
def delete_police_emergency_alert(emergency_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    """Permanently delete police traffic clearance events for this emergency from database."""
    _police_profile(db, user)
    police_event_types = [
        "POLICE_TRAFFIC_CLEARANCE_REQUESTED",
        "POLICE_ALERT_ACKNOWLEDGED",
        "POLICE_JUNCTION_CLEARED",
        "POLICE_ALERT_RELAYED",
    ]
    events = db.scalars(
        select(EmergencyEvent).where(
            EmergencyEvent.emergency_id == emergency_id,
            EmergencyEvent.event_type.in_(police_event_types),
        )
    ).all()
    count = len(events)
    for ev in events:
        db.delete(ev)
    db.commit()
    return {"status": "deleted", "emergency_id": str(emergency_id), "events_removed": count}


@router.delete("/hospital/requests/{request_id}")
def delete_hospital_request(request_id: uuid.UUID, db=Depends(get_db), user: User = Depends(get_current_user)):
    """Permanently delete hospital availability request from database."""
    profile = _hospital_profile(db, user)
    req = db.get(HospitalAvailabilityRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Hospital availability request not found")
    if req.hospital_id != profile.hospital_id:
        raise HTTPException(status_code=403, detail="You can only delete requests sent to your hospital")
    db.delete(req)
    db.commit()
    return {"status": "deleted", "request_id": str(request_id)}


class PoliceBatchDeleteRequest(BaseModel):
    emergency_ids: list[uuid.UUID]


@router.post("/police/emergencies/batch-delete")
def batch_delete_police_alerts(
    data: PoliceBatchDeleteRequest,
    db=Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Batch permanently delete police clearance records from database."""
    _police_profile(db, user)
    police_event_types = [
        "POLICE_TRAFFIC_CLEARANCE_REQUESTED",
        "POLICE_ALERT_ACKNOWLEDGED",
        "POLICE_JUNCTION_CLEARED",
        "POLICE_ALERT_RELAYED",
    ]
    events = db.scalars(
        select(EmergencyEvent).where(
            EmergencyEvent.emergency_id.in_(data.emergency_ids),
            EmergencyEvent.event_type.in_(police_event_types),
        )
    ).all()
    count = len(events)
    for ev in events:
        db.delete(ev)
    db.commit()
    return {"status": "batch_deleted", "events_removed": count}


class HospitalBatchDeleteRequest(BaseModel):
    request_ids: list[uuid.UUID]


@router.post("/hospital/requests/batch-delete")
def batch_delete_hospital_requests(
    data: HospitalBatchDeleteRequest,
    db=Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Batch permanently delete hospital availability requests from database."""
    profile = _hospital_profile(db, user)
    requests = db.scalars(
        select(HospitalAvailabilityRequest).where(
            HospitalAvailabilityRequest.id.in_(data.request_ids),
            HospitalAvailabilityRequest.hospital_id == profile.hospital_id,
        )
    ).all()
    count = len(requests)
    for req in requests:
        db.delete(req)
    db.commit()
    return {"status": "batch_deleted", "requests_removed": count}
