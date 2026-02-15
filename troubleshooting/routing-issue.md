# 🔧 Troubleshooting: Routing Issue — Missing Route

## Scenario
A new subnet (VLAN 20 — Clients) was added to the network. Clients in VLAN 20 **cannot reach the internet** or servers in VLAN 10. Internal pings between VLANs also fail.

---

## Symptoms
- VLAN 20 clients can ping their default gateway (`10.0.20.1`) ✅
- VLAN 20 clients **cannot** ping VLAN 10 servers (`10.0.10.10`) ❌
- VLAN 20 clients **cannot** reach the internet (`ping 8.8.8.8`) ❌
- VLAN 10 servers can reach the internet normally ✅
- `traceroute` from VLAN 20 shows packets dying at the first hop

## Screenshot — Symptom Observed


---

## Diagnosis Steps

### Step 1: Verify client configuration
```bash
# From VLAN 20 Linux Client (10.0.20.100)
ip addr show eth0
ip route show
```
**Check:** Is the default gateway set to `10.0.20.1`?

### Step 2: Ping the default gateway
```bash
ping -c 3 10.0.20.1
```
**Result:** Success → Layer 2 and local routing work.

### Step 3: Traceroute to VLAN 10
```bash
traceroute 10.0.10.10
```
**Result:** `* * *` after hop 1 → Router is not forwarding packets.

### Step 4: Check router's routing table
```bash
# On the VyOS Edge Router
show ip route
```


**Finding:** The routing table shows:
```
C    10.0.10.0/24 is directly connected, eth1.10
S    0.0.0.0/0 [1/0] via 203.0.113.2, eth0
```
⚠️ **VLAN 20 subnet (10.0.20.0/24) is MISSING** — the VLAN 20 sub-interface was never configured.

### Step 5: Check interfaces
```bash
show interfaces
```
**Finding:** `eth1.20` does not exist — the VLAN 20 sub-interface was never created on the router.

---

## Root Cause

When VLAN 20 was added to the core switch, the corresponding **sub-interface on the router (`eth1.20`) was never configured**. Without this interface, the router has no route to `10.0.20.0/24` and cannot forward traffic for that subnet.

---

## Fix

### Step 1: Add VLAN 20 sub-interface on router
```bash
# On VyOS router
configure

set interfaces ethernet eth1 vif 20 address '10.0.20.1/24'
set interfaces ethernet eth1 vif 20 description 'VLAN 20 - Clients'

commit
save
```

### Step 2: Add NAT rule for VLAN 20
```bash
set nat source rule 200 outbound-interface name 'eth0'
set nat source rule 200 source address '10.0.20.0/24'
set nat source rule 200 translation address 'masquerade'

commit
save
```

### Step 3: Verify the routing table
```bash
show ip route
```


**Expected:** Both subnets now appear:
```
C    10.0.10.0/24 is directly connected, eth1.10
C    10.0.20.0/24 is directly connected, eth1.20
S    0.0.0.0/0 [1/0] via 203.0.113.2, eth0
```

---

## Verification

### From VLAN 20 Client:
```bash
# Inter-VLAN connectivity
ping -c 3 10.0.10.10        # DNS server in VLAN 10
ping -c 3 10.0.10.12        # Web server in VLAN 10

# Internet access
ping -c 3 8.8.8.8
traceroute 8.8.8.8

# Full path trace
traceroute 10.0.10.10
```

### From VLAN 10 Server:
```bash
# Reverse path
ping -c 3 10.0.20.100       # Linux client in VLAN 20
```


---

## Lessons Learned
- Every VLAN needs a corresponding **router sub-interface** (router-on-a-stick)
- Always verify `show ip route` after adding VLANs
- The `traceroute` tool is invaluable for pinpointing where packets are being dropped
- NAT rules must explicitly include each internal subnet
