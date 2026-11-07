import uuid
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.ambulance import Ambulance

router = APIRouter(prefix="/ambulances", tags=["Ambulances"])


class AmbulanceUpdate(BaseModel):
    fuel_percentage: int | None = Field(default=None, ge=0, le=100)
    status: str | None = Field(default=None, max_length=30)
    current_latitude: float | None = Field(default=None, ge=-90, le=90)
    current_longitude: float | None = Field(default=None, ge=-180, le=180)
    oxygen_cylinders: int | None = Field(default=None, ge=0, le=50)
    equipment_notes: str | None = Field(default=None, max_length=255)


@router.get("/mine")
def my_ambulances(db=Depends(get_db), current_user=Depends(get_current_user)):
    rows = db.scalars(
        select(Ambulance)
        .where(Ambulance.paramedic_id == current_user.id)
        .order_by(Ambulance.vehicle_number)
    ).all()
    return [
        {
            "id": str(item.id),
            "vehicle_number": item.vehicle_number,
            "status": item.status,
            "current_latitude": item.current_latitude,
            "current_longitude": item.current_longitude,
            "fuel_percentage": getattr(item, "fuel_percentage", 85) or 85,
            "oxygen_cylinders": getattr(item, "oxygen_cylinders", 2) or 2,
            "equipment_notes": getattr(item, "equipment_notes", "Full Trauma & Oxygen Kit Configured") or "Full Trauma & Oxygen Kit Configured",
        }
        for item in rows
    ]


@router.put("/mine")
def update_my_ambulance(data: AmbulanceUpdate, db=Depends(get_db), current_user=Depends(get_current_user)):
    ambulance = db.scalar(
        select(Ambulance)
        .where(Ambulance.paramedic_id == current_user.id)
        .order_by(Ambulance.vehicle_number)
        .limit(1)
    )
    if not ambulance:
        raise HTTPException(status_code=404, detail="No ambulance assigned to this paramedic.")

    if data.fuel_percentage is not None:
        ambulance.fuel_percentage = data.fuel_percentage
    if data.status is not None and data.status.strip():
        ambulance.status = data.status.strip().upper()
    if data.current_latitude is not None:
        ambulance.current_latitude = data.current_latitude
    if data.current_longitude is not None:
        ambulance.current_longitude = data.current_longitude
    if data.oxygen_cylinders is not None:
        ambulance.oxygen_cylinders = data.oxygen_cylinders
    if data.equipment_notes is not None:
        ambulance.equipment_notes = data.equipment_notes.strip()

    db.commit()
    db.refresh(ambulance)
    return {
        "id": str(ambulance.id),
        "vehicle_number": ambulance.vehicle_number,
        "status": ambulance.status,
        "fuel_percentage": ambulance.fuel_percentage,
        "current_latitude": ambulance.current_latitude,
        "current_longitude": ambulance.current_longitude,
        "oxygen_cylinders": ambulance.oxygen_cylinders,
        "equipment_notes": ambulance.equipment_notes,
    }


@router.post("/dev-assign")
def dev_assign_ambulance(vehicle_number: str, db=Depends(get_db), current_user=Depends(get_current_user)):
    """Development bootstrap helper. Protect/remove before public deployment."""
    ambulance = db.scalar(select(Ambulance).where(Ambulance.vehicle_number == vehicle_number))
    if not ambulance:
        ambulance = Ambulance(vehicle_number=vehicle_number, status="AVAILABLE")
        db.add(ambulance)
        db.flush()
    ambulance.paramedic_id = current_user.id
    db.commit()
    db.refresh(ambulance)
    return {"id": str(ambulance.id), "vehicle_number": ambulance.vehicle_number, "status": ambulance.status}
