"""Persistent police junctions and hospital availability workflow.

Revision ID: 0002_coordination
Revises: 0001_initial
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002_coordination"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "police_officer_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("badge_number", sa.String(50), nullable=False),
        sa.Column("station_name", sa.String(180), nullable=False),
        sa.Column("junction_name", sa.String(180), nullable=False),
        sa.Column("junction_latitude", sa.Float(), nullable=True),
        sa.Column("junction_longitude", sa.Float(), nullable=True),
        sa.Column("current_latitude", sa.Float(), nullable=True),
        sa.Column("current_longitude", sa.Float(), nullable=True),
        sa.Column("duty_status", sa.String(24), nullable=False, server_default="ON_DUTY"),
        sa.Column("last_location_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", name="uq_police_officer_profiles_user_id"),
        sa.UniqueConstraint("badge_number", name="uq_police_officer_profiles_badge_number"),
    )
    op.create_index("ix_police_officer_profiles_user_id", "police_officer_profiles", ["user_id"])
    op.create_index("ix_police_officer_profiles_badge_number", "police_officer_profiles", ["badge_number"])

    op.create_table(
        "hospital_operator_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("hospital_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("hospitals.id", ondelete="CASCADE"), nullable=False),
        sa.Column("department", sa.String(100), nullable=False, server_default="Emergency Department"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", name="uq_hospital_operator_profiles_user_id"),
    )
    op.create_index("ix_hospital_operator_profiles_user_id", "hospital_operator_profiles", ["user_id"])
    op.create_index("ix_hospital_operator_profiles_hospital_id", "hospital_operator_profiles", ["hospital_id"])

    op.create_table(
        "hospital_availability_requests",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("emergency_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("hospital_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("hospitals.id", ondelete="CASCADE"), nullable=False),
        sa.Column("requested_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("responded_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("status", sa.String(24), nullable=False, server_default="REQUESTED"),
        sa.Column("requested_eta_seconds", sa.Integer(), nullable=True),
        sa.Column("ambulance_latitude", sa.Float(), nullable=True),
        sa.Column("ambulance_longitude", sa.Float(), nullable=True),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("response_note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("emergency_id", "hospital_id", name="uq_hospital_availability_emergency_hospital"),
    )
    op.create_index("ix_hospital_availability_requests_emergency_id", "hospital_availability_requests", ["emergency_id"])
    op.create_index("ix_hospital_availability_requests_hospital_id", "hospital_availability_requests", ["hospital_id"])


def downgrade() -> None:
    op.drop_index("ix_hospital_availability_requests_hospital_id", table_name="hospital_availability_requests")
    op.drop_index("ix_hospital_availability_requests_emergency_id", table_name="hospital_availability_requests")
    op.drop_table("hospital_availability_requests")
    op.drop_index("ix_hospital_operator_profiles_hospital_id", table_name="hospital_operator_profiles")
    op.drop_index("ix_hospital_operator_profiles_user_id", table_name="hospital_operator_profiles")
    op.drop_table("hospital_operator_profiles")
    op.drop_index("ix_police_officer_profiles_badge_number", table_name="police_officer_profiles")
    op.drop_index("ix_police_officer_profiles_user_id", table_name="police_officer_profiles")
    op.drop_table("police_officer_profiles")
