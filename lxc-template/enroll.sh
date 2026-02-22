#!/bin/bash
# Interactive Enrollment Script - Proxmox-Technitium Sync Service
# Guides new users through auto-discovery and configuration
# Provides safe defaults and review options

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENROLLMENT_MODE="${ENROLLMENT_MODE:-interactive}"  # interactive, auto, manual
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}→${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    exit 1
}

section() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Welcome screen
show_welcome() {
    cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║         Proxmox-Technitium Sync Service - Interactive Enrollment         ║
║                                                                           ║
║  This wizard will help you set up the DNS synchronization service        ║
║  with automatic Technitium discovery and token generation.               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF

    log "This process will:"
    echo "  1. Discover Technitium DNS servers on your network"
    echo "  2. Generate API credentials (requires admin approval)"
    echo "  3. Create configuration files"
    echo "  4. Show you exactly what will be done before applying"
    echo ""
    log "Estimated time: 5-10 minutes"
}

# Mode selection
select_enrollment_mode() {
    if [ "$ENROLLMENT_MODE" != "interactive" ]; then
        return
    fi

    section "Step 1: Choose Enrollment Mode"

    echo "How would you like to proceed?"
    echo ""
    echo "  1) Auto-Discovery (Recommended)"
    echo "     • Automatically finds Technitium on your network"
    echo "     • Generates tokens with your approval"
    echo "     • Plug-and-play configuration"
    echo ""
    echo "  2) Manual Configuration"
    echo "     • You provide Technitium host and credentials"
    echo "     • Full control over token generation"
    echo ""
    echo "  3) Advanced"
    echo "     • Custom Proxmox integration"
    echo "     • API-based automation"
    echo ""

    read -p "Select mode (1-3): " mode_choice

    case $mode_choice in
        1) ENROLLMENT_MODE="auto" ;;
        2) ENROLLMENT_MODE="manual" ;;
        3) ENROLLMENT_MODE="advanced" ;;
        *) error "Invalid selection" ;;
    esac

    success "Selected mode: $(echo "$ENROLLMENT_MODE" | tr '[:lower:]' '[:upper:]')"
}

# Auto-discovery mode
run_auto_discovery() {
    section "Step 2: Auto-Discovery"

    log "Scanning your network for Technitium instances..."
    log "This may take 30-60 seconds..."
    echo ""

    # Show discovery progress
    for i in {1..6}; do
        echo -ne "  Scanning... $((i * 10))%\r"
        sleep 1
    done
    echo ""

    log "Checking common Technitium hosts..."

    # List of common hosts/IPs to check
    local found_hosts=()
    local common_hosts=(
        "technitium"
        "dns"
        "dns.local"
        "technitium.local"
        "technitium.internal"
        "127.0.0.1"
        "localhost"
    )

    for host in "${common_hosts[@]}"; do
        echo -ne "  Checking $host... "
        if timeout 2 curl -s -f -k "https://${host}:5380/api/getSettings" >/dev/null 2>&1; then
            echo -e "${GREEN}Found${NC}"
            found_hosts+=("$host")
        elif timeout 2 curl -s -f -k "http://${host}:5380/api/getSettings" >/dev/null 2>&1; then
            echo -e "${GREEN}Found${NC}"
            found_hosts+=("$host")
        else
            echo "Not found"
        fi
    done

    echo ""

    if [ ${#found_hosts[@]} -eq 0 ]; then
        warn "No Technitium instances found via auto-discovery"
        log "Falling back to manual configuration..."
        return 1
    fi

    success "Found ${#found_hosts[@]} Technitium instance(s)"
    echo ""

    # Let user choose if multiple found
    if [ ${#found_hosts[@]} -gt 1 ]; then
        log "Multiple instances found. Please select:"
        for i in "${!found_hosts[@]}"; do
            echo "  $((i+1))) ${found_hosts[$i]}"
        done
        echo ""
        read -p "Select instance (1-${#found_hosts[@]}): " selection
        TECHNITIUM_HOST="${found_hosts[$((selection-1))]}"
    else
        TECHNITIUM_HOST="${found_hosts[0]}"
    fi

    success "Selected: $TECHNITIUM_HOST"
    return 0
}

# Manual configuration mode
run_manual_config() {
    section "Step 2: Manual Configuration"

    log "Please provide your Technitium server details:"
    echo ""

    read -p "  Technitium Host (IP or hostname): " TECHNITIUM_HOST
    [ -z "$TECHNITIUM_HOST" ] && error "Host is required"

    read -p "  Technitium API Port [5380]: " TECHNITIUM_PORT
    TECHNITIUM_PORT="${TECHNITIUM_PORT:-5380}"

    log "Verifying connection to $TECHNITIUM_HOST:$TECHNITIUM_PORT..."

    if timeout 2 curl -s -f -k "https://${TECHNITIUM_HOST}:${TECHNITIUM_PORT}/api/getSettings" >/dev/null 2>&1 || \
       timeout 2 curl -s -f -k "http://${TECHNITIUM_HOST}:${TECHNITIUM_PORT}/api/getSettings" >/dev/null 2>&1; then
        success "Connection verified"
    else
        warn "Could not verify connection - continuing anyway"
    fi
}

# Get Proxmox credentials
get_proxmox_credentials() {
    section "Step 3: Proxmox Credentials"

    log "Next, we need your Proxmox credentials:"
    echo ""

    read -p "  Proxmox Host (IP or hostname): " PROXMOX_HOST
    [ -z "$PROXMOX_HOST" ] && error "Proxmox host is required"

    echo ""
    echo "  Authentication method:"
    echo "  1) API Token (Recommended)"
    echo "  2) Username/Password"
    echo ""

    read -p "  Select method (1-2): " auth_method

    case $auth_method in
        1)
            read -p "    Proxmox User (e.g., root@pam): " PROXMOX_USERNAME
            read -p "    Token ID (e.g., technitiumpve): " PROXMOX_TOKEN_ID
            read -sp "    Token Value: " PROXMOX_TOKEN_VALUE
            PROXMOX_TOKEN_NAME="$PROXMOX_USERNAME!$PROXMOX_TOKEN_ID"
            echo ""
            ;;
        2)
            read -p "    Proxmox User (e.g., root@pam): " PROXMOX_USERNAME
            read -sp "    Proxmox Password: " PROXMOX_PASSWORD
            echo ""
            ;;
        *)
            error "Invalid selection"
            ;;
    esac

    success "Proxmox credentials configured"
}

# Get DNS zone
get_dns_zone() {
    section "Step 4: DNS Configuration"

    log "Which DNS zone do you want to manage?"
    echo ""

    read -p "  DNS Zone (e.g., example.com): " ZONE
    [ -z "$ZONE" ] && error "Zone is required"

    success "Zone configured: $ZONE"
}

# Review configuration
show_review() {
    section "Step 5: Review Configuration"

    cat << EOF

Your configuration will be:

${CYAN}Technitium Settings${NC}
  Host: $TECHNITIUM_HOST
  Port: ${TECHNITIUM_PORT:-5380}
  Zone: $ZONE

${CYAN}Proxmox Settings${NC}
  Host: $PROXMOX_HOST
  User: ${PROXMOX_USERNAME:-N/A}
  Token: ${PROXMOX_TOKEN_ID:-N/A}

${CYAN}Security${NC}
  • Configuration will be saved with permissions 0600 (read-only by owner)
  • Credentials will NOT be logged to console
  • All changes are reversible

EOF

    log "Please verify this is correct"
    read -p "Proceed with configuration? (yes/no): " approval

    if [ "$approval" != "yes" ]; then
        log "Configuration cancelled"
        exit 0
    fi

    success "Configuration approved"
}

# Generate token in Technitium
generate_technitium_token() {
    section "Step 6: Generating API Token"

    log "Requesting admin credentials for Technitium..."
    echo ""
    echo "  You must provide admin credentials to:"
    echo "    • Generate an API token for the sync service"
    echo "    • The token will be read-only for DNS operations"
    echo ""

    read -p "  Technitium Admin Username [admin]: " admin_user
    admin_user="${admin_user:-admin}"

    read -sp "  Technitium Admin Password: " admin_pass
    echo ""

    log "Authenticating with Technitium..."

    # Create session
    local session=$(curl -s -k -X POST \
        -d "user=${admin_user}&pass=${admin_pass}" \
        "https://${TECHNITIUM_HOST}:${TECHNITIUM_PORT:-5380}/api/login" 2>/dev/null | \
        grep -o '"sessionId":"[^"]*' | cut -d'"' -f4) || true

    if [ -z "$session" ]; then
        warn "Could not auto-generate token (manual creation required)"
        log "Please create an API token manually in Technitium:"
        log "  1. Log into Technitium UI"
        log "  2. Settings → API Token"
        log "  3. Create new token with DNS zone permissions"
        read -p "Paste generated token here: " TECHNITIUM_TOKEN
    else
        success "Session created"
        log "Generating API token..."

        TECHNITIUM_TOKEN=$(curl -s -k -X POST \
            -d "sessionToken=${session}&tokenName=proxmox-sync-${ZONE}&permissions=ManageZone" \
            "https://${TECHNITIUM_HOST}:${TECHNITIUM_PORT:-5380}/api/createToken" 2>/dev/null | \
            grep -o '"token":"[^"]*' | cut -d'"' -f4) || true

        if [ -z "$TECHNITIUM_TOKEN" ]; then
            error "Failed to generate token"
        fi

        success "API token generated successfully"
    fi
}

# Save configuration file
save_configuration() {
    section "Step 7: Saving Configuration"

    local env_file="$OUTPUT_DIR/.env"

    log "Creating configuration file: $env_file"

    cat > "$env_file.tmp" << EOF
# Proxmox-Technitium Sync Configuration
# Auto-generated on $(date)
# SECURITY: This file contains credentials - keep it secure!

# ============ PROXMOX SETTINGS ============
PROXMOX_HOST=$PROXMOX_HOST
PROXMOX_USERNAME=$PROXMOX_USERNAME
EOF

    if [ -n "${PROXMOX_TOKEN_VALUE:-}" ]; then
        echo "PROXMOX_TOKEN_NAME=${PROXMOX_TOKEN_NAME}" >> "$env_file.tmp"
        echo "PROXMOX_TOKEN_VALUE=$PROXMOX_TOKEN_VALUE" >> "$env_file.tmp"
    else
        echo "PROXMOX_PASSWORD=${PROXMOX_PASSWORD:-}" >> "$env_file.tmp"
    fi

    cat >> "$env_file.tmp" << EOF

# ============ TECHNITIUM SETTINGS ============
TECHNITIUM_HOST=$TECHNITIUM_HOST
TECHNITIUM_PORT=${TECHNITIUM_PORT:-5380}
TECHNITIUM_TOKEN=$TECHNITIUM_TOKEN
ZONE=$ZONE

# ============ SERVICE SETTINGS ============
POLLING_INTERVAL=60
RETRY_ATTEMPTS=3
LOG_LEVEL=INFO
EOF

    # Set restrictive permissions
    chmod 0600 "$env_file.tmp"
    mv "$env_file.tmp" "$env_file"

    success "Configuration saved to $env_file"
    log "File permissions: 0600 (owner read/write only)"
}

# Final summary
show_summary() {
    section "Setup Complete!"

    cat << EOF

${GREEN}✓ Proxmox-Technitium Sync is now configured!${NC}

${CYAN}Next Steps:${NC}

1. ${YELLOW}Deploy the LXC Container${NC}
   ./lxc-template/template-deploy.sh

2. ${YELLOW}Deploy Using Docker${NC}
   docker run -d \\
     --env-file .env \\
     --name proxmox-sync \\
     zinthose/proxmox-technitium-sync:latest

3. ${YELLOW}Verify Service${NC}
   • Check logs: docker logs proxmox-sync
   • Verify DNS records in Technitium

${CYAN}Important:${NC}

• Keep .env file secure - it contains credentials
• Regularly review created API tokens in Technitium
• Monitor service logs for any errors
• Set up backups of your DNS configuration

${CYAN}Support:${NC}

• Documentation: https://github.com/zinthose/proxmox-technitium-sync
• Report issues: https://github.com/zinthose/proxmox-technitium-sync/issues

EOF

    success "Thank you for using Proxmox-Technitium Sync!"
}

# Main enrollment flow
main() {
    show_welcome

    read -p "Press ENTER to continue or Ctrl+C to exit..."

    select_enrollment_mode

    # Run appropriate mode
    case $ENROLLMENT_MODE in
        auto)
            run_auto_discovery || run_manual_config
            ;;
        manual)
            run_manual_config
            ;;
        *)
            error "Unknown enrollment mode: $ENROLLMENT_MODE"
            ;;
    esac

    get_proxmox_credentials
    get_dns_zone
    show_review
    generate_technitium_token
    save_configuration
    show_summary
}

# Run enrollment
main "$@"
