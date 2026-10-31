<#
.SYNOPSIS
    Bootstraps the `.venv` Python environment, installs dependencies (`flask`,
    `mysql-connector-python`, `python-dotenv`), and launches the CVGPS Console
    at http://127.0.0.1:5000.
#>

param(
    [switch]$RunConcurrencyTest
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir  = Join-Path $RepoRoot ".venv"
$VenvPy   = Join-Path $VenvDir "Scripts\python.exe"

if (-not (Test-Path $VenvPy)) {
    Write-Host "==> Creating virtual environment in .venv..." -ForegroundColor Cyan
    python -m venv $VenvDir
}

Write-Host "==> Verifying Python dependencies..." -ForegroundColor Cyan
& $VenvPy -m pip install --quiet --disable-pip-version-check -r (Join-Path $RepoRoot "backend\requirements.txt")

if ($RunConcurrencyTest) {
    Write-Host "==> Running 10-thread Pessimistic Locking Concurrency Test..." -ForegroundColor Yellow
    & $VenvPy (Join-Path $RepoRoot "backend\concurrency_test.py")
    exit $LASTEXITCODE
}

Write-Host "==> Starting CVGPS Database-First Console at http://127.0.0.1:5000 ..." -ForegroundColor Green
& $VenvPy (Join-Path $RepoRoot "backend\app.py")

