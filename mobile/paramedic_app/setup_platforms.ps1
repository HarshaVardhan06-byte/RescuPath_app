$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not on PATH. Install Flutter first.'
}
flutter create .
Write-Host 'Flutter platform folders generated. The project lib/, pubspec.yaml and AndroidManifest.xml from this package can now be used.'
