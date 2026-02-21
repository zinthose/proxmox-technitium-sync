"""Test suite for Proxmox-Technitium Sync"""

# ./tests/test_core.py
# Copyright (c) 2026 Zinthose
# Licensed under the MIT License - see LICENSE file for details

from src.core import (
    GuestState,
    DnsPayload,
    parse_static_ip_config,
    extract_lxc_running_ip,
    build_technitium_payload,
)


class TestIpExtraction:
    """Unit tests for IP extraction functions in core.py"""

    def test_parse_static_ip_config_valid_ip(self) -> None:
        """Should extract the IP from a standard Proxmox config string."""
        config_str = (
            "name=eth0,bridge=vmbr0,gw=10.0.99.1,hwaddr=1A:2B:3C:4D,"
            "ip=10.0.99.15/24,type=veth"
        )
        assert parse_static_ip_config(config_str) == "10.0.99.15"

    def test_parse_static_ip_config_dhcp(self) -> None:
        """Should return None if the interface is configured for DHCP."""
        config_str = "name=eth0,bridge=vmbr0,hwaddr=1A:2B:3C:4D,ip=dhcp,type=veth"
        assert parse_static_ip_config(config_str) is None

    def test_parse_static_ip_config_no_ip_field(self) -> None:
        """Should return None if no IP configuration is present."""
        config_str = "name=eth0,bridge=vmbr0,hwaddr=1A:2B:3C:4D,type=veth"
        assert parse_static_ip_config(config_str) is None

    def test_extract_lxc_running_ip_valid(self) -> None:
        """Should extract the first non-loopback IPv4 address."""
        interfaces = [
            {"name": "lo", "inet": "127.0.0.1/8"},
            {"name": "eth0", "inet": "10.0.99.20/24", "inet6": "fe80::/64"},
        ]
        assert extract_lxc_running_ip(interfaces) == "10.0.99.20"

    def test_extract_lxc_running_ip_loopback_only(self) -> None:
        """Should return None if only loopback interfaces are found."""
        interfaces = [{"name": "lo", "inet": "127.0.0.1/8"}]
        assert extract_lxc_running_ip(interfaces) is None

    def test_extract_lxc_running_ip_empty(self) -> None:
        """
        Should return None if interface list is empty or
        lacks inet fields.
        """
        interfaces = [{"name": "eth0"}]
        assert extract_lxc_running_ip(interfaces) is None


class TestPayloadBuilder:
    """Unit tests for the payload builder in core.py"""

    def test_build_technitium_payload_active_with_ip(self) -> None:
        """
        Should build a complete DnsPayload for an active guest
        with an IP.
        """
        guest = GuestState(hostname="web-server", ip_address="10.0.99.25", is_active=True)
        zone = "zinthose.pve"

        expected = DnsPayload(
            domain="web-server.zinthose.pve",
            zone="zinthose.pve",
            record_type="A",
            ip_address="10.0.99.25",
            overwrite="true",
        )
        assert build_technitium_payload(guest, zone) == expected

    def test_build_technitium_payload_inactive(self) -> None:
        """
        Should return None for inactive guests to prevent
        stale IP mapping.
        """
        guest = GuestState(hostname="db-server", ip_address="10.0.99.30", is_active=False)
        assert build_technitium_payload(guest, "zinthose.pve") is None

    def test_build_technitium_payload_missing_ip(self) -> None:
        """
        Should return None if the guest is active but no IP
        could be extracted.
        """
        guest = GuestState(hostname="new-node", ip_address="", is_active=True)
        assert build_technitium_payload(guest, "zinthose.pve") is None
