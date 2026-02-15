# 📦 Packet Captures — Analysis Documentation

This directory contains packet captures from the Enterprise Network Lab.
Captures are generated using `tcpdump` and analyzed with Wireshark.

---

## Capture Methodology

All captures are created using the automated script:
```bash
sudo bash scripts/capture-traffic.sh [dns|arp|tcp|all]
```

### Capture Parameters
| Parameter      | Value                  |
|:---------------|:-----------------------|
| Tool           | tcpdump 4.99+          |
| Max Packets    | 100 per capture        |
| Duration       | 30 seconds             |
| Output Format  | `.pcap` (libpcap)      |
| Analysis Tool  | Wireshark 4.x          |

---

## 1. DNS Traffic Analysis

### Capture Command
```bash
sudo tcpdump -i eth0 port 53 -w dns-capture.pcap -c 50
```

### Wireshark Filter
```
dns
```

### What to Look For

| Packet          | Direction                        | Meaning                          |
|:----------------|:---------------------------------|:---------------------------------|
| DNS Query       | Client → DNS Server (10.0.10.10) | Client requesting name resolution |
| DNS Response    | DNS Server → Client              | Server returning IP address       |
| NXDOMAIN        | DNS Server → Client              | Domain does not exist             |
| SERVFAIL        | DNS Server → Client              | Server error / misconfiguration   |

### Example Analysis

![DNS query and response in Wireshark](screenshots/dns-capture-wireshark.png)

**Normal DNS resolution flow:**
```
1. Client (10.0.20.100) → DNS (10.0.10.10) : Standard query A web.enterprise.lab
2. DNS (10.0.10.10)     → Client            : Standard response A 10.0.10.12
   └── Response time: ~2ms (healthy)
```

### Key Observations
- DNS queries use **UDP port 53** (standard)
- Response time should be **< 10ms** on local network
- Watch for **retransmissions** (indicates packet loss or server issues)
- Zone transfer attempts (`AXFR`) from unexpected sources = security concern

---

## 2. ARP Traffic Analysis

### Capture Command
```bash
sudo tcpdump -i eth0 arp -w arp-capture.pcap -c 50
```

### Wireshark Filter
```
arp
```

### What to Look For

| Packet        | Type             | Meaning                              |
|:--------------|:-----------------|:-------------------------------------|
| ARP Request   | `who-has`        | Host looking for MAC of an IP        |
| ARP Reply     | `is-at`          | Host providing its MAC address       |
| Gratuitous ARP| `announce`       | Host announcing IP-to-MAC binding    |
| ARP Flood     | Many requests    | Possible ARP scan or spoofing attack |

### Example Analysis

![ARP request and reply in Wireshark](screenshots/arp-capture-wireshark.png)

**Normal ARP resolution:**
```
1. 10.0.20.100 (client) → Broadcast : Who has 10.0.20.1? Tell 10.0.20.100
2. 10.0.20.1 (gateway)  → 10.0.20.100 : 10.0.20.1 is at 00:50:56:00:01:01
```

### Key Observations
- ARP operates at **Layer 2** — only visible within the same VLAN/broadcast domain
- **Duplicate ARP replies** for the same IP = possible ARP spoofing
- **Gratuitous ARP** after failover is normal
- Large volume of ARP requests = possible network scan

---

## 3. TCP Three-Way Handshake

### Capture Command
```bash
sudo tcpdump -i eth0 'tcp[tcpflags] & (tcp-syn|tcp-ack) != 0' -w tcp-handshake.pcap -c 50
```

### Wireshark Filter
```
tcp.flags.syn == 1 || tcp.flags.ack == 1
```

### What to Look For

| Step | Packet   | Flags    | Direction         | Meaning                 |
|:-----|:---------|:---------|:------------------|:------------------------|
| 1    | SYN      | `[S]`    | Client → Server   | Connection request      |
| 2    | SYN-ACK  | `[S.]`   | Server → Client   | Server acknowledges     |
| 3    | ACK      | `[.]`    | Client → Server   | Connection established  |

### Example Analysis

![TCP three-way handshake in Wireshark](screenshots/tcp-handshake-wireshark.png)

**Successful HTTP connection (port 80):**
```
1. 10.0.20.100:54321 → 10.0.10.12:80  [SYN]      Seq=0
2. 10.0.10.12:80     → 10.0.20.100    [SYN, ACK]  Seq=0, Ack=1
3. 10.0.20.100:54321 → 10.0.10.12:80  [ACK]       Seq=1, Ack=1
4. HTTP GET / ...
```

### Failed Connection (Firewall Block):
```
1. 10.0.20.100:54321 → 10.0.10.12:22  [SYN]      Seq=0
2. (no response — SYN dropped by firewall)
3. 10.0.20.100:54321 → 10.0.10.12:22  [SYN]      (retransmission after 1s)
4. (no response — connection timeout)
```

### Key Observations
- **SYN without SYN-ACK** = port filtered (firewall) or host down
- **RST** response = port closed (service not running)
- **Retransmissions** = packet loss or congestion
- Handshake should complete in **< 5ms** on local network

---

## Opening Captures in Wireshark

```bash
# Open a specific capture
wireshark packet-captures/dns-capture_20240201_143000.pcap

# Open all captures
wireshark packet-captures/*.pcap
```

### Useful Wireshark Display Filters
| Filter                                    | Purpose                            |
|:------------------------------------------|:-----------------------------------|
| `ip.addr == 10.0.10.10`                   | All traffic to/from DNS server     |
| `dns.qry.name == "web.enterprise.lab"`    | Specific DNS query                 |
| `tcp.port == 80 && tcp.flags.syn == 1`    | HTTP SYN packets only              |
| `arp.opcode == 1`                         | ARP requests only                  |
| `tcp.analysis.retransmission`             | Retransmitted packets              |
| `frame.time_delta > 0.5`                  | Packets with > 500ms gap           |
