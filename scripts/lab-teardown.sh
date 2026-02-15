#!/bin/bash
# ============================================================
# Enterprise Network Lab — Teardown
# ============================================================
# Removes all namespaces, bridges, and processes created by lab-setup.sh
# Usage: sudo bash lab-teardown.sh
# ============================================================

set -euo pipefail

echo "════════════════════════════════════════"
echo "  Enterprise Network Lab — Teardown"
echo "════════════════════════════════════════"
echo ""

# Kill dnsmasq and web server processes
echo "[*] Stopping services..."
kill $(cat /tmp/enterprise-lab/dnsmasq-dns.pid 2>/dev/null) 2>/dev/null || true
pkill -f "dnsmasq.*enterprise-lab" 2>/dev/null || true
pkill -f "http.server.*enterprise-lab" 2>/dev/null || true

# Remove namespaces (this also removes their veth ends)
echo "[*] Removing namespaces..."
for ns in ns-router ns-dns ns-web ns-client; do
    ip netns del $ns 2>/dev/null && echo "    ✓ Deleted $ns" || echo "    - $ns not found"
done

# Remove bridges
echo "[*] Removing bridges..."
for br in br-vlan10 br-vlan20; do
    ip link set $br down 2>/dev/null || true
    ip link del $br 2>/dev/null && echo "    ✓ Deleted $br" || echo "    - $br not found"
done

# Remove remaining veth pairs (host ends)
echo "[*] Cleaning up veth pairs..."
for veth in veth-r-v10 veth-r-v20 veth-dns veth-web veth-cli; do
    ip link del $veth 2>/dev/null && echo "    ✓ Deleted $veth" || true
done

# Clean temp files
echo "[*] Removing temp files..."
rm -rf /tmp/enterprise-lab

echo ""
echo "════════════════════════════════════════"
echo "  Teardown complete ✓"
echo "════════════════════════════════════════"
