# Auto-Discovery & Token Generation - Security & Implementation Guide

## Overview

The Proxmox-Technitium Sync service includes automatic discovery and token generation features that allow for "plug-and-play" deployment. This document explains the security implications, how it works, and how to safely use these features.

## What Auto-Discovery Does

**Auto-Discovery** scans your network for Technitium DNS instances and collects basic information:
- Hostname/IP address
- Port availability
- API responsiveness
- Zone names

**Token Generation** creates API credentials in Technitium that allow the sync service to:
- Query VM/container information from Proxmox
- Create DNS A records
- Update DNS A records
- Delete DNS A records
- Query existing DNS records (read-only validation)

## Security Implications

### ✅ What IS Secure

1. **Token Scope Limited**
   - API tokens created have DNS zone management permissions ONLY
   - Cannot access Technitium admin panel
   - Cannot modify other zones or system settings
   - Cannot create new admin users

2. **Credential Isolation**
   - Generated tokens are stored in `.env` file with mode 0600
   - Only accessible by the service user (syncer UID 1001)
   - Not logged to console or system logs
   - Can be revoked immediately from Technitium UI

3. **Network Isolation**
   - Auto-discovery only works on networks where Technitium responds
   - Protected by firewall rules on both Proxmox and Technitium
   - API tokens only work from services that have the token
   - Token value never transmitted in URLs (POST body instead)

4. **Audit Trail**
   - All token creation operations appear in Technitium logs
   - Admin can see when, where, and by whom tokens were created
   - Tokens can be individually disabled or deleted
   - Service logs all DNS operations performed

### ⚠️ Security Risks & Mitigations

1. **Network Traffic (HTTP/HTTPS)**
   - **Risk**: Credentials transmitted over network
   - **Mitigation**: Use HTTPS with valid certificates
   - **Recommendation**: Generate tokens over private network only

2. **Technitium Admin Credentials**
   - **Risk**: Required temporarily to generate tokens
   - **Mitigation**: Never stored permanently
   - **Recommendation**: Use separate admin account with limited access

3. **Local File Access**
   - **Risk**: `.env` file readable by any process running as syncer user
   - **Mitigation**: File permissions 0600 (owner read/write only)
   - **Recommendation**: Use separate container/VM for security-critical environments

4. **Token Exposure**
   - **Risk**: Token could be viewed/captured by unauthorized users
   - **Mitigation**: Immediate revocation from Technitium UI
   - **Recommendation**: Rotate tokens regularly (monthly/quarterly)

5. **Automatic Assumptions**
   - **Risk**: Script may generate tokens with incorrect permissions
   - **Mitigation**: Review mode shows all changes before applying
   - **Recommendation**: Always use `--dry-run` first

## How Auto-Discovery Works

### Step 1: Network Scanning
```
enroll.sh
├─ Scans common Technitium hostnames
│  (technitium, dns, technitium.local, etc.)
├─ Checks port 5380 (default Technitium API)
├─ Verifies API responsiveness
└─ Returns list of discovered instances
```

### Step 2: User Selection
- If 1 instance found → automatically selected
- If >1 instance found → user chooses
- If 0 instances found → falls back to manual entry

### Step 3: Authentication
```
enroll.sh
├─ Prompts for Technitium admin username
├─ Prompts for Technitium admin password
├─ Creates temporary API session
└─ Session used ONLY for token generation
    (session token NOT stored)
```

### Step 4: Token Generation
```
Technitium API
├─ Creates new API token with name: proxmox-sync-{zone}
├─ Assigns permissions: ManageZone (DNS operations only)
├─ Returns token value (one-time display)
└─ User must copy and save securely
```

### Step 5: Configuration Storage
```
.env file created with mode 0600
├─ TECHNITIUM_HOST=detected_host
├─ TECHNITIUM_TOKEN=generated_token
├─ PROXMOX_HOST=user_entered
├─ PROXMOX_TOKEN=user_entered
└─ ZONE=user_selected
```

## Safe Usage Guide

### For Home Lab / Development

✅ **Recommended Approach:**

```bash
# 1. Interactive enrollment (only on home network)
cd lxc-template
./enroll.sh

# 2. Review the generated .env file
cat .env

# 3. Deploy with verified configuration
./template-deploy.sh
```

**Security measures:**
- Only run on trusted private networks
- Use default Technitium password initially
- Review generated token in Technitium UI
- Set up container firewall rules restricting API access

### For Production / Enterprise

⚠️ **Enhanced Security Approach:**

```bash
# 1. Dry-run first to understand what will happen
cd lxc-template
./discover-and-generate-tokens.sh --dry-run

# 2. Manual token generation with explicit approval
./discover-and-generate-tokens.sh \
    --technitium-host dns.internal \
    --accept-implications

# 3. Review all changes
cat .env
git diff

# 4. Store credentials in vault (Hashicorp Vault, etc.)
# Don't commit .env to git!

# 5. Deploy to container
./template-deploy.sh
```

**Security requirements:**
- Use HTTPS with valid certificates
- Enable Technitium API authentication
- Create separate admin token with expiration
- Store .env in secure vault, not in repository
- Enable container network policies
- Monitor DNS operations via Technitium logs
- Rotate tokens quarterly
- Audit script output for errors

### For Air-Gapped / Offline Networks

❌ **Auto-Discovery Won't Work**

Use manual configuration instead:

```bash
# Skip discovery, use manual entry
./enroll.sh  # Select "Manual Configuration" mode
# OR
./discover-and-generate-tokens.sh \
    --technitium-host your.dns.server \
    --dry-run
```

## Review Modes Explained

### Enrollment Review Mode (Default)

```bash
./enroll.sh
```

Shows:
1. Security implications upfront
2. Requires "yes" confirmation before proceeding
3. Network scanning progress
4. Configuration review before saving
5. Asks for approval at each step

**Perfect for:** First-time setup, learning about the system

### Dry-Run Mode

```bash
./discover-and-generate-tokens.sh --dry-run
```

Shows:
1. Everything that WOULD be done
2. No credentials actually generated
3. No files actually created
4. Safe to run as many times as needed

**Perfect for:** Testing, understanding the process, troubleshooting

### Manual Approval Mode

```bash
./discover-and-generate-tokens.sh --accept-implications
./enroll.sh  # With explicit "yes" responses
```

Shows:
1. Skips initial warnings (you already approved)
2. Still asks for confirmation at critical steps
3. Safer than full automation

**Perfect for:** Routine deployments after initial testing

## Troubleshooting

### Auto-Discovery Finds Nothing

**Causes:**
- Technitium not running on network
- Wrong port (default: 5380)
- Firewall blocking connectivity
- Hostname not matching common patterns

**Solutions:**
```bash
# Use manual host entry
./enroll.sh  # Select manual configuration

# Dry-run with specific host
./discover-and-generate-tokens.sh \
    --technitium-host 192.168.1.50 \
    --dry-run
```

### Authentication Fails

**Causes:**
- Wrong admin password
- Admin account disabled
- Technitium API not responding

**Solutions:**
```bash
# Test Technitium connectivity
curl -k https://your-technitium-host:5380/api/getSettings

# Verify admin credentials in Technitium UI first
# Then try enrollment again
```

### Token Generation Fails But Auth Succeeds

**Causes:**
- Insufficient admin permissions
- Zone doesn't exist in Technitium
- API permission restrictions

**Solutions:**
```bash
# Fall back to manual token creation
# In Technitium UI:
# Settings → API Token → Create Token

# Then manually edit .env
vim .env
```

## Best Practices

1. **Always Review First**
   - Run with `--dry-run` before applying
   - Don't skip review mode on first run
   - Check generated .env before deployment

2. **Test Before Production**
   - Deploy to test environment first
   - Verify DNS records are created correctly
   - Monitor logs for 24-48 hours

3. **Credential Management**
   - Never commit `.env` to git
   - Use `.gitignore` to exclude credentials
   - Store in vault for production
   - Rotate tokens regularly

4. **Network Security**
   - Use HTTPS for API communications
   - Restrict network access to API ports
   - Implement firewall rules
   - Monitor for unusual API activity

5. **Monitoring & Auditing**
   - Enable Technitium logging
   - Monitor service logs for errors
   - Set up alerts for failed operations
   - Regularly review access tokens

6. **Disaster Recovery**
   - Document token generation process
   - Keep backup copies of credentials (encrypted)
   - Test token rotation procedure
   - Have rollback plan ready

## FAQ

**Q: Can auto-discovery find Technitium on remote/WAN networks?**
A: No, it scans local network only. Use manual mode for remote instances.

**Q: What happens if I run the script multiple times?**
A: It creates new tokens each time. Clean up old tokens in Technitium UI.

**Q: Can I use the same token for multiple services?**
A: Yes, but not recommended. Create separate tokens per service.

**Q: How do I revoke a token?**
A: Log into Technitium UI → Settings → API Token → Delete

**Q: Is the generated .env file encrypted?**
A: No, only file permissions (0600). For additional security, use a vault.

**Q: Can I automate this completely without user interaction?**
A: Yes, use environment variables and `--accept-implications --dry-run`, but we don't recommend it for security reasons.

## Support

- 📖 [Full Documentation](https://github.com/zinthose/proxmox-technitium-sync)
- 🐛 [Report Issues](https://github.com/zinthose/proxmox-technitium-sync/issues)
- 💬 [Discussions](https://github.com/zinthose/proxmox-technitium-sync/discussions)
