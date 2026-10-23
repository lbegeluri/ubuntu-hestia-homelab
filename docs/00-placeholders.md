# Placeholders used in this repository

Every identifying value was replaced with a neutral example. Swap them for your own when you follow the guides.

## Domain and hostnames

| Placeholder | Meaning |
|---|---|
| `example.com` | your domain |
| `host.example.com` | the server's own name (hostname, panel on port 8083) |
| `mail.example.com` | the mail server name (MX target, IMAP/SMTP, Let's Encrypt cert), DNS only |
| `webmail.example.com` | Roundcube webmail |
| `wordpress.example.com` | a WordPress site |
| `download.example.com` | a simple file-listing site |
| `corp-dns.example.local` | a corporate DNS server (appears once, in a note about cached negative DNS answers) |

## Addresses

| Placeholder | Meaning |
|---|---|
| `203.0.113.10` | the server's public IP (documentation range, RFC 5737) |
| `198.51.100.20` | the public IP of your admin workstation |
| `198.51.100.77` | the public IP of your phone on mobile data (it changes) |
| `198.51.100.88` | the public IP of a second admin machine |
| `192.168.1.50` | the server's LAN address (DHCP reservation) |
| `192.168.1.1` | the router / gateway |
| `192.168.1.0/24` | the LAN subnet |
| `10.0.0.5` | a corporate DNS server address |

## Accounts

| Placeholder | Meaning |
|---|---|
| `sysadmin` | the Linux sudo user you log in over SSH with |
| `webuser` | the Hestia user that owns the websites and the mail domain |
| `admin` | Hestia's panel administrator (the installer's default name) |
| `admin@example.com` | an example mailbox |
| `you@company.example` | an address at another provider, used only to test delivery |

## Third-party values

| Placeholder | Meaning |
|---|---|
| `xxxxxxxx@smtp-brevo.com` | your Brevo SMTP login (not secret, but account-specific) |
| `YOUR_BREVO_CODE` | the domain verification code Brevo shows you |

Passwords, SMTP keys and private keys never appear in these documents. Keep them in a password manager.
