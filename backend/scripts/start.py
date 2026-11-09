"""Resilient production startup script for RescuPath Backend on Render / Linux."""
import os
import subprocess
import sys

def main():
    print("=========================================")
    print(" RescuPath Emergency Coordination Backend")
    print("=========================================")

    # 1. Run migrations safely
    try:
        print("[1/3] Running database migrations...")
        result = subprocess.run(["alembic", "upgrade", "head"], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Alembic migration warning:\n{result.stderr}")
        else:
            print("Database migrations completed.")
    except Exception as e:
        print(f"Skipping migration step due to: {e}")

    # 2. Run seed demo data
    try:
        print("[2/3] Seeding demo hospitals and verified directory...")
        result = subprocess.run([sys.executable, "scripts/seed_demo.py"], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Seed notice:\n{result.stderr}")
        else:
            print("Seed demo script completed successfully.")
    except Exception as e:
        print(f"Skipping seed step due to: {e}")

    # 3. Launch Uvicorn
    port = os.environ.get("PORT", "8000")
    host = os.environ.get("HOST", "0.0.0.0")
    print(f"[3/3] Starting Uvicorn API server on {host}:{port}...")
    sys.stdout.flush()

    uvicorn_cmd = [
        sys.executable, "-m", "uvicorn", "app.main:app",
        "--host", host,
        "--port", str(port),
    ]
    sys.exit(subprocess.call(uvicorn_cmd))

if __name__ == "__main__":
    main()
