"""Add missing columns for hospitals, ambulances, and hospital_resources.

Revision ID: 0003_extended_columns
Revises: 0002_coordination
"""
from alembic import op
import sqlalchemy as sa

revision = "0003_extended_columns"
down_revision = "0002_coordination"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Hospitals extended columns
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS gst_number VARCHAR(30)")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS gst_photo_url TEXT")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS gst_verified BOOLEAN NOT NULL DEFAULT TRUE")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS specialties VARCHAR(255) DEFAULT 'Multi-Specialty Emergency Care'")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS admin_name VARCHAR(120)")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS admin_email VARCHAR(120)")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS admin_phone VARCHAR(30)")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS staff_count INTEGER NOT NULL DEFAULT 25")
    op.execute("ALTER TABLE hospitals ADD COLUMN IF NOT EXISTS parking_available BOOLEAN NOT NULL DEFAULT TRUE")
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_hospitals_gst_number ON hospitals (gst_number)")

    # 2. Ambulances extended columns
    op.execute("ALTER TABLE ambulances ADD COLUMN IF NOT EXISTS fuel_percentage INTEGER DEFAULT 85")
    op.execute("ALTER TABLE ambulances ADD COLUMN IF NOT EXISTS equipment_notes VARCHAR(255) DEFAULT 'Full Trauma & Oxygen Kit Configured'")
    op.execute("ALTER TABLE ambulances ADD COLUMN IF NOT EXISTS oxygen_cylinders INTEGER DEFAULT 2")

    # 3. Hospital Resources extended columns
    op.execute("ALTER TABLE hospital_resources ADD COLUMN IF NOT EXISTS oxygen_cylinders_available INTEGER NOT NULL DEFAULT 20")


def downgrade() -> None:
    op.execute("ALTER TABLE hospital_resources DROP COLUMN IF EXISTS oxygen_cylinders_available")
    op.execute("ALTER TABLE ambulances DROP COLUMN IF EXISTS oxygen_cylinders")
    op.execute("ALTER TABLE ambulances DROP COLUMN IF EXISTS equipment_notes")
    op.execute("ALTER TABLE ambulances DROP COLUMN IF EXISTS fuel_percentage")
    op.execute("DROP INDEX IF EXISTS ix_hospitals_gst_number")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS parking_available")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS staff_count")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS admin_phone")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS admin_email")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS admin_name")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS specialties")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS gst_verified")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS gst_photo_url")
    op.execute("ALTER TABLE hospitals DROP COLUMN IF EXISTS gst_number")
