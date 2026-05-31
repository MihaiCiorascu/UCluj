# orient.ps1
# Prints the canonical-worktree banner and verifies that the current location
# is the one true source of truth for the UmbraRo thesis and app work.
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\orient.ps1
#
# Exit code 0 when run from the canonical worktree, 1 otherwise.

$ErrorActionPreference = 'Stop'

$Canonical = 'C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack\.claude\worktrees\elated-swirles-549361'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  UmbraRo: CANONICAL WORKTREE' -ForegroundColor Cyan
Write-Host '  Continue ALL work from here. Other worktrees are outdated.' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ("Canonical path : {0}" -f $Canonical)
Write-Host ("Canonical branch: claude/elated-swirles-549361")
Write-Host ''

# 1. Location check: compare the CURRENT working directory to the canonical path.
$here = (Get-Location).Path.TrimEnd('\')
if ($here -ieq $Canonical.TrimEnd('\')) {
    Write-Host '[OK] Your current directory IS the canonical worktree.' -ForegroundColor Green
    $inCanonical = $true
} else {
    Write-Host '[WARN] Your current directory is NOT the canonical worktree.' -ForegroundColor Yellow
    Write-Host ("       You are in : {0}" -f $here) -ForegroundColor Yellow
    Write-Host ("       cd into    : {0}" -f $Canonical) -ForegroundColor Yellow
    $inCanonical = $false
}
Write-Host ''

# 2. Branch check
try {
    $branch = (git -C $Canonical rev-parse --abbrev-ref HEAD).Trim()
    Write-Host ("Current branch : {0}" -f $branch)
} catch {
    Write-Host '[WARN] Could not read the git branch.' -ForegroundColor Yellow
}

# 3. Uncommitted-work warning
try {
    $changes = (git -C $Canonical status --short)
    $count = ($changes | Measure-Object -Line).Lines
    Write-Host ''
    Write-Host ("[!] Source of truth is the UNCOMMITTED working tree: {0} changed entries." -f $count) -ForegroundColor Magenta
    Write-Host '    Do NOT run git reset --hard or git checkout -- . here. It would destroy the work.' -ForegroundColor Magenta
    Write-Host '    A push to main is NOT authorised. Ask before pushing.' -ForegroundColor Magenta
} catch {
    Write-Host '[WARN] Could not read git status.' -ForegroundColor Yellow
}

# 4. Worktree map
Write-Host ''
Write-Host 'Worktrees (only the first is canonical):'
try {
    git -C $Canonical worktree list | ForEach-Object {
        if ($_ -match 'elated-swirles-549361') {
            Write-Host ("  [CANONICAL] {0}" -f $_) -ForegroundColor Green
        } else {
            Write-Host ("  [outdated ] {0}" -f $_) -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Host '[WARN] Could not list worktrees.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Read START_HERE.md in this folder for the full orientation.' -ForegroundColor Cyan
Write-Host ''

if ($inCanonical) { exit 0 } else { exit 1 }
