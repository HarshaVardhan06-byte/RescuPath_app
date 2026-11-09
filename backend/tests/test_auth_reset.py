import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_forgot_password_and_reset_flow():
    test_email = f"test.user.{uuid.uuid4().hex[:8]}@rescupath.org"
    reg_res = client.post("/auth/register", json={
        "full_name": "Test Officer",
        "email": test_email,
        "password": "initialPassword123",
        "phone": "+919876543210",
    })
    assert reg_res.status_code == 200

    # Request password reset OTP
    res = client.post("/auth/forgot-password", json={"email": test_email})
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert "otp" in data
    otp = data["otp"]
    assert len(otp) == 6

    # Test reset password using the returned OTP
    reset_res = client.post("/auth/reset-password", json={
        "email": test_email,
        "otp": otp,
        "new_password": "newSecurePassword123",
    })
    assert reset_res.status_code == 200
    assert reset_res.json()["status"] == "success"

    # Verify login with the new password
    login_res = client.post("/auth/login", json={
        "email": test_email,
        "password": "newSecurePassword123",
    })
    assert login_res.status_code == 200
    assert "access_token" in login_res.json()
