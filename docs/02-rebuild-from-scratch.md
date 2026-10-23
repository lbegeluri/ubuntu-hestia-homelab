
# example.com — rebuild from scratch

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md) · DNS: [DNS records (Cloudflare)](03-dns-cloudflare.md) · IP/router change: [Public IP or router change](06-public-ip-or-router-change.md) · Problems: [Troubleshooting](07-troubleshooting.md)

> Goal: PC died / disk wiped → get the same state back. ~2–3 hours. Values come from the hub note.

## 0. Gather before starting
- [ ] Cloudflare login · Brevo login · password manager
- [ ] Origin cert + PRIVATE KEY (or create new: Cloudflare → SSL/TLS → Origin Server → Create Certificate: `example.com`, `*.example.com`, RSA, 15y; ! key shown once)
- [ ] Brevo SMTP login `xxxxxxxx@smtp-brevo.com` + a (new) SMTP key
- [ ] SSH public keys: PC `you@company.example`, iPhone `termius-iphone` (Termius → Keychain → public key)
- [ ] Old backups if any: `dkim.pem`, mailbox dir, site files, `/etc/ssh/ssh_host_*`
- [ ] Router access (see hub for forwards) · public IP check ([Public IP or router change](06-public-ip-or-router-change.md) §0)
- [ ] Admin IPs: PC `198.51.100.20`, LAN `192.168.1.0/24`, phone IP

## 1. OS
- Ubuntu Server 24.04 LTS · user `sysadmin` · install OpenSSH server · whole disk (`/dev/nvme0n1`)
- Router: DHCP reservation for the new MAC → `192.168.1.50`
```bash
sudo apt update && sudo apt -y upgrade && sudo apt -y install openssh-server curl
sudo hostnamectl set-hostname host.example.com
sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1 host.example.com host" | sudo tee -a /etc/hosts
hostname -f        # → host.example.com
```

## 2. SSH keys + hardening (LAN first, keep a 2nd session open!)
```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# paste each public key on its own line:
nano ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
sudo tee /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
AllowUsers sysadmin webuser@127.0.0.1
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo passwd -l root
sudo apt -y install unattended-upgrades
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\nAPT::Periodic::AutocleanInterval "7";\n' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
```
- ! test a NEW ssh login with the key BEFORE closing the first session
- ! do NOT install ufw / fail2ban / docker — Hestia brings its own iptables + fail2ban

## 3. Router
- Forwards per hub note (22, 80, 443, 25, 465, 587, 993, 8083) → `192.168.1.50`
- Cloudflare DNS per [DNS records (Cloudflare)](03-dns-cloudflare.md) (A records → current public IP)

## 4. Hestia install
```bash
cd ~ && curl -O https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
sudo bash hst-install.sh --hostname host.example.com --email REAL_EMAIL \
  --apache no --phpfpm yes --multiphp no --vsftpd no --proftpd no --named no \
  --mysql yes --postgresql no --exim yes --dovecot yes --clamav no --spamassassin yes \
  --iptables yes --fail2ban yes --quota no --api no --interactive yes
```
- ! `REAL_EMAIL` — a placeholder leaves the admin contact wrong (fix: `v-change-user-contact admin REAL_EMAIL`)
- Installer prints panel URL + admin password → save → reboot
- If it dies with "Unable to connect to the Hestia APT repository": the check `wget https://apt.hestiacp.com` gets 404 (bug). Patch and run the Ubuntu script directly:
```bash
grep -n 'Unable to connect to the Hestia APT' -B2 ~/hst-install-ubuntu.sh   # find the wget line (was 483)
sed -i '483s|"https://$RHOST"|"https://$RHOST/pubkey.gpg"|' ~/hst-install-ubuntu.sh
sudo bash ~/hst-install-ubuntu.sh <same options as above>
```
- ! password with `!!` on the command line → bash history expansion → always single-quote passwords

## 5. After install
```bash
# nginx must wait for the LAN address (Hestia binds nginx to 192.168.1.50)
sudo mkdir -p /etc/systemd/system/nginx.service.d
printf '[Unit]\nAfter=network-online.target\nWants=network-online.target\n' | sudo tee /etc/systemd/system/nginx.service.d/wait-network.conf
sudo systemctl daemon-reload && sudo systemctl restart nginx

# Hestia firewall: lock SSH + panel to admin IPs, then remove the "any" rules
H=/usr/local/hestia/bin
sudo $H/v-add-firewall-rule ACCEPT 198.51.100.20 22 TCP SSH-PC
sudo $H/v-add-firewall-rule ACCEPT 192.168.1.0/24 22 TCP SSH-LAN
sudo $H/v-list-firewall                 # test NEW ssh login, then delete the 22/0.0.0.0/0 rule:
sudo $H/v-delete-firewall-rule RULE_ID
sudo $H/v-change-firewall-rule 2 ACCEPT 198.51.100.20 8083 TCP Panel-PC     # RULE_ID of 8083 any
sudo $H/v-add-firewall-rule ACCEPT 192.168.1.0/24 8083 TCP Panel-LAN
sudo nano /etc/fail2ban/jail.local      # [DEFAULT] ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24 198.51.100.20
sudo systemctl restart fail2ban
```
- iPhone: `sudo $H/v-add-firewall-rule ACCEPT PHONE_IP 22 TCP SSH-iphone` (mobile IP changes!)
- Panel: `https://host.example.com:8083` (or tunnel [Hestia panel via SSH tunnel](08-hestia-panel-via-ssh-tunnel.md))
- Optional Let's Encrypt for the panel name: `sudo $H/v-add-letsencrypt-host` (needs port 80 reachable, `host` A record)

## 6. Website
- Panel (as admin): Users → Add `webuser` (role User, strong password)
- Log in as `webuser` (NOT impersonating — File Manager is empty/errors when impersonated)
- Web → Add Web Domain `example.com` (alias www), no DNS, no mail
- Origin cert into Hestia (needs the Cloudflare Origin **root CA** as `.ca`):
```bash
H=/usr/local/hestia/bin; T=$(mktemp -d)
cp ORIGIN_CERT.pem $T/example.com.crt; cp ORIGIN_KEY.key $T/example.com.key
curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem -o $T/example.com.ca
chmod 644 $T/*
sudo $H/v-add-web-domain-ssl webuser example.com $T yes
sudo $H/v-add-web-domain-ssl-force webuser example.com
rm -rf $T
```
- Site files → `/home/webuser/web/example.com/public_html/` (File Manager as `webuser`, or scp to `~/upload` then `sudo cp -r … && sudo chown -R webuser:webuser …`)
- File Manager uses SFTP to `127.0.0.1` as `webuser` → needs `AllowUsers … webuser@127.0.0.1` (step 2) else "Unknown error"/empty
- Real visitor IPs: Hestia nginx already trusts Cloudflare headers — do NOT add another `real_ip_header` conf (duplicate → nginx fails)
- Test: `curl -I https://example.com` → 200 + `server: cloudflare`

## 7. Mail
- Panel as `webuser`: Mail → Add Mail Domain `example.com` — Roundcube, Spam Filter, Reject Spam, DKIM on
- Add account `sysadmin` (strong password)
- DNS: MX, DKIM (`mail._domainkey` value from Mail → DNS icon), SPF, DMARC, Brevo records → [DNS records (Cloudflare)](03-dns-cloudflare.md)
  - ! if restoring the old `dkim.pem` into `/etc/exim4/domains/example.com/` the old DKIM TXT stays valid; a fresh install makes a NEW key → update `mail._domainkey`
- TLS for mail + webmail (both names DNS only, port 80 open):
```bash
sudo /usr/local/hestia/bin/v-add-letsencrypt-domain webuser example.com '' yes
```
  - Panel form alternative: tick SSL + Let's Encrypt with the 3 certificate boxes EMPTY (leftover text → "SSL intermediate chain is not valid")
- Brevo: Senders, Domains → authenticate `example.com` (code + 2 DKIM + DMARC + branding on `bm`, not `mail`); Security → Authorized IPs → server public IP; SMTP & API → create SMTP key
- Outgoing relay: panel → Mail → edit `example.com` → tick **SMTP Relay**: host `smtp-relay.brevo.com`, port `587`, user `xxxxxxxx@smtp-brevo.com`, password = SMTP key (typed in the panel only)
  - ! do NOT hand-edit `exim4.conf.template` with your own authenticator: it already has `smtp_relay_login` (public_name LOGIN) → duplicate = Exim won't start
- Antivirus (optional, ~1 GB RAM):
```bash
sudo apt-get install -y clamav clamav-daemon
sudo systemctl stop clamav-freshclam; sudo freshclam; sudo systemctl enable --now clamav-freshclam clamav-daemon
sudo usermod -aG clamav Debian-exim
grep -q '^ANTIVIRUS_SYSTEM' /usr/local/hestia/conf/hestia.conf || echo "ANTIVIRUS_SYSTEM='clamav-daemon'" | sudo tee -a /usr/local/hestia/conf/hestia.conf
sudo /usr/local/hestia/bin/v-add-mail-domain-antivirus webuser example.com
sudo systemctl restart exim4
```

## 8. Clients
- iPhone Mail: **IMAP** tab · host `mail.example.com` · user = FULL address `admin@example.com` (in/out) · IMAP 993 SSL · SMTP **465 SSL** (587 only with STARTTLS = SSL off)
- Webmail: `https://webmail.example.com`
- Termius: host `203.0.113.10` / `host.example.com`, port 22, user `sysadmin`, key (not password)

## 9. Final tests (all must pass)
- [ ] `curl -I https://example.com` 200 via cloudflare · `https://webmail.example.com` valid cert
- [ ] from outside: `nc -vz PUBLICIP 25 465 587 993` open
- [ ] Gmail → `admin@example.com` arrives (`sudo tail /var/log/exim4/mainlog` → `<=` then `=> … local_delivery`)
- [ ] `admin@example.com` → Gmail: log `=> … R=send_via_smtp_relay … H=smtp-relay.brevo.com … 250 OK`; Gmail "Show original" → SPF/DKIM/DMARC PASS
- [ ] phone IMAP login in `/var/log/dovecot.log`
- [ ] `sudo sshd -T | grep -Ei 'permitroot|passwordauth|allowusers'` as in step 2
- [ ] `sudo /usr/local/hestia/bin/v-list-firewall` — no `0.0.0.0/0` for 22 or 8083
- [ ] set up backups (hub note) and copy Origin key + DKIM key off the box
