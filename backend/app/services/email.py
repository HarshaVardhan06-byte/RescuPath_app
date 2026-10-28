from email.message import EmailMessage
import smtplib
from app.core.config import settings


def send_password_reset_email(recipient: str, token: str) -> bool:
    if not all([settings.smtp_host, settings.smtp_username, settings.smtp_password, settings.smtp_from]):
        return False
    message = EmailMessage()
    message["Subject"] = "RescuPath password reset"
    message["From"] = settings.smtp_from
    message["To"] = recipient
    link = f"{settings.reset_base_url}/reset-password?token={token}"
    message.set_content(f"Reset your RescuPath password using this link:\n{link}\n\nThis link expires in 30 minutes.")
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
        server.starttls()
        server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(message)
    return True
