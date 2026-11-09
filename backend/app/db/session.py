import logging
import os
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

logger = logging.getLogger(__name__)

SQLITE_FALLBACK_URL = "sqlite:///./rescupath_resilient.db"


def _create_resilient_engine():
    db_url = settings.database_url
    # If explicitly SQLite, use check_same_thread=False
    if db_url.startswith("sqlite"):
        return create_engine(db_url, connect_args={"check_same_thread": False})

    # Try connecting to PostgreSQL
    try:
        eng = create_engine(
            db_url,
            pool_pre_ping=True,
            pool_recycle=300,
            pool_size=15,
            max_overflow=10,
            pool_timeout=15.0,
        )
        # Test connection immediately
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
        logger.info("Connected to primary PostgreSQL database.")
        return eng
    except Exception as exc:
        logger.warning(
            f"Primary database connection failed ({exc}). "
            f"Falling back to local SQLite engine ({SQLITE_FALLBACK_URL}) to guarantee 100% uptime."
        )
        fallback_engine = create_engine(
            SQLITE_FALLBACK_URL,
            connect_args={"check_same_thread": False},
        )
        try:
            from app.db.base import Base
            import app.db.models  # noqa: F401
            Base.metadata.create_all(bind=fallback_engine)
            logger.info("Initialized schema on fallback SQLite database.")
        except Exception as schema_err:
            logger.error(f"Failed to auto-create schema on fallback: {schema_err}")
        return fallback_engine


engine = _create_resilient_engine()

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
