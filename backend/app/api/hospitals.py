import uuid
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.hospital import Hospital
from app.models.hospital_resource import HospitalResource
from app.schemas.hospital import (
    HospitalCreate, HospitalResponse,
    HospitalResourceCreate, HospitalResourceResponse,
    HospitalCandidate,
)
from app.services.hospital_selection import find_candidates

router = APIRouter(prefix="/hospitals", tags=["Hospitals"])


@router.post("/", response_model=HospitalResponse)
def create_hospital(data: HospitalCreate, db=Depends(get_db), _=Depends(get_current_user)):
    hospital = Hospital(**data.model_dump())
    db.add(hospital)
    db.commit()
    db.refresh(hospital)
    return hospital


@router.get("/", response_model=list[HospitalResponse])
def list_hospitals(db=Depends(get_db), _=Depends(get_current_user)):
    return db.scalars(select(Hospital).order_by(Hospital.name)).all()


@router.get("/nearby", response_model=list[HospitalCandidate])
async def nearby_hospitals(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(10, gt=0, le=100),
    db=Depends(get_db),
    _=Depends(get_current_user),
):
    return await find_candidates(db, latitude, longitude, radius_km)


@router.get("/{hospital_id}", response_model=HospitalResponse)
def get_hospital(hospital_id: uuid.UUID, db=Depends(get_db), _=Depends(get_current_user)):
    hospital = db.get(Hospital, hospital_id)
    if not hospital:
        raise HTTPException(404, "Hospital not found")
    return hospital


@router.post("/{hospital_id}/resources", response_model=HospitalResourceResponse)
def upsert_resources(
    hospital_id: uuid.UUID,
    data: HospitalResourceCreate,
    db=Depends(get_db),
    _=Depends(get_current_user),
):
    if not db.get(Hospital, hospital_id):
        raise HTTPException(404, "Hospital not found")

    resource = db.scalar(
        select(HospitalResource).where(HospitalResource.hospital_id == hospital_id)
    )
    if resource:
        for key, value in data.model_dump().items():
            setattr(resource, key, value)
    else:
        resource = HospitalResource(hospital_id=hospital_id, **data.model_dump())
        db.add(resource)

    db.commit()
    db.refresh(resource)
    return resource
