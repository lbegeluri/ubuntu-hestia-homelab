# Security hardening

What was done to the setup, why, and how to test it from outside. Placeholders are explained in [00-placeholders.md](00-placeholders.md).

## Principles

- Expose only what the service needs; restrict admin ports to known addresses
- Prefer key-only authentication and no direct root login
- Put attackers' blocking where the traffic actually arrives (Cloudflare for proxied sites)
- Test every restriction from an address that is **not** on the allow list
- Let the panel manage firewall, nginx and Exim configuration; hand edits get overwritten on upgrade

## SSH

File `/etc/ssh/sshd_config.d/00-hardening.conf` (the `00-` prefix makes it win over cloud-init's `50-` file):

```
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
```

- `webuser@127.0.0.1` is needed because Hestia's File Manager logs in over SFTP to the server itself; the `@127.0.0.1` part keeps that account unreachable from the internet
- Lock the root password: `sudo passwd -l root`
- Always open a **second** session and test a new login before closing the first
- Script: [`scripts/harden-ssh.sh`](../scripts/harden-ssh.sh)

## Firewall (Hestia iptables)

- Do not install ufw, fail2ban or Docker before Hestia: it brings its own iptables rules and fail2ban jails
- Remove the default "SSH from anywhere" and "panel from anywhere" rules after adding your own:

```bash
H=/usr/local/hestia/bin
sudo $H/v-add-firewall-rule ACCEPT 198.51.100.20 22 TCP SSH-admin
sudo $H/v-add-firewall-rule ACCEPT 192.168.1.0/24 22 TCP SSH-LAN
sudo $H/v-add-firewall-rule ACCEPT 198.51.100.20 8083 TCP Panel-admin
sudo $H/v-add-firewall-rule ACCEPT 192.168.1.0/24 8083 TCP Panel-LAN
sudo $H/v-list-firewall            # find the old 0.0.0.0/0 rules for 22 and 8083, then:
sudo $H/v-delete-firewall-rule RULE_ID
```

- Mail and web ports stay open to everyone: 25, 80, 443, 465, 587, 993
- The router forwards are public, so these Hestia rules are the only thing keeping SSH and the panel private
- Mobile and shared addresses change: keep the SSH tunnel ([08](08-hestia-panel-via-ssh-tunnel.md)) as a fallback

## fail2ban

- Hestia's jails: `ssh-iptables`, `dovecot-iptables`, `exim-iptables`, `hestia-iptables`, `phpmyadmin-auth`, `recidive`
- Add your own addresses to `ignoreip` in `/etc/fail2ban/jail.local` (`[DEFAULT]`): a few wrong panel passwords will otherwise ban you
- Unban: `sudo fail2ban-client set hestia-iptables unbanip ADDRESS`
- fail2ban cannot protect Cloudflare-proxied sites: iptables sees Cloudflare's addresses, not the visitor's

## WordPress

[`scripts/harden-wp.sh`](../scripts/harden-wp.sh) installs one must-use plugin and an nginx include:

```php
<?php
// REST API: hide /wp/v2/users from visitors who are not logged in
add_filter('rest_endpoints', function ($endpoints) {
    if (!is_user_logged_in()) {
        foreach (array_keys($endpoints) as $route) {
            if (preg_match('#^/wp/v2/users(/|$)#', $route)) {
                unset($endpoints[$route]);
            }
        }
    }
    return $endpoints;
});

// Author archives and /?author=N -> homepage (priority 0: before core's canonical redirect leaks the slug)
add_action('template_redirect', function () {
    if (is_author() || isset($_GET['author'])) {
        wp_safe_redirect(home_url('/'), 301);
        exit;
    }
}, 0);

remove_action('wp_head', 'wp_generator');
add_filter('the_generator', '__return_empty_string');
add_filter('xmlrpc_enabled', '__return_false');
```

```nginx
location = /readme.html  { return 404; }
location = /license.txt  { return 404; }
location = /xmlrpc.php   { return 403; }
```

Also: pick an admin username that is not `admin`, use a long generated password, turn on automatic updates.

## Cloudflare (free plan)

- SSL mode **Full (strict)**, Always Use HTTPS on
- WAF custom rules (the free plan allows five):
  - Block: `http.host eq "wordpress.example.com" and http.request.uri.path eq "/xmlrpc.php"`
  - Managed Challenge for the login page, except from your own address:
    `http.host eq "wordpress.example.com" and (http.request.uri.path eq "/wp-login.php" or starts_with(http.request.uri.path, "/wp-admin/")) and http.request.uri.path ne "/wp-admin/admin-ajax.php" and ip.src ne 198.51.100.20`
- Rate limiting on the free plan is one rule with a 10-second window, so a challenge rule is the better first line of defence
- Response headers (Rules → Transform Rules → Modify Response Header) on static sites:
  `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`
- **HSTS**: use `max-age=31536000` only. Leave out `includeSubDomains` and `preload` unless every subdomain has a valid certificate: a panel with a self-signed certificate becomes unreachable, and preload cannot be undone
- **CSP**: only on simple static pages; start with `Content-Security-Policy-Report-Only`; never on WordPress admin

## Mail authentication

- SPF with a soft fail while testing: `v=spf1 a:mail.example.com include:spf.brevo.com ~all`
- DKIM from Hestia plus the relay's own DKIM records
- DMARC progression: `p=none` while checking reports, then `p=quarantine; pct=100`, later `p=reject`
- Before tightening DMARC, send a test message and confirm SPF, DKIM and DMARC all show PASS in the recipient's "show original"
- Treat relay SMTP keys as secrets: rotate yearly and after any exposure ([04](04-brevo-smtp-relay.md))

## Testing from outside

An allow list can only be tested from an address that is not on it.

```bash
# from a phone on mobile data, or any network that is not allow-listed
for p in 22 25 80 443 465 587 993 8083; do nc -vz -w 5 203.0.113.10 $p; done
```

- 25, 80, 443, 465, 587, 993 should be open
- 22 and 8083 should time out
- Web checks: `curl -I https://example.com`, and the WordPress items: `/wp-json/wp/v2/users` should be 401 or 404, `/xmlrpc.php` 403, `/readme.html` 404
- A scoped review prompt is in [10](10-external-security-review-prompt.md)

## Residual risks

- Hestia, WordPress, plugins and the OS need regular updates (`sudo apt update && sudo apt upgrade`, WordPress auto-updates)
- Everything runs on one machine: a compromise of one service can reach the others
- The DNS-only names (`host`, `mail`, `webmail`) reveal the server's real address
- Backups are not automated here: copy the Origin certificate key, the DKIM key, the SSH host keys, the mailboxes and the site files off the machine
