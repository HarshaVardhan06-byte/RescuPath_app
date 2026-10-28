$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root 'backend'
$Apps = @(
  @{ Name = 'RescuPath API'; Path = $Backend; Command = "`$ErrorActionPreference='Stop'; Set-Location '$Backend'; if (!(Test-Path '.venv\Scripts\python.exe')) { throw 'Create backend .venv and install requirements first.' }; & '.venv\Scripts\python.exe' -m alembic upgrade head; if (`$LASTEXITCODE -ne 0) { throw 'Alembic migration failed; backend not started.' }; & '.venv\Scripts\python.exe' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000" },
  @{ Name = 'RescuPath Paramedic'; Path = (Join-Path $Root 'mobile\paramedic_app'); Command = "Set-Location '$(Join-Path $Root 'mobile\paramedic_app')'; flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5050" },
  @{ Name = 'RescuPath Police'; Path = (Join-Path $Root 'mobile\police_app'); Command = "Set-Location '$(Join-Path $Root 'mobile\police_app')'; flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5051" },
  @{ Name = 'RescuPath Hospital'; Path = (Join-Path $Root 'mobile\hospital_app'); Command = "Set-Location '$(Join-Path $Root 'mobile\hospital_app')'; flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5052" }
)
foreach ($app in $Apps) {
  if (!(Test-Path $app.Path)) { throw "Missing app directory: $($app.Path)" }
}
foreach ($app in $Apps) {
  Start-Process powershell.exe -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $app.Command) -WorkingDirectory $app.Path
}
Write-Host 'Started backend and three frontend terminal windows.' -ForegroundColor Green
Write-Host 'URLs: API docs http://127.0.0.1:8000/docs | Paramedic 5050 | Police 5051 | Hospital 5052'
Write-Host 'Run flutter pub get once in each app first. Keep backend/.env private and configured.'
