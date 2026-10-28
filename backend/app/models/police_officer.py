import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PoliceOfficerProfile(Base):
    __tablename__ = "police_officer_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True)
    badge_number: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    station_name: Mapped[str] = mapped_column(String(180))
    junction_name: Mapped[str] = mapped_column(String(180))
    junction_latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    junction_longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    current_latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    current_longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    duty_status: Mapped[str] = mapped_column(String(24), default="ON_DUTY")
    last_location_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
