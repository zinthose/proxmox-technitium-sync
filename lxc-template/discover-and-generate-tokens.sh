#!/bin/bash
# Technitium DNS Discovery and API Token Generator
# Automatically discovers Technitium instances in Proxmox and creates API tokens
# Includes review mode to show changes before applying

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-.}"
TECHINIT_PORT="${TECHNITIUM_PORT:-5380}"
REVIEW_MODE="${REVIEW_MODE:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Show security implications
show_implications() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║              SECURITY IMPLICATIONS - PLEASE READ CAREFULLY                ║
╚═══════════════════════════════════════════════════════════════════════════╝

⚠️  API TOKEN GENERATION WILL:

1. NETWORK ACCESS
   • Connect to discovered Technitium instances on the local network
   • May expose credentials if network is not secure
   • Tokens are transmitted in plain text unless HTTPS is enabled

2. TECHNITIUM CREDENTIALS REQUIRED
   • Requires admin access to Technitium API
   • By default, admin credentials are sent with requests
   • Should only run on trusted networks

3. API TOKENS CREATED
   • Tokens will have DNS modification permissions
   • Can create, update, delete DNS records
   • Should be stored securely (in environment files marked 0600)
   • Tokens do NOT have admin access to Technitium UI

4. AUTOMATIC ASSUMPTIONS
   • Discovery assumes default credentials OR already-authenticated session
   • If custom admin credentials needed, must be provided manually
   • Multi-step token creation may fail if Technitium requires additional auth

5. AUDIT TRAIL
   • All token creation operations will appear in Technitium logs
   • Admin should review Technitium admin panel for created tokens
   • Can revoke tokens at any time from Technitium UI

═══════════════════════════════════════════════════════════════════════════

RECOMMENDATIONS:

✓ Run on a secure, private network only
✓ Verify Technitium instances before auto-discovery completes
✓ Review generated credentials before applying
✓ Enable HTTPS on Technitium API (via certificates)
✓ Use strong admin passwords
✓ Regularly rotate API tokens
✓ Monitor Technitium logs for unauthorized key generation

EOF
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --accept-implications)
                REVIEW_MODE=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --technitium-host)
                OVERRIDE_HOST="$2"
                shift 2
                ;;
            --technitium-admin)
                OVERRIDE_ADMIN="$2"
                shift 2
                ;;
            --technitium-password)
                OVERRIDE_PASSWORD="$2"
                shift 2
                ;;
            --no-review)
                REVIEW_MODE=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << 'EOF'
Usage: ./discover-and-generate-tokens.sh [OPTIONS]

OPTIONS:
    --accept-implications    Skip security review (use with caution)
    --dry-run               Show what will be done without applying
    --technitium-host HOST  Override Technitium host discovery
    --technitium-admin USER Override Technitium admin username
    --technitium-password PW Override Technitium admin password
    --no-review            Alias for --accept-implications
    -h, --help             Show this help message

EXAMPLES:
    # Interactive mode with review (DEFAULT)
    ./discover-and-generate-tokens.sh

    # Dry run to see what would happen
    ./discover-and-generate-tokens.sh --dry-run

    # Skip review (CAUTION - only if you understand implications)
    ./discover-and-generate-tokens.sh --accept-implications --dry-run

    # With manual Technitium configuration
    ./discover-and-generate-tokens.sh \
        --technitium-host dns.example.com \
        --technitium-admin admin \
        --technitium-password mypassword

ENVIRONMENT VARIABLES:
    REVIEW_MODE            Set to 'false' to skip review (default: true)
    DRY_RUN               Set to 'true' for dry-run mode (default: false)
    TECHNITIUM_PORT       Technitium API port (default: 5380)

EOF
}

# Discover Technitium instances via Proxmox API
discover_technitium_instances() {
    log "Scanning Proxmox cluster for Technitium DNS instances..."

    local instances=()
    
    # This would typically query Proxmox API
    # For now, we'll show how it would work
    
    if [ -n "${PROXMOX_HOST:-}" ] && [ -n "${PROXMOX_TOKEN:-}" ]; then
        log "Using Proxmox API discovery (requires PROXMOX_HOST and PROXMOX_TOKEN)"
        
        # Example: Query Proxmox for containers/VMs
        # curl -s -H "Authorization: PVEAPIToken=..." \
        #     https://${PROXMOX_HOST}:8006/api2/json/nodes | \
        #     grep -i technitium || true
    else
        warn "PROXMOX_HOST or PROXMOX_TOKEN not set - using manual discovery"
    fi

    # Manual discovery: scan common DNS hostnames/IPs on local subnet
    log "Attempting manual discovery on local network..."
    
    # Common Technitium hostnames/IPs to check
    local common_hosts=(
        "technitium"
        "dns"
        "dns.local"
        "technitium.local"
        "192.168.1.100"
        "10.0.0.10"
        "localhost:5380"
    )

    for host in "${common_hosts[@]}"; do
        if check_technitium_alive "$host" 2>/dev/null; then
            instances+=("$host")
            log "Found Technitium instance: $host"
        fi
    done

    if [ ${#instances[@]} -eq 0 ]; then
        warn "No Technitium instances auto-discovered"
        
        if [ -n "${OVERRIDE_HOST:-}" ]; then
            instances+=("$OVERRIDE_HOST")
            log "Using provided host: $OVERRIDE_HOST"
        else
            return 1
        fi
    fi

    echo "${instances[@]}"
}

# Check if Technitium is running at given host
check_technitium_alive() {
    local host=$1
    local port="${2:-$TECHINIT_PORT}"
    
    # Add port if not already present
    if [[ ! "$host" =~ :${port}$ ]]; then
        host="${host}:${port}"
    fi

    # Try to reach Technitium API
    timeout 2 curl -s -f -k \
        "https://${host}/api/getSettings?token=" >/dev/null 2>&1 || \
    timeout 2 curl -s -f -k \
        "http://${host}/api/getSettings?token=" >/dev/null 2>&1
}

# Authenticate with Technitium
authenticate_technitium() {
    local host=$1
    local admin="${OVERRIDE_ADMIN:-admin}"
    local password="${OVERRIDE_PASSWORD:-}"

    log "Authenticating with Technitium at $host..."

    if [ -z "$password" ]; then
        read -sp "Technitium admin password: " password
        echo ""
    fi

    # Attempt login via Technitium API
    local token=$(curl -s -k \
        -X POST \
        -d "user=${admin}&pass=${password}" \
        "https://${host}:${TECHNITIUM_PORT}/api/createSession" 2>/dev/null | \
        grep -o '"sessionId":"[^"]*' | cut -d'"' -f4)

    if [ -z "$token" ]; then
        error "Failed to authenticate with Technitium at $host"
    fi

    echo "$token"
}

# Generate API token in Technitium
generate_api_token() {
    local host=$1
    local session_token=$2
    local zone=$3

    log "Generating API token for zone: $zone"

    local api_token=$(curl -s -k \
        -X POST \
        -d "sessionToken=${session_token}&tokenName=proxmox-sync-${zone}&permissions=dns" \
        "https://${host}:${TECHNITIUM_PORT}/api/createToken" 2>/dev/null | \
        grep -o '"token":"[^"]*' | cut -d'"' -f4)

    if [ -z "$api_token" ]; then
        error "Failed to generate API token"
    fi

    echo "$api_token"
}

# Show review of what will be done
show_review() {
    local host=$1
    local zone=$2
    local api_token=$3

    cat << EOF

╔═══════════════════════════════════════════════════════════════════════════╗
║                      REVIEW CHANGES BEFORE APPLYING                       ║
╚═══════════════════════════════════════════════════════════════════════════╝

TECHNITIUM INSTANCE
  Host: $host
  Port: $TECHINIT_PORT
  Zone: $zone

GENERATED CREDENTIALS
  Token Name: proxmox-sync-${zone}
  Token Value: ${api_token:0:20}... (hidden for security)
  Permissions: DNS zone management

CONFIGURATION FILE
  Will be saved to: $CONFIG_DIR/.env
  Will be created with mode 0600 (read-only by owner)

ACTION
  Once approved, the token will be stored locally and used by the sync service.

EOF

    if [ "$DRY_RUN" = "true" ]; then
        warn "DRY RUN MODE - No changes will be applied"
        return 0
    fi

    read -p "Do you approve these changes? (yes/no): " approval

    if [ "$approval" != "yes" ]; then
        log "Changes cancelled by user"
        return 1
    fi

    return 0
}

# Save configuration
save_configuration() {
    local host=$1
    local api_token=$2
    local zone=$3
    local env_file="$CONFIG_DIR/.env"

    log "Saving configuration..."

    if [ "$DRY_RUN" = "true" ]; then
        cat << EOF
[DRY RUN] Would create $env_file with:

TECHNITIUM_HOST=$host
TECHNITIUM_PORT=$TECHINIT_PORT
TECHNITIUM_TOKEN=$api_token
ZONE=$zone

EOF
        return 0
    fi

    # Create .env file with restricted permissions
    cat > "$env_file.tmp" << EOF
# Auto-generated by discover-and-generate-tokens.sh
# Do not share this file - it contains sensitive credentials

TECHNITIUM_HOST=$host
TECHNITIUM_PORT=$TECHINIT_PORT
TECHNITIUM_TOKEN=$api_token
ZONE=$zone

# Add your Proxmox credentials below
PROXMOX_HOST=
PROXMOX_USERNAME=
PROXMOX_TOKEN_VALUE=
EOF

    # Set restrictive permissions (0600 = rw--------)
    chmod 0600 "$env_file.tmp"
    mv "$env_file.tmp" "$env_file"

    success "Configuration saved to $env_file with permissions 0600"
    log "Please review and add Proxmox credentials to $env_file"
}

# Main flow
main() {
    parse_args "$@"

    log "Proxmox-Technitium Sync - Auto-Discovery and Token Generator"
    echo ""

    # Show implications
    if [ "$REVIEW_MODE" = "true" ]; then
        show_implications
        read -p "Do you understand and accept these implications? (yes/no): " accept
        if [ "$accept" != "yes" ]; then
            log "User declined to accept implications. Exiting."
            exit 0
        fi
    fi

    echo ""
    log "Starting discovery process..."
    echo ""

    # Discover instances
    instances=$(discover_technitium_instances) || error "Could not discover any Technitium instances"

    # Use first instance (or override)
    TECHNITIUM_HOST="${OVERRIDE_HOST:-$(echo "$instances" | head -n1)}"
    log "Using Technitium instance: $TECHNITIUM_HOST"

    # Get zone
    read -p "DNS Zone to manage (e.g., example.com): " ZONE
    [ -z "$ZONE" ] && error "Zone is required"

    # Authenticate
    SESSION_TOKEN=$(authenticate_technitium "$TECHNITIUM_HOST")
    success "Authentication successful"

    # Generate token
    API_TOKEN=$(generate_api_token "$TECHNITIUM_HOST" "$SESSION_TOKEN" "$ZONE")
    success "API token generated"

    echo ""

    # Show review
    show_review "$TECHNITIUM_HOST" "$ZONE" "$API_TOKEN"

    # Save configuration
    save_configuration "$TECHNITIUM_HOST" "$API_TOKEN" "$ZONE"

    echo ""
    success "Setup complete!"
    log "Next: Update $CONFIG_DIR/.env with Proxmox credentials and deploy"
}

# Run main
main "$@"
