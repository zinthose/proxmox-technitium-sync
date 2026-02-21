#!/bin/bash
# Proxmox LXC Template Deployment Helper Script
# This script helps deploy multiple instances of the DNS sync service

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:?Error: PROXMOX_HOST not set}"
PROXMOX_USER="${PROXMOX_USER:?Error: PROXMOX_USER not set}"
PROXMOX_TOKEN="${PROXMOX_TOKEN:?Error: PROXMOX_TOKEN not set}"
PROXMOX_VERIFY_SSL="${PROXMOX_VERIFY_SSL:-true}"

BASE_IMAGE="debian-12-standard_12.2-1_amd64.tar.zst"  # Change to your LXC template

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Function to create SSL configuration
create_ssl_config() {
    if [ "$PROXMOX_VERIFY_SSL" = "false" ]; then
        echo "-k"
    else
        echo ""
    fi
}

# Function to deploy a new instance
deploy_instance() {
    local container_id=$1
    local container_name=$2
    local node=$3
    local environment_file=$4

    log "Deploying instance: $container_name (ID: $container_id) on node: $node"

    local ssl_flag=$(create_ssl_config)

    # Create container
    log "Creating LXC container..."
    curl $ssl_flag -X POST \
        -H "Authorization: PVEAPIToken=${PROXMOX_USER}!${PROXMOX_TOKEN}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes/${node}/lxc" \
        -d "vmid=${container_id}" \
        -d "hostname=${container_name}" \
        -d "osname=debian" \
        -d "osversion=12" \
        -d "cores=2" \
        -d "memory=512" \
        -d "swap=512" \
        -d "storage=local-lvm" \
        -d "unprivileged=1" \
        -d "start=0"

    log "Container created. Starting container..."
    
    # Start container
    curl $ssl_flag -X POST \
        -H "Authorization: PVEAPIToken=${PROXMOX_USER}!${PROXMOX_TOKEN}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes/${node}/lxc/${container_id}/status/start" \
        || error "Failed to start container"

    log "Container started. Waiting for network..."
    sleep 3

    # Upload custom user script and environment
    log "Configuring container..."
    
    # Read the deployment script into the container
    if [ -f "template-deploy.sh" ]; then
        proxmox-shell-exec "$container_id" "bash" < template-deploy.sh
    fi

    # Copy environment configuration
    if [ -f "$environment_file" ]; then
        proxmox-file-push "$container_id" "$environment_file" "/etc/proxmox-sync/.env"
    fi

    log "✅ Instance $container_name deployment complete"
}

# Function to execute commands in container
proxmox-shell-exec() {
    local container_id=$1
    shift
    
    local node=$(get_container_node "$container_id")
    
    curl -s -X POST \
        -H "Authorization: PVEAPIToken=${PROXMOX_USER}!${PROXMOX_TOKEN}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes/${node}/lxc/${container_id}/status/start" \
        >/dev/null 2>&1 || true
    
    # Note: Actual command execution requires SSH or direct container access
    # This is a placeholder for the concept
    log "Would execute: $@"
}

# Get container's node
get_container_node() {
    local container_id=$1
    # This would query Proxmox API to find which node has the container
    # For now, return first node
    echo "pve"
}

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    -i, --id <ID>              Container VMID (100-999999)
    -n, --name <NAME>          Container hostname
    -N, --node <NODE>          Proxmox node name (default: pve)
    -e, --env <FILE>           Environment configuration file
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy single instance
    ./deploy.sh -i 102 -n dns-sync-1 -e .env

    # With specific node
    ./deploy.sh -i 102 -n dns-sync-1 -N pve-01 -e .env

ENVIRONMENT VARIABLES:
    PROXMOX_HOST       Proxmox host (IP or hostname)
    PROXMOX_USER       Proxmox user (format: user@realm!token-id)
    PROXMOX_TOKEN      Proxmox API token
    PROXMOX_VERIFY_SSL Verify SSL certificates (true/false)

EOF
}

# Parse arguments
CONTAINER_ID=""
CONTAINER_NAME=""
NODE="pve"
ENV_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--id)
            CONTAINER_ID="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -N|--node)
            NODE="$2"
            shift 2
            ;;
        -e|--env)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
[ -z "$CONTAINER_ID" ] && error "Container ID required (-i/--id)"
[ -z "$CONTAINER_NAME" ] && error "Container name required (-n/--name)"

log "Proxmox LXC Template Deployment"
log "Host: $PROXMOX_HOST"
log "Node: $NODE"
log "Container: $CONTAINER_NAME (ID: $CONTAINER_ID)"
log "Environment file: ${ENV_FILE:-(using defaults)}"
log ""

# Deploy
deploy_instance "$CONTAINER_ID" "$CONTAINER_NAME" "$NODE" "$ENV_FILE"
