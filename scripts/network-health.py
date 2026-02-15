#!/usr/bin/env python3
"""
Enterprise Network Health Check
================================
Comprehensive network health monitoring tool that checks
connectivity, DNS, HTTP services, and latency across the
enterprise lab network.

Usage:
    python3 network-health.py
    python3 network-health.py --json     # JSON output
    python3 network-health.py --watch    # Continuous monitoring
"""

import subprocess
import socket
import time
import sys
import json
from datetime import datetime

# ============================================================
# Configuration
# ============================================================

HOSTS = {
    "Edge Router":    {"ip": "10.0.10.1",   "vlan": "Infrastructure"},
    "DNS Server":     {"ip": "10.0.10.10",  "vlan": "VLAN 10 — Servers"},
    "DHCP Server":    {"ip": "10.0.10.11",  "vlan": "VLAN 10 — Servers"},
    "Web Server":     {"ip": "10.0.10.12",  "vlan": "VLAN 10 — Servers"},
    "Linux Client":   {"ip": "10.0.20.100", "vlan": "VLAN 20 — Clients"},
    "Windows Client": {"ip": "10.0.20.101", "vlan": "VLAN 20 — Clients"},
}

DNS_RECORDS = [
    ("web.enterprise.lab",    "10.0.10.12"),
    ("dns.enterprise.lab",    "10.0.10.10"),
    ("dhcp.enterprise.lab",   "10.0.10.11"),
    ("router.enterprise.lab", "10.0.10.1"),
]

HTTP_ENDPOINTS = [
    ("http://10.0.10.12", 200),
]

DNS_SERVER = "10.0.10.10"

# ============================================================
# Colors
# ============================================================

class Colors:
    GREEN  = "\033[92m"
    RED    = "\033[91m"
    YELLOW = "\033[93m"
    CYAN   = "\033[96m"
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    RESET  = "\033[0m"

def green(s):  return f"{Colors.GREEN}{s}{Colors.RESET}"
def red(s):    return f"{Colors.RED}{s}{Colors.RESET}"
def yellow(s): return f"{Colors.YELLOW}{s}{Colors.RESET}"
def cyan(s):   return f"{Colors.CYAN}{s}{Colors.RESET}"
def bold(s):   return f"{Colors.BOLD}{s}{Colors.RESET}"

# ============================================================
# Check Functions
# ============================================================

def ping_host(ip, count=3, timeout=2):
    """Ping a host and return (success, avg_latency_ms)."""
    try:
        result = subprocess.run(
            ["ping", "-c", str(count), "-W", str(timeout), ip],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            # Parse avg latency from ping output
            for line in result.stdout.splitlines():
                if "avg" in line:
                    parts = line.split("=")[-1].strip().split("/")
                    avg_ms = float(parts[1])
                    return True, avg_ms
            return True, 0.0
        return False, 0.0
    except (subprocess.TimeoutExpired, Exception):
        return False, 0.0


def check_dns(hostname, expected_ip, server=DNS_SERVER):
    """Resolve a hostname and verify the result."""
    try:
        result = subprocess.run(
            ["dig", "+short", f"@{server}", hostname],
            capture_output=True, text=True, timeout=5
        )
        resolved = result.stdout.strip().split("\n")[0]
        return resolved == expected_ip, resolved
    except Exception:
        return False, "error"


def check_http(url, expected_code):
    """Check HTTP endpoint returns expected status code."""
    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "--connect-timeout", "3", url],
            capture_output=True, text=True, timeout=10
        )
        code = int(result.stdout.strip())
        return code == expected_code, code
    except Exception:
        return False, 0


def check_port(ip, port, timeout=2):
    """Check if a TCP port is open."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((ip, port))
        sock.close()
        return result == 0
    except Exception:
        return False


# ============================================================
# Main Health Check
# ============================================================

def run_health_check(json_output=False):
    """Run all health checks and display results."""
    results = {
        "timestamp": datetime.now().isoformat(),
        "ping": [],
        "dns": [],
        "http": [],
        "services": [],
        "summary": {"pass": 0, "fail": 0, "warn": 0}
    }

    if not json_output:
        print(f"\n{bold('════════════════════════════════════════')}")
        print(f"{bold('  Enterprise Network Health Dashboard')}")
        print(f"{Colors.DIM}  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{Colors.RESET}")
        print(f"{bold('════════════════════════════════════════')}")

    # --- Ping Checks ---
    if not json_output:
        print(f"\n{cyan('━━━ ICMP Reachability ━━━')}")

    for name, info in HOSTS.items():
        success, latency = ping_host(info["ip"])
        check = {
            "host": name,
            "ip": info["ip"],
            "vlan": info["vlan"],
            "reachable": success,
            "latency_ms": latency
        }
        results["ping"].append(check)

        if not json_output:
            if success:
                lat_color = green if latency < 10 else yellow
                lat_str = lat_color(f"{latency:.1f}ms")
                print(f"  {green('✓')} {name:18s} {info['ip']:15s} {lat_str}")
                results["summary"]["pass"] += 1
            else:
                print(f"  {red('✗')} {name:18s} {info['ip']:15s} {red('UNREACHABLE')}")
                results["summary"]["fail"] += 1

    # --- DNS Checks ---
    if not json_output:
        print(f"\n{cyan('━━━ DNS Resolution ━━━')}")

    for hostname, expected in DNS_RECORDS:
        success, resolved = check_dns(hostname, expected)
        check = {
            "hostname": hostname,
            "expected": expected,
            "resolved": resolved,
            "correct": success
        }
        results["dns"].append(check)

        if not json_output:
            if success:
                print(f"  {green('✓')} {hostname:30s} → {green(resolved)}")
                results["summary"]["pass"] += 1
            else:
                print(f"  {red('✗')} {hostname:30s} → {red(resolved)} (expected {expected})")
                results["summary"]["fail"] += 1

    # --- HTTP Checks ---
    if not json_output:
        print(f"\n{cyan('━━━ HTTP Services ━━━')}")

    for url, expected_code in HTTP_ENDPOINTS:
        success, code = check_http(url, expected_code)
        check = {
            "url": url,
            "expected_code": expected_code,
            "actual_code": code,
            "success": success
        }
        results["http"].append(check)

        if not json_output:
            if success:
                print(f"  {green('✓')} {url:35s} HTTP {green(str(code))}")
                results["summary"]["pass"] += 1
            else:
                print(f"  {red('✗')} {url:35s} HTTP {red(str(code))}")
                results["summary"]["fail"] += 1

    # --- Service Port Checks ---
    if not json_output:
        print(f"\n{cyan('━━━ Service Ports ━━━')}")

    services = [
        ("DNS",  DNS_SERVER, 53),
        ("HTTP", "10.0.10.12", 80),
        ("SSH",  "10.0.10.1", 22),
    ]

    for svc_name, ip, port in services:
        open_port = check_port(ip, port)
        check = {
            "service": svc_name,
            "ip": ip,
            "port": port,
            "open": open_port
        }
        results["services"].append(check)

        if not json_output:
            if open_port:
                print(f"  {green('✓')} {svc_name:6s} {ip}:{port:5d}  {green('OPEN')}")
                results["summary"]["pass"] += 1
            else:
                print(f"  {red('✗')} {svc_name:6s} {ip}:{port:5d}  {red('CLOSED')}")
                results["summary"]["fail"] += 1

    # --- Summary ---
    if json_output:
        print(json.dumps(results, indent=2))
    else:
        p = results["summary"]["pass"]
        f = results["summary"]["fail"]
        total = p + f
        print(f"\n{bold('════════════════════════════════════════')}")
        print(f"  {green(f'PASS: {p}')}")
        print(f"  {red(f'FAIL: {f}')}")
        print(f"  TOTAL: {total}")
        print(f"{bold('════════════════════════════════════════')}")

        if f == 0:
            print(f"\n  {green('✓ All systems operational')}\n")
        else:
            print(f"\n  {red(f'⚠ {f} check(s) failed — investigate above')}\n")

    return results


# ============================================================
# Entry Point
# ============================================================

if __name__ == "__main__":
    json_mode = "--json" in sys.argv
    watch_mode = "--watch" in sys.argv

    if watch_mode:
        print(f"{bold('Monitoring mode — Ctrl+C to stop')}")
        try:
            while True:
                run_health_check(json_output=json_mode)
                time.sleep(30)
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
    else:
        results = run_health_check(json_output=json_mode)
        sys.exit(1 if results["summary"]["fail"] > 0 else 0)
