#!/bin/bash
# ============================================================
# VLAN & Bridge Setup Script
# Enterprise Network Lab — Core Switch Configuration
# ============================================================
# This script creates VLAN interfaces and bridges using
# iproute2 and Open vSwitch to simulate a Layer 2/3 switch.
#
# Run as root on the Core Switch (Ubuntu VM).
# ============================================================

set -euo pipefail

echo "========================================"
echo " Enterprise Network Lab — VLAN Setup"
echo "========================================"

# --- Configuration ---
TRUNK_IF="eth1"          # Physical interface (trunk to router)
VLAN10_ID=10
VLAN20_ID=20
VLAN10_IP="10.0.10.2/24"
VLAN20_IP="10.0.20.2/24"
GATEWAY="10.0.1.1"

# --- Enable IP Forwarding ---
echo "[*] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# --- Create VLAN Interfaces ---
echo "[*] Creating VLAN interfaces on ${TRUNK_IF}..."

# VLAN 10 — Servers
ip link add link ${TRUNK_IF} name ${TRUNK_IF}.${VLAN10_ID} type vlan id ${VLAN10_ID}
ip addr add ${VLAN10_IP} dev ${TRUNK_IF}.${VLAN10_ID}
ip link set ${TRUNK_IF}.${VLAN10_ID} up
echo "    ✓ VLAN ${VLAN10_ID} created: ${VLAN10_IP}"

# VLAN 20 — Clients
ip link add link ${TRUNK_IF} name ${TRUNK_IF}.${VLAN20_ID} type vlan id ${VLAN20_ID}
ip addr add ${VLAN20_IP} dev ${TRUNK_IF}.${VLAN20_ID}
ip link set ${TRUNK_IF}.${VLAN20_ID} up
echo "    ✓ VLAN ${VLAN20_ID} created: ${VLAN20_IP}"

# --- Create Linux Bridges (one per VLAN) ---
echo "[*] Creating bridges..."

# Bridge for VLAN 10
ip link add br-vlan10 type bridge
ip link set br-vlan10 up
ip link set ${TRUNK_IF}.${VLAN10_ID} master br-vlan10
echo "    ✓ Bridge br-vlan10 created"

# Bridge for VLAN 20
ip link add br-vlan20 type bridge
ip link set br-vlan20 up
ip link set ${TRUNK_IF}.${VLAN20_ID} master br-vlan20
echo "    ✓ Bridge br-vlan20 created"

# --- Add Static Route to Router ---
echo "[*] Adding default route via ${GATEWAY}..."
ip route add default via ${GATEWAY} || echo "    (default route already exists)"

# --- Verify Configuration ---
echo ""
echo "========================================"
echo " Verification"
echo "========================================"
echo ""
echo "[*] VLAN Interfaces:"
ip -br link show | grep -E "vlan|br-"
echo ""
echo "[*] IP Addresses:"
ip -br addr show | grep -E "vlan|br-"
echo ""
echo "[*] Bridge Members:"
bridge link show
echo ""
echo "[*] Routing Table:"
ip route show
echo ""
echo "========================================"
echo " VLAN Setup Complete!"
echo "========================================"
