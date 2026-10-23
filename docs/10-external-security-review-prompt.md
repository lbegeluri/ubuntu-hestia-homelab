# Authorized external security review — *.example.com

## Authorization
I am the owner/administrator of example.com and all its subdomains, and of the
origin server behind it (public IP 203.0.113.10). I authorize this
assessment against my own infrastructure. Treat this as an authorized,
non-destructive external pentest of assets I own and control.

## Scope
- `example.com`, `www.example.com` (static site, Cloudflare-proxied)
- `wordpress.example.com` (WordPress, Cloudflare-proxied)
- `mail.example.com`, `webmail.example.com` (HestiaCP mail: Exim, Dovecot, Roundcube)
- `host.example.com` (Hestia panel, port 8083)
- Origin IP: 203.0.113.10 (do NOT scan unrelated IPs on the same 4G network/ISP)
- Ports in scope: 22 (SSH), 25/465/587 (SMTP), 80/443 (HTTP/S), 993 (IMAPS), 8083 (panel)

## Explicitly OUT of scope / forbidden
- No denial-of-service, no flooding, no brute-force beyond a handful of
  auth attempts (fail2ban will ban the source — that's fine, don't try to evade it)
- No sending spam/bulk mail through any discovered relay
- No actions beyond "whole box dies" (no destructive writes, no ransomware-style
  testing, no deleting/altering data)
- No scanning IPs/hosts outside the explicit scope list above
- No social engineering, no contacting the registrar/host/ISP
- No exploitation that would leave a persistent backdoor, user, or cron job

## Goal
Identify what an anonymous external attacker (no credentials) could discover
or achieve against this scope, and report findings with severity and remediation.
Mirror a standard external web/mail/SSH pentest checklist:

1. **Recon**
   - DNS enumeration (A/AAAA/MX/TXT/SRV/CNAME) for *.example.com via public
     resolvers only (no zone transfer attempts against authoritative NS unless
     explicitly testing AXFR refusal)
   - Passive subdomain enumeration (cert transparency logs, public sources) —
     no active brute-force subdomain guessing beyond a short common wordlist
   - Service/version fingerprinting on each open port (banner grabs only)
   - WHOIS / ASN info on 203.0.113.10 (informational only)

2. **Web (example.com, www, wordpress.example.com)**
   - TLS config: protocol versions, cipher suites, cert chain, HSTS
   - HTTP security headers (CSP, X-Frame-Options, X-Content-Type-Options, etc.)
   - Common path/file disclosure (.env, .git, backup files, phpinfo, etc.) —
     passive requests only, no fuzzing that generates heavy traffic
   - WordPress-specific: version disclosure, exposed wp-login.php /
     xmlrpc.php, user enumeration via REST API or author archives, readable
     wp-config backups, plugin/theme version fingerprinting via static assets
   - Note: traffic to example.com/www goes through Cloudflare — note what the
     proxy blocks vs. what reaches origin; do not attempt to bypass Cloudflare
     to hit the origin IP directly unless I ask for that separately

3. **Mail (mail.example.com, webmail.example.com)**
   - SMTP: open relay test (single harmless probe only — attempt to relay a
     test message to an external address I control, not a real third party),
     STARTTLS support, supported auth mechanisms, banner/version disclosure
   - SPF/DKIM/DMARC record review for business logic weaknesses
   - IMAPS: version/capability banner, supported auth mechanisms
   - Roundcube: version disclosure, login page hardening, default paths
     (e.g. /installer), any known CVEs for the detected version
   - A handful (not a flood) of invalid logins against one test account to
     confirm fail2ban/rate-limiting actually engages, then stop

4. **SSH (port 22) and panel (port 8083)**
   - Banner/version disclosure, supported auth methods (confirm password
     auth is actually disabled externally, confirm root login is refused)
   - Panel (8083): confirm it still requires auth from allowed IPs; if
     reachable from your test vantage point, only test login hardening
     (lockout/rate-limit), do not attempt credential guessing beyond a
     handful of attempts

5. **Report**
   - Findings ranked by severity (critical/high/medium/low/info)
   - For each: what was found, how it was found (command/request used),
     potential impact, and a concrete remediation step
   - Clearly separate "confirmed" vs "suspected" issues
   - Note anything that looks mis-scoped, unclear, or blocked by Cloudflare/
     firewall so I can decide whether to retest from a different vantage point

## Constraints on execution
- Run everything from this machine/session only, at a reasonable pace
  (no parallel aggressive scanning)
- Prefer passive/non-intrusive techniques first; ask me before anything that
  could cause a service restart, lockout, or ban your own source IP for long
- Stop and report back immediately if anything behaves unexpectedly
  (unhandled error pages, service crash, unusual response)
