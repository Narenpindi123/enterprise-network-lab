#!/bin/bash
# ============================================================
# Network Validation Script
# Enterprise Network Lab
# ============================================================
# Runs a comprehensive suite of connectivity and service
# checks across the enterprise network.
#
# Usage: sudo bash validate-network.sh
# ============================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Counters ---
PASS=0
FAIL=0
WARN=0

# --- Helper Functions ---
pass() { echo -e "  ${GREEN}✓ PASS${NC} — $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC} — $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC} — $1"; ((WARN++)); }
header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# --- Configuration ---
ROUTER_IP="10.0.10.1"
DNS_SERVER="10.0.10.10"
DHCP_SERVER="10.0.10.11"
WEB_SERVER="10.0.10.12"
CLIENT_LINUX="10.0.20.100"
CLIENT_WINDOWS="10.0.20.101"
EXTERNAL_DNS="8.8.8.8"
DOMAIN="enterprise.lab"

echo "========================================"
echo " Enterprise Network Validation Suite"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# ============================================================
# 1. PING SWEEP — Layer 3 Reachability
# ============================================================
header "Layer 3 Reachability (ICMP)"

declare -A HOSTS=(
    ["Router"]=$ROUTER_IP
    ["DNS Server"]=$DNS_SERVER
    ["DHCP Server"]=$DHCP_SERVER
    ["Web Server"]=$WEB_SERVER
    ["Linux Client"]=$CLIENT_LINUX
)

for name in "${!HOSTS[@]}"; do
    ip=${HOSTS[$name]}
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        pass "$name ($ip) is reachable"
    else
        fail "$name ($ip) is unreachable"
    fi
done

# ============================================================
# 2. DNS RESOLUTION
# ============================================================
header "DNS Resolution"

DNS_TESTS=(
    "web.enterprise.lab"
    "dns.enterprise.lab"
    "dhcp.enterprise.lab"
    "router.enterprise.lab"
)

for record in "${DNS_TESTS[@]}"; do
    result=$(dig +short @${DNS_SERVER} "$record" 2>/dev/null)
    if [[ -n "$result" ]]; then
        pass "Resolved $record → $result"
    else
        fail "Failed to resolve $record"
    fi
done

# External DNS forwarding
ext_result=$(dig +short @${DNS_SERVER} google.com 2>/dev/null)
if [[ -n "$ext_result" ]]; then
    pass "External DNS forwarding works (google.com → $ext_result)"
else
    warn "External DNS forwarding may not be configured"
fi

# ============================================================
# 3. DHCP LEASE CHECK
# ============================================================
header "DHCP Service"

if ping -c 1 -W 2 "$DHCP_SERVER" &>/dev/null; then
    pass "DHCP server ($DHCP_SERVER) is reachable"
else
    fail "DHCP server ($DHCP_SERVER) is unreachable"
fi

# Check if lease file exists (local server only)
if [[ -f /var/lib/dhcp/dhcpd.leases ]]; then
    lease_count=$(grep -c "^lease" /var/lib/dhcp/dhcpd.leases 2>/dev/null || echo 0)
    pass "DHCP lease file found — $lease_count lease entries"
else
    warn "DHCP lease file not found (may not be running on this host)"
fi

# ============================================================
# 4. WEB SERVER CHECK
# ============================================================
header "Web Server (HTTP)"

http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://${WEB_SERVER}" 2>/dev/null || echo "000")
if [[ "$http_code" == "200" ]]; then
    pass "Web server returns HTTP 200"
elif [[ "$http_code" == "000" ]]; then
    fail "Web server unreachable (connection timeout)"
else
    warn "Web server returned HTTP $http_code"
fi

# ============================================================
# 5. ROUTING TABLE VALIDATION
# ============================================================
header "Routing Table"

routes=$(ip route show 2>/dev/null)
if echo "$routes" | grep -q "default"; then
    pass "Default route exists"
else
    fail "No default route found"
fi

if echo "$routes" | grep -q "10.0.10.0"; then
    pass "Route to VLAN 10 (10.0.10.0/24) exists"
else
    warn "No explicit route to VLAN 10"
fi

if echo "$routes" | grep -q "10.0.20.0"; then
    pass "Route to VLAN 20 (10.0.20.0/24) exists"
else
    warn "No explicit route to VLAN 20"
fi

# ============================================================
# 6. FIREWALL STATUS
# ============================================================
header "Firewall (nftables)"

if command -v nft &>/dev/null; then
    rule_count=$(sudo nft list ruleset 2>/dev/null | grep -c "accept\|drop" || echo 0)
    if [[ "$rule_count" -gt 0 ]]; then
        pass "nftables active with $rule_count rules"
    else
        warn "nftables loaded but no rules found"
    fi
else
    warn "nftables not installed"
fi

# ============================================================
# 7. INTERNET CONNECTIVITY
# ============================================================
header "Internet Connectivity"

if ping -c 1 -W 3 "$EXTERNAL_DNS" &>/dev/null; then
    pass "Internet reachable via ICMP (8.8.8.8)"
else
    fail "Cannot reach internet (8.8.8.8)"
fi

if dig +short google.com @${EXTERNAL_DNS} &>/dev/null; then
    pass "External DNS resolution works"
else
    warn "External DNS resolution failed"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "========================================"
echo " Results Summary"
echo "========================================"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}WARN: $WARN${NC}"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
    echo -e "\n${RED}⚠ Some checks failed. Review output above.${NC}"
    exit 1
else
    echo -e "\n${GREEN}✓ All critical checks passed.${NC}"
    exit 0
fi
