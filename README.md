# Proxmox to Technitium DNS Sync

## Automatically sync Proxmox VM and LXC container IP addresses to Technitium DNS

A lightweight, production-ready Docker service that polls your Proxmox cluster every ~60 seconds and automatically registers active LXC and VM guest IP addresses as A records in your Technitium DNS zone. Perfect for dynamic infrastructure where VMs/containers are frequently created/destroyed.

## Features

- ✅ **Automated polling**: Syncs every 60 seconds (configurable)
- ✅ **Token-based authentication**: Works with Proxmox API tokens (recommended) or password auth
- ✅ **Idempotent syncing**: Safe to run 24/7; uses `overwrite=true` for automatic deduplication
- ✅ **Retry logic**: Exponential backoff for transient API failures
- ✅ **Lightweight**: Alpine-based, ~50MB footprint, runs as non-root user
- ✅ **Health checks**: Built-in container health status
- ✅ **Structured logging**: DEBUG and INFO levels for troubleshooting
- ✅ **Security hardened**: SSL verification, input validation, rate limiting

## Quick Start

### Docker

```bash
docker run -d \
  --name proxmox-technitium-sync \
  -e PROXMOX_HOST=pve-01.proxmox.local \
  -e PROXMOX_USER=root \
  -e PROXMOX_TOKEN_NAME=dns-sync \
  -e PROXMOX_TOKEN_VALUE=your-token-value \
  -e TECHNITIUM_URL=http://10.0.99.14:5380 \
  -e TECHNITIUM_TOKEN=your-technitium-token \
  -e ZONE=zinthose.pve \
  -e POLL_INTERVAL=60 \
  --restart unless-stopped \
  mcr-gitlab/proxmox-technitium-sync:latest
```

### Docker Compose

```yaml
version: '3.8'
services:
  proxmox-sync:
    image: mcr-gitlab/proxmox-technitium-sync:latest
    restart: unless-stopped
    environment:
      PROXMOX_HOST: pve-01.proxmox.local
      PROXMOX_USER: root
      PROXMOX_TOKEN_NAME: dns-sync
      PROXMOX_TOKEN_VALUE: ${PROXMOX_TOKEN}
      TECHNITIUM_URL: http://10.0.99.14:5380
      TECHNITIUM_TOKEN: ${TECHNITIUM_TOKEN}
      ZONE: zinthose.pve
      POLL_INTERVAL: 60
```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `PROXMOX_HOST` | Proxmox server hostname or IP | `pve-01.proxmox.local` |
| `PROXMOX_USER` | Proxmox username | `root` |
| `PROXMOX_TOKEN_NAME` | API token name | `dns-sync` |
| `PROXMOX_TOKEN_VALUE` | API token secret | (see creating tokens below) |
| `TECHNITIUM_URL` | Technitium DNS server URL | `http://10.0.99.14:5380` |
| `TECHNITIUM_TOKEN` | Technitium API token | (see creating tokens below) |
| `ZONE` | DNS zone to manage | `zinthose.pve` |

### Optional Environment Variables

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `PROXMOX_REALM` | Proxmox auth realm | `pam` |
| `POLL_INTERVAL` | Sync interval in seconds | `60` |
| `DEBUG` | Enable debug logging | `false` |

### Creating a Proxmox API Token

1. Log in to Proxmox Web UI
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Fill in:
   - **User**: `root@pam`
   - **Token ID**: Give it a memorable name (e.g., `dns-sync`)
   - **Expire**: Set an expiration date or leave empty for no expiration
5. Click **Add** and **immediately copy the token value** (you won't see it again!)
6. Grant the token the necessary permissions:
   - **Datacenter → Permissions → Add** (or edit existing role)
   - Assign role with at least: **Vm.Audit**, **Nodes.Audit**

### Creating a Technitium API Token

1. Log in to Technitium Web Console
2. Go to **Settings → API**
3. Create a new API token with appropriate permissions
4. Copy the token and add it to your environment

### Environment File Setup

Create a `.env` file:

```bash
cp .env.example .env  # Copy the template
# Edit .env with your credentials
docker run --env-file .env proxmox-technitium-sync:latest
```

⚠️ **Security**: Never commit your `.env` file to version control!

## Monitoring & Logs

Check container status:

```bash
docker ps --filter name=proxmox-technitium-sync
docker logs proxmox-technitium-sync
```

Expected logs show:

```log
Successfully authenticated with Proxmox
Poll cycle 1: Synced 11 records
Poll cycle 2: Synced 11 records
```

If records aren't syncing:

1. Verify API tokens are correct
2. Check Proxmox token has **Vm.Audit** and **Nodes.Audit** permissions
3. Enable `DEBUG=true` environment variable for detailed logging
4. Run `docker logs proxmox-technitium-sync` and look for error messages

## Automated Deployments (Optional)

This project includes GitHub Actions CI/CD workflows that automatically build and push Docker images to Docker Hub when you push to main or create tagged releases.

See [DOCKER_HUB_SETUP.md](DOCKER_HUB_SETUP.md) for automated deployment configuration.

---

## Development

### Directory Structure

```text
proxmox-technitium-sync/
├── README.md               # This file
├── Dockerfile              # Alpine-based container definition
├── requirements.txt        # Python dependencies
├── .env.example            # Sample environment configuration
├── src/
│   ├── __init__.py
│   ├── core.py             # Functional Core: Pure data models and mapping logic
│   └── main.py             # Imperative Shell: Proxmox/Technitium API interactions
├── tests/
│   ├── __init__.py
│   └── test_core.py        # Pytest suite for Functional Core
├── .github/
│   └── workflows/
│       └── docker-build-push.yml  # GitHub Actions CI/CD
└── docs/
    ├── DOCKER_HUB_SETUP.md        # Automated deployment guide
    └── SECURITY.md                 # Security audit trail
```

### Architecture

Built using **Functional Core / Imperative Shell** architecture:

- **Functional Core** (`src/core.py`): Pure, side-effect-free data validation and mapping
  - No external dependencies or API calls
  - 100% deterministic and testable
  - Immutable dataclasses for data models
  
- **Imperative Shell** (`src/main.py`): Orchestrates API interactions
  - Calls the Functional Core for validation
  - Handles Proxmox and Technitium API communication
  - Manages polling loop and error handling

### Local Development

Install dependencies and run locally:

```bash
pip install -r requirements.txt
source .env  # Load environment variables
python src/main.py
```

### Testing

Run the test suite:

```bash
pip install -r requirements.txt
pytest tests/ -v
```

All 9 tests should pass. Tests focus on the Functional Core to ensure data mapping logic is correct and predictable.

### Building the Docker Image Locally

```bash
docker build -t proxmox-dns-sync:dev .
docker run -d --name test-sync --env-file .env proxmox-dns-sync:dev
docker logs test-sync
```

## Security

This project prioritizes security with multiple layers of protection:

- ✅ **Input Validation**: Strict hostname and IP address validation
- ✅ **SSL/TLS**: SSL verification enabled by default
- ✅ **Rate Limiting**: Minimum 10-second poll interval prevents API flooding
- ✅ **Secure Authentication**: Token-based API authentication (no hardcoded credentials)
- ✅ **Audit Logging**: Structured logs track all DNS modifications
- ✅ **Container Hardening**: Non-root user, Alpine base, health checks

**Latest Security Audit:** See [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md)

Status: ✅ No known vulnerabilities (0 CVEs in direct dependencies)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### What This Means

You're free to:

- ✅ Use commercially
- ✅ Modify and distribute
- ✅ Use privately
- ✅ Create derivative works

No warranty is provided. See [LICENSE](LICENSE) for the full legal text.
