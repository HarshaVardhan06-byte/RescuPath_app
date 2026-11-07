import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Hospital(Base):
    __tablename__ = "hospitals"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    gst_number: Mapped[str | None] = mapped_column(String(30), unique=True, index=True, nullable=True)
    name: Mapped[str] = mapped_column(String(200))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(30), default="ACTIVE")
    is_emergency_available: Mapped[bool] = mapped_column(Boolean, default=True)
    gst_photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    gst_verified: Mapped[bool] = mapped_column(Boolean, default=True)
    specialties: Mapped[str | None] = mapped_column(String(255), default="Multi-Specialty Emergency Care", nullable=True)
    admin_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    admin_email: Mapped[str | None] = mapped_column(String(120), nullable=True)
    admin_phone: Mapped[str | None] = mapped_column(String(30), nullable=True)
    staff_count: Mapped[int] = mapped_column(Integer, default=25)
    parking_available: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
