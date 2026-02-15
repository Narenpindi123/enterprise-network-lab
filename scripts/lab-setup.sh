#!/bin/bash
# ============================================================
# Enterprise Network Lab — Full Setup (Network Namespaces)
# ============================================================
# Builds the entire enterprise network on a single Linux host
# using network namespaces, veth pairs, and bridges.
#
# Topology:
#   [ns-router]  ── br-vlan10 ── [ns-dns] [ns-web]
#       |
#       └──────── br-vlan20 ── [ns-client]
#
# Usage: sudo bash lab-setup.sh
# Teardown: sudo bash lab-teardown.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

header() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }
step()   { echo -e "  ${GREEN}[+]${NC} $1"; }
info()   { echo -e "  ${YELLOW}[i]${NC} $1"; }

header "Enterprise Network Lab Setup"
echo ""
info "This script creates a full enterprise network using Linux namespaces."
info "Requires: root privileges, iproute2, nftables, dnsmasq, tcpdump"
echo ""

# ============================================================
# Step 1: Create Network Namespaces
# ============================================================
header "Step 1: Creating Network Namespaces"

for ns in ns-router ns-dns ns-web ns-client; do
    ip netns add $ns 2>/dev/null || true
    ip netns exec $ns ip link set lo up
    step "Created namespace: $ns"
done

echo ""
ip netns list
echo ""

# ============================================================
# Step 2: Create Bridges (Core Switch)
# ============================================================
header "Step 2: Creating Bridges (Core Switch)"

# VLAN 10 bridge (Servers)
ip link add br-vlan10 type bridge 2>/dev/null || true
ip link set br-vlan10 up
step "Created bridge: br-vlan10 (VLAN 10 — Servers)"

# VLAN 20 bridge (Clients)
ip link add br-vlan20 type bridge 2>/dev/null || true
ip link set br-vlan20 up
step "Created bridge: br-vlan20 (VLAN 20 — Clients)"

echo ""
ip -br link show type bridge
echo ""

# ============================================================
# Step 3: Create veth Pairs & Connect to Bridges
# ============================================================
header "Step 3: Creating Virtual Ethernet Links"

# --- Router ↔ VLAN 10 ---
ip link add veth-r-v10 type veth peer name veth-v10-r 2>/dev/null || true
ip link set veth-v10-r netns ns-router
ip link set veth-r-v10 master br-vlan10
ip link set veth-r-v10 up
ip netns exec ns-router ip link set veth-v10-r up
ip netns exec ns-router ip addr add 10.0.10.1/24 dev veth-v10-r
step "Router (10.0.10.1) ↔ VLAN 10 bridge"

# --- Router ↔ VLAN 20 ---
ip link add veth-r-v20 type veth peer name veth-v20-r 2>/dev/null || true
ip link set veth-v20-r netns ns-router
ip link set veth-r-v20 master br-vlan20
ip link set veth-r-v20 up
ip netns exec ns-router ip link set veth-v20-r up
ip netns exec ns-router ip addr add 10.0.20.1/24 dev veth-v20-r
step "Router (10.0.20.1) ↔ VLAN 20 bridge"

# --- DNS Server ↔ VLAN 10 ---
ip link add veth-dns type veth peer name veth-v10-dns 2>/dev/null || true
ip link set veth-v10-dns netns ns-dns
ip link set veth-dns master br-vlan10
ip link set veth-dns up
ip netns exec ns-dns ip link set veth-v10-dns up
ip netns exec ns-dns ip addr add 10.0.10.10/24 dev veth-v10-dns
ip netns exec ns-dns ip route add default via 10.0.10.1
step "DNS Server (10.0.10.10) ↔ VLAN 10 bridge"

# --- Web Server ↔ VLAN 10 ---
ip link add veth-web type veth peer name veth-v10-web 2>/dev/null || true
ip link set veth-v10-web netns ns-web
ip link set veth-web master br-vlan10
ip link set veth-web up
ip netns exec ns-web ip link set veth-v10-web up
ip netns exec ns-web ip addr add 10.0.10.12/24 dev veth-v10-web
ip netns exec ns-web ip route add default via 10.0.10.1
step "Web Server (10.0.10.12) ↔ VLAN 10 bridge"

# --- Client ↔ VLAN 20 ---
ip link add veth-cli type veth peer name veth-v20-cli 2>/dev/null || true
ip link set veth-v20-cli netns ns-client
ip link set veth-cli master br-vlan20
ip link set veth-cli up
ip netns exec ns-client ip link set veth-v20-cli up
ip netns exec ns-client ip addr add 10.0.20.100/24 dev veth-v20-cli
ip netns exec ns-client ip route add default via 10.0.20.1
step "Linux Client (10.0.20.100) ↔ VLAN 20 bridge"

echo ""

# ============================================================
# Step 4: Enable Routing on Router Namespace
# ============================================================
header "Step 4: Enabling IP Forwarding on Router"

ip netns exec ns-router sysctl -w net.ipv4.ip_forward=1
step "IP forwarding enabled on ns-router"

echo ""

# ============================================================
# Step 5: Start DNS Server (dnsmasq in ns-dns)
# ============================================================
header "Step 5: Starting DNS Server"

# Create hosts file for internal DNS
mkdir -p /tmp/enterprise-lab
cat > /tmp/enterprise-lab/hosts <<EOF
10.0.10.1    router.enterprise.lab gateway.enterprise.lab
10.0.10.10   dns.enterprise.lab ns1.enterprise.lab
10.0.10.12   web.enterprise.lab www.enterprise.lab
10.0.20.1    router-vlan20.enterprise.lab
10.0.20.100  linux-client.enterprise.lab
EOF

# Start dnsmasq as DNS server in the DNS namespace
ip netns exec ns-dns dnsmasq \
    --no-daemon \
    --listen-address=10.0.10.10 \
    --bind-interfaces \
    --no-resolv \
    --server=8.8.8.8 \
    --addn-hosts=/tmp/enterprise-lab/hosts \
    --domain=enterprise.lab \
    --local=/enterprise.lab/ \
    --log-queries \
    --log-facility=/tmp/enterprise-lab/dns.log \
    --pid-file=/tmp/enterprise-lab/dnsmasq-dns.pid \
    &

sleep 1
step "DNS server (dnsmasq) running at 10.0.10.10"
step "Internal domain: enterprise.lab"
info "DNS log: /tmp/enterprise-lab/dns.log"

echo ""

# ============================================================
# Step 6: Start Web Server (Python HTTP in ns-web)
# ============================================================
header "Step 6: Starting Web Server"

# Create a simple web page
mkdir -p /tmp/enterprise-lab/www
cat > /tmp/enterprise-lab/www/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Enterprise Lab Web Server</title></head>
<body>
<h1>Enterprise Network Lab</h1>
<p>Web server running on VLAN 10 (10.0.10.12)</p>
<p>Hostname: web.enterprise.lab</p>
<p>Server time: $(date)</p>
</body>
</html>
EOF

ip netns exec ns-web python3 -m http.server 80 \
    --directory /tmp/enterprise-lab/www \
    --bind 10.0.10.12 \
    &>/tmp/enterprise-lab/web.log &

sleep 1
step "Web server (Python HTTP) running at 10.0.10.12:80"
info "Serving: /tmp/enterprise-lab/www/"

echo ""

# ============================================================
# Step 7: Apply Firewall Rules on Router
# ============================================================
header "Step 7: Applying Firewall Rules (nftables)"

ip netns exec ns-router nft flush ruleset 2>/dev/null || true

ip netns exec ns-router nft -f - <<'NFTRULES'
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iif "lo" accept
        ip protocol icmp accept
        tcp dport 22 accept
        log prefix "[NFT-INPUT-DROP] " counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept

        # VLAN 20 → DNS server (port 53)
        ip saddr 10.0.20.0/24 ip daddr 10.0.10.10 tcp dport 53 accept
        ip saddr 10.0.20.0/24 ip daddr 10.0.10.10 udp dport 53 accept

        # VLAN 20 → Web server (port 80, 443)
        ip saddr 10.0.20.0/24 ip daddr 10.0.10.12 tcp dport { 80, 443 } accept

        # ICMP between VLANs
        ip saddr 10.0.20.0/24 ip daddr 10.0.10.0/24 ip protocol icmp accept
        ip saddr 10.0.10.0/24 ip daddr 10.0.20.0/24 ip protocol icmp accept

        # Log and drop everything else
        log prefix "[NFT-FORWARD-DROP] " counter drop
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
NFTRULES

step "nftables firewall rules applied on ns-router"
info "Policy: DROP all, allow DNS/HTTP/ICMP from VLAN 20 → VLAN 10"

echo ""

# ============================================================
# Done!
# ============================================================
header "Lab Setup Complete!"
echo ""
step "Namespaces: ns-router, ns-dns, ns-web, ns-client"
step "Bridges: br-vlan10 (Servers), br-vlan20 (Clients)"
step "DNS: 10.0.10.10 (enterprise.lab)"
step "Web: 10.0.10.12:80"
step "Client: 10.0.20.100"
step "Firewall: nftables on ns-router"
echo ""
info "Run tests with: sudo ip netns exec ns-client <command>"
info "Teardown with: sudo bash lab-teardown.sh"
echo ""
