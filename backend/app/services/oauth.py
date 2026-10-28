from __future__ import annotations
import httpx
from fastapi import HTTPException
from jose import jwt
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
from app.core.config import settings


def verify_google(token: str) -> dict:
    if not settings.google_web_client_id:
        raise HTTPException(503, "Google Sign-In is not configured on the server")
    try:
        info = google_id_token.verify_oauth2_token(token, google_requests.Request(), settings.google_web_client_id)
    except Exception as exc:
        raise HTTPException(401, "Invalid Google identity token") from exc
    if info.get("email_verified") is False:
        raise HTTPException(403, "Google email is not verified")
    return info


async def verify_apple(token: str) -> dict:
    if not settings.apple_service_id:
        raise HTTPException(503, "Apple Sign-In is not configured on the server")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            keys = (await client.get(settings.apple_jwks_url)).json()
        header = jwt.get_unverified_header(token)
        key = next((k for k in keys.get("keys", []) if k.get("kid") == header.get("kid")), None)
        if not key:
            raise ValueError("Apple signing key not found")
        claims = jwt.decode(token, key, algorithms=["RS256"], audience=settings.apple_service_id, issuer=settings.apple_issuer)
        return claims
    except Exception as exc:
        raise HTTPException(401, "Invalid Apple identity token") from exc
