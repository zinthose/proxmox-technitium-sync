# Proxmox LXC Template - Proxmox-Technitium Sync Service

This directory contains resources to deploy the Proxmox-Technitium Sync service as a Proxmox LXC container template for automated DNS synchronization.

## Overview

The LXC template automates container creation and configuration for running the DNS sync service within a Proxmox environment.

## Components

- **`cloud-init-setup.sh`** - Cloud-init script for container initialization
- **`post-install-config.sh`** - Post-installation configuration script
- **`template-deploy.sh`** - Proxmox custom user script for template deployment
- **`.env.template`** - Environment configuration template

## Deployment Methods

### Method 1: Custom User Script (Recommended)
Use Proxmox's custom user script feature during LXC container creation:

1. In Proxmox UI: CT > Create > Advanced > Custom User Script
2. Paste contents of `template-deploy.sh`
3. Provide `.env` configuration during container creation

### Method 2: Cloud-Init
Deploy using cloud-init directly:

```bash
pct exec <container-id> -- bash -s < cloud-init-setup.sh
```

### Method 3: Manual

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

## Features

- ✅ Alpine Linux 3.12+ base
- ✅ Non-root user execution (syncer)
- ✅ Automatic dependency installation
- ✅ Service auto-start on container boot
- ✅ Health checks configured
- ✅ Logging to syslog

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
