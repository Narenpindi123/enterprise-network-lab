# 🔧 Troubleshooting: VLAN Misconfiguration

## Scenario
After a maintenance window, clients on VLAN 20 **can no longer communicate** with each other or reach their default gateway. VLAN 10 servers are unaffected and operate normally.

---

## Symptoms
- VLAN 20 clients get an IP address from DHCP ✅
- VLAN 20 clients **cannot** ping their gateway (`10.0.20.1`) ❌
- VLAN 20 clients **cannot** ping each other ❌
- VLAN 10 servers work normally ✅
- Physical link lights are up on all ports ✅

## Screenshot — Symptom Observed


---

## Diagnosis Steps

### Step 1: Verify client IP configuration
```bash
# From VLAN 20 Linux Client (10.0.20.100)
ip addr show eth0
ip route show
```
**Result:** Client has correct IP `10.0.20.100/24`, gateway `10.0.20.1`. Config looks correct.

### Step 2: Check Layer 2 connectivity
```bash
# ARP check — can we resolve the gateway MAC?
arping -c 3 10.0.20.1
```
**Result:** `Timeout` — No ARP reply. This is a Layer 2 (switching/VLAN) problem.

### Step 3: Inspect VLAN tagging on the core switch
```bash
# On the Core Switch
ip -d link show eth1.20
cat /proc/net/vlan/eth1.20
```


**Finding:**
```
eth1.20@eth1: <BROADCAST,MULTICAST,UP>
    vlan protocol 802.1Q id 200    ← WRONG! Should be VLAN 20, not 200
```

⚠️ The VLAN ID was set to **200** instead of **20** during maintenance.

### Step 4: Verify the router sub-interface
```bash
# On VyOS router
show interfaces ethernet eth1 vif 20
```
**Result:** Router is correctly configured for VLAN ID 20. The **mismatch** between the switch (200) and router (20) means tagged frames never match.

---

## Root Cause

During a maintenance window, the VLAN setup script was modified and the VLAN ID for the client network was accidentally changed from `20` to `200`. The router's sub-interface is still configured for VLAN 20. Since the VLAN tags don't match, frames from the switch are tagged with `200` but the router expects `20` — they are effectively on different VLANs.

```bash
# The script had:
ip link add link eth1 name eth1.20 type vlan id 200   ← BUG: should be "id 20"
```

---

## Fix

### Step 1: Remove the incorrect VLAN interface
```bash
# On Core Switch
sudo ip link set eth1.20 down
sudo ip link delete eth1.20
```

### Step 2: Recreate with correct VLAN ID
```bash
sudo ip link add link eth1 name eth1.20 type vlan id 20
sudo ip addr add 10.0.20.2/24 dev eth1.20
sudo ip link set eth1.20 up
```

### Step 3: Re-attach to bridge
```bash
sudo ip link set eth1.20 master br-vlan20
```

### Step 4: Fix the setup script
```bash
# In configs/vlan-setup.sh, correct the VLAN ID:
# BEFORE: ip link add link eth1 name eth1.20 type vlan id 200
# AFTER:  ip link add link eth1 name eth1.20 type vlan id 20
```

### Step 5: Verify VLAN configuration
```bash
ip -d link show eth1.20
cat /proc/net/vlan/eth1.20
```


---

## Verification

### From VLAN 20 Client:
```bash
# Gateway reachability
ping -c 3 10.0.20.1

# Peer connectivity
ping -c 3 10.0.20.101

# Cross-VLAN
ping -c 3 10.0.10.10

# ARP resolution
arping -c 3 10.0.20.1
```

### Capture VLAN tags:
```bash
# On Core Switch trunk port
sudo tcpdump -i eth1 -e -c 10 vlan
```


---

## Lessons Learned
- **Always verify VLAN IDs** on both the switch and router after changes — they must match
- Use `ip -d link show` to inspect the actual VLAN ID on an interface
- `arping` is the go-to tool when you suspect Layer 2 issues
- VLAN mismatches are silent failures — no error messages, just dropped frames
- Document VLAN IDs in a central table and cross-reference during changes
