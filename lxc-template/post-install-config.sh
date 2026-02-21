#!/bin/bash
# Post-Installation Configuration Script
# Run this after the container is created to configure the DNS sync service

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Proxmox-Technitium Sync - Post-Installation Configuration"

SERVICE_USER="syncer"
SERVICE_HOME="/var/lib/proxmox-sync"
APP_DIR="/opt/proxmox-sync"
ENV_FILE="/etc/proxmox-sync/.env"
LOG_DIR="/var/log/proxmox-sync"

# Verify service user exists
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    log "Creating service user..."
    addgroup -S "$SERVICE_USER" 2>/dev/null || true
    adduser -S -G "$SERVICE_USER" -h "$SERVICE_HOME" -s /sbin/nologin "$SERVICE_USER"
fi

# Verify directories
log "Verifying directory structure..."
for dir in "$APP_DIR" "$SERVICE_HOME" "$(dirname "$ENV_FILE")" "$LOG_DIR"; do
    mkdir -p "$dir"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$dir" 2>/dev/null || true
done

# Check environment configuration
if [ ! -f "$ENV_FILE" ]; then
    log "⚠️  Environment file not found: $ENV_FILE"
    log "Creating template from .env.example..."
    if [ -f "$APP_DIR/.env.example" ]; then
        cp "$APP_DIR/.env.example" "$ENV_FILE"
        log "Template created. Please edit $ENV_FILE with your configuration."
    else
        log "ERROR: .env.example not found!"
        exit 1
    fi
fi

# Verify Python environment
log "Checking Python environment..."
if [ ! -d "$APP_DIR/venv" ]; then
    log "Creating Python virtual environment..."
    python3 -m venv "$APP_DIR/venv"
    source "$APP_DIR/venv/bin/activate"
    pip install --upgrade pip setuptools wheel
    pip install -r "$APP_DIR/requirements.txt"
else
    log "Python environment already exists"
fi

# Verify required packages
log "Verifying dependencies..."
REQUIRED_PACKAGES="python3 git ca-certificates curl"
for pkg in $REQUIRED_PACKAGES; do
    if ! apk list -i | grep -q "^$pkg"; then
        log "Installing missing package: $pkg"
        apk add --no-cache "$pkg"
    fi
done

# Create systemd/OpenRC service if not exists
if [ ! -f "/etc/init.d/proxmox-sync" ]; then
    log "Creating OpenRC service script..."
    cat > /etc/init.d/proxmox-sync << 'SERVICE_EOF'
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
}

start() {
    ebegin "Starting Proxmox-Technitium Sync"
    export $(cat /etc/proxmox-sync/.env | xargs 2>/dev/null || true)
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
SERVICE_EOF
    chmod +x /etc/init.d/proxmox-sync
    rc-update add proxmox-sync default 2>/dev/null || true
fi

# Test service start
log "Testing service startup..."
if rc-service proxmox-sync start >/dev/null 2>&1; then
    log "✅ Service started successfully"
    sleep 2
    rc-service proxmox-sync status
else
    log "⚠️  Service failed to start - verify .env configuration"
fi

log ""
log "✅ Post-installation configuration complete!"
log ""
log "Next steps:"
log "1. Edit configuration: vi $ENV_FILE"
log "2. Restart service: rc-service proxmox-sync restart"
log "3. Check logs: tail -f $LOG_DIR/service.log"
