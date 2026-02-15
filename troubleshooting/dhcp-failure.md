# 🔧 Troubleshooting: DHCP Failure

## Scenario
New clients added to VLAN 20 **cannot obtain an IP address** via DHCP. They fall back to an APIPA address (169.254.x.x). Existing clients with active leases still work.

---

## Symptoms
- New VLAN 20 clients get `169.254.x.x` addresses (APIPA / link-local) ❌
- Existing clients with valid leases continue to work ✅
- `dhclient -v eth0` shows **"No DHCPOFFER received"**
- Manually setting a static IP works — network path is fine ✅

## Screenshot — Symptom Observed


---

## Diagnosis Steps

### Step 1: Request a lease manually and watch output
```bash
# From VLAN 20 client
sudo dhclient -v eth0
```
**Output:**
```
DHCPDISCOVER on eth0 to 255.255.255.255 port 67 interval 3
DHCPDISCOVER on eth0 to 255.255.255.255 port 67 interval 6
No DHCPOFFER received.
No working leases in persistent database — sleeping.
```

### Step 2: Capture DHCP traffic
```bash
# On the DHCP server (10.0.10.11)
sudo tcpdump -i vlan10 port 67 or port 68 -c 10
```
**Result:** No DHCP DISCOVER packets arriving at the server → packets are being lost between client and server.

### Step 3: Check DHCP relay on router
```bash
# On VyOS router
show service dhcp-relay
```


**Finding:** The DHCP relay is configured but the relay interface for VLAN 20 is missing:
```
interface: eth1.20    ← Not configured!
server: 10.0.10.11   ← Correct
```

### Step 4: Verify DHCP server is running
```bash
# On DHCP server (10.0.10.11)
sudo systemctl status isc-dhcp-server
```
**Result:** Service is running. The VLAN 20 subnet is defined in `dhcpd.conf`. Problem is that DHCP broadcasts from VLAN 20 never get relayed to the server.

---

## Root Cause

VLAN 20 clients send DHCP DISCOVER as broadcasts (`255.255.255.255`). Since the DHCP server is in VLAN 10, a **DHCP relay agent** on the router must forward these broadcasts. The relay was configured but **the VLAN 20 interface (`eth1.20`) was not added to the relay configuration**, so broadcasts from VLAN 20 are never forwarded.

---

## Fix

### Step 1: Configure DHCP relay on router
```bash
# On VyOS router
configure

set service dhcp-relay interface 'eth1.20'
set service dhcp-relay server '10.0.10.11'
set service dhcp-relay relay-options relay-agents-packets 'discard'

commit
save
```

### Step 2: Verify relay configuration
```bash
show service dhcp-relay
```

**Expected output:**
```
interface: eth1.20
server: 10.0.10.11
relay-options:
    relay-agents-packets: discard
```

### Step 3: Verify DHCP server has VLAN 20 scope
```bash
# On DHCP server, check dhcpd.conf includes VLAN 20 subnet
grep -A 5 "10.0.20" /etc/dhcp/dhcpd.conf
```


---

## Verification

### From VLAN 20 Client:
```bash
# Release current (APIPA) address
sudo dhclient -r eth0

# Request new lease
sudo dhclient -v eth0

# Verify IP assignment
ip addr show eth0
cat /etc/resolv.conf
```

**Expected:** Client receives `10.0.20.x` address with correct gateway and DNS.

### Packet Capture verification:
```bash
# On router, capture the relay in action
sudo tcpdump -i eth1.20 port 67 or port 68 -c 4
```

**Expected capture:**
```
DHCP DISCOVER → 255.255.255.255 (broadcast from client)
DHCP OFFER    ← 10.0.10.11 (relayed from server)
DHCP REQUEST  → 255.255.255.255
DHCP ACK      ← 10.0.10.11
```

### Check active leases:
```bash
# On DHCP server
sudo dhcp-lease-list
```


---

## Lessons Learned
- DHCP relies on **broadcasts** which don't cross VLAN boundaries — a relay is required
- When adding new VLANs, always check: sub-interface, firewall rules, AND DHCP relay
- `dhclient -v` is the best first diagnostic — it shows the full DORA handshake
- Existing clients may still work (active leases) while new clients fail — this narrows the cause
