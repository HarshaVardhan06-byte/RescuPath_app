"""Seed local and cloud demo hospitals, resources, and agency accounts.
Restores all authentic local development user accounts, hospitals, and ambulances.
"""
import json
import sys
import uuid
from pathlib import Path

# Ensure backend root is on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.ambulance import Ambulance
from app.models.hospital import Hospital
from app.models.hospital_operator import HospitalOperatorProfile
from app.models.hospital_resource import HospitalResource
from app.models.paramedic import ParamedicProfile
from app.models.police_officer import PoliceOfficerProfile
from app.models.user import User, UserRole

BACKUP_FILE = Path(__file__).resolve().parents[1] / "app" / "db" / "local_backup.json"


def seed():
    default_pwd_hash = hash_password("password123")

    with SessionLocal() as db:
        # Check if authentic local backup data exists
        if BACKUP_FILE.exists():
            try:
                with open(BACKUP_FILE, "r", encoding="utf-8") as f:
                    backup = json.load(f)

                # 1. Restore all authentic Users with their exact original passwords
                for u in backup.get("users", []):
                    user = db.scalar(select(User).where(User.email == u["email"].lower().strip()))
                    role_str = u["role"].split(".")[-1] if "." in u["role"] else u["role"]
                    role = UserRole[role_str] if role_str in UserRole.__members__ else UserRole.PARAMEDIC
                    if not user:
                        user = User(
                            id=uuid.UUID(u["id"]),
                            full_name=u["full_name"],
                            email=u["email"].lower().strip(),
                            phone=u.get("phone"),
                            password_hash=u["password_hash"],
                            role=role,
                            is_active=u.get("is_active", True),
                        )
                        db.add(user)
                    else:
                        user.password_hash = u["password_hash"]
                        user.is_active = u.get("is_active", True)
                db.commit()

                # 2. Restore all authentic Hospitals with their exact GST numbers
                for h in backup.get("hospitals", []):
                    hosp = None
                    if h.get("gst_number"):
                        hosp = db.scalar(select(Hospital).where(Hospital.gst_number == h["gst_number"].strip().upper()))
                    if not hosp:
                        hosp = db.scalar(select(Hospital).where(Hospital.name == h["name"]))

                    if not hosp:
                        hosp = Hospital(
                            id=uuid.UUID(h["id"]),
                            name=h["name"],
                            gst_number=h.get("gst_number").strip().upper() if h.get("gst_number") else None,
                            latitude=h["latitude"],
                            longitude=h["longitude"],
                            status=h.get("status", "ACTIVE"),
                            is_emergency_available=h.get("is_emergency_available", True),
                            specialties=h.get("specialties", "Multi-Specialty Emergency Care"),
                            admin_name=h.get("admin_name"),
                            admin_email=h.get("admin_email"),
                            admin_phone=h.get("admin_phone"),
                            staff_count=h.get("staff_count", 25),
                            parking_available=h.get("parking_available", True),
                            gst_verified=h.get("gst_verified", True),
                        )
                        db.add(hosp)
                    else:
                        if h.get("gst_number"):
                            hosp.gst_number = h["gst_number"].strip().upper()
                        if h.get("admin_email"):
                            hosp.admin_email = h["admin_email"]
                        if h.get("specialties"):
                            hosp.specialties = h["specialties"]
                db.commit()

                # 3. Restore Hospital Resources
                for r in backup.get("resources", []):
                    hosp_id = uuid.UUID(r["hospital_id"])
                    res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hosp_id))
                    if not res:
                        res = HospitalResource(
                            id=uuid.UUID(r["id"]),
                            hospital_id=hosp_id,
                            emergency_beds_available=r.get("emergency_beds_available", 10),
                            icu_beds_available=r.get("icu_beds_available", 2),
                            ventilators_available=r.get("ventilators_available", 1),
                            oxygen_cylinders_available=r.get("oxygen_cylinders_available", 10),
                            oxygen_available=r.get("oxygen_available", True),
                            trauma_capable=r.get("trauma_capable", False),
                            cardiac_capable=r.get("cardiac_capable", False),
                        )
                        db.add(res)
                db.commit()

                # 4. Restore Paramedic Profiles
                for p in backup.get("paramedics", []):
                    u_id = uuid.UUID(p["user_id"])
                    prof = db.scalar(select(ParamedicProfile).where(ParamedicProfile.user_id == u_id))
                    if not prof:
                        db.add(ParamedicProfile(
                            id=uuid.UUID(p["id"]),
                            user_id=u_id,
                            license_number=p.get("license_number"),
                            availability_status=p.get("availability_status", "AVAILABLE"),
                        ))
                db.commit()

                # 5. Restore Police Officer Profiles
                for po in backup.get("police", []):
                    u_id = uuid.UUID(po["user_id"])
                    prof = db.scalar(select(PoliceOfficerProfile).where(PoliceOfficerProfile.user_id == u_id))
                    if not prof:
                        db.add(PoliceOfficerProfile(
                            id=uuid.UUID(po["id"]),
                            user_id=u_id,
                            badge_number=po["badge_number"],
                            station_name=po["station_name"],
                            junction_name=po["junction_name"],
                            junction_latitude=po.get("junction_latitude"),
                            junction_longitude=po.get("junction_longitude"),
                            current_latitude=po.get("current_latitude"),
                            current_longitude=po.get("current_longitude"),
                            duty_status=po.get("duty_status", "ON_DUTY"),
                        ))
                db.commit()

                # 6. Restore Hospital Operator Profiles
                for op_prof in backup.get("operators", []):
                    u_id = uuid.UUID(op_prof["user_id"])
                    h_id = uuid.UUID(op_prof["hospital_id"])
                    prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == u_id))
                    if not prof:
                        db.add(HospitalOperatorProfile(
                            id=uuid.UUID(op_prof["id"]),
                            user_id=u_id,
                            hospital_id=h_id,
                            department=op_prof.get("department", "Emergency Department"),
                        ))
                db.commit()

                # 7. Restore Ambulances
                for a in backup.get("ambulances", []):
                    amb = db.scalar(select(Ambulance).where(Ambulance.vehicle_number == a["vehicle_number"]))
                    param_id = uuid.UUID(a["paramedic_id"]) if a.get("paramedic_id") else None
                    if not amb:
                        db.add(Ambulance(
                            id=uuid.UUID(a["id"]),
                            vehicle_number=a["vehicle_number"],
                            status=a.get("status", "AVAILABLE"),
                            current_latitude=a.get("current_latitude"),
                            current_longitude=a.get("current_longitude"),
                            fuel_percentage=a.get("fuel_percentage", 85),
                            equipment_notes=a.get("equipment_notes", "Trauma kit ready"),
                            oxygen_cylinders=a.get("oxygen_cylinders", 2),
                            paramedic_id=param_id,
                        ))
                    elif param_id and not amb.paramedic_id:
                        amb.paramedic_id = param_id
                db.commit()
                print("All authentic database users, hospitals, and ambulances restored successfully!")
                return
            except Exception as e:
                print("Notice during local backup restore:", e)
                db.rollback()

    print("Seed complete.")


if __name__ == "__main__":
    seed()
