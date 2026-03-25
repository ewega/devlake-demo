<#
.SYNOPSIS
    Sets up Apache DevLake with GitHub + Copilot connections using gh-devlake CLI.

.DESCRIPTION
    Deploys DevLake locally via Docker Compose (upstream images), creates GitHub
    and optionally GitHub Copilot connections, adds repository scopes with DORA
    configuration, creates a project, and triggers the first data collection.

    Prerequisites:
      - Docker Desktop running
      - GitHub CLI (gh) installed and authenticated
      - gh-devlake extension: gh extension install DevExpGBB/gh-devlake

.PARAMETER Pat
    GitHub PAT with scopes: repo, read:org, read:user.
    For Copilot: also manage_billing:copilot.
    Falls back to GITHUB_PAT env var or .env file.

.PARAMETER Org
    GitHub organization slug. Enables Copilot connection.
    Falls back to GITHUB_ORG env var or .env file.

.PARAMETER Repos
    Comma-separated repos to collect (owner/repo format).
    Default: apache/incubator-devlake

.PARAMETER ProjectName
    DevLake project name. Default: DevLake Demo

.PARAMETER Version
    DevLake image version tag. Default: latest

.PARAMETER SkipDeploy
    Skip deployment step (use if DevLake is already running).

.EXAMPLE
    .\setup.ps1 -Pat ghp_xxx123
    .\setup.ps1 -Pat ghp_xxx123 -Org my-org -Repos "my-org/repo1,my-org/repo2"
    .\setup.ps1 -SkipDeploy  # If DevLake is already running, uses env vars
#>

[CmdletBinding()]
param(
    [string]$Pat,
    [string]$Org,
    [string]$Repos,
    [string]$ProjectName,
    [string]$Version = "latest",
    [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve parameters from flags → env vars → .env file
# ---------------------------------------------------------------------------

function Read-EnvFile {
    $envFile = Join-Path $PSScriptRoot ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)$' -and $_ -notmatch '^\s*#') {
                [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim('"').Trim("'"), "Process")
            }
        }
    }
}

Read-EnvFile

if (-not $Pat)         { $Pat         = $env:GITHUB_PAT }
if (-not $Org)         { $Org         = $env:GITHUB_ORG }
if (-not $Repos)       { $Repos       = if ($env:REPOS) { $env:REPOS } else { "apache/incubator-devlake" } }
if (-not $ProjectName) { $ProjectName = if ($env:PROJECT_NAME) { $env:PROJECT_NAME } else { "DevLake Demo" } }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "===  DevLake Demo Setup  ===" -ForegroundColor Cyan
Write-Host ""

# Check gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: GitHub CLI (gh) is not installed. Install from https://cli.github.com/" -ForegroundColor Red
    exit 1
}

# Check gh-devlake extension
$extensions = gh extension list 2>&1
if ($extensions -notmatch "gh-devlake") {
    Write-Host "Installing gh-devlake extension..." -ForegroundColor Yellow
    gh extension install DevExpGBB/gh-devlake
}

# Check Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker is not installed. Install from https://docs.docker.com/get-docker/" -ForegroundColor Red
    exit 1
}

# Check PAT
if (-not $Pat) {
    Write-Host "ERROR: GitHub PAT is required. Pass -Pat, set GITHUB_PAT env var, or add to .env" -ForegroundColor Red
    exit 1
}

Write-Host "  PAT:     ****$(($Pat)[-4..-1] -join '')" -ForegroundColor Gray
Write-Host "  Org:     $(if ($Org) { $Org } else { '(none - Copilot connection skipped)' })" -ForegroundColor Gray
Write-Host "  Repos:   $Repos" -ForegroundColor Gray
Write-Host "  Project: $ProjectName" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1: Deploy DevLake
# ---------------------------------------------------------------------------

if (-not $SkipDeploy) {
    Write-Host "[1/5] Deploying DevLake locally..." -ForegroundColor Cyan
    gh devlake deploy local --source official --version $Version --dir $PSScriptRoot
    Write-Host ""
} else {
    Write-Host "[1/5] Skipping deployment (--SkipDeploy)" -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Step 2: Wait for healthy
# ---------------------------------------------------------------------------

Write-Host "[2/5] Checking DevLake health..." -ForegroundColor Cyan
$maxRetries = 30
$retryCount = 0
$healthy = $false

while (-not $healthy -and $retryCount -lt $maxRetries) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8080/ping" -TimeoutSec 5 -ErrorAction Stop
        $healthy = $true
        Write-Host "  DevLake is healthy" -ForegroundColor Green
    } catch {
        $retryCount++
        Write-Host "  Waiting for DevLake... ($retryCount/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $healthy) {
    Write-Host "ERROR: DevLake did not become healthy after $($maxRetries * 5) seconds" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 3: Create connections
# ---------------------------------------------------------------------------

Write-Host "[3/5] Creating connections..." -ForegroundColor Cyan

# GitHub connection
Write-Host "  Creating GitHub connection..." -ForegroundColor Gray
gh devlake configure connection add `
    --plugin github `
    --token $Pat `
    --name "GitHub"

# Copilot connection (optional)
if ($Org) {
    Write-Host "  Creating GitHub Copilot connection..." -ForegroundColor Gray
    gh devlake configure connection add `
        --plugin gh-copilot `
        --token $Pat `
        --org $Org `
        --name "GitHub Copilot - $Org"
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 4: Add scopes
# ---------------------------------------------------------------------------

Write-Host "[4/5] Adding scopes..." -ForegroundColor Cyan

# GitHub repo scopes with DORA config
Write-Host "  Adding repository scopes: $Repos" -ForegroundColor Gray
gh devlake configure scope add `
    --plugin github `
    --repos $Repos `
    --deployment-pattern "(?i)deploy" `
    --production-pattern "(?i)prod" `
    --incident-label "incident"

# Copilot scope (optional)
if ($Org) {
    Write-Host "  Adding Copilot scope: $Org" -ForegroundColor Gray
    gh devlake configure scope add `
        --plugin gh-copilot `
        --org $Org
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 5: Create project and trigger sync
# ---------------------------------------------------------------------------

Write-Host "[5/5] Creating project and triggering first sync..." -ForegroundColor Cyan
$connSpec = "github:1"
if ($Org) {
    $connSpec = "github:1,gh-copilot:1"
}
gh devlake configure project add `
    --project-name $ProjectName `
    --connections $connSpec

Write-Host ""
Write-Host "===  Setup Complete  ===" -ForegroundColor Green
Write-Host ""
Write-Host "  Grafana:    http://localhost:3002  (admin / admin)" -ForegroundColor White
Write-Host "  Config UI:  http://localhost:4000" -ForegroundColor White
Write-Host "  DevLake API: http://localhost:8080" -ForegroundColor White
Write-Host ""
Write-Host "  Data collection is running. Depending on repo size," -ForegroundColor Gray
Write-Host "  dashboards will populate in 10-30 minutes." -ForegroundColor Gray
Write-Host ""
Write-Host "  Check status:  gh devlake status" -ForegroundColor Gray
Write-Host "  Tear down:     gh devlake cleanup --local --force" -ForegroundColor Gray
Write-Host ""
