import hashlib
import secrets

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException

from sqlalchemy import select

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.security import create_access_token, hash_password, verify_password
from app.db.session import get_db

from app.models.paramedic import ParamedicProfile
from app.models.password_reset import PasswordResetToken
from app.models.user import User, UserRole
from app.models.ambulance import Ambulance

from app.schemas.auth import (
    LoginRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
    OAuthRequest,
    ForgotPasswordRequest,
    ResetPasswordRequest,
    ProfileUpdateRequest,
    DutyModeRequest,
)

from app.services.email import send_password_reset_email
from app.services.oauth import verify_google, verify_apple


router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
)


def _create_default_ambulance(db, user: User) -> Ambulance:
    ambulance = db.scalar(
        select(Ambulance)
        .where(Ambulance.paramedic_id == user.id)
        .limit(1)
    )

    if ambulance:
        return ambulance

    ambulance = Ambulance(
        vehicle_number=f"AMB-{str(user.id)[:8].upper()}",
        status="AVAILABLE",
        paramedic_id=user.id,
    )

    db.add(ambulance)
    db.flush()

    return ambulance


def _social_user(db, email: str, full_name: str | None):
    user = db.scalar(
        select(User).where(User.email == email)
    )

    if not user:
        user = User(
            full_name=full_name or email.split("@")[0],
            email=email,
            password_hash=hash_password(secrets.token_urlsafe(32)),
            role=UserRole.PARAMEDIC,
        )

        db.add(user)
        db.flush()

        db.add(
            ParamedicProfile(
                user_id=user.id,
                availability_status="AVAILABLE",
            )
        )

        _create_default_ambulance(db, user)

        db.commit()
        db.refresh(user)

    elif user.role == UserRole.PARAMEDIC:
        ambulance = db.scalar(
            select(Ambulance)
            .where(Ambulance.paramedic_id == user.id)
            .limit(1)
        )

        if ambulance is None:
            _create_default_ambulance(db, user)
            db.commit()

    return user


@router.post(
    "/register",
    response_model=TokenResponse,
)
def register(
    data: RegisterRequest,
    db=Depends(get_db),
):
    existing = db.scalar(
        select(User).where(User.email == data.email)
    )

    if existing:
        raise HTTPException(
            409,
            "Email already registered",
        )

    user = User(
        full_name=data.full_name,
        email=data.email,
        phone=data.phone,
        password_hash=hash_password(data.password),
        role=UserRole.PARAMEDIC,
    )

    db.add(user)
    db.flush()

    db.add(
        ParamedicProfile(
            user_id=user.id,
            availability_status="AVAILABLE",
        )
    )

    # Every paramedic automatically owns one ambulance.
    _create_default_ambulance(db, user)

    db.commit()
    db.refresh(user)

    return TokenResponse(
        access_token=create_access_token(
            str(user.id),
            user.role.value,
        )
    )


@router.post(
    "/login",
    response_model=TokenResponse,
)
def login(
    data: LoginRequest,
    db=Depends(get_db),
):
    user = db.scalar(
        select(User).where(User.email == data.email)
    )

    if not user or not verify_password(
        data.password,
        user.password_hash,
    ):
        raise HTTPException(
            401,
            "Invalid email or password",
        )

    if not user.is_active:
        raise HTTPException(
            403,
            "User is inactive",
        )

    # Existing paramedics automatically get an ambulance
    # if the account was created before this rule was introduced.
    if user.role == UserRole.PARAMEDIC:
        ambulance = db.scalar(
            select(Ambulance)
            .where(Ambulance.paramedic_id == user.id)
            .limit(1)
        )

        if ambulance is None:
            _create_default_ambulance(db, user)
            db.commit()

    return TokenResponse(
        access_token=create_access_token(
            str(user.id),
            user.role.value,
        )
    )


@router.post(
    "/oauth/google",
    response_model=TokenResponse,
)
def google_login(
    data: OAuthRequest,
    db=Depends(get_db),
):
    claims = verify_google(data.id_token)

    email = claims.get("email")

    if not email:
        raise HTTPException(
            400,
            "Google account has no email",
        )

    user = _social_user(
        db,
        email,
        data.full_name or claims.get("name"),
    )

    return TokenResponse(
        access_token=create_access_token(
            str(user.id),
            user.role.value,
        )
    )


@router.post(
    "/oauth/apple",
    response_model=TokenResponse,
)
async def apple_login(
    data: OAuthRequest,
    db=Depends(get_db),
):
    claims = await verify_apple(data.id_token)

    email = claims.get("email")

    if not email:
        raise HTTPException(
            400,
            "Apple identity has no email",
        )

    user = _social_user(
        db,
        email,
        data.full_name or "RescuPath Paramedic",
    )

    return TokenResponse(
        access_token=create_access_token(
            str(user.id),
            user.role.value,
        )
    )


@router.post("/forgot-password")
def forgot_password(
    data: ForgotPasswordRequest,
    db=Depends(get_db),
):
    user = db.scalar(
        select(User).where(User.email == data.email)
    )

    response = {
        "message": "If the account exists, reset instructions have been sent."
    }

    if not user:
        return response

    raw = secrets.token_urlsafe(48)
    hashed = hashlib.sha256(raw.encode()).hexdigest()

    db.add(
        PasswordResetToken(
            user_id=user.id,
            token_hash=hashed,
            expires_at=(
                datetime.now(timezone.utc)
                + timedelta(minutes=30)
            ),
        )
    )

    db.commit()

    sent = send_password_reset_email(
        user.email,
        raw,
    )

    if settings.environment != "production" and not sent:
        response["development_token"] = raw

    return response


@router.post("/reset-password")
def reset_password(
    data: ResetPasswordRequest,
    db=Depends(get_db),
):
    hashed = hashlib.sha256(
        data.token.encode()
    ).hexdigest()

    row = db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == hashed,
            PasswordResetToken.used.is_(False),
        )
    )

    if not row or row.expires_at < datetime.now(timezone.utc):
        raise HTTPException(
            400,
            "Reset token is invalid or expired",
        )

    user = db.get(
        User,
        row.user_id,
    )

    user.password_hash = hash_password(
        data.new_password
    )

    row.used = True

    db.commit()

    return {
        "message": "Password reset successfully"
    }


@router.get(
    "/me",
    response_model=UserResponse,
)
def me(
    current_user=Depends(get_current_user),
):
    return current_user

@router.put("/me", response_model=UserResponse)
def update_me(
    data: ProfileUpdateRequest,
    db=Depends(get_db),
    current_user=Depends(get_current_user),
):
    current_user.full_name = data.full_name.strip()
    current_user.phone = data.phone.strip() if data.phone else None
    db.commit()
    db.refresh(current_user)
    return current_user


@router.put("/duty")
def update_duty_mode(
    data: DutyModeRequest,
    db=Depends(get_db),
    current_user=Depends(get_current_user),
):
    profile = db.scalar(
        select(ParamedicProfile).where(ParamedicProfile.user_id == current_user.id)
    )
    if not profile:
        profile = ParamedicProfile(user_id=current_user.id)
        db.add(profile)
    profile.availability_status = "AVAILABLE" if data.enabled else "OFF_DUTY"

    ambulance = db.scalar(
        select(Ambulance).where(Ambulance.paramedic_id == current_user.id).limit(1)
    )
    if ambulance and ambulance.status != "ON_EMERGENCY":
        ambulance.status = "AVAILABLE" if data.enabled else "OFF_DUTY"

    db.commit()
    return {
        "enabled": data.enabled,
        "availability_status": profile.availability_status,
        "ambulance_status": ambulance.status if ambulance else None,
    }
