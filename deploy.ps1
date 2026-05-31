# deploy.ps1 - Ruleaza din folderul ucluj-hackathon
# Porneste backend, tunel cloudflare si face deploy pe AWS Amplify Hosting
# Requires: amplify init + amplify add hosting (one-time setup)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot
$backendDir = Join-Path $rootDir "backend"
$venvPython = "C:\Users\xrebe\OneDrive\Desktop\HackatonU\venv\Scripts\python.exe"

Write-Host "=== PORNIRE BACKEND ===" -ForegroundColor Cyan

# Verifica daca backenu-ul deja ruleaza pe portul 8000
$existing = netstat -ano | Select-String ":8000\s+.*LISTENING"
if ($existing) {
    Write-Host "Backend deja ruleaza pe portul 8000." -ForegroundColor Green
} else {
    Write-Host "Pornesc backend-ul..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backendDir'; & '$venvPython' -m uvicorn app.main:app --host 127.0.0.1 --port 8000" -WindowStyle Normal
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "=== PORNIRE TUNEL CLOUDFLARE PENTRU BACKEND ===" -ForegroundColor Cyan
Write-Host "Astept URL-ul tunelului..." -ForegroundColor Yellow

# Porneste tunelul si captureaza output-ul
$tunnelOutput = ""
$job = Start-Job -ScriptBlock {
    npx cloudflared tunnel --url http://127.0.0.1:8000 2>&1
}

# Asteapta pana apare URL-ul
$tunnelUrl = ""
$timeout = 60
$elapsed = 0
while ($elapsed -lt $timeout -and $tunnelUrl -eq "") {
    Start-Sleep -Seconds 2
    $elapsed += 2
    $output = Receive-Job $job
    $tunnelOutput += $output
    $match = [regex]::Match($tunnelOutput, "https://[a-z0-9-]+\.trycloudflare\.com")
    if ($match.Success) {
        $tunnelUrl = $match.Value
    }
}

if ($tunnelUrl -eq "") {
    Write-Host "EROARE: Nu am putut obtine URL-ul tunelului!" -ForegroundColor Red
    Stop-Job $job
    exit 1
}

$apiUrl = "$tunnelUrl/api/v1"
Write-Host ""
Write-Host "URL Backend: $apiUrl" -ForegroundColor Green
Write-Host ""

# Update web/config.json so AppConfig.load() uses the correct URL
$configPath = Join-Path $rootDir "web\config.json"
if (Test-Path $configPath) {
    $configJson = @{ apiBaseUrl = $apiUrl } | ConvertTo-Json
    $configJson | Out-File -FilePath $configPath -Encoding utf8
    Write-Host "Updated web/config.json with tunnel URL." -ForegroundColor Gray
}

Write-Host "=== BUILD FLUTTER WEB ===" -ForegroundColor Cyan
Set-Location $rootDir
flutter build web `
    --dart-define=APP_ENV=development `
    "--dart-define=API_BASE_URL=$apiUrl" `
    --base-href=/

if ($LASTEXITCODE -ne 0) {
    Write-Host "EROARE la build Flutter!" -ForegroundColor Red
    Stop-Job $job
    exit 1
}

Write-Host ""
Write-Host "=== DEPLOY PE AWS AMPLIFY HOSTING ===" -ForegroundColor Cyan
amplify publish --yes

if ($LASTEXITCODE -ne 0) {
    Write-Host "EROARE la deploy Amplify!" -ForegroundColor Red
    Stop-Job $job
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "SUCCES! App deployed via Amplify." -ForegroundColor Green
Write-Host "  Backend API: $apiUrl" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tunelul backend ruleaza in fundal. NU inchide aceasta fereastra!" -ForegroundColor Yellow
Write-Host "Apasa Ctrl+C pentru a opri tunelul." -ForegroundColor Yellow

# Mentine tunelul activ
Receive-Job $job -Wait
