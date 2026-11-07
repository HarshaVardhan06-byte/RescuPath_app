"""Add missing columns for hospital_availability_requests.

Revision ID: 0004_availability_req_ext
Revises: 0003_extended_columns
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_availability_req_ext"
down_revision = "0003_extended_columns"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS is_dismissed BOOLEAN NOT NULL DEFAULT FALSE")
    op.execute("ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMP WITH TIME ZONE")
    op.execute("ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_intake_at TIMESTAMP WITH TIME ZONE")
    op.execute("ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_exit_at TIMESTAMP WITH TIME ZONE")
    op.execute("ALTER TABLE hospital_availability_requests ADD COLUMN IF NOT EXISTS patient_exit_notes TEXT")


def downgrade() -> None:
    op.execute("ALTER TABLE hospital_availability_requests DROP COLUMN IF EXISTS patient_exit_notes")
    op.execute("ALTER TABLE hospital_availability_requests DROP COLUMN IF EXISTS patient_exit_at")
    op.execute("ALTER TABLE hospital_availability_requests DROP COLUMN IF EXISTS patient_intake_at")
    op.execute("ALTER TABLE hospital_availability_requests DROP COLUMN IF EXISTS dismissed_at")
    op.execute("ALTER TABLE hospital_availability_requests DROP COLUMN IF EXISTS is_dismissed")
