"""Proxmox-Technitium Sync - Automatic DNS record management"""

# Copyright (c) 2026 Zinthose
# Licensed under the MIT License - see LICENSE file for details

import os
import sys
import time
import logging
from typing import List

import requests
from proxmoxer import ProxmoxAPI  # type: ignore

from src.core import (
    GuestState,
    DnsPayload,
    build_technitium_payload,
    extract_lxc_running_ip,
    parse_static_ip_config,
    is_valid_ipv4,
    is_valid_hostname,
)

# Configure structured logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# --- Environment Configuration ---
PROXMOX_HOST = os.environ.get("PROXMOX_HOST", "proxmox.local")
PROXMOX_USER = os.environ.get("PROXMOX_USER", "root")
PROXMOX_REALM = os.environ.get("PROXMOX_REALM", "pam")
# Token-based authentication
PROXMOX_TOKEN_NAME = os.environ.get("PROXMOX_TOKEN_NAME")
PROXMOX_TOKEN_VALUE = os.environ.get("PROXMOX_TOKEN_VALUE")
# Password-based authentication (alternative to tokens)
PROXMOX_PASSWORD = os.environ.get("PROXMOX_PASSWORD")
TECHNITIUM_URL = os.environ.get("TECHNITIUM_URL", "http://technitium.local:5380")
TECHNITIUM_TOKEN = os.environ.get("TECHNITIUM_TOKEN")
ZONE = os.environ.get("ZONE", "local.pve")
# Validate poll interval (min 10s to prevent API flooding)
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "60"))
if POLL_INTERVAL < 10:
    raise ValueError("POLL_INTERVAL must be >= 10 seconds")
# SSL verification (default: enabled for security)
VERIFY_SSL = os.environ.get("VERIFY_SSL", "true").lower() == "true"
# Max retries for transient API failures
MAX_RETRIES = 3
RETRY_BACKOFF_FACTOR = 2  # Exponential backoff: 1s, 2s, 4s


def get_proxmox_guests(proxmox: ProxmoxAPI) -> List[GuestState]:
    """
    Queries the Proxmox API for all LXCs and VMs and extracts their IP states.
    Sanitizes hostnames and validates IP addresses before returning.
    """
    guests: List[GuestState] = []

    try:
        nodes = proxmox.nodes.get()
    except (ConnectionError, TimeoutError) as e:
        logger.error("Failed to get nodes from Proxmox: %s", type(e).__name__)
        return guests
    except Exception as e:
        logger.error("Unexpected error fetching nodes: %s: %s", type(e).__name__, e)
        return guests

    for node in nodes:
        node_name = str(node.get("node"))
        if not node_name:
            continue

        # 1. Process LXC Containers
        try:
            for lxc in proxmox.nodes(node_name).lxc.get():
                vmid = int(lxc.get("vmid", 0))
                name = str(lxc.get("name", f"lxc-{vmid}")).lower()
                # Sanitize hostname: replace underscores with hyphens
                name = name.replace("_", "-")
                is_active = str(lxc.get("status")) == "running"
                ip_address = ""

                if is_active:
                    try:
                        interfaces = proxmox.nodes(node_name).lxc(vmid).interfaces.get()
                        extracted_ip = extract_lxc_running_ip(interfaces)
                        if extracted_ip and is_valid_ipv4(extracted_ip):
                            ip_address = extracted_ip
                    except (KeyError, ConnectionError, TimeoutError, TypeError):
                        pass

                # Fallback to static config
                if not ip_address:
                    try:
                        config = proxmox.nodes(node_name).lxc(vmid).config.get()
                        for key, val in config.items():
                            if key.startswith("net"):
                                extracted_ip = parse_static_ip_config(str(val))
                                if extracted_ip:
                                    ip_address = extracted_ip
                                    break
                    except (KeyError, ConnectionError, TimeoutError, TypeError):
                        pass

                guests.append(GuestState(hostname=name, ip_address=ip_address, is_active=is_active))
        except (ConnectionError, TimeoutError) as e:
            logger.warning("Failed to fetch LXCs from %s: %s", node_name, type(e).__name__)
        except Exception as e:
            logger.warning(
                "Unexpected error fetching LXCs from %s: %s",
                node_name,
                type(e).__name__,
            )

        # 2. Process QEMU VMs
        try:
            for vm in proxmox.nodes(node_name).qemu.get():
                vmid = int(vm.get("vmid", 0))
                name = str(vm.get("name", f"vm-{vmid}")).lower()
                # Sanitize hostname
                name = name.replace("_", "-")
                is_active = str(vm.get("status")) == "running"
                ip_address = ""

                try:
                    config = proxmox.nodes(node_name).qemu(vmid).config.get()
                    for key, val in config.items():
                        if key.startswith("ipconfig"):
                            extracted_ip = parse_static_ip_config(str(val))
                            if extracted_ip:
                                ip_address = extracted_ip
                                break
                except (KeyError, ConnectionError, TimeoutError, TypeError):
                    pass

                guests.append(GuestState(hostname=name, ip_address=ip_address, is_active=is_active))
        except (ConnectionError, TimeoutError) as e:
            logger.warning("Failed to fetch VMs from %s: %s", node_name, type(e).__name__)
        except Exception as e:
            logger.warning(
                "Unexpected error fetching VMs from %s: %s",
                node_name,
                type(e).__name__,
            )

    return guests


def push_to_technitium(payload: DnsPayload) -> bool:
    """
    Execute HTTP API request to Technitium to create/update A record.
    Includes retry logic with exponential backoff.
    """
    endpoint = f"{TECHNITIUM_URL}/api/zones/records/add"
    params = {
        "token": TECHNITIUM_TOKEN,
        "domain": payload.domain,
        "zone": payload.zone,
        "type": payload.record_type,
        "ipAddress": payload.ip_address,
        "overwrite": payload.overwrite,
    }

    for attempt in range(MAX_RETRIES):
        try:
            response = requests.post(endpoint, params=params, timeout=10, verify=VERIFY_SSL)
            response.raise_for_status()
            return True
        except requests.RequestException as e:
            if attempt < MAX_RETRIES - 1:
                wait_time = RETRY_BACKOFF_FACTOR**attempt
                logger.warning(
                    "Push retry %s/%s for %s in %ss: %s",
                    attempt + 1,
                    MAX_RETRIES,
                    payload.domain,
                    wait_time,
                    type(e).__name__,
                )
                time.sleep(wait_time)
            else:
                logger.error(
                    "Failed to update %s after %s attempts: %s",
                    payload.domain,
                    MAX_RETRIES,
                    type(e).__name__,
                )
    return False


def delete_from_technitium(domain: str) -> bool:
    """
    Delete a DNS A record from Technitium with retry logic.
    Logs all deletion attempts for audit trail.
    """
    # Validate inputs
    if not is_valid_hostname(domain.split(".")[0]):
        logger.warning("Invalid domain '%s' - rejected", domain)
        return False

    endpoint = f"{TECHNITIUM_URL}/api/zones/records/delete"
    params = {"token": TECHNITIUM_TOKEN, "domain": domain, "zone": ZONE, "type": "A"}

    for attempt in range(MAX_RETRIES):
        try:
            response = requests.post(endpoint, params=params, timeout=10, verify=VERIFY_SSL)
            response.raise_for_status()
            logger.info("AUDIT: Deleted DNS record %s from %s", domain, ZONE)
            return True
        except requests.RequestException as e:
            if attempt < MAX_RETRIES - 1:
                wait_time = RETRY_BACKOFF_FACTOR**attempt
                logger.warning(
                    "Delete retry %s/%s for %s in %ss: %s",
                    attempt + 1,
                    MAX_RETRIES,
                    domain,
                    wait_time,
                    type(e).__name__,
                )
                time.sleep(wait_time)
            else:
                logger.error(
                    "Failed to delete Technitium record %s after %s attempts: %s",
                    domain,
                    MAX_RETRIES,
                    type(e).__name__,
                )
    return False


def get_existing_records() -> dict:
    """
    Fetch existing DNS records from Technitium for the zone.

    NOTE: Technitium's API does not support fetching all zone records efficiently.
    The /api/zones/records/get endpoint requires the full domain name, not a zone name.
    Since we use overwrite=true when adding records, change detection isn't necessary.
    Returns empty dict - all records will be re-added with overwrite=true.
    """
    return {}


def main() -> None:
    logger.info("Starting Proxmox -> Technitium Sync for zone: %s", ZONE)
    logger.info("SSL verification: %s", "ENABLED" if VERIFY_SSL else "DISABLED")

    if not TECHNITIUM_TOKEN:
        logger.error("TECHNITIUM_TOKEN environment variable is required")
        sys.exit(1)

    # Determine authentication method
    use_token_auth = PROXMOX_TOKEN_NAME and PROXMOX_TOKEN_VALUE
    use_password_auth = PROXMOX_PASSWORD

    if not use_token_auth and not use_password_auth:
        logger.error(
            "Either (PROXMOX_TOKEN_NAME + PROXMOX_TOKEN_VALUE) or PROXMOX_PASSWORD is required"
        )
        sys.exit(1)

    # Initialize Proxmox API
    try:
        logger.info("Authenticating to Proxmox at %s", PROXMOX_HOST)

        if use_token_auth:
            logger.info(
                "Using token-based authentication for %s@%s",
                PROXMOX_USER,
                PROXMOX_REALM,
            )
            proxmox = ProxmoxAPI(
                PROXMOX_HOST,
                user=f"{PROXMOX_USER}@{PROXMOX_REALM}!{PROXMOX_TOKEN_NAME}",
                password=PROXMOX_TOKEN_VALUE,
                verify_ssl=VERIFY_SSL,
            )
        else:
            logger.info(
                "Using password-based authentication for %s@%s",
                PROXMOX_USER,
                PROXMOX_REALM,
            )
            proxmox = ProxmoxAPI(
                PROXMOX_HOST,
                user=f"{PROXMOX_USER}@{PROXMOX_REALM}",
                password=PROXMOX_PASSWORD,
                verify_ssl=VERIFY_SSL,
            )

        logger.info("Successfully authenticated with Proxmox")
    except (ConnectionError, TimeoutError, KeyError) as e:
        logger.error("Authentication failed: %s: %s", type(e).__name__, e)
        if use_token_auth:
            logger.error(
                "Token Auth Troubleshooting: 1) PROXMOX_TOKEN_NAME correct? "
                "2) PROXMOX_TOKEN_VALUE complete? 3) Token expired? "
                "4) Token has Vm.Audit + Nodes.Audit?"
            )
        else:
            logger.error(
                "Password Auth Troubleshooting: 1) PROXMOX_USER correct? "
                "2) PROXMOX_PASSWORD correct?"
            )
        sys.exit(1)
    except Exception as e:
        logger.error("Unexpected authentication error: %s: %s", type(e).__name__, e)
        sys.exit(1)

    while True:
        try:
            guests = get_proxmox_guests(proxmox)

            # Build list of DNS records that SHOULD exist
            desired_records = {}  # domain -> ip
            for guest in guests:
                payload = build_technitium_payload(guest, ZONE)
                if payload:
                    desired_records[payload.domain] = payload.ip_address

            # Get existing records from Technitium
            existing_records = get_existing_records()

            # Delete stale records (exist in Technitium but not in Proxmox)
            for domain in existing_records:
                if domain not in desired_records:
                    if delete_from_technitium(domain):
                        logger.info("Deleted stale record: %s", domain)
                    continue

            # Add/update all desired records with overwrite=true
            # (Technitium API doesn't support efficient zone record fetching)
            for domain, ip in desired_records.items():
                payload = DnsPayload(
                    domain=domain, zone=ZONE, record_type="A", ip_address=ip, overwrite="true"
                )
                if push_to_technitium(payload):
                    logger.info("Synced: %s -> %s", domain, ip)

            logger.info("Poll cycle complete - synced %s records", len(desired_records))

        except (ConnectionError, TimeoutError, KeyError) as e:
            logger.error("Critical polling error: %s: %s", type(e).__name__, e)
        except Exception as e:
            logger.error("Unexpected polling error: %s: %s", type(e).__name__, e)

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
