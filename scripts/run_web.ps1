# Fixed URL: http://127.0.0.1:8080
Set-Location $PSScriptRoot\..
flutter run -d chrome `
  --web-hostname=127.0.0.1 `
  --web-port=8080 `
  --dart-define=APP_ENV=development `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
