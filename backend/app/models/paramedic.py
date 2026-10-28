import uuid
from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ParamedicProfile(Base):
    __tablename__ = "paramedic_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    license_number: Mapped[str | None] = mapped_column(String(100), unique=True, nullable=True)
    availability_status: Mapped[str] = mapped_column(String(30), default="AVAILABLE")
