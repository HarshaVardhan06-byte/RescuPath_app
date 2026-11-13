from email.message import EmailMessage
import logging
import os
import smtplib
from typing import Any
from app.core.config import settings

logger = logging.getLogger(__name__)


def _mask_email(email: str | None) -> str:
    """Mask email for safe diagnostic logging without exposing full identity."""
    if not email or "@" not in email:
        return "[not configured]"
    parts = email.strip().split("@")
    name, domain = parts[0], parts[1]
    masked_name = name[0] + "***" + (name[-1] if len(name) > 1 else "")
    return f"{masked_name}@{domain}"


def get_smtp_config() -> dict[str, Any]:
    """Retrieve and sanitize SMTP configuration without exposing secrets."""
    host = (os.getenv("SMTP_HOST") or settings.smtp_host or "smtp.gmail.com").strip()
    raw_port = os.getenv("SMTP_PORT") or settings.smtp_port or 465
    try:
        port = int(raw_port)
    except (ValueError, TypeError):
        port = 465

    raw_user = (
        os.getenv("SMTP_USERNAME")
        or os.getenv("SMTP_USER")
        or os.getenv("GMAIL_USER")
        or os.getenv("GMAIL_USERNAME")
        or os.getenv("GMAIL_ADDRESS")
        or settings.smtp_username
    )
    raw_pass = (
        os.getenv("SMTP_PASSWORD")
        or os.getenv("SMTP_PASS")
        or os.getenv("GMAIL_APP_PASSWORD")
        or os.getenv("GMAIL_PASSWORD")
        or settings.smtp_password
    )
    raw_from = (
        os.getenv("SMTP_FROM")
        or settings.smtp_from
    )

    username = str(raw_user).strip() if raw_user else None
    # Strip spaces from Google App Passwords (e.g. 'abcd efgh ijkl mnop' -> 'abcdefghijklmnop')
    password = str(raw_pass).strip().replace(" ", "") if raw_pass else None

    # Sender address defaults to authenticated username for Gmail SPF/DMARC compatibility
    from_addr = str(raw_from).strip() if raw_from else (username or "noreply@rescupath.org")
    if username and "@gmail.com" in username.lower() and "@gmail.com" not in from_addr.lower():
        from_addr = username

    resend_key = os.getenv("RESEND_API_KEY") or getattr(settings, "resend_api_key", None)

    return {
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "from_addr": from_addr,
        "resend_key": str(resend_key).strip() if resend_key else None,
        "is_smtp_configured": bool(host and username and password),
        "is_https_configured": bool(resend_key),
    }


def _dispatch_message(message: EmailMessage, recipient: str, plain_content: str, html_content: str) -> bool:
    """Deliver an email message using HTTPS API (if configured) or direct SMTP."""
    cfg = get_smtp_config()
    masked_to = _mask_email(recipient)
    masked_from = _mask_email(cfg["from_addr"])
    masked_user = _mask_email(cfg["username"])

    logger.info(f"[EMAIL_DISPATCH] Initiating email delivery to {masked_to} (from={masked_from})")

    # 1. Check for HTTPS API fallback (Resend over Port 443 - bypasses cloud SMTP port blocks)
    if cfg["is_https_configured"]:
        try:
            logger.info(f"[EMAIL_HTTPS] Attempting HTTPS email delivery via Resend API (Port 443) to {masked_to}")
            import httpx
            with httpx.Client(timeout=10) as client:
                res = client.post(
                    "https://api.resend.com/emails",
                    headers={"Authorization": f"Bearer {cfg['resend_key']}"},
                    json={
                        "from": f"RescuPath <{cfg['from_addr']}>" if "<" not in cfg["from_addr"] else cfg["from_addr"],
                        "to": [recipient],
                        "subject": str(message["Subject"]),
                        "html": html_content,
                        "text": plain_content,
                    },
                )
                if res.status_code in (200, 201):
                    logger.info(f"[EMAIL_SUCCESS] Email delivered successfully to {masked_to} via HTTPS API (Port 443)")
                    return True
                else:
                    logger.warning(f"[EMAIL_HTTPS_FAIL] Resend API responded with status {res.status_code}: {res.text}")
        except Exception as https_err:
            logger.warning(f"[EMAIL_HTTPS_ERROR] HTTPS dispatch error: {type(https_err).__name__}: {https_err}")

    # 2. Check SMTP credentials
    if not cfg["is_smtp_configured"]:
        logger.warning(
            f"[EMAIL_UNCONFIGURED] SMTP is not fully configured (missing SMTP_USERNAME or SMTP_PASSWORD). "
            f"Cannot dispatch email to {masked_to}."
        )
        return False

    smtp_host = cfg["host"]
    configured_port = cfg["port"]
    smtp_username = cfg["username"]
    smtp_password = cfg["password"]

    # Determine connection candidates: Port 465 MUST use SSL; Port 587 MUST use STARTTLS
    candidates: list[tuple[int, bool]] = []
    if configured_port == 465:
        candidates = [(465, True), (587, False)]
    elif configured_port == 587:
        candidates = [(587, False), (465, True)]
    else:
        candidates = [(configured_port, False), (465, True), (587, False)]

    last_error: Exception | None = None
    timeout_seconds = 6

    for port, use_ssl in candidates:
        try:
            logger.info(
                f"[EMAIL_SMTP_CONNECT] Connecting to {smtp_host}:{port} "
                f"(ssl={use_ssl}, auth_user={masked_user}, timeout={timeout_seconds}s)"
            )
            if use_ssl:
                with smtplib.SMTP_SSL(smtp_host, port, timeout=timeout_seconds) as server:
                    logger.info(f"[EMAIL_SMTP_AUTH] Authenticating with {smtp_host}:{port}...")
                    server.login(smtp_username, smtp_password)
                    logger.info(f"[EMAIL_SMTP_SEND] Sending message to {masked_to}...")
                    server.send_message(message, from_addr=smtp_username)
                    logger.info(f"[EMAIL_SUCCESS] Successfully delivered email to {masked_to} via {smtp_host}:{port} (SSL)")
                    return True
            else:
                with smtplib.SMTP(smtp_host, port, timeout=timeout_seconds) as server:
                    logger.info(f"[EMAIL_SMTP_STARTTLS] Issuing STARTTLS on {smtp_host}:{port}...")
                    server.starttls()
                    logger.info(f"[EMAIL_SMTP_AUTH] Authenticating with {smtp_host}:{port}...")
                    server.login(smtp_username, smtp_password)
                    logger.info(f"[EMAIL_SMTP_SEND] Sending message to {masked_to}...")
                    server.send_message(message, from_addr=smtp_username)
                    logger.info(f"[EMAIL_SUCCESS] Successfully delivered email to {masked_to} via {smtp_host}:{port} (STARTTLS)")
                    return True

        except smtplib.SMTPAuthenticationError as auth_err:
            last_error = auth_err
            logger.error(
                f"[EMAIL_AUTH_FAIL] SMTP Authentication failed on {smtp_host}:{port} for {masked_user}. "
                f"Reason: {auth_err}. "
                f"Verify: 1) SMTP_USERNAME is the full Gmail address, 2) SMTP_PASSWORD is a valid 16-character Google App Password (not account password), 3) 2-Step Verification is enabled on the Google Account."
            )
            # Bad credentials won't succeed on other ports
            break

        except (TimeoutError, smtplib.SMTPConnectError, OSError) as net_err:
            last_error = net_err
            logger.warning(
                f"[EMAIL_PORT_BLOCKED] Connection to {smtp_host}:{port} failed ({type(net_err).__name__}: {net_err}). "
                f"Note: Free-tier instances on Render block outbound SMTP ports 25, 465, and 587. "
                f"Render requires upgrading to Starter ($7/mo) to open ports 465/587, or using an HTTPS API."
            )
            continue

        except Exception as gen_err:
            last_error = gen_err
            logger.warning(f"[EMAIL_SMTP_FAIL] SMTP attempt on {smtp_host}:{port} failed: {type(gen_err).__name__}: {gen_err}")
            continue

    logger.error(
        f"[EMAIL_DISPATCH_FAILED] All delivery attempts to {masked_to} failed. "
        f"Final error: {type(last_error).__name__}: {last_error}"
    )
    return False


def send_password_reset_otp_email(recipient: str, otp: str, user_name: str | None = None) -> bool:
    cfg = get_smtp_config()
    sender = cfg["from_addr"]
    from_header = f"RescuPath <{sender}>" if "<" not in sender else sender

    greeting = f"Hello {user_name}," if user_name else "Hello,"
    plain_content = (
        f"{greeting}\n\n"
        f"We received a request to reset your password for your RescuPath account.\n\n"
        f"Your One-Time Password (OTP) verification code is:\n"
        f"====== {otp} ======\n\n"
        f"This code is valid for 15 minutes. Enter it in the RescuPath login screen to set a new password.\n\n"
        f"If you did not request this password reset, please ignore this email.\n\n"
        f"Best regards,\n"
        f"RescuPath Emergency Coordination Support"
    )

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0A1930; color: #FFFFFF; margin: 0; padding: 20px; }}
        .card {{ background: #112240; border-radius: 16px; max-width: 520px; margin: 0 auto; padding: 32px; border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 20px 40px rgba(0,0,0,0.4); }}
        .badge {{ background: #E63946; color: #FFFFFF; font-weight: 800; font-size: 11px; padding: 4px 10px; border-radius: 20px; display: inline-block; letter-spacing: 0.5px; text-transform: uppercase; }}
        .header {{ margin-top: 16px; font-size: 24px; font-weight: 900; color: #FFFFFF; }}
        .text {{ color: #BAC8E5; font-size: 14px; line-height: 1.6; margin: 16px 0; }}
        .otp-box {{ background: linear-gradient(135deg, #1E3A8A 0%, #0A1930 100%); border: 2px dashed #00A8E8; border-radius: 12px; padding: 20px; text-align: center; margin: 24px 0; }}
        .otp-code {{ font-size: 36px; font-weight: 900; letter-spacing: 8px; color: #00A8E8; margin: 0; }}
        .footer {{ font-size: 12px; color: #64748B; border-top: 1px solid rgba(255,255,255,0.08); padding-top: 16px; margin-top: 24px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <span class="badge">Emergency Network Security</span>
        <div class="header">Password Reset Request</div>
        <p class="text">{greeting}</p>
        <p class="text">You recently requested to reset your password for the RescuPath Coordination Network. Please use the following 6-digit verification code:</p>
        <div class="otp-box">
          <div class="otp-code">{otp}</div>
        </div>
        <p class="text">This code will expire in <strong>15 minutes</strong>. Enter this OTP on your login screen to confirm and set your new password.</p>
        <div class="footer">
          If you did not initiate this request, you can safely discard this email.<br>
          &copy; RescuPath Agency Coordination Network. All rights reserved.
        </div>
      </div>
    </body>
    </html>
    """

    message = EmailMessage()
    message["Subject"] = f"RescuPath Security: Your Password Reset OTP is {otp}"
    message["From"] = from_header
    message["To"] = recipient
    message.set_content(plain_content)
    message.add_alternative(html_content, subtype="html")

    return _dispatch_message(message, recipient, plain_content, html_content)


def send_password_reset_email(recipient: str, token: str) -> bool:
    cfg = get_smtp_config()
    sender = cfg["from_addr"]
    from_header = f"RescuPath <{sender}>" if "<" not in sender else sender

    link = f"{settings.reset_base_url}/reset-password?token={token}"
    plain_content = (
        f"Reset your RescuPath password using this link:\n{link}\n\n"
        f"This link expires in 30 minutes."
    )
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="font-family: sans-serif; background-color: #0A1930; color: #FFFFFF; padding: 24px;">
      <div style="background: #112240; border-radius: 12px; max-width: 500px; margin: 0 auto; padding: 24px;">
        <h2 style="color: #00A8E8;">RescuPath Password Reset</h2>
        <p>Click below to reset your password:</p>
        <p><a href="{link}" style="display: inline-block; background: #00A8E8; color: #FFFFFF; padding: 10px 20px; border-radius: 6px; text-decoration: none; font-weight: bold;">Reset Password</a></p>
        <p style="font-size: 12px; color: #64748B;">This link expires in 30 minutes.</p>
      </div>
    </body>
    </html>
    """

    message = EmailMessage()
    message["Subject"] = "RescuPath Password Reset"
    message["From"] = from_header
    message["To"] = recipient
    message.set_content(plain_content)
    message.add_alternative(html_content, subtype="html")

    return _dispatch_message(message, recipient, plain_content, html_content)
