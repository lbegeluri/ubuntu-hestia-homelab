
# example.com — troubleshooting and gotchas


Part of: [Architecture and inventory](01-architecture-and-inventory.md) · Rebuild: [Rebuild from scratch](02-rebuild-from-scratch.md) · IP/router: [Public IP or router change](06-public-ip-or-router-change.md)

## Health check (paste block)
```bash
echo "== services"; systemctl is-active nginx hestia exim4 dovecot mariadb fail2ban clamav-daemon | paste -sd' '
echo "== listening"; sudo ss -tlnp | awk '/:(22|25|80|443|465|587|993|8083|3306)\s/{print $4}' | sort -u | paste -sd' '
echo "== exim queue"; sudo exim4 -bpc
echo "== firewall"; sudo /usr/local/hestia/bin/v-list-firewall
echo "== ssh"; sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|allowusers) '
echo "== fail2ban"; sudo fail2ban-client status
echo "== disk/ram"; df -h / | tail -1; free -h | sed -n 2p
echo "== cert expiry"; echo | openssl s_client -connect localhost:443 -servername mail.example.com 2>/dev/null | openssl x509 -noout -enddate
```
- Outside: `curl -I https://example.com` · `for p in 25 465 587 993; do nc -vz -w5 PUBLICIP $p; done`

## Symptom → cause → fix
| Symptom | Cause | Fix |
|---|---|---|
| nginx `failed`, ports 80/443 closed after boot | Hestia nginx binds `192.168.1.50`, started before DHCP gave it | `systemctl start nginx`; drop-in `wait-network.conf`; DHCP reservation |
| Hestia installer: "Unable to connect to the Hestia APT repository" | installer does `wget https://apt.hestiacp.com` → 404 | patch line to `/pubkey.gpg` (see [Rebuild from scratch](02-rebuild-from-scratch.md) §4) |
| `v-add-web-domain-ssl`: "Certificate Authority not found" | missing `.ca` | add Cloudflare `origin_ca_rsa_root.pem` as `example.com.ca` |
| Hestia File Manager: "Unknown error" / empty | (1) impersonating (`webuser (sysadmin)`) (2) sshd `AllowUsers` lacks `webuser@127.0.0.1` | log in directly as `webuser`; fix AllowUsers; error in `/var/log/hestia/nginx-error.log` "Could not login with username: webuser, host: 127.0.0.1" |
| Panel :8083 times out from my IP (SSH works) | fail2ban `hestia-iptables` banned my IP after failed panel logins | `sudo fail2ban-client set hestia-iptables unbanip IP` + `v-delete-firewall-ban IP PANEL`; add to `ignoreip` |
| Panel unreachable, IP changed | Hestia firewall rule has old admin IP | SSH tunnel from allowed place or LAN → `v-change-firewall-rule` |
| Exim won't start: "two client authenticators … same public name (LOGIN)" | hand-added authenticator duplicates Hestia's `smtp_relay_login` | remove `# BEGIN brevo … # END brevo` blocks or restore `exim4.conf.template.bak.*`; use the panel SMTP Relay |
| Brevo: "Unauthorized IP addresses are blocked for your SMTP keys" | server public IP not in Brevo → Security → Authorized IPs | add it |
| Brevo wizard: "multiple DMARC records" | cached old `_dmarc` or 2 records | keep exactly one |
| Brevo branded record collides with `mail` | wizard default subdomain `mail` | choose `bm` |
| Mail from 365 never arrives | port 25 forward missing (also: forwards removed after test) / ufw | check router "25"; `grep '<=' /var/log/exim4/mainlog` shows nothing = never reached |
| Mail to 365 goes to Junk | new domain reputation | Not junk, reply, send normal mail; check headers SPF/DKIM/DMARC pass |
| iPhone: "Cannot Connect Using SSL" | POP tab (no POP3 listener), username without domain, wrong ports | IMAP tab, full address, 993 SSL, SMTP 465 SSL |
| Exim log "SMTP call dropped: too many syntax or protocol errors" with binary text | client uses SSL on 587 (plain/STARTTLS port) | SMTP 465 SSL, or 587 with SSL off |
| Let's Encrypt for mail fails | `mail`/`webmail` Proxied, port 80 closed, DNS not yet there | DNS only, wait, retry; form boxes empty |
| Panel SSL form: "SSL intermediate chain is not valid" | leftover text in cert/key/CA boxes (self-signed generated) | clear all three boxes or use `v-add-letsencrypt-domain webuser example.com '' yes` |
| `webmail.example.com` NXDOMAIN on office PC only | DC01 `10.0.0.5` negative cache (~30 min) | `nslookup NAME 1.1.1.1`; wait; phone on mobile data |
| nginx test: "real_ip_header directive is duplicate" | Hestia already has Cloudflare real-ip | delete my extra `/etc/nginx/conf.d/cloudflare-realip.conf` |
| Exim "Too many Received headers – suspected mail loop" for `*@host.example.com` | `host.example.com` not in `local_domains` (only `/etc/exim4/domains/*`) → routed to itself | harmless; delete frozen msgs: `sudo exim4 -bp`, `sudo exim4 -Mrm ID`; old `127.0.1.1 ubuntu` line removed from `/etc/hosts` |
| Script said "edit LOGIN and KEY first" though edited | nano replace-all also rewrote the script's own check | don't use placeholder replace-all; type secrets into the Hestia panel instead |
| Password `...!!` ran a different command | bash history expansion | single quotes |
| Cloudflare "origin IP partially exposed" | `host`/`mail`/`webmail` DNS only | expected for mail |

## Logs: what to grep
```bash
sudo tail -f /var/log/exim4/mainlog                                  # SMTP in/out
sudo grep -E '<=|=>|\*\*' /var/log/exim4/mainlog | tail -20           # accepted / delivered / errors
sudo grep -hiE 'imap-login|auth failed' /var/log/dovecot.log | tail   # IMAP logins
sudo grep sshd /var/log/auth.log | tail -20                          # SSH
sudo tail -30 /var/log/nginx/domains/example.com.log                  # web hits (real IPs)
sudo tail -20 /var/log/hestia/error.log /var/log/hestia/nginx-error.log /var/log/hestia/auth.log
sudo fail2ban-client status ssh-iptables                             # also dovecot-iptables exim-iptables hestia-iptables
```
- Exim relay success looks like: `=> you@company.example R=send_via_smtp_relay T=smtp_relay_smtp H=smtp-relay.brevo.com … A=smtp_relay_login … 250 2.0.0 OK: queued`
- Authenticated client submission: `<= admin@example.com … A=dovecot_login:admin@example.com` (webmail) / `A=dovecot_plain:…` (phone)

## Useful commands
```bash
H=/usr/local/hestia/bin
sudo $H/v-list-users; sudo $H/v-list-web-domains webuser; sudo $H/v-list-mail-domains webuser; sudo $H/v-list-mail-accounts webuser example.com
sudo $H/v-list-sys-ips; sudo $H/v-list-firewall; sudo $H/v-list-firewall-ban
sudo $H/v-change-user-password webuser 'NEW'     # ! single quotes
sudo exim4 -bt -f admin@example.com someone@gmail.com     # which router/transport?
sudo exim4 -bp ; sudo exim4 -Mrm MSGID ; sudo exim4 -qff   # queue list / remove / retry all
```

## Rules of thumb (learned today)
- ! Never type secrets (Brevo key, passwords) into chat; type them into the Hestia panel
- ! Test a NEW SSH login before closing the old one, every time sshd/firewall changes
- ! Hestia manages iptables/fail2ban/nginx/exim configs — use `v-*` commands or the panel; hand-edits get overwritten on upgrade
- ! Keep exactly one SPF and one DMARC TXT
- Admin IP (`198.51.100.20`) is a shared company IP; phone IP changes → firewall rules need updates
- Brevo SMTP keys expire after 1 year (2027-10) and after 90 days idle
- Order of fixing mail: DNS → port forwards → TLS cert → relay → client settings
