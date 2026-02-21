#!/bin/bash
# Proxmox LXC Custom User Script - Proxmox-Technitium Sync Service
# This script is designed to be used as a custom user script during LXC container creation
# It automates the full setup of the DNS sync service within the container

set -euo pipefail

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/proxmox-sync-deploy.log
}

log "Starting Proxmox-Technitium Sync service deployment..."

# Update system
log "Updating system packages..."
apk update && apk upgrade

# Install dependencies
log "Installing dependencies..."
apk add --no-cache \
    python3 \
    py3-pip \
    py3-virtualenv \
    curl \
    wget \
    git \
    ca-certificates \
    openssh-client \
    dcron \
    logrotate

# Create non-root user for service
log "Creating service user..."
addgroup -S syncer 2>/dev/null || true
adduser -S -G syncer -h /var/lib/proxmox-sync -s /sbin/nologin syncer 2>/dev/null || true

# Create application directories
log "Setting up application directories..."
mkdir -p /opt/proxmox-sync
mkdir -p /var/lib/proxmox-sync
mkdir -p /etc/proxmox-sync
mkdir -p /var/log/proxmox-sync

chown -R syncer:syncer /opt/proxmox-sync
chown -R syncer:syncer /var/lib/proxmox-sync
chown -R syncer:syncer /var/log/proxmox-sync

# Clone or download application code
log "Fetching application code..."
cd /opt/proxmox-sync
git clone https://github.com/zinthose/proxmox-technitium-sync.git . || \
    wget -qO- https://github.com/zinthose/proxmox-technitium-sync/archive/v1.0.0.tar.gz | tar xz --strip-components=1

# Setup Python environment
log "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt

# Copy configuration template if not exists
log "Configuring environment..."
if [ ! -f /etc/proxmox-sync/.env ]; then
    cp .env.example /etc/proxmox-sync/.env
    log "⚠️  Please configure /etc/proxmox-sync/.env with your settings"
fi

# Create systemd service
log "Creating systemd service..."
cat > /etc/init.d/proxmox-sync << 'EOF'
#!/sbin/openrc-run

description="Proxmox-Technitium DNS Sync Service"
command="/opt/proxmox-sync/venv/bin/python"
command_args="/opt/proxmox-sync/src/main.py"
pidfile="/var/run/proxmox-sync.pid"
logfile="/var/log/proxmox-sync/service.log"
start_stop_daemon_args="-u syncer -g syncer"
output_log="$logfile"
error_log="$logfile"

depend() {
    need net
    use dns
}

start() {
    ebegin "Starting Proxmox-Technitium Sync"
    export $(cat /etc/proxmox-sync/.env | xargs)
    start_stop_daemon --start \
        --pidfile="$pidfile" \
        --user=syncer \
        --group=syncer \
        --background \
        --make-pidfile \
        --exec "$command" -- $command_args
    eend $?
}

stop() {
    ebegin "Stopping Proxmox-Technitium Sync"
    start_stop_daemon --stop --pidfile="$pidfile"
    eend $?
}

restart() {
    stop
    sleep 1
    start
}
EOF

chmod +x /etc/init.d/proxmox-sync

# Configure service to start on boot (Alpine OpenRC style)
log "Enabling service auto-start..."
rc-service proxmox-sync start || log "⚠️  Service start deferred - configure .env first"
rc-update add proxmox-sync default

# Setup log rotation
log "Configuring logrotate..."
cat > /etc/logrotate.d/proxmox-sync << 'EOF'
/var/log/proxmox-sync/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 syncer syncer
    sharedscripts
    postrotate
        rc-service proxmox-sync reload 2>/dev/null || true
    endscript
}
EOF

# Setup health check script
log "Creating health check script..."
cat > /usr/local/bin/proxmox-sync-health << 'EOF'
#!/bin/sh
# Health check for monitoring

if rc-service proxmox-sync status >/dev/null 2>&1; then
    echo "✅ Service is running"
    exit 0
else
    echo "❌ Service is not running"
    exit 1
fi
EOF

chmod +x /usr/local/bin/proxmox-sync-health

log "✅ Proxmox-Technitium Sync service deployment completed!"
log "📝 Next steps:"
log "   1. Edit /etc/proxmox-sync/.env with your Proxmox and Technitium credentials"
log "   2. Restart service: rc-service proxmox-sync restart"
log "   3. Check status: rc-service proxmox-sync status"
log "   4. View logs: tail -f /var/log/proxmox-sync/service.log"
