# 🔧 Troubleshooting: Firewall Block — Legitimate Traffic Dropped

## Scenario
After applying updated firewall rules, VLAN 20 clients **can no longer access the web server** in VLAN 10. DNS resolution works, but HTTP connections time out.

---

## Symptoms
- `dig @10.0.10.10 web.enterprise.lab` → Returns `10.0.10.12` ✅
- `curl http://10.0.10.12` → **Connection timed out** ❌
- `ping 10.0.10.12` → **Works** ✅
- `ssh 10.0.10.12` → **Blocked** (expected by policy) ✅
- VLAN 10 servers can reach the internet ✅

## Screenshot — Symptom Observed


---

## Diagnosis Steps

### Step 1: Confirm HTTP is the issue
```bash
# From VLAN 20 client
curl -v --connect-timeout 5 http://10.0.10.12
```
**Output:**
```
* Trying 10.0.10.12:80...
* Connection timed out after 5000 milliseconds
```

### Step 2: Check if web server is listening
```bash
# On web server (10.0.10.12)
ss -tlnp | grep :80
```
**Result:** `LISTEN 0 511 *:80` → Apache is running and listening.

### Step 3: Trace the packet path
```bash
# On VLAN 20 client
sudo tcpdump -i eth0 host 10.0.10.12 and port 80 -c 5
```
**Result:** SYN packets are sent but no SYN-ACK received → firewall is dropping them.

### Step 4: Check firewall rules
```bash
# On firewall/core switch
sudo nft list chain inet filter forward
```


**Finding:** The updated rules are missing the HTTP allow rule:
```
# Current rules in FORWARD chain:
ip saddr 10.0.20.0/24 ip daddr 10.0.10.10 tcp dport 53 accept   ← DNS
ip saddr 10.0.20.0/24 ip daddr 10.0.10.10 udp dport 53 accept   ← DNS
ip saddr 10.0.20.0/24 ip daddr 10.0.10.0/24 icmp accept          ← ICMP
# ⚠️ NO RULE for port 80/443 to web server!
```

### Step 5: Check firewall drop logs
```bash
# Check for dropped packets in kernel log
sudo dmesg | grep "NFT-FORWARD-DROP" | tail -5
```
**Result:**
```
[NFT-FORWARD-DROP] IN=vlan20 OUT=vlan10 SRC=10.0.20.100 DST=10.0.10.12 
    PROTO=TCP SPT=54321 DPT=80 — DROPPED
```
Confirmed: firewall is dropping HTTP traffic to the web server.

---

## Root Cause

During a firewall rule update, the rule allowing VLAN 20 clients to access the web server on ports 80 and 443 was **accidentally removed**. The default FORWARD policy is `drop`, so without an explicit allow rule, HTTP/HTTPS traffic is silently dropped.

---

## Fix

### Step 1: Add the missing HTTP/HTTPS rule
```bash
# Add rule to allow VLAN 20 → Web Server (HTTP/HTTPS)
sudo nft add rule inet filter forward \
    ip saddr 10.0.20.0/24 \
    ip daddr 10.0.10.12 \
    tcp dport { 80, 443 } \
    accept
```

### Step 2: Verify the rule was added
```bash
sudo nft list chain inet filter forward
```


### Step 3: Save rules persistently
```bash
sudo nft list ruleset > /etc/nftables.conf
```

---

## Verification

### From VLAN 20 Client:
```bash
# HTTP access
curl -v http://10.0.10.12

# HTTPS access (if configured)
curl -vk https://10.0.10.12

# Full browser test
wget -qO- http://web.enterprise.lab
```

### Packet capture of successful TCP handshake:
```bash
# On firewall
sudo tcpdump -i vlan20 host 10.0.10.12 and port 80 -c 6
```

**Expected:**
```
SYN      10.0.20.100:54321 → 10.0.10.12:80
SYN-ACK  10.0.10.12:80     → 10.0.20.100:54321
ACK      10.0.20.100:54321 → 10.0.10.12:80
```

### Verify no more drops in log:
```bash
# Should show no new HTTP drops
sudo dmesg | grep "NFT-FORWARD-DROP" | grep "DPT=80"
```


---

## Lessons Learned
- Always **diff** firewall rulesets before and after changes: `nft list ruleset > before.txt` → make changes → `diff before.txt <(nft list ruleset)`
- Use `nft monitor` to watch rule matches in real-time during testing
- Log prefixes (`[NFT-FORWARD-DROP]`) are essential for diagnosing which chain is dropping traffic
- Test **all** expected traffic flows after firewall changes, not just the ones you modified
- Keep a backup of working rules: `nft list ruleset > /etc/nftables.conf.bak`
