
# example.com — public IP change / router replacement

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md) · DNS table: [DNS records (Cloudflare)](03-dns-cloudflare.md)

> Current public IP: `203.0.113.10` · server LAN: `192.168.1.50` · router/gateway: `192.168.1.1`

## 0. First check: can the new connection accept inbound?
- Compare router WAN IP with `curl ifconfig.me` from the server
  - equal + not in `10.x`, `172.16–31.x`, `192.168.x`, `100.64–127.x` → port forwarding works
  - different or private → CGNAT → forwards will NOT work
- CGNAT fallback: website → Cloudflare Tunnel (`cloudflared`), mail → no direct receive (use Cloudflare Email Routing for receiving, relay for sending)
- Operator must allow inbound 25 (test later with `nc -vz NEWIP 25` from outside)

## A. Only the PUBLIC IP changed (same router, same LAN)
Replace `203.0.113.10` → `NEWIP` in every place:

| # | Where | What to do |
|---|---|---|
| 1 | Cloudflare DNS | edit A records: `example.com`, `host`, `mail`, `webmail` → NEWIP (keep proxy settings) |
| 2 | **Brevo** → Security → **Authorized IPs** | add NEWIP, remove old. ! otherwise relay fails: "Unauthorized IP addresses are blocked for your SMTP keys" |
| 3 | Hestia NAT IP | `sudo /usr/local/hestia/bin/v-list-sys-ips` → `sudo /usr/local/hestia/bin/v-change-sys-ip-nat 192.168.1.50 NEWIP` |
| 4 | Hestia web domain IP | panel shows web domain IP = NAT IP → follows #3; check Web → example.com |
| 5 | Termius / `~/.ssh/config` / any saved host | edit host to NEWIP (or use `host.example.com` / `ssh` via DNS name) |
| 6 | SPF | uses `a:mail.example.com` → follows DNS automatically, no edit |
| 7 | Anything with the IP hard-coded | `grep -rn 203.0.113.10 /etc /usr/local/hestia/data 2>/dev/null` |

Then verify (section C).

## B. Router REPLACED
1. New router LAN: keep `192.168.1.0/24`, gateway `192.168.1.1` → server needs NO change
   - ! if the new router uses a different subnet → server IP changes → Hestia nginx is bound to the old LAN IP → see B2
2. DHCP reservation: server MAC (`ip -br link show enp3s0`) → `192.168.1.50`
3. Port forwards TCP (WAN port = LAN port) → `192.168.1.50`: **22, 80, 443, 25, 465, 587, 993** and **8083** (panel; protected only by Hestia firewall rules → or skip 8083 and use the SSH tunnel)
4. Admin: change default password, disable WAN/remote admin
5. If the public IP changed too → do section A
6. Reboot server once, then verify (C)

### B2. LAN subnet changed (new server IP)
- Set the new IP (DHCP reservation or netplan `/etc/netplan/50-cloud-init.yaml`)
- Hestia keeps the old IP in `/usr/local/hestia/data/ips/` and nginx configs bind it:
```bash
sudo /usr/local/hestia/bin/v-list-sys-ips
sudo /usr/local/hestia/bin/v-add-sys-ip NEWLANIP 255.255.255.0 enp3s0 admin shared NEWPUBLICIP
# move domains to the new IP (repeat per domain)
sudo /usr/local/hestia/bin/v-change-web-domain-ip webuser example.com NEWLANIP
sudo /usr/local/hestia/bin/v-delete-sys-ip 192.168.1.50
sudo /usr/local/hestia/bin/v-rebuild-web-domains webuser
sudo systemctl restart nginx exim4 dovecot
```
- Update Hestia firewall rules that mention the old LAN (`192.168.1.0/24`)

## C. Verify after any change
```bash
# DNS (from anywhere)
dig +short A example.com @1.1.1.1; dig +short A mail.example.com @1.1.1.1
# ports from OUTSIDE (phone data / other network)
for p in 25 80 443 465 587 993; do nc -vz -w 5 NEWIP $p; done
# on the server
sudo grep -E 'smtp-relay|\*\*' /var/log/exim4/mainlog | tail
systemctl is-active nginx exim4 dovecot hestia
```
- Web: `curl -I https://example.com` → `HTTP/2 200` + `server: cloudflare`
- Mail receive: send from Gmail to `admin@example.com` → `sudo tail /var/log/exim4/mainlog` shows `<=` from google
- Mail send: send from webmail to Gmail → mainlog shows `=> … H=smtp-relay.brevo.com … 250 OK`
- Brevo relay error "unauthorized IP" → step A2 not done

## D. Quick reference — what each symptom means
- Website 521/522 → port 443 not forwarded / wrong LAN IP · 526 → Origin cert problem · 525 → TLS mode
- Can send but not receive → port 25 forward missing or operator blocks inbound 25
- Can receive but not send → Brevo authorized IP / key (`sudo grep brevo /var/log/exim4/mainlog`)
- SSH timeout → Hestia firewall rule for your current IP (admin IP also changes!)
