import bcrypt
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from app.core.config import settings


JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_MINUTES = getattr(
    settings,
    "access_token_expire_minutes",
    60,
)


def hash_password(password: str) -> str:
    password_bytes = password.encode("utf-8")

    if len(password_bytes) > 72:
        raise ValueError("Password must not exceed 72 UTF-8 bytes.")

    return bcrypt.hashpw(
        password_bytes,
        bcrypt.gensalt(),
    ).decode("utf-8")


def verify_password(password: str, hashed_password: str) -> bool:
    password_bytes = password.encode("utf-8")

    if len(password_bytes) > 72:
        return False

    try:
        return bcrypt.checkpw(
            password_bytes,
            hashed_password.encode("utf-8"),
        )
    except (ValueError, TypeError):
        return False


def create_access_token(
    subject: str,
    role: str | None = None,
    expires_minutes: int | None = None,
) -> str:
    configured_minutes = getattr(
        settings,
        "access_token_expire_minutes",
        60,
    )

    try:
        configured_minutes = int(configured_minutes)
    except (TypeError, ValueError):
        configured_minutes = 60

    minutes = (
        int(expires_minutes)
        if expires_minutes is not None
        else configured_minutes
    )

    expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)

    payload = {
        "sub": subject,
        "role": role,
        "exp": expire,
    }

    return jwt.encode(
        payload,
        settings.secret_key,
        algorithm=JWT_ALGORITHM,
    )


def decode_access_token(token: str) -> dict:
    try:
        return jwt.decode(
            token,
            settings.secret_key,
            algorithms=[JWT_ALGORITHM],
        )
    except JWTError as exc:
        raise exc