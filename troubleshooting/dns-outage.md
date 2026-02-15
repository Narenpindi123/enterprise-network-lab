# 🔧 Troubleshooting: DNS Outage

## Scenario
Users on VLAN 20 (Clients) report they **cannot browse the web** or reach internal services by hostname. Ping by IP address works, but `nslookup` and `dig` fail.

---

## Symptoms
- `nslookup web.enterprise.lab` returns **"connection timed out; no servers could be reached"**
- `ping 10.0.10.12` (web server by IP) **works fine**
- `curl http://web.enterprise.lab` fails with **"Could not resolve host"**
- Users can still communicate between VLANs via IP

## Screenshot — Symptom Observed


---

## Diagnosis Steps

### Step 1: Check DNS from client
```bash
# From VLAN 20 Linux Client (10.0.20.100)
nslookup web.enterprise.lab
dig @10.0.10.10 web.enterprise.lab
```
**Expected:** Both should return `10.0.10.12`
**Actual:** Connection timed out

### Step 2: Verify DNS server is reachable
```bash
# Can we reach the DNS server at all?
ping 10.0.10.10
```
**Result:** Ping succeeds → Network path is fine, DNS service is the issue.

### Step 3: Check DNS service on server
```bash
# SSH to DNS server (10.0.10.10)
ssh admin@10.0.10.10

# Check BIND9 service status
sudo systemctl status named
```


**Result:** Service is `inactive (dead)` — BIND9 has stopped.

### Step 4: Check DNS server logs
```bash
# View recent BIND9 logs
sudo journalctl -u named --since "1 hour ago" --no-pager
```

**Result:** Log shows: `zone enterprise.lab/IN: loading from master file failed: file not found`

---

## Root Cause

The BIND9 DNS server crashed because the zone file path in `named.conf` was incorrect. The configuration referenced `/etc/bind/zones/db.enterprise.lab`, but the file was moved to `/etc/bind/db.enterprise.lab` during a recent change.

```
zone "enterprise.lab" {
    type master;
    file "/etc/bind/zones/db.enterprise.lab";   ← File doesn't exist here
};
```

---

## Fix

### Step 1: Move zone file to correct location
```bash
sudo mkdir -p /etc/bind/zones/
sudo cp /etc/bind/db.enterprise.lab /etc/bind/zones/db.enterprise.lab
```

### Step 2: Verify zone file syntax
```bash
sudo named-checkzone enterprise.lab /etc/bind/zones/db.enterprise.lab
```
**Expected output:** `zone enterprise.lab/IN: loaded serial 2024020101 — OK`

### Step 3: Restart BIND9
```bash
sudo systemctl restart named
sudo systemctl status named
```


---

## Verification

### From VLAN 20 Client:
```bash
# DNS resolution should work now
dig @10.0.10.10 web.enterprise.lab

# Expected output:
# ;; ANSWER SECTION:
# web.enterprise.lab.   604800  IN  A  10.0.10.12

# Full connectivity test
curl http://web.enterprise.lab
nslookup dns.enterprise.lab
```

### Packet Capture confirmation:
```bash
# On DNS server, capture the query-response
sudo tcpdump -i vlan10 port 53 -c 5
```


---

## Lessons Learned
- Always use `named-checkconf` after editing BIND9 configuration
- Monitor DNS service health with automated checks (see `scripts/validate-network.sh`)
- Symptom (can't browse) vs root cause (DNS service down) — always test layer by layer
