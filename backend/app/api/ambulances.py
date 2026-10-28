import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.ambulance import Ambulance

router = APIRouter(prefix="/ambulances", tags=["Ambulances"])


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
        }
        for item in rows
    ]


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
