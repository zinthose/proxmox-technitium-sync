#!/bin/bash
# Cloud-Init Script for Proxmox-Technitium Sync Service
# This script automatically configures an LXC container for the DNS sync service

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/proxmox-sync-setup.log
}

log "Proxmox-Technitium Sync - Cloud-Init Setup"

# System updates
log "Updating system..."
apk update && apk upgrade --no-cache

# Install required packages
log "Installing packages..."
apk add --no-cache \
    python3 \
    py3-pip \
    py3-virtualenv \
    git \
    ca-certificates \
    curl \
    dcron

# Create application user
log "Setting up application user..."
addgroup -S syncer 2>/dev/null || true
adduser -S -G syncer -h /var/lib/proxmox-sync -s /sbin/nologin syncer 2>/dev/null || true

# Create directories
log "Creating directories..."
mkdir -p /opt/proxmox-sync /var/lib/proxmox-sync /etc/proxmox-sync /var/log/proxmox-sync
chown -R syncer:syncer /opt/proxmox-sync /var/lib/proxmox-sync /var/log/proxmox-sync

# Clone application
log "Cloning application repository..."
cd /opt/proxmox-sync
git clone --depth 1 https://github.com/zinthose/proxmox-technitium-sync.git . || {
    log "Git clone failed, using archive..."
    wget -qO- https://github.com/zinthose/proxmox-technitium-sync/archive/v1.0.0.tar.gz | tar xz --strip-components=1
}

# Setup Python environment
log "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt

# Setup environment file
if [ ! -f /etc/proxmox-sync/.env ]; then
    cp .env.example /etc/proxmox-sync/.env
fi

log "Cloud-init setup complete. Configure /etc/proxmox-sync/.env and start the service."
