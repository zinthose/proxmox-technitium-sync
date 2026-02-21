# ./src/core.py
# Copyright (c) 2026 Zinthose
# Licensed under the MIT License - see LICENSE file for details

import re
from dataclasses import dataclass
from typing import Optional, List, Dict, Any
import ipaddress
import logging

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GuestState:
    """Immutable state representation of a Proxmox Guest (LXC or VM)."""

    hostname: str
    ip_address: str
    is_active: bool


@dataclass(frozen=True)
class DnsPayload:
    """Immutable payload required for the Technitium API request."""

    domain: str
    zone: str
    record_type: str
    ip_address: str
    overwrite: str


def parse_static_ip_config(config_string: str) -> Optional[str]:
    """
    Extracts IPv4 address from Proxmox 'netX' (LXC) or 'ipconfigX'
    (VM Cloud-init) strings. Validates extracted IP.
    Example input: 'name=eth0,bridge=vmbr0,ip=10.0.99.15/24'
    Returns None if DHCP is configured or no IP is found.
    """
    match = re.search(r"ip=([0-9]{1,3}(?:\.[0-9]{1,3}){3})(?:/\d+)?", config_string)
    if match and match.group(1) != "dhcp":
        ip = match.group(1)
        if is_valid_ipv4(ip):
            return ip
    return None


def extract_lxc_running_ip(interfaces: List[Dict[str, Any]]) -> Optional[str]:
    """
    Extracts the first valid IPv4 from running LXC interface data,
    ignoring local loopback addresses.
    """
    for iface in interfaces:
        if iface.get("name") == "lo":
            continue
        inet = str(iface.get("inet", ""))
        if inet and not inet.startswith("127."):
            # Proxmox returns 'inet' as '10.0.99.15/24', we only want the IP
            return inet.split("/", maxsplit=1)[0]
    return None


def is_valid_ipv4(ip: str) -> bool:
    """Validate IPv4 address format."""
    try:
        ipaddress.IPv4Address(ip)
        return True
    except (ipaddress.AddressValueError, ValueError):
        return False


def is_valid_hostname(hostname: str) -> bool:
    """
    Validate hostname according to DNS naming rules.
    Must be 1-63 chars, alphanumeric/hyphens, no leading/trailing hyphens.
    """
    if not hostname or len(hostname) > 63:
        return False
    if hostname.startswith("-") or hostname.endswith("-"):
        return False
    # Allow only alphanumeric and hyphens
    return bool(re.match(r"^[a-zA-Z0-9-]+$", hostname))


def build_technitium_payload(guest: GuestState, zone: str) -> Optional[DnsPayload]:
    """
    Maps an active GuestState into the required Technitium API payload.
    Validates hostname and IP before creating payload.
    Returns None if the guest is inactive, missing an IP, or validation fails.
    """
    if not guest.is_active or not guest.ip_address:
        return None

    # Validate hostname
    if not is_valid_hostname(guest.hostname):
        logger.warning("Invalid hostname '%s' - contains invalid chars", guest.hostname)
        return None

    # Validate IP address
    if not is_valid_ipv4(guest.ip_address):
        logger.warning("Invalid IP '%s' for %s", guest.ip_address, guest.hostname)
        return None

    return DnsPayload(
        domain=f"{guest.hostname}.{zone}",
        zone=zone,
        record_type="A",
        ip_address=guest.ip_address,
        overwrite="true",
    )
