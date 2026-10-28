import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class HospitalResource(Base):
    __tablename__ = "hospital_resources"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    hospital_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("hospitals.id", ondelete="CASCADE"), unique=True)
    icu_beds_available: Mapped[int] = mapped_column(Integer, default=0)
    emergency_beds_available: Mapped[int] = mapped_column(Integer, default=0)
    ventilators_available: Mapped[int] = mapped_column(Integer, default=0)
    oxygen_available: Mapped[bool] = mapped_column(Boolean, default=True)
    trauma_capable: Mapped[bool] = mapped_column(Boolean, default=False)
    cardiac_capable: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
