<#
.SYNOPSIS
    Initializes the CVGPS Database (`cvgps_pro`), populates the 22-scenario edge-case
    seed data matrix, and optionally runs the 38-assertion automated business-rule
    verification suite.
#>

param(
    [switch]$RunTests,
    [switch]$RunExplain
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
if (-not (Test-Path $MysqlExe)) {
    $MysqlExe = "mysql"
}

# Read root credentials from backend/.env if present
$RootUser = "root"
$RootPass = "Admin@123"
$EnvFile  = Join-Path $RepoRoot "backend\.env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match "^DB_ROOT_USER=(.+)$")     { $RootUser = $Matches[1].Trim() }
        if ($_ -match "^DB_ROOT_PASSWORD=(.+)$") { $RootPass = $Matches[1].Trim() }
    }
}

$TempCnf = Join-Path $env:TEMP "cvgps_setup_$([guid]::NewGuid().ToString('N')).cnf"
@"
[client]
user=$RootUser
password=$RootPass
host=localhost
port=3306
default-character-set=utf8mb4
"@ | Set-Content -Path $TempCnf -Encoding ASCII

try {
    Write-Host "==> [1/2] Applying database/01_production_schema.sql (DDL, Triggers, Procs, Views, Event, Grants)..." -ForegroundColor Cyan
    Get-Content (Join-Path $RepoRoot "database\01_production_schema.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf"
    if ($LASTEXITCODE -ne 0) { throw "01_production_schema.sql failed with exit code $LASTEXITCODE" }

    Write-Host "==> [2/2] Applying database/02_seed_data.sql (Edge-Case Seed Data Matrix)..." -ForegroundColor Cyan
    Get-Content (Join-Path $RepoRoot "database\02_seed_data.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "02_seed_data.sql failed with exit code $LASTEXITCODE" }

    if ($RunTests) {
        Write-Host "==> Running database/04_test_business_rules.sql (38 Automated Assertions)..." -ForegroundColor Yellow
        Get-Content (Join-Path $RepoRoot "database\04_test_business_rules.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf" --table
        Write-Host "==> Restoring clean seed state after test mutations..." -ForegroundColor Cyan
        Get-Content (Join-Path $RepoRoot "database\01_production_schema.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf"
        Get-Content (Join-Path $RepoRoot "database\02_seed_data.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf" | Out-Null
    }

    if ($RunExplain) {
        Write-Host "==> Running database/03_indexing_and_explain.sql (50,000-row EXPLAIN ANALYZE Benchmarks)..." -ForegroundColor Yellow
        Get-Content (Join-Path $RepoRoot "database\03_indexing_and_explain.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf" --table
        Write-Host "==> Restoring clean seed state after load benchmark..." -ForegroundColor Cyan
        Get-Content (Join-Path $RepoRoot "database\01_production_schema.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf"
        Get-Content (Join-Path $RepoRoot "database\02_seed_data.sql") -Raw | & $MysqlExe "--defaults-extra-file=$TempCnf" | Out-Null
    }

    Write-Host "==> SUCCESS: Database 'cvgps_pro' and least-privilege user 'gp_app' are ready!" -ForegroundColor Green
}
finally {
    Remove-Item -Force $TempCnf -ErrorAction SilentlyContinue
}

