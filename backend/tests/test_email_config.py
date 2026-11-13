import os
from unittest.mock import MagicMock, patch
from email.message import EmailMessage
from app.services.email import (
    _mask_email,
    get_smtp_config,
    _dispatch_message,
    send_password_reset_otp_email,
)


def test_mask_email_safe():
    """Ensure email masking safely obscures identities and handles edge cases."""
    assert _mask_email("user@gmail.com") == "u***r@gmail.com"
    assert _mask_email("officer.command@rescupath.org") == "o***d@rescupath.org"
    assert _mask_email("a@b.com") == "a***@b.com"
    assert _mask_email("") == "[not configured]"
    assert _mask_email(None) == "[not configured]"
    assert _mask_email("invalid-no-at") == "[not configured]"


def test_smtp_config_space_stripping_and_defaults():
    """Verify that Google App Password spaces are stripped and defaults are applied."""
    with patch.dict(os.environ, {
        "SMTP_HOST": "smtp.gmail.com",
        "SMTP_PORT": "465",
        "SMTP_USERNAME": "testofficer@gmail.com",
        "SMTP_PASSWORD": "abcd efgh ijkl mnop",  # Google-style 4-group app password with spaces
        "SMTP_FROM": "noreply@rescupath.org",
    }):
        cfg = get_smtp_config()
        assert cfg["host"] == "smtp.gmail.com"
        assert cfg["port"] == 465
        assert cfg["username"] == "testofficer@gmail.com"
        # Verify spaces are cleanly stripped without altering characters
        assert cfg["password"] == "abcdefghijklmnop"
        assert " " not in cfg["password"]
        # Verify Gmail sender rule: envelope/from matches authenticated gmail address
        assert cfg["from_addr"] == "testofficer@gmail.com"
        assert cfg["is_smtp_configured"] is True


def test_dispatch_message_smtp_ssl_mock():
    """Verify successful SSL SMTP connection and send_message call without exposing secrets."""
    with patch.dict(os.environ, {
        "SMTP_HOST": "smtp.gmail.com",
        "SMTP_PORT": "465",
        "SMTP_USERNAME": "testsender@gmail.com",
        "SMTP_PASSWORD": "dummysecretpassword123",
        "SMTP_FROM": "testsender@gmail.com",
    }):
        mock_server = MagicMock()
        with patch("smtplib.SMTP_SSL") as mock_ssl:
            mock_ssl.return_value.__enter__.return_value = mock_server

            result = send_password_reset_otp_email(
                recipient="officer@agency.org",
                otp="654321",
                user_name="Officer Jane",
            )

            assert result is True
            mock_ssl.assert_called_once_with("smtp.gmail.com", 465, timeout=6)
            mock_server.login.assert_called_once_with("testsender@gmail.com", "dummysecretpassword123")
            assert mock_server.send_message.called


def test_dispatch_message_handles_missing_credentials_safely():
    """Verify unconfigured credentials return False safely without throwing or exposing secrets."""
    with patch.dict(os.environ, {
        "SMTP_HOST": "",
        "SMTP_USERNAME": "",
        "SMTP_PASSWORD": "",
        "RESEND_API_KEY": "",
    }, clear=True):
        result = send_password_reset_otp_email(
            recipient="test@example.com",
            otp="112233",
        )
        assert result is False
