# Proxmox LXC Template - Proxmox-Technitium Sync Service

This directory contains resources to deploy the Proxmox-Technitium Sync service as a Proxmox LXC container template for automated DNS synchronization.

## Overview

The LXC template automates container creation and configuration for running the DNS sync service within a Proxmox environment.

## Components

- **`cloud-init-setup.sh`** - Cloud-init script for container initialization
- **`post-install-config.sh`** - Post-installation configuration script
- **`template-deploy.sh`** - Proxmox custom user script for template deployment
- **`.env.template`** - Environment configuration template

## Quick Start (Recommended)

**Fastest way to get running with auto-discovery:**

```bash
# 1. Run interactive enrollment (auto-discovers Technitium!)
./enroll.sh

# 2. Deploy container
./template-deploy.sh

# 3. Start service - it will use auto-generated .env
```

## Deployment Methods

### Method 1: Interactive Enrollment + Custom User Script (Recommended) ⭐

1. **Auto-discover Technitium and generate credentials:**
   ```bash
   ./enroll.sh
   ```
   This interactive wizard will:
   - Scan network for Technitium instances
   - Generate API tokens automatically
   - Create secure configuration file
   - Show you exactly what will be done before applying

2. **Use custom user script in Proxmox UI:**
   - CT > Create > Advanced > Custom User Script
   - Paste contents of `template-deploy.sh`
   - Container will auto-start service

### Method 2: Manual Discovery and Token Generation

```bash
# Generate credentials with manual review
./discover-and-generate-tokens.sh

# Shows security implications before proceeding
# Requires admin approval for each step
# Dry-run mode available for testing
```

### Method 3: Cloud-Init
Deploy using cloud-init directly:

```bash
pct exec <container-id> -- bash -s < cloud-init-setup.sh
```

### Method 4: Manual Setup

```bash
pct exec <container-id> -- bash -s < post-install-config.sh
```

## Configuration

Environment variables required in `.env`:

```
PROXMOX_HOST=your-proxmox-host
PROXMOX_USERNAME=root
PROXMOX_PASSWORD=your-password
PROXMOX_TOKEN_NAME=token-id
PROXMOX_TOKEN_VALUE=token-secret
TECHNITIUM_HOST=your-technitium-host
TECHNITIUM_TOKEN=your-api-token
ZONE=example.com
```

### Automatic Discovery & Token Generation

The `enroll.sh` script provides interactive setup:

**Features:**
- 🔍 Auto-discovers Technitium instances on your network
- 🔑 Generates API tokens automatically (with admin approval)
- 👁️ Shows exactly what changes will be made
- 📋 Review mode for security-conscious deployments
- ✅ Dry-run testing before applying
- 🔒 Creates secure configuration files (mode 0600)

**Security Implications:**
- Requires Technitium admin credentials (temporary)
- Network traffic should be on trusted networks only
- Generated tokens allow DNS zone management only
- Tokens can be revoked from Technitium UI anytime
- All token creation appears in Technitium logs
- Highly recommended to use HTTPS with valid certificates

**Running Enrollment:**

```bash
# Interactive mode (asks for approvals)
./enroll.sh

# Specific Technitium host
./enroll.sh --technitium-host dns.example.com

# Dry-run (shows what would happen)
./enroll.sh --dry-run
```

### Manual Token Generation

If auto-generation fails, manually create tokens in Technitium:

```bash
./discover-and-generate-tokens.sh --technitium-host dns.local
```

This script:
- Shows security implications before proceeding
- Requires explicit user confirmation
- Never applies changes without review
- Can be run in dry-run mode first
- Safely handles authentication failures

**Discovery Script Options:**

```bash
# Dry-run mode (no changes applied)
./discover-and-generate-tokens.sh --dry-run

# Skip review (requires --accept-implications)
./discover-and-generate-tokens.sh --accept-implications

# Manual host specification
./discover-and-generate-tokens.sh --technitium-host 10.0.0.10

# Custom admin credentials
./discover-and-generate-tokens.sh \
  --technitium-host dns.local \
  --technitium-admin myuser \
  --technitium-password mypass
```

## Features

- ✅ Alpine Linux 3.12+ base
- ✅ Non-root user execution (syncer)
- ✅ Automatic dependency installation
- ✅ Service auto-start on container boot
- ✅ Health checks configured
- ✅ Logging to syslog
- ✅ **Auto-discovery of Technitium instances** 🔍
- ✅ **Automatic API token generation** 🔑
- ✅ **Interactive enrollment wizard** 🧙
- ✅ **Dry-run and review modes for safety** 👁️
- ✅ **Secure credential handling (0600 permissions)** 🔒

## Testing

After deployment, verify the service:

```bash
pct exec <container-id> -- systemctl status proxmox-sync
pct exec <container-id> -- journalctl -u proxmox-sync -f
```

## Notes

- Template requires Python 3.11+ (compatible with Alpine Edge)
- Service runs unprivileged (UID 1001)
- Minimum recommended: 256MB RAM, 1 vCPU
- Data persistence: uses `/var/lib/proxmox-sync/` on host

## Version

Proxmox-Technitium Sync v1.0.0
