from __future__ import annotations
import httpx
from fastapi import HTTPException
from jose import jwt
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
import os
from app.core.config import settings

FALLBACK_GOOGLE_CLIENT_ID = "1084797807505-ceafnjn387ilrjl7oi7iigr654vuh9o4.apps.googleusercontent.com"


def verify_google(token: str) -> dict:
    client_id = os.getenv("GOOGLE_WEB_CLIENT_ID") or settings.google_web_client_id or FALLBACK_GOOGLE_CLIENT_ID

    # 1. Direct OIDC verification with google-auth
    try:
        info = google_id_token.verify_oauth2_token(token, google_requests.Request(), client_id)
        if info.get("email_verified") is False:
            raise HTTPException(403, "Google email is not verified")
        return info
    except HTTPException:
        raise
    except Exception:
        pass

    # 2. Check tokeninfo endpoint (works for any valid Google ID token)
    try:
        with httpx.Client(timeout=10) as client:
            res = client.get(f"https://oauth2.googleapis.com/tokeninfo?id_token={token}")
            if res.status_code == 200:
                data = res.json()
                if data.get("email"):
                    if data.get("email_verified") in (False, "false"):
                        raise HTTPException(403, "Google email is not verified")
                    return data
    except HTTPException:
        raise
    except Exception:
        pass

    # 3. Check userinfo endpoint (works when token is an OAuth2 Access Token)
    try:
        with httpx.Client(timeout=10) as client:
            res = client.get("https://www.googleapis.com/oauth2/v3/userinfo", headers={"Authorization": f"Bearer {token}"})
            if res.status_code == 200:
                data = res.json()
                if data.get("email"):
                    return data
    except Exception:
        pass

    raise HTTPException(401, "Invalid Google identity token")


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
