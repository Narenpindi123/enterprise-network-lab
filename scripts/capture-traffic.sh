#!/bin/bash
# ============================================================
# Traffic Capture Script
# Enterprise Network Lab
# ============================================================
# Automates packet capture for DNS, ARP, and TCP analysis.
# Saves captures as .pcap files for Wireshark analysis.
#
# Usage: sudo bash capture-traffic.sh [dns|arp|tcp|all]
# ============================================================

set -euo pipefail

# --- Configuration ---
CAPTURE_DIR="$(dirname "$0")/../packet-captures"
INTERFACE="${CAPTURE_IF:-eth0}"
DURATION=30        # seconds
PACKET_COUNT=100   # max packets per capture

# --- Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$CAPTURE_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# --- Capture Functions ---

capture_dns() {
    local OUTFILE="${CAPTURE_DIR}/dns-capture_${TIMESTAMP}.pcap"
    echo -e "${CYAN}[DNS]${NC} Capturing DNS traffic on ${INTERFACE}..."
    echo "  Filter: port 53"
    echo "  Output: ${OUTFILE}"
    echo "  Duration: ${DURATION}s (max ${PACKET_COUNT} packets)"
    echo ""

    sudo tcpdump -i "$INTERFACE" \
        -c "$PACKET_COUNT" \
        -w "$OUTFILE" \
        'port 53' \
        2>&1 &
    local PID=$!

    sleep "$DURATION" 2>/dev/null || true
    sudo kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true

    echo -e "${GREEN}✓ DNS capture saved:${NC} ${OUTFILE}"
    echo ""

    # Quick analysis
    echo "  --- Quick Analysis ---"
    sudo tcpdump -r "$OUTFILE" -c 10 2>/dev/null || true
    echo ""
}

capture_arp() {
    local OUTFILE="${CAPTURE_DIR}/arp-capture_${TIMESTAMP}.pcap"
    echo -e "${CYAN}[ARP]${NC} Capturing ARP traffic on ${INTERFACE}..."
    echo "  Filter: arp"
    echo "  Output: ${OUTFILE}"
    echo ""

    sudo tcpdump -i "$INTERFACE" \
        -c "$PACKET_COUNT" \
        -w "$OUTFILE" \
        'arp' \
        2>&1 &
    local PID=$!

    sleep "$DURATION" 2>/dev/null || true
    sudo kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true

    echo -e "${GREEN}✓ ARP capture saved:${NC} ${OUTFILE}"
    echo ""

    echo "  --- Quick Analysis ---"
    sudo tcpdump -r "$OUTFILE" -c 10 2>/dev/null || true
    echo ""
}

capture_tcp() {
    local OUTFILE="${CAPTURE_DIR}/tcp-handshake_${TIMESTAMP}.pcap"
    echo -e "${CYAN}[TCP]${NC} Capturing TCP SYN/SYN-ACK/ACK on ${INTERFACE}..."
    echo "  Filter: tcp[tcpflags] & (tcp-syn|tcp-ack) != 0"
    echo "  Output: ${OUTFILE}"
    echo ""

    sudo tcpdump -i "$INTERFACE" \
        -c "$PACKET_COUNT" \
        -w "$OUTFILE" \
        'tcp[tcpflags] & (tcp-syn|tcp-ack) != 0' \
        2>&1 &
    local PID=$!

    sleep "$DURATION" 2>/dev/null || true
    sudo kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true

    echo -e "${GREEN}✓ TCP handshake capture saved:${NC} ${OUTFILE}"
    echo ""

    echo "  --- Quick Analysis ---"
    sudo tcpdump -r "$OUTFILE" -c 10 2>/dev/null || true
    echo ""
}

# --- Main ---
echo "========================================"
echo " Enterprise Network — Traffic Capture"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Interface: ${INTERFACE}"
echo "========================================"
echo ""

MODE="${1:-all}"

case "$MODE" in
    dns)  capture_dns ;;
    arp)  capture_arp ;;
    tcp)  capture_tcp ;;
    all)
        capture_dns
        capture_arp
        capture_tcp
        ;;
    *)
        echo "Usage: $0 [dns|arp|tcp|all]"
        exit 1
        ;;
esac

echo "========================================"
echo -e "${GREEN}✓ All captures complete.${NC}"
echo "  Files saved to: ${CAPTURE_DIR}/"
echo "  Open with: wireshark ${CAPTURE_DIR}/*.pcap"
echo "========================================"
