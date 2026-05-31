################################################################################
#  deploy_web.ps1
#  First run  : full Flutter build + Amplify deploy
#  After that : only config.json is updated (3 seconds, no rebuild)
#  Requires   : amplify init + amplify add hosting (one-time setup)
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File scripts\deploy_web.ps1
################################################################################

$ErrorActionPreference = "Continue"
$root    = Split-Path $PSScriptRoot -Parent
$backend = Join-Path $root "backend"
$cf      = "$env:TEMP\cloudflared.exe"
$cfLog   = "$env:TEMP\cf_tunnel.log"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg)       { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── 1. cloudflared binary ────────────────────────────────────────────────────
Write-Step "Checking cloudflared..."
if (-not (Test-Path $cf)) {
    Write-Host "  Downloading cloudflared..."
    Invoke-WebRequest `
        -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" `
        -OutFile $cf -UseBasicParsing
}
Write-Host "  OK: $(&$cf --version)"

# ── 2. Kill stale processes ──────────────────────────────────────────────────
Write-Step "Stopping old processes..."
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# ── 3. Start backend ─────────────────────────────────────────────────────────
Write-Step "Starting FastAPI backend..."
$backendProc = Start-Process -FilePath "python" `
    -ArgumentList "-m uvicorn app.main:app --host 127.0.0.1 --port 8000" `
    -WorkingDirectory $backend -WindowStyle Hidden -PassThru

$ready = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/api/v1/health" -UseBasicParsing -TimeoutSec 2
        Write-Host "  Backend ready: $($r.Content)"
        $ready = $true; break
    } catch {}
}
if (-not $ready) { Fail "Backend did not start in time." }

# ── 4. Start Cloudflare tunnel ───────────────────────────────────────────────
Write-Step "Starting Cloudflare tunnel..."
if (Test-Path $cfLog) { Remove-Item $cfLog }
Start-Process -FilePath $cf `
    -ArgumentList "tunnel --url http://127.0.0.1:8000 --logfile `"$cfLog`"" `
    -WindowStyle Hidden

$tunnelUrl = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $cfLog) {
        $match = Select-String -Path $cfLog -Pattern "https://[a-z0-9\-]+\.trycloudflare\.com"
        if ($match) { $tunnelUrl = $match.Matches[0].Value; break }
    }
}
if (-not $tunnelUrl) { Fail "Could not get tunnel URL." }
Write-Host "  Tunnel: $tunnelUrl"

$apiUrl = "$tunnelUrl/api/v1"

# ── 5. Check if build/web exists (skip rebuild if already built) ─────────────
Set-Location $root
$needsBuild = -not (Test-Path "build\web\main.dart.js")

if ($needsBuild) {
    Write-Step "Building Flutter web (first time, ~40s)..."
    $buildOut = flutter build web `
        "--dart-define=APP_ENV=production" 2>&1
    $buildOut | Where-Object { $_ -match "Built|error" } | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { Fail "Flutter build failed." }
} else {
    Write-Host "`n==> Skipping Flutter rebuild (build already exists)"
}

# ── 6. Write config.json with current tunnel URL (no rebuild needed) ─────────
Write-Step "Writing config.json..."
$config = @{ apiBaseUrl = $apiUrl } | ConvertTo-Json
$config | Out-File -FilePath "build\web\config.json" -Encoding utf8
Write-Host "  API URL: $apiUrl"

# ── 7. Amplify deploy ────────────────────────────────────────────────────────
Write-Step "Deploying via Amplify..."
$depOut = amplify publish --yes 2>&1
$depOut | Where-Object { $_ -match "complete|Error|Hosting URL|release" } | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) { Fail "Amplify deploy failed." }

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Amplify deploy complete" -ForegroundColor Green
Write-Host "  Backend: http://127.0.0.1:8000" -ForegroundColor Green
Write-Host "  Tunnel:  $tunnelUrl" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tunnel activ. Tine fereastra deschisa." -ForegroundColor Yellow
Write-Host "Daca tunelul expira, ruleaza scriptul din nou (rebuild: NU)." -ForegroundColor Yellow
Read-Host "`nApasa ENTER pentru a opri"

Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force
$backendProc | Stop-Process -Force -ErrorAction SilentlyContinue
