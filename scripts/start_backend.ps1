Set-Location "$PSScriptRoot\..\backend"
if (!(Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created backend/.env. Set SECRET_KEY and review configuration."
}
python -m venv .venv
& ".\.venv\Scripts\python.exe" -m pip install -r requirements.txt
docker compose -f ..\docker-compose.yml up -d postgres redis
& ".\.venv\Scripts\alembic.exe" upgrade head
& ".\.venv\Scripts\uvicorn.exe" app.main:app --reload
