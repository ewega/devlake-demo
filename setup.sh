#!/usr/bin/env bash
# =============================================================================
# DevLake Demo Setup — uses gh-devlake CLI
# =============================================================================
#
# Usage:
#   ./setup.sh                                   # uses .env / env vars
#   ./setup.sh --pat ghp_xxx                     # explicit PAT
#   ./setup.sh --pat ghp_xxx --org my-org        # + Copilot connection
#   ./setup.sh --skip-deploy                     # DevLake already running
#
# Prerequisites:
#   - Docker running
#   - gh CLI installed and authenticated
#   - gh extension install DevExpGBB/gh-devlake
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PAT="${GITHUB_PAT:-}"
ORG="${GITHUB_ORG:-}"
REPOS="${REPOS:-apache/incubator-devlake}"
PROJECT_NAME="${PROJECT_NAME:-DevLake Demo}"
VERSION="${VERSION:-latest}"
SKIP_DEPLOY=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pat)         PAT="$2"; shift 2 ;;
        --org)         ORG="$2"; shift 2 ;;
        --repos)       REPOS="$2"; shift 2 ;;
        --project)     PROJECT_NAME="$2"; shift 2 ;;
        --version)     VERSION="$2"; shift 2 ;;
        --skip-deploy) SKIP_DEPLOY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--pat PAT] [--org ORG] [--repos owner/repo,...] [--skip-deploy]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Load .env if it exists
# ---------------------------------------------------------------------------
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
    PAT="${PAT:-$GITHUB_PAT}"
    ORG="${ORG:-$GITHUB_ORG}"
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
echo ""
echo "===  DevLake Demo Setup  ==="
echo ""

if ! command -v gh &>/dev/null; then
    echo "ERROR: GitHub CLI (gh) not found. Install from https://cli.github.com/"
    exit 1
fi

if ! gh extension list 2>/dev/null | grep -q "gh-devlake"; then
    echo "Installing gh-devlake extension..."
    gh extension install DevExpGBB/gh-devlake
fi

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found. Install from https://docs.docker.com/get-docker/"
    exit 1
fi

if [[ -z "$PAT" ]]; then
    echo "ERROR: GitHub PAT required. Pass --pat, set GITHUB_PAT, or add to .env"
    exit 1
fi

echo "  PAT:     ****${PAT: -4}"
echo "  Org:     ${ORG:-(none — Copilot connection skipped)}"
echo "  Repos:   $REPOS"
echo "  Project: $PROJECT_NAME"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Deploy
# ---------------------------------------------------------------------------
if [[ "$SKIP_DEPLOY" == "false" ]]; then
    echo "[1/5] Deploying DevLake locally..."
    gh devlake deploy local --source official --version "$VERSION" --dir "$SCRIPT_DIR"
    echo ""
else
    echo "[1/5] Skipping deployment (--skip-deploy)"
    echo ""
fi

# ---------------------------------------------------------------------------
# Step 2: Health check
# ---------------------------------------------------------------------------
echo "[2/5] Checking DevLake health..."
retries=0
max_retries=30
until curl -sf http://localhost:8080/ping >/dev/null 2>&1; do
    retries=$((retries + 1))
    if [[ $retries -ge $max_retries ]]; then
        echo "ERROR: DevLake not healthy after $((max_retries * 5))s"
        exit 1
    fi
    echo "  Waiting for DevLake... ($retries/$max_retries)"
    sleep 5
done
echo "  DevLake is healthy"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Create connections
# ---------------------------------------------------------------------------
echo "[3/5] Creating connections..."

echo "  Creating GitHub connection..."
gh devlake configure connection add \
    --plugin github \
    --token "$PAT" \
    --name "GitHub"

if [[ -n "$ORG" ]]; then
    echo "  Creating GitHub Copilot connection..."
    gh devlake configure connection add \
        --plugin gh-copilot \
        --token "$PAT" \
        --org "$ORG" \
        --name "GitHub Copilot - $ORG"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 4: Add scopes
# ---------------------------------------------------------------------------
echo "[4/5] Adding scopes..."

echo "  Adding repository scopes: $REPOS"
gh devlake configure scope add \
    --plugin github \
    --repos "$REPOS" \
    --deployment-pattern '(?i)deploy' \
    --production-pattern '(?i)prod' \
    --incident-label "incident"

if [[ -n "$ORG" ]]; then
    echo "  Adding Copilot scope: $ORG"
    gh devlake configure scope add \
        --plugin gh-copilot \
        --org "$ORG"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 5: Create project + sync
# ---------------------------------------------------------------------------
echo "[5/5] Creating project and triggering first sync..."
gh devlake configure project add \
    --project-name "$PROJECT_NAME"

echo ""
echo "===  Setup Complete  ==="
echo ""
echo "  Grafana:     http://localhost:3002  (admin / admin)"
echo "  Config UI:   http://localhost:4000"
echo "  DevLake API: http://localhost:8080"
echo ""
echo "  Data collection is running. Depending on repo size,"
echo "  dashboards will populate in 10-30 minutes."
echo ""
echo "  Check status:  gh devlake status"
echo "  Tear down:     gh devlake cleanup --local --force"
echo ""
