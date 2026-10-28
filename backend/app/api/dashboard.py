from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.ambulance import Ambulance
from app.models.emergency import Emergency

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])

@router.get("/summary")
def summary(db=Depends(get_db), current_user=Depends(get_current_user)):
    ambulance = db.scalar(select(Ambulance).where(Ambulance.paramedic_id == current_user.id).limit(1))
    total = db.scalar(select(func.count(Emergency.id)).where(Emergency.created_by == current_user.id)) or 0
    active = db.scalar(select(func.count(Emergency.id)).where(Emergency.created_by == current_user.id, Emergency.status.notin_(["COMPLETED","CANCELLED"]))) or 0
    return {"total_responses": int(total), "active_emergencies": int(active), "pending": 0, "ambulance": None if not ambulance else {"id": str(ambulance.id), "vehicle_number": ambulance.vehicle_number, "status": ambulance.status, "latitude": ambulance.current_latitude, "longitude": ambulance.current_longitude}}

@router.get("/emergencies")
def history(db=Depends(get_db), current_user=Depends(get_current_user)):
    rows = db.scalars(select(Emergency).where(Emergency.created_by == current_user.id).order_by(Emergency.created_at.desc()).limit(50)).all()
    return [{"id": str(x.id), "severity": x.severity, "status": x.status, "pickup_latitude": x.pickup_latitude, "pickup_longitude": x.pickup_longitude, "destination_latitude": x.destination_latitude, "destination_longitude": x.destination_longitude, "created_at": x.created_at.isoformat()} for x in rows]
