from email.message import EmailMessage
import logging
import os
import smtplib
from app.core.config import settings

logger = logging.getLogger(__name__)


def send_password_reset_email(recipient: str, token: str) -> bool:
    smtp_host = settings.smtp_host or os.getenv("SMTP_HOST") or "smtp.gmail.com"
    smtp_port = settings.smtp_port or int(os.getenv("SMTP_PORT", "587"))
    smtp_username = settings.smtp_username or os.getenv("SMTP_USERNAME") or os.getenv("GMAIL_USER")
    smtp_password = settings.smtp_password or os.getenv("SMTP_PASSWORD") or os.getenv("GMAIL_APP_PASSWORD")
    smtp_from = settings.smtp_from or os.getenv("SMTP_FROM") or smtp_username

    if not all([smtp_host, smtp_username, smtp_password, smtp_from]):
        logger.warning("SMTP is not fully configured; skipping email dispatch.")
        return False

    try:
        message = EmailMessage()
        message["Subject"] = "RescuPath Password Reset"
        message["From"] = smtp_from
        message["To"] = recipient
        link = f"{settings.reset_base_url}/reset-password?token={token}"
        message.set_content(f"Reset your RescuPath password using this link:\n{link}\n\nThis link expires in 30 minutes.")

        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_username, smtp_password)
            server.send_message(message)
        return True
    except Exception as e:
        logger.error(f"Failed to send password reset email to {recipient}: {e}")
        return False


def send_password_reset_otp_email(recipient: str, otp: str, user_name: str | None = None) -> bool:
    smtp_host = settings.smtp_host or os.getenv("SMTP_HOST") or "smtp.gmail.com"
    smtp_port = settings.smtp_port or int(os.getenv("SMTP_PORT", "587"))
    smtp_username = (
        settings.smtp_username
        or os.getenv("SMTP_USERNAME")
        or os.getenv("SMTP_USER")
        or os.getenv("GMAIL_USER")
        or os.getenv("GMAIL_USERNAME")
        or os.getenv("GMAIL_ADDRESS")
    )
    smtp_password = (
        settings.smtp_password
        or os.getenv("SMTP_PASSWORD")
        or os.getenv("SMTP_PASS")
        or os.getenv("GMAIL_APP_PASSWORD")
        or os.getenv("GMAIL_PASSWORD")
    )
    smtp_from = settings.smtp_from or os.getenv("SMTP_FROM") or smtp_username or "noreply@rescupath.org"

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

    if not all([smtp_host, smtp_username, smtp_password]):
        logger.warning(f"SMTP credentials missing. Mocked OTP delivery for {recipient}: OTP={otp}")
        return False

    try:
        message = EmailMessage()
        message["Subject"] = f"RescuPath Security: Your Password Reset OTP is {otp}"
        message["From"] = smtp_from
        message["To"] = recipient
        message.set_content(plain_content)
        message.add_alternative(html_content, subtype="html")

        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_username, smtp_password)
            server.send_message(message)
        logger.info(f"Successfully sent password reset OTP email to {recipient}")
        return True
    except Exception as e:
        logger.error(f"Failed to dispatch password reset OTP email to {recipient}: {e}")
        return False
