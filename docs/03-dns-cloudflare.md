
# example.com — DNS records (Cloudflare)

*Last modified: 2026-10-23*

Part of: [Architecture and inventory](01-architecture-and-inventory.md) · If public IP changes → [Public IP or router change](06-public-ip-or-router-change.md)

## Zone settings
- SSL/TLS mode: **Full (strict)** · Always Use HTTPS: on
- Origin CA certificate: hostnames `example.com`, `*.example.com`, RSA, 15 years, expires 2041-10-19
- ! Origin cert is trusted ONLY via Cloudflare proxy → never use it for mail (clients don't trust it)

## Records (state 2026-10-23, 15 records)
| Type | Name | Content | Proxy | Why |
|---|---|---|---|---|
| A | `example.com` | `203.0.113.10` | **Proxied** | website via Cloudflare |
| CNAME | `www` | `example.com` | **Proxied** | www |
| A | `host` | `203.0.113.10` | DNS only | server name, Hestia panel :8083 |
| A | `mail` | `203.0.113.10` | DNS only | MX target, IMAP/SMTP, LE cert |
| A | `webmail` | `203.0.113.10` | DNS only (may be Proxied after LE cert exists) | Roundcube |
| MX | `example.com` | `mail.example.com` prio 10 | – | receive mail |
| TXT | `example.com` | `v=spf1 a:mail.example.com include:spf.brevo.com ~all` | – | SPF: own server + Brevo |
| TXT | `example.com` | `brevo-code:YOUR_BREVO_CODE` | – | Brevo domain verification |
| TXT | `mail._domainkey` | `v=DKIM1; k=rsa; p=…` (410 chars, from Hestia: Mail → example.com → DNS icon) | – | DKIM for Exim signing |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com` | – | DMARC (monitor mode) — ONLY ONE record |
| CNAME | `brevo1._domainkey` | `b1.example-com.dkim.brevo.com` | DNS only | Brevo DKIM 1 |
| CNAME | `brevo2._domainkey` | `b2.example-com.dkim.brevo.com` | DNS only | Brevo DKIM 2 |
| CNAME | `bm` | `bm-example-com.brand.brevosend.com` | DNS only | Brevo branded link |
| CNAME | `r.bm` | `bm-example-com.r.brand.brevosend.com` | DNS only | Brevo redirect |
| CNAME | `img.bm` | `bm-example-com.img.brand.brevosend.com` | DNS only | Brevo image redirect |

## Added later (same day)
| Type | Name | Content | Proxy | Why |
|---|---|---|---|---|
| A or CNAME (verify in Cloudflare) | `wordpress` | `example.com` / `203.0.113.10` | **Proxied** (resolves to Cloudflare IPs `104.21.21.207`, `172.67.200.86`) | WordPress site `wordpress.example.com` (Hestia web domain under user `webuser`, Let's Encrypt cert, Quick Install App → WordPress creates its own DB) |

- Any new subdomain = Hestia **web domain** with the full name + a proxied Cloudflare record; the Origin cert covers `*.example.com`

## Cloudflare setup steps (from scratch)
1. Add site `example.com` → nameservers at the registrar → wait until Active
2. SSL/TLS → Overview → mode **Full (strict)**; Edge Certificates → **Always Use HTTPS** on
3. SSL/TLS → Origin Server → **Create Certificate**: RSA, hostnames `example.com` + `*.example.com`, 15 years, PEM → copy certificate AND private key (key shown once → password manager)
4. DNS → Records → Add record (table above); toggle the cloud: orange = Proxied, grey = DNS only
   - proxied: `example.com`, `www`, `wordpress` · everything else grey
5. Delete Cloudflare's automatic "no-mail" records: `TXT v=spf1 -all`, DMARC `p=reject` → replace with ours (table above)
6. Brevo records → [Brevo SMTP relay](04-brevo-smtp-relay.md)

## Rules to remember
- ! Brevo wizard default branded subdomain is `mail` → collides with our `A mail` → we chose `bm`
- ! Cloudflare auto-adds `v=spf1 -all` + DMARC `p=reject` for domains without mail → must be replaced (SPF above, DMARC p=none)
- Only ONE SPF TXT and ONE DMARC TXT
- A TXT value pasted into Cloudflare: select-all/copy from Hestia, never retype
- Cloudflare warns "origin IP exposed" because host/mail are DNS-only → expected (mail needs it)
- Later tighten DMARC: `p=none` → `quarantine` → `reject` after weeks of clean reports
- No PTR (reverse DNS) possible: 4G operator owns `203.0.113.10` → reason for the Brevo relay

## Check commands
```bash
dig +short MX example.com @1.1.1.1
dig +short TXT example.com @1.1.1.1
dig +short TXT mail._domainkey.example.com @1.1.1.1
dig +short TXT _dmarc.example.com @1.1.1.1
dig +short A mail.example.com @1.1.1.1
```
- On office PC: `nslookup NAME 1.1.1.1` — DC01 (`10.0.0.5`) caches NXDOMAIN ~30 min for new records
