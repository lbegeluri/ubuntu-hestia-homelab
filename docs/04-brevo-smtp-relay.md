
# Brevo SMTP relay for example.com — full setup

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md) · DNS: [DNS records (Cloudflare)](03-dns-cloudflare.md) · Rebuild: [Rebuild from scratch](02-rebuild-from-scratch.md) · Problems: [Troubleshooting](07-troubleshooting.md)

## Why a relay
- 4G public IP `203.0.113.10` has NO reverse DNS (PTR) and is a mobile range → Gmail/365 spam-folder or reject direct mail
- Receiving works directly (port 25 in); only OUTGOING goes via Brevo
- Operator allows outbound 587 (tested) → relay on `smtp-relay.brevo.com:587`
- Free tier ≈ 300 mails/day for the whole account (all mailboxes share it)

## Values
| Item | Value |
|---|---|
| SMTP server | `smtp-relay.brevo.com` |
| Port | `587` (STARTTLS) |
| Login | `xxxxxxxx@smtp-brevo.com` (identifier, not secret) |
| Key | SMTP key → password manager ONLY. Created 2026-10-23, 1-year expiry (→ 2027-10-23), also dies after 90 days idle |
| Authorized IP | `203.0.113.10` (Brevo → Security → Authorized IPs) |
| Where used | Hestia per-domain relay → `/etc/exim4/domains/example.com/smtp_relay.conf` |

## Step by step
### 1. Account
- brevo.com → sign up (free plan) · account may be reviewed before sending is active

### 2. Authenticate the domain
- Settings → **Senders, domains, IPs** → **Domains** → Add domain → `example.com`
- Wizard steps: Domain → **Branded subdomain** → Setup method → Records
- ! Branded subdomain: wizard default is `mail` → NO (collides with our `A mail` = MX/IMAP host) → choose `bm`
- Setup method: "Other" provider (manual) → copy records into Cloudflare (all **DNS only**):
  - `TXT @` → `brevo-code:YOUR_BREVO_CODE`
  - `CNAME brevo1._domainkey` → `b1.example-com.dkim.brevo.com`
  - `CNAME brevo2._domainkey` → `b2.example-com.dkim.brevo.com`
  - `TXT _dmarc` → `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com`
  - `CNAME bm` → `bm-example-com.brand.brevosend.com`
  - `CNAME r.bm` → `bm-example-com.r.brand.brevosend.com`
  - `CNAME img.bm` → `bm-example-com.img.brand.brevosend.com`
- Click **Verify records** → all green → **Authenticate domain**
- "Multiple DMARC records" error = cached old `_dmarc` or two records → keep exactly one, wait, verify again
- SPF is edited separately (Brevo does not require it in the wizard): `TXT @` → `v=spf1 a:mail.example.com include:spf.brevo.com ~all` (ONE SPF record only)

### 3. Authorized IP
- Brevo → **Security → Authorized IPs** → add `203.0.113.10`
- Without it: "Unauthorized IP addresses are blocked for your SMTP keys" and Exim log shows auth/connection failures
- ! Must be the SERVER's public IP, not the admin PC's `198.51.100.20` (Brevo may suggest your browser IP)

### 4. SMTP key
- **SMTP & API → SMTP** → note server/port/login → **Generate a new SMTP key**
  - Name `hestia-exim` · Variant **Standard** (64 chars) · Expiry 1 year
  - Shown ONCE → copy into password manager
- ! Never paste the key in chat/scripts; type it only in the Hestia panel
- Key exposed anywhere → delete it in Brevo, generate a new one, update Hestia

### 5. Hestia (panel, as user `webuser`)
- Mail → edit `example.com` → tick **SMTP Relay**
  - Host `smtp-relay.brevo.com` · Port `587` · User `xxxxxxxx@smtp-brevo.com` · Password = SMTP key
- Save → Hestia writes `/etc/exim4/domains/example.com/smtp_relay.conf` and Exim routes mail from `@example.com` through it
- ! Do not add your own authenticator to `exim4.conf.template` — Hestia's `smtp_relay_login` (public_name LOGIN) already exists → duplicate = Exim fails to start

### 6. Test
- Send from webmail/phone as `admin@example.com` to Gmail/365
- Server log must show:
```
=> someone@gmail.com R=send_via_smtp_relay T=smtp_relay_smtp H=smtp-relay.brevo.com [172.246.243.66] … CV=yes A=smtp_relay_login … C="250 2.0.0 OK: queued as <…>"
```
```bash
sudo grep -E 'smtp-relay|\*\*' /var/log/exim4/mainlog | tail
```
- Gmail → ⋮ → Show original → SPF / DKIM / DMARC = PASS
- Brevo dashboard → Transactional → Logs shows each accepted message

## Rotating the key (do this every year / after any exposure)
1. Brevo → SMTP & API → generate new key → copy
2. Panel → Mail → edit `example.com` → SMTP Relay → replace password → Save
3. Send a test mail (step 6)
4. Delete the OLD key in Brevo

## Common errors
| Error | Fix |
|---|---|
| `Unauthorized IP addresses are blocked` | add server public IP in Brevo Authorized IPs |
| `535 Authentication failed` in mainlog | wrong login/key, key deleted/expired (90 days idle) → new key → panel |
| Mail goes out but lands in Junk | new-domain reputation → Not junk, replies, normal volume; verify SPF/DKIM/DMARC pass |
| Wizard: branded record mismatch | records not added, or `mail` used instead of `bm`; proxy must be DNS only |
| Public IP changed | update Brevo Authorized IPs FIRST → [Public IP or router change](06-public-ip-or-router-change.md) |
