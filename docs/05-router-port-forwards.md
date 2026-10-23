
# 4G router — virtual servers (port forwards) and settings

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md) · Router replaced / IP changed → [Public IP or router change](06-public-ip-or-router-change.md)

## Network
- Router LAN: `192.168.1.1` · subnet `192.168.1.0/24` · DHCP on
- Server: `192.168.1.50` (DHCP reservation for its MAC — `ip -br link show enp3s0`)
- Public (WAN) IP: `203.0.113.10` (4G operator static)

## Virtual Servers List (as configured, copied from the router UI 2026-10-23)
| Name | Remote host | WAN Port | LAN IP Address | LAN Port | Protocol |
|---|---|---|---|---|---|
| ubuntu SSH | (empty) | 22-22 | 192.168.1.50 | 22-22 | TCP |
| 80 | (empty) | 80-80 | 192.168.1.50 | 80-80 | TCP |
| 443 | (empty) | 443-443 | 192.168.1.50 | 443-443 | TCP |
| 25 | (empty) | 25-25 | 192.168.1.50 | 25-25 | TCP |
| 8083 hestia | (empty) | 8083-8083 | 192.168.1.50 | 8083-8083 | TCP |
| 993 | (empty) | 993-993 | 192.168.1.50 | 993-993 | TCP |
| 465 | (empty) | 465-465 | 192.168.1.50 | 465-465 | TCP |
| 587 | (empty) | 587-587 | 192.168.1.50 | 587-587 | TCP |

- Remote host empty = from anywhere → source limiting is done on the server by the Hestia firewall, not on the router
- ! `8083 hestia` and `ubuntu SSH` are open to the internet at the router → ONLY the Hestia firewall rules (PC `198.51.100.20`, LAN `192.168.1.0/24`, iPhone IP) keep them private
  - check: `sudo /usr/local/hestia/bin/v-list-firewall` → no `0.0.0.0/0` for 22 or 8083
- Option to close 8083 at the router and use the SSH tunnel → [Hestia panel via SSH tunnel](08-hestia-panel-via-ssh-tunnel.md)

## What each rule is for
| Port | Service | Who uses it |
|---|---|---|
| 22 | SSH | admin PC, Termius on iPhone |
| 80 | HTTP | Cloudflare → origin, Let's Encrypt validation |
| 443 | HTTPS | website `example.com` (via Cloudflare), webmail |
| 25 | SMTP | other mail servers delivering to `@example.com` |
| 465 | SMTPS (submission) | mail clients sending |
| 587 | SMTP submission (STARTTLS) | mail clients sending |
| 993 | IMAPS | mail clients reading |
| 8083 | Hestia panel | admin |

## Other router settings to keep
- Admin password changed from default · remote/WAN administration OFF
- ! Do NOT add port 110/995 (POP3 not running), 143 (IMAP plain), 3306 (MariaDB)
- Operator behaviour (tested 2026-10-23): inbound 25, 80, 443 allowed; outbound 25 and 587 allowed. A new SIM/operator must be re-tested → [Public IP or router change](06-public-ip-or-router-change.md) §0

## Test from outside (phone on mobile data / other network)
```bash
for p in 22 25 80 443 465 587 993 8083; do nc -vz -w 5 203.0.113.10 $p; done
```
- 22 and 8083 only answer from allowed IPs (others time out — correct)
- 25, 80, 443, 465, 587, 993 should be open from anywhere
