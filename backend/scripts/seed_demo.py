"""Seed local and cloud demo hospitals, resources, and default agency accounts.
Run after migrations: python scripts/seed_demo.py
"""
import sys
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

# 10 Official Partner Hospitals matching the Hospital App demo quick-select
HOSPITALS_DATA = [
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
        # 1. Seed Hospitals and their Hospital Resources
        for (
            name,
            gst,
            lat,
            lng,
            beds,
            oxygen,
            trauma,
            cardiac,
            specialties,
            admin_name,
            admin_email,
            admin_phone,
        ) in HOSPITALS_DATA:
            hospital = db.scalar(
                select(Hospital).where(
                    (Hospital.gst_number == gst) | (Hospital.name == name)
                )
            )
            if not hospital:
                hospital = Hospital(
                    name=name,
                    gst_number=gst,
                    latitude=lat,
                    longitude=lng,
                    status="ACTIVE",
                    is_emergency_available=True,
                    specialties=specialties,
                    admin_name=admin_name,
                    admin_email=admin_email,
                    admin_phone=admin_phone,
                    staff_count=35,
                    parking_available=True,
                )
                db.add(hospital)
                db.flush()
            else:
                hospital.gst_number = gst
                hospital.latitude = lat
                hospital.longitude = lng
                hospital.status = "ACTIVE"
                hospital.is_emergency_available = True
                hospital.specialties = specialties
                hospital.admin_name = admin_name
                hospital.admin_email = admin_email
                hospital.admin_phone = admin_phone
                db.flush()

            resource = db.scalar(
                select(HospitalResource).where(
                    HospitalResource.hospital_id == hospital.id
                )
            )
            if not resource:
                resource = HospitalResource(hospital_id=hospital.id)
                db.add(resource)
            resource.emergency_beds_available = beds
            resource.icu_beds_available = max(2, beds // 4)
            resource.ventilators_available = max(1, beds // 8)
            resource.oxygen_cylinders_available = max(10, beds // 2)
            resource.oxygen_available = oxygen
            resource.trauma_capable = trauma
            resource.cardiac_capable = cardiac

            # Ensure each hospital has an operator user account linked to its GST
            operator_email = f"{gst.lower()}@hospital.rescupath.com"
            hosp_user = db.scalar(
                select(User).where(User.email == operator_email)
            )
            if not hosp_user:
                hosp_user = User(
                    full_name=f"{hospital.name} Desk",
                    email=operator_email,
                    password_hash=default_pwd_hash,
                    role=UserRole.HOSPITAL,
                    is_active=True,
                )
                db.add(hosp_user)
                db.flush()
            else:
                hosp_user.password_hash = default_pwd_hash
                hosp_user.is_active = True

            hosp_profile = db.scalar(
                select(HospitalOperatorProfile).where(
                    HospitalOperatorProfile.hospital_id == hospital.id
                )
            )
            if not hosp_profile:
                db.add(
                    HospitalOperatorProfile(
                        user_id=hosp_user.id,
                        hospital_id=hospital.id,
                        department="Emergency Coordination Desk",
                    )
                )

        # Also create a generic hospital@rescupath.com user mapped to Sri Jayadeva
        generic_hosp_user = db.scalar(
            select(User).where(User.email == "hospital@rescupath.com")
        )
        jayadeva = db.scalar(
            select(Hospital).where(Hospital.gst_number == "29AAETS5552M2ZS")
        )
        if jayadeva:
            if not generic_hosp_user:
                generic_hosp_user = User(
                    full_name="Sri Jayadeva Emergency Desk",
                    email="hospital@rescupath.com",
                    password_hash=default_pwd_hash,
                    role=UserRole.HOSPITAL,
                    is_active=True,
                )
                db.add(generic_hosp_user)
                db.flush()
                db.add(
                    HospitalOperatorProfile(
                        user_id=generic_hosp_user.id,
                        hospital_id=jayadeva.id,
                        department="Central Triage Desk",
                    )
                )
            else:
                generic_hosp_user.password_hash = default_pwd_hash
                generic_hosp_user.is_active = True

        # 2. Seed Default Paramedic Account (paramedic@rescupath.com / password123)
        paramedic_user = db.scalar(
            select(User).where(User.email == "paramedic@rescupath.com")
        )
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
            db.add(
                ParamedicProfile(
                    user_id=paramedic_user.id,
                    license_number="KA-PARAMEDIC-108",
                    availability_status="AVAILABLE",
                )
            )
        else:
            paramedic_user.password_hash = default_pwd_hash
            paramedic_user.is_active = True

        # Ensure ambulance is linked to paramedic
        ambulance = db.scalar(
            select(Ambulance).where(
                Ambulance.paramedic_id == paramedic_user.id
            )
        )
        if not ambulance:
            db.add(
                Ambulance(
                    vehicle_number="KA-01-AMB-108",
                    status="AVAILABLE",
                    current_latitude=12.9352,
                    current_longitude=77.6245,
                    fuel_percentage=92,
                    equipment_notes="Advanced Cardiac Life Support & Trauma Response Unit",
                    oxygen_cylinders=4,
                    paramedic_id=paramedic_user.id,
                )
            )

        # 3. Seed Default Police Account (police@rescupath.com / password123)
        police_user = db.scalar(
            select(User).where(User.email == "police@rescupath.com")
        )
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
            db.add(
                PoliceOfficerProfile(
                    user_id=police_user.id,
                    badge_number="POL-BLR-007",
                    station_name="Cubbon Park Traffic Unit",
                    junction_name="MG Road Junction",
                    junction_latitude=12.9756,
                    junction_longitude=77.6066,
                    current_latitude=12.9756,
                    current_longitude=77.6066,
                    duty_status="ON_DUTY",
                )
            )
        else:
            police_user.password_hash = default_pwd_hash
            police_user.is_active = True

        db.commit()
    print("Demo hospitals, resources, and agency accounts successfully seeded!")


if __name__ == "__main__":
    seed()
