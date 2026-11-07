"""Seed local and cloud demo hospitals, resources, and agency accounts.
Restores all authentic local development user accounts, hospitals, and ambulances.
Guarantees fault-tolerant execution using savepoints and deduplication.
"""
import json
import logging
import sys
import uuid
from pathlib import Path

# Ensure backend root is on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select, text
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.ambulance import Ambulance
from app.models.hospital import Hospital
from app.models.hospital_operator import HospitalOperatorProfile
from app.models.hospital_resource import HospitalResource
from app.models.paramedic import ParamedicProfile
from app.models.police_officer import PoliceOfficerProfile
from app.models.user import User, UserRole

logger = logging.getLogger("seed_demo")
logging.basicConfig(level=logging.INFO)

BACKUP_FILE = Path(__file__).resolve().parents[1] / "app" / "db" / "local_backup.json"

OFFICIAL_PRESET_HOSPITALS = [
    (
        "Sri Jayadeva Institute of Cardiovascular Sciences",
        "29AAETS5552M2ZS",
        12.9172,
        77.5924,
        45,
        True,
        True,
        True,
        "Apex Cardiac Care & 24/7 Cath Lab",
        "Dr. C. N. Manjunath",
        "jayadeva.admin@rescupath.com",
        "+91 80 2297 7400",
    ),
    (
        "Fortis Hospital Bannerghatta",
        "29AABCF3718N1ZA",
        12.8954,
        77.5986,
        35,
        True,
        True,
        True,
        "Tertiary Cardiac & Emergency Resuscitation",
        "Admin Fortis",
        "fortis.admin@rescupath.com",
        "+91 80 6621 4444",
    ),
    (
        "Apollo Hospitals Bannerghatta",
        "29AAACA5443N6Z9",
        12.8943,
        77.5980,
        40,
        True,
        True,
        True,
        "Multi-Specialty Emergency & Trauma Care",
        "Admin Apollo",
        "apollo.admin@rescupath.com",
        "+91 80 2630 4050",
    ),
    (
        "NIMHANS Neuro Emergency",
        "29AABTN6120B2ZX",
        12.9392,
        77.5960,
        50,
        True,
        True,
        False,
        "National Apex Neuro & Acute Stroke Center",
        "Admin NIMHANS",
        "nimhans.admin@rescupath.com",
        "+91 80 2699 5000",
    ),
    (
        "Aster RV Hospital",
        "29AACCD7912K1ZD",
        12.9152,
        77.5847,
        30,
        True,
        True,
        True,
        "Critical Care, Pulmonology & ECMO Unit",
        "Admin Aster RV",
        "aster.admin@rescupath.com",
        "+91 80 6604 0400",
    ),
    (
        "Manipal Hospital Old Airport Rd",
        "29AAGCM5933R2ZK",
        12.9585,
        77.6485,
        42,
        True,
        True,
        True,
        "Tertiary Emergency & Trauma Care",
        "Admin Manipal",
        "manipal.admin@rescupath.com",
        "+91 80 2502 4444",
    ),
    (
        "HOSMAT Hospital",
        "29AABCP2221Q1Z6",
        12.9698,
        77.6146,
        28,
        True,
        True,
        True,
        "Apex Orthopedic & Spine Trauma Centre",
        "Admin HOSMAT",
        "hosmat.admin@rescupath.com",
        "+91 80 2559 3796",
    ),
    (
        "St. John's Medical College Hospital",
        "29AAATC0773E4ZU",
        12.9324,
        77.6218,
        55,
        True,
        True,
        True,
        "Major Tertiary Multi-Specialty Emergency Hospital",
        "Admin St Johns",
        "stjohns.admin@rescupath.com",
        "+91 80 2206 5000",
    ),
    (
        "Victoria Hospital Emergency Trauma",
        "29AAAGV1001V1ZX",
        12.9642,
        77.5746,
        60,
        True,
        True,
        True,
        "Apex Burns & Emergency Trauma Care",
        "Admin Victoria",
        "victoria.admin@rescupath.com",
        "+91 80 2670 1150",
    ),
    (
        "Kidwai Memorial Institute of Oncology",
        "29AAATK3049D1ZS",
        12.9416,
        77.5946,
        25,
        True,
        True,
        False,
        "Specialized Emergency Oncology Care",
        "Admin Kidwai",
        "kidwai.admin@rescupath.com",
        "+91 80 2609 4000",
    ),
]


def seed():
    default_pwd_hash = hash_password("password123")

    with SessionLocal() as db:
        # Guarantee missing database columns exist
        for col_sql in [
            "ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS is_dismissed BOOLEAN NOT NULL DEFAULT FALSE",
            "ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_intake_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_exit_at TIMESTAMP WITH TIME ZONE",
            "ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_exit_notes TEXT",
        ]:
            try:
                db.execute(text(col_sql))
                db.commit()
            except Exception:
                db.rollback()

        user_id_map: dict[str, uuid.UUID] = {}
        hospital_id_map: dict[str, uuid.UUID] = {}

        # ----------------------------------------------------
        # 1. Restore authentic local backup data if available
        # ----------------------------------------------------
        if BACKUP_FILE.exists():
            try:
                with open(BACKUP_FILE, "r", encoding="utf-8") as f:
                    backup = json.load(f)

                # 1.1 Restore Users (Deduplicated, fault-tolerant savepoints)
                seen_emails: set[str] = set()
                for u in backup.get("users", []):
                    email = u["email"].lower().strip()
                    if email in seen_emails:
                        continue
                    seen_emails.add(email)

                    u_id = uuid.UUID(u["id"])
                    role_str = u["role"].split(".")[-1] if "." in u["role"] else u["role"]
                    role = UserRole[role_str] if role_str in UserRole.__members__ else UserRole.PARAMEDIC

                    try:
                        with db.begin_nested():
                            user = db.scalar(select(User).where((User.email == email) | (User.id == u_id)))
                            if not user:
                                user = User(
                                    id=u_id,
                                    full_name=u["full_name"],
                                    email=email,
                                    phone=u.get("phone"),
                                    password_hash=u["password_hash"],
                                    role=role,
                                    is_active=u.get("is_active", True),
                                )
                                db.add(user)
                                db.flush()
                                user_id_map[u["id"]] = user.id
                            else:
                                user.password_hash = u["password_hash"]
                                user.is_active = True
                                user.role = role
                                user.full_name = u["full_name"]
                                user_id_map[u["id"]] = user.id
                    except Exception as e:
                        logger.warning(f"Notice restoring user {email}: {e}")

                db.commit()
                logger.info(f"Restored authentic users. ID map has {len(user_id_map)} entries.")

                # 1.2 Restore Hospitals
                for h in backup.get("hospitals", []):
                    h_id = uuid.UUID(h["id"])
                    gst = h.get("gst_number").strip().upper() if h.get("gst_number") else None

                    try:
                        with db.begin_nested():
                            hosp = None
                            if gst:
                                hosp = db.scalar(select(Hospital).where(Hospital.gst_number == gst))
                            if not hosp:
                                hosp = db.scalar(select(Hospital).where(Hospital.id == h_id))
                            if not hosp:
                                hosp = db.scalar(select(Hospital).where(Hospital.name == h["name"]))

                            if not hosp:
                                hosp = Hospital(
                                    id=h_id,
                                    name=h["name"],
                                    gst_number=gst,
                                    latitude=h["latitude"],
                                    longitude=h["longitude"],
                                    status="ACTIVE",
                                    is_emergency_available=True,
                                    specialties=h.get("specialties", "Multi-Specialty Emergency Care"),
                                    admin_name=h.get("admin_name"),
                                    admin_email=h.get("admin_email"),
                                    admin_phone=h.get("admin_phone"),
                                    staff_count=h.get("staff_count", 25),
                                    parking_available=h.get("parking_available", True),
                                    gst_verified=True,
                                )
                                db.add(hosp)
                                db.flush()
                                hospital_id_map[h["id"]] = hosp.id
                            else:
                                hosp.status = "ACTIVE"
                                hosp.is_emergency_available = True
                                hosp.gst_verified = True
                                if gst:
                                    hosp.gst_number = gst
                                if h.get("admin_email"):
                                    hosp.admin_email = h["admin_email"]
                                if h.get("specialties"):
                                    hosp.specialties = h["specialties"]
                                hospital_id_map[h["id"]] = hosp.id
                    except Exception as e:
                        logger.warning(f"Notice restoring hospital {h.get('name')}: {e}")

                db.commit()
                logger.info(f"Restored authentic hospitals. ID map has {len(hospital_id_map)} entries.")

                # 1.3 Restore Hospital Resources
                for r in backup.get("resources", []):
                    raw_h_id = r["hospital_id"]
                    mapped_h_id = hospital_id_map.get(raw_h_id, uuid.UUID(raw_h_id))

                    try:
                        with db.begin_nested():
                            target_hosp = db.get(Hospital, mapped_h_id)
                            if not target_hosp:
                                continue

                            res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == mapped_h_id))
                            if not res:
                                res = HospitalResource(
                                    hospital_id=mapped_h_id,
                                    emergency_beds_available=r.get("emergency_beds_available", 20),
                                    icu_beds_available=r.get("icu_beds_available", 8),
                                    ventilators_available=r.get("ventilators_available", 4),
                                    oxygen_cylinders_available=r.get("oxygen_cylinders_available", 25),
                                    oxygen_available=r.get("oxygen_available", True),
                                    trauma_capable=r.get("trauma_capable", True),
                                    cardiac_capable=r.get("cardiac_capable", True),
                                )
                                db.add(res)
                            else:
                                res.emergency_beds_available = r.get("emergency_beds_available", res.emergency_beds_available)
                                res.icu_beds_available = r.get("icu_beds_available", res.icu_beds_available)
                                res.ventilators_available = r.get("ventilators_available", res.ventilators_available)
                                res.oxygen_cylinders_available = r.get("oxygen_cylinders_available", res.oxygen_cylinders_available)
                                res.oxygen_available = True
                                res.trauma_capable = True
                                res.cardiac_capable = True
                    except Exception as e:
                        logger.warning(f"Notice restoring resource for hospital {mapped_h_id}: {e}")

                db.commit()

                # 1.4 Restore Paramedic Profiles
                for p in backup.get("paramedics", []):
                    raw_u_id = p["user_id"]
                    mapped_u_id = user_id_map.get(raw_u_id, uuid.UUID(raw_u_id))

                    try:
                        with db.begin_nested():
                            target_u = db.get(User, mapped_u_id)
                            if not target_u:
                                continue

                            prof = db.scalar(select(ParamedicProfile).where(ParamedicProfile.user_id == mapped_u_id))
                            if not prof:
                                db.add(ParamedicProfile(
                                    user_id=mapped_u_id,
                                    license_number=p.get("license_number", f"KA-PARAMEDIC-{str(mapped_u_id)[:6].upper()}"),
                                    availability_status=p.get("availability_status", "AVAILABLE"),
                                ))
                    except Exception as e:
                        logger.warning(f"Notice restoring paramedic profile: {e}")

                db.commit()

                # 1.5 Restore Police Officer Profiles
                for po in backup.get("police", []):
                    raw_u_id = po["user_id"]
                    mapped_u_id = user_id_map.get(raw_u_id, uuid.UUID(raw_u_id))

                    try:
                        with db.begin_nested():
                            target_u = db.get(User, mapped_u_id)
                            if not target_u:
                                continue

                            prof = db.scalar(select(PoliceOfficerProfile).where(PoliceOfficerProfile.user_id == mapped_u_id))
                            if not prof:
                                db.add(PoliceOfficerProfile(
                                    user_id=mapped_u_id,
                                    badge_number=po["badge_number"],
                                    station_name=po["station_name"],
                                    junction_name=po["junction_name"],
                                    junction_latitude=po.get("junction_latitude"),
                                    junction_longitude=po.get("junction_longitude"),
                                    current_latitude=po.get("current_latitude"),
                                    current_longitude=po.get("current_longitude"),
                                    duty_status=po.get("duty_status", "ON_DUTY"),
                                ))
                    except Exception as e:
                        logger.warning(f"Notice restoring police profile: {e}")

                db.commit()

                # 1.6 Restore Hospital Operator Profiles
                for op_prof in backup.get("operators", []):
                    raw_u_id = op_prof["user_id"]
                    raw_h_id = op_prof["hospital_id"]
                    mapped_u_id = user_id_map.get(raw_u_id, uuid.UUID(raw_u_id))
                    mapped_h_id = hospital_id_map.get(raw_h_id, uuid.UUID(raw_h_id))

                    try:
                        with db.begin_nested():
                            target_u = db.get(User, mapped_u_id)
                            target_h = db.get(Hospital, mapped_h_id)
                            if not target_u or not target_h:
                                continue

                            prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == mapped_u_id))
                            if not prof:
                                db.add(HospitalOperatorProfile(
                                    user_id=mapped_u_id,
                                    hospital_id=mapped_h_id,
                                    department=op_prof.get("department", "Emergency Department"),
                                ))
                    except Exception as e:
                        logger.warning(f"Notice restoring hospital operator profile: {e}")

                db.commit()

                # 1.7 Restore Ambulances
                for a in backup.get("ambulances", []):
                    raw_p_id = a.get("paramedic_id")
                    mapped_p_id = user_id_map.get(raw_p_id, uuid.UUID(raw_p_id)) if raw_p_id else None

                    try:
                        with db.begin_nested():
                            amb = db.scalar(select(Ambulance).where(Ambulance.vehicle_number == a["vehicle_number"]))
                            if not amb:
                                db.add(Ambulance(
                                    vehicle_number=a["vehicle_number"],
                                    status=a.get("status", "AVAILABLE"),
                                    current_latitude=a.get("current_latitude"),
                                    current_longitude=a.get("current_longitude"),
                                    fuel_percentage=a.get("fuel_percentage", 85),
                                    equipment_notes=a.get("equipment_notes", "Trauma kit ready"),
                                    oxygen_cylinders=a.get("oxygen_cylinders", 2),
                                    paramedic_id=mapped_p_id,
                                ))
                            elif mapped_p_id and not amb.paramedic_id:
                                amb.paramedic_id = mapped_p_id
                    except Exception as e:
                        logger.warning(f"Notice restoring ambulance {a.get('vehicle_number')}: {e}")

                db.commit()
                logger.info("Authentic local backup restored successfully!")

            except Exception as e:
                logger.error(f"Error during local backup restoration: {e}")
                db.rollback()

        # ----------------------------------------------------
        # 2. Guarantee 10 Bangalore Preset Partner Hospitals
        # ----------------------------------------------------
        for (
            name, gst, lat, lng, beds, oxy, trauma, cardiac, specs,
            admin_name, admin_email, admin_phone
        ) in OFFICIAL_PRESET_HOSPITALS:
            try:
                with db.begin_nested():
                    hosp = db.scalar(select(Hospital).where(Hospital.gst_number == gst))
                    if not hosp:
                        hosp = db.scalar(select(Hospital).where(Hospital.name == name))

                    if not hosp:
                        hosp = Hospital(
                            name=name,
                            gst_number=gst,
                            latitude=lat,
                            longitude=lng,
                            status="ACTIVE",
                            is_emergency_available=True,
                            specialties=specs,
                            admin_name=admin_name,
                            admin_email=admin_email,
                            admin_phone=admin_phone,
                            staff_count=35,
                            parking_available=True,
                            gst_verified=True,
                        )
                        db.add(hosp)
                        db.flush()
                    else:
                        hosp.gst_number = gst
                        hosp.status = "ACTIVE"
                        hosp.is_emergency_available = True
                        hosp.gst_verified = True
                        if admin_email and not hosp.admin_email:
                            hosp.admin_email = admin_email

                    res = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hosp.id))
                    if not res:
                        db.add(HospitalResource(
                            hospital_id=hosp.id,
                            emergency_beds_available=beds,
                            icu_beds_available=max(2, beds // 4),
                            ventilators_available=max(1, beds // 8),
                            oxygen_cylinders_available=max(10, beds // 2),
                            oxygen_available=oxy,
                            trauma_capable=trauma,
                            cardiac_capable=cardiac,
                        ))
                    else:
                        res.oxygen_available = True
                        res.trauma_capable = trauma
                        res.cardiac_capable = cardiac

                    # Ensure hospital operator user exists
                    op_user = db.scalar(select(User).where(User.email == admin_email.lower().strip()))
                    if not op_user:
                        op_user = User(
                            full_name=admin_name,
                            email=admin_email.lower().strip(),
                            phone=admin_phone,
                            password_hash=default_pwd_hash,
                            role=UserRole.HOSPITAL,
                            is_active=True,
                        )
                        db.add(op_user)
                        db.flush()
                        db.add(HospitalOperatorProfile(
                            user_id=op_user.id,
                            hospital_id=hosp.id,
                            department="Central Emergency Desk",
                        ))
                    else:
                        op_prof = db.scalar(select(HospitalOperatorProfile).where(HospitalOperatorProfile.user_id == op_user.id))
                        if not op_prof:
                            db.add(HospitalOperatorProfile(
                                user_id=op_user.id,
                                hospital_id=hosp.id,
                                department="Central Emergency Desk",
                            ))
            except Exception as e:
                logger.warning(f"Notice configuring preset hospital {name}: {e}")

        db.commit()

        # ----------------------------------------------------
        # 3. Guarantee Standard Test Accounts (Paramedic & Police)
        # ----------------------------------------------------
        # Paramedic: paramedic@rescupath.com / password123
        try:
            with db.begin_nested():
                paramedic_user = db.scalar(select(User).where(User.email == "paramedic@rescupath.com"))
                if not paramedic_user:
                    paramedic_user = User(
                        full_name="Chief Paramedic Rajesh Sharma",
                        email="paramedic@rescupath.com",
                        phone="+91 98765 43210",
                        password_hash=default_pwd_hash,
                        role=UserRole.PARAMEDIC,
                        is_active=True,
                    )
                    db.add(paramedic_user)
                    db.flush()
                    db.add(ParamedicProfile(
                        user_id=paramedic_user.id,
                        license_number="KA-PARAMEDIC-108",
                        availability_status="AVAILABLE",
                    ))
                else:
                    paramedic_user.is_active = True
                    paramedic_user.role = UserRole.PARAMEDIC

                # Ensure linked ambulance
                amb = db.scalar(select(Ambulance).where(Ambulance.paramedic_id == paramedic_user.id))
                if not amb:
                    db.add(Ambulance(
                        vehicle_number="KA-01-AMB-108",
                        status="AVAILABLE",
                        current_latitude=12.9352,
                        current_longitude=77.6245,
                        fuel_percentage=95,
                        equipment_notes="Advanced Cardiac Life Support & Trauma Response Unit",
                        oxygen_cylinders=4,
                        paramedic_id=paramedic_user.id,
                    ))
        except Exception as e:
            logger.warning(f"Notice seeding paramedic account: {e}")

        # Police: police@rescupath.com / password123
        try:
            with db.begin_nested():
                police_user = db.scalar(select(User).where(User.email == "police@rescupath.com"))
                if not police_user:
                    police_user = User(
                        full_name="Inspector Ramesh Kumar",
                        email="police@rescupath.com",
                        phone="+91 98877 66554",
                        password_hash=default_pwd_hash,
                        role=UserRole.POLICE,
                        is_active=True,
                    )
                    db.add(police_user)
                    db.flush()
                    db.add(PoliceOfficerProfile(
                        user_id=police_user.id,
                        badge_number="POL-BLR-007",
                        station_name="Cubbon Park Traffic Unit",
                        junction_name="MG Road Junction",
                        junction_latitude=12.9756,
                        junction_longitude=77.6066,
                        current_latitude=12.9756,
                        current_longitude=77.6066,
                        duty_status="ON_DUTY",
                    ))
                else:
                    police_user.is_active = True
                    police_user.role = UserRole.POLICE
        except Exception as e:
            logger.warning(f"Notice seeding police account: {e}")

        # Hospital: hospital@rescupath.com / password123
        try:
            with db.begin_nested():
                hosp_user = db.scalar(select(User).where(User.email == "hospital@rescupath.com"))
                jayadeva = db.scalar(select(Hospital).where(Hospital.gst_number == "29AAETS5552M2ZS"))
                if not hosp_user:
                    hosp_user = User(
                        full_name="Sri Jayadeva Emergency Desk",
                        email="hospital@rescupath.com",
                        password_hash=default_pwd_hash,
                        role=UserRole.HOSPITAL,
                        is_active=True,
                    )
                    db.add(hosp_user)
                    db.flush()
                    if jayadeva:
                        db.add(HospitalOperatorProfile(
                            user_id=hosp_user.id,
                            hospital_id=jayadeva.id,
                            department="Central Triage Desk",
                        ))
                else:
                    hosp_user.is_active = True
                    hosp_user.role = UserRole.HOSPITAL
        except Exception as e:
            logger.warning(f"Notice seeding hospital account: {e}")

        db.commit()
    logger.info("Seed execution complete.")


if __name__ == "__main__":
    seed()
