# restart_and_deploy.ps1
# Full deploy: restarts tunnel + backend, rebuilds Flutter, deploys via Amplify.
# Use this when Flutter/Dart code has changed.
# Requires: amplify init + amplify add hosting (one-time setup)
#
# For tunnel-only restarts (no code changes), use:
#   .\quick-restart.ps1   (~30 s, no Flutter rebuild)
#
# Run from the repo root: .\restart_and_deploy.ps1

param(
    [switch]$SkipBuild   # pass -SkipBuild to restart services only (no Flutter build or deploy)
)

$Root = "C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack"

# ── Steps 1-4: tunnel + backend + config  (delegated to quick-restart.ps1) ──
Write-Host "=== Restarting services via quick-restart.ps1 ==="
& "$Root\quick-restart.ps1" -SkipDeploy
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ── Step 5: Flutter rebuild + full deploy ────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`n[5/5] Building Flutter web..."
    Set-Location $Root
    flutter build web --release
    if ($LASTEXITCODE -ne 0) { Write-Host "Flutter build FAILED"; exit 1 }

    Write-Host "      Deploying via Amplify..."
    amplify publish --yes
    if ($LASTEXITCODE -ne 0) { Write-Host "Amplify deploy FAILED"; exit 1 }

    Write-Host "`n✓ Done! Amplify deploy complete."
} else {
    Write-Host "`n[5/5] Skipped Flutter build (-SkipBuild flag set)"
    Write-Host "      Run '.\restart_and_deploy.ps1' (without -SkipBuild) when ready to deploy."
}
