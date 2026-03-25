# DevLake Demo

Deploy [Apache DevLake](https://devlake.apache.org/) locally and get DORA + GitHub Copilot dashboards from real repository data in under 15 minutes.

Uses the [`gh-devlake`](https://github.com/DevExpGBB/gh-devlake) CLI extension to deploy, configure connections, and trigger data collection — all from the terminal.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| [Docker Desktop](https://docs.docker.com/get-docker/) | Runs the DevLake stack |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Required by `gh-devlake` |
| [gh-devlake](https://github.com/DevExpGBB/gh-devlake) | Deploys and configures DevLake |
| GitHub PAT | Authenticates data collection |

**Install gh-devlake:**

```bash
gh extension install DevExpGBB/gh-devlake
```

**GitHub PAT scopes needed:**

| Scope | Purpose |
|-------|---------|
| `repo` | Repository data (PRs, commits, issues) |
| `read:org` | Organization metadata |
| `read:user` | Contributor info |
| `manage_billing:copilot` | Copilot usage metrics (optional) |

## Quick Start

### Option 1: Setup Script (recommended)

```bash
# Clone and configure
git clone https://github.com/ewega/devlake-demo.git
cd devlake-demo
cp .env.example .env
# Edit .env — set ENCRYPTION_SECRET and GITHUB_PAT

# Run setup (deploys DevLake + creates connections + triggers collection)
./setup.sh --pat ghp_YOUR_TOKEN

# With Copilot dashboards:
./setup.sh --pat ghp_YOUR_TOKEN --org your-github-org

# With your own repos:
./setup.sh --pat ghp_YOUR_TOKEN --repos "your-org/repo1,your-org/repo2"
```

**PowerShell (Windows):**

```powershell
.\setup.ps1 -Pat ghp_YOUR_TOKEN
.\setup.ps1 -Pat ghp_YOUR_TOKEN -Org your-github-org
```

### Option 2: Step by Step with gh-devlake

```bash
# 1. Deploy
gh devlake deploy local --source official

# 2. Create GitHub connection
gh devlake configure connection add --plugin github --token ghp_YOUR_TOKEN

# 3. Add repos with DORA config
gh devlake configure scope add --plugin github \
  --repos apache/incubator-devlake \
  --deployment-pattern '(?i)deploy' \
  --incident-label incident

# 4. Create project and start collecting
gh devlake configure project add --project-name "DevLake Demo"

# 5. Check status
gh devlake status
```

### Option 3: Codespaces (zero local setup)

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/ewega/devlake-demo)

After the Codespace starts, run `./setup.sh --pat ghp_YOUR_TOKEN`.

## Dashboards

After the first collection completes (~10-30 minutes depending on repo size), open Grafana:

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3002 | admin / admin |
| Config UI | http://localhost:4000 | — |
| DevLake API | http://localhost:8080 | — |

### Available Dashboards

| Dashboard | What It Shows | Requires |
|-----------|---------------|----------|
| **DORA** | Deployment Frequency, Lead Time, CFR, MTTR | GitHub connection + repo scopes |
| **GitHub** | PR throughput, review time, contributor activity | GitHub connection |
| **GitHub Copilot Adoption** | Seat utilization, language breakdown, acceptance rates | Copilot connection (`--org`) |
| **GitHub Copilot DORA Correlation** | Adoption tiers vs. DORA metrics | Both GitHub + Copilot |

## How It Works

DevLake collects data from your configured sources and normalizes it into a standard data model:

```
GitHub API  ──→  DevLake  ──→  MySQL  ──→  Grafana Dashboards
                   │
Copilot API ──→───┘
```

**DORA metrics** are computed from:
- **Deployment Frequency** — GitHub Actions workflow runs matching `deploymentPattern`
- **Lead Time for Changes** — Time from first commit to deployment
- **Change Failure Rate** — Failed deployments / total deployments
- **Mean Time to Recovery** — Time to close issues labeled `incident`

### Keep-Alive (automatic DORA data)

This repo includes a scheduled GitHub Action (`.github/workflows/keep-alive.yml`) that runs twice weekly to generate real DORA signals — creating PRs, merging them, opening/closing incident issues, and occasionally triggering failed deployments. After a few weeks, the repo itself becomes a rich data source.

## Customizing

### Use Different Images

To use the [DevExpGBB fork](https://github.com/DevExpGBB/incubator-devlake) images instead of upstream Apache:

```bash
# In .env:
IMAGE_REPO=ghcr.io/devexpgbb
IMAGE_TAG=latest
```

### Change Ports

```bash
# In .env:
DEVLAKE_PORT=8085
CONFIG_UI_PORT=4004
GRAFANA_PORT=3004
MYSQL_PORT=3307
```

### Bring Your Own Repos

```bash
./setup.sh --pat ghp_TOKEN --repos "my-org/repo1,my-org/repo2,other-org/repo3"
```

## Teardown

```bash
gh devlake cleanup --local --force
```

## Related Projects

| Project | Description |
|---------|-------------|
| [Apache DevLake](https://github.com/apache/incubator-devlake) | The upstream open-source project |
| [gh-devlake](https://github.com/DevExpGBB/gh-devlake) | CLI extension for DevLake deployment and configuration |

## License

[Apache License 2.0](LICENSE)
