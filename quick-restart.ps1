# quick-restart.ps1
# Restarts the Cloudflare tunnel + Python backend, updates config.json,
# and deploys ONLY hosting via Amplify — no Flutter rebuild needed.
# Requires: amplify init + amplify add hosting (one-time setup)
#
# Use this every time the tunnel dies (PC sleep, crash, etc.).
# Takes ~25-35 s instead of the ~3 min full restart_and_deploy.ps1.
#
# Usage:
#   .\quick-restart.ps1              # full run (tunnel + backend + Amplify deploy)
#   .\quick-restart.ps1 -SkipDeploy # skip deploy (local testing only)

param([switch]$SkipDeploy)

$Root    = "C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack"
$Backend = "$Root\backend"
$CfBin   = "C:\Users\Mihai\AppData\Local\npm-cache\_npx\8a26fc3a61fe4212\node_modules\cloudflared\bin\cloudflared.exe"
$CfLog   = "C:\temp\cf_tunnel.log"
$UvLog   = "C:\temp\uvicorn_err.log"

# ── 1. Kill old processes ────────────────────────────────────────────────────
Write-Host "`n[1/5] Stopping old processes..."
Stop-Process -Name "cloudflared","python" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ── 2. Start new Cloudflare tunnel ──────────────────────────────────────────
Write-Host "[2/5] Starting Cloudflare tunnel..."
New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
Remove-Item $CfLog -ErrorAction SilentlyContinue
Start-Process -FilePath $CfBin -ArgumentList "tunnel --url http://localhost:8000" `
    -RedirectStandardError $CfLog -NoNewWindow

$tunnelUrl = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    $log = Get-Content $CfLog -Raw -ErrorAction SilentlyContinue
    if ($log -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
        $tunnelUrl = $Matches[0]
        break
    }
}
if (-not $tunnelUrl) {
    Write-Host "ERROR: Could not get tunnel URL. Check $CfLog"
    exit 1
}
Write-Host "   Tunnel: $tunnelUrl"

# ── 3. Update config.json in BOTH locations ──────────────────────────────────
#   web/config.json       → used by future `flutter build web` runs
#   build/web/config.json → used by the current Amplify deploy (no rebuild needed)
Write-Host "[3/5] Updating config.json..."
$configJson = "{`"apiBaseUrl`": `"$tunnelUrl/api/v1`"}"
Set-Content -Path "$Root\web\config.json"       -Value $configJson -Encoding utf8
Set-Content -Path "$Root\build\web\config.json" -Value $configJson -Encoding utf8
Write-Host "   config.json → $tunnelUrl/api/v1"

# Patch CORS in main.py (add new URL if not already present)
$mainPy = Get-Content "$Backend\app\main.py" -Raw
if ($mainPy -notmatch [regex]::Escape($tunnelUrl)) {
    $mainPy = $mainPy -replace '(allow_origins=\[)', "`$1`n        `"$tunnelUrl`","
    Set-Content "$Backend\app\main.py" $mainPy -Encoding utf8
    Write-Host "   CORS updated in main.py"
}

# ── 4. Start uvicorn backend ─────────────────────────────────────────────────
Write-Host "[4/5] Starting backend..."
Set-Location $Backend
Start-Process -FilePath "python" `
    -ArgumentList "-m uvicorn app.main:app --host 127.0.0.1 --port 8000" `
    -RedirectStandardError $UvLog -NoNewWindow
Start-Sleep -Seconds 5

$uvLog = Get-Content $UvLog -Raw -ErrorAction SilentlyContinue
if ($uvLog -match "Application startup complete") {
    Write-Host "   Backend OK"
} else {
    Write-Host "   WARNING: backend may not be ready yet — check $UvLog"
}

# ── 5. Deploy ONLY hosting (no Flutter rebuild) ──────────────────────────────
if (-not $SkipDeploy) {
    Write-Host "[5/5] Deploying config via Amplify — no Flutter rebuild..."
    Set-Location $Root
    amplify publish --yes
    Write-Host "`n✓ Done! Amplify deploy complete."
} else {
    Write-Host "[5/5] Skipped Amplify deploy (-SkipDeploy flag set)"
    Write-Host "   Tunnel is live at $tunnelUrl"
}
