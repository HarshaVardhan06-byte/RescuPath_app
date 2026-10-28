"""Seed local demo hospitals/resources.
Run after migrations: python scripts/seed_demo.py
"""
from sqlalchemy import select
from app.db.session import SessionLocal
from app.models.hospital import Hospital
from app.models.hospital_resource import HospitalResource

HOSPITALS = [
    ("RescuPath Central Medical Center", 12.9716, 77.5946, 40, True, True, True),
    ("RescuPath Emergency Institute", 12.9352, 77.6245, 28, True, True, False),
    ("RescuPath Trauma & Cardiac", 12.9970, 77.5920, 22, True, True, True),
]

with SessionLocal() as db:
    for name, lat, lng, beds, oxygen, trauma, cardiac in HOSPITALS:
        hospital = db.scalar(select(Hospital).where(Hospital.name == name))
        if not hospital:
            hospital = Hospital(name=name, latitude=lat, longitude=lng, status="ACTIVE", is_emergency_available=True)
            db.add(hospital)
            db.flush()
        resource = db.scalar(select(HospitalResource).where(HospitalResource.hospital_id == hospital.id))
        if not resource:
            resource = HospitalResource(hospital_id=hospital.id)
            db.add(resource)
        resource.emergency_beds_available = beds
        resource.icu_beds_available = max(1, beds // 5)
        resource.ventilators_available = max(1, beds // 10)
        resource.oxygen_available = oxygen
        resource.trauma_capable = trauma
        resource.cardiac_capable = cardiac
    db.commit()
print("Demo hospitals/resources ready.")
