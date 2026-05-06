# restart_and_deploy.ps1
# Full deploy: restarts tunnel + backend, rebuilds Flutter, deploys to Firebase.
# Use this when Flutter/Dart code has changed.
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

    Write-Host "      Deploying to Firebase..."
    firebase deploy --only hosting --project uhack26-8050e
    if ($LASTEXITCODE -ne 0) { Write-Host "Firebase deploy FAILED"; exit 1 }

    Write-Host "`n✓ Done! App live at https://uhack26-8050e.web.app"
} else {
    Write-Host "`n[5/5] Skipped Flutter build (-SkipBuild flag set)"
    Write-Host "      Run '.\restart_and_deploy.ps1' (without -SkipBuild) when ready to deploy."
}
