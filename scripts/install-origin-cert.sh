#!/usr/bin/env bash
# Install a Cloudflare Origin certificate on a HestiaCP web domain and force HTTPS.
#
#   WEB_USER=webuser DOMAIN=example.com CERT=/path/origin.pem KEY=/path/origin.key sudo -E bash install-origin-cert.sh
#
# Create the certificate in Cloudflare: SSL/TLS -> Origin Server -> Create Certificate
# (hostnames: example.com and *.example.com). The private key is shown only once: store it in a password manager.
# ! An Origin certificate is trusted only through Cloudflare's proxy. Never use it for mail names.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

WEB_USER=${WEB_USER:?set WEB_USER (the Hestia user that owns the domain)}
DOMAIN=${DOMAIN:?set DOMAIN (the web domain, e.g. example.com)}
CERT=${CERT:?set CERT (path to the Origin certificate PEM)}
KEY=${KEY:?set KEY (path to the Origin private key)}
H=/usr/local/hestia/bin
CA_URL=https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem

[ -f "$CERT" ] && [ -f "$KEY" ] || { echo "certificate or key file not found"; exit 1; }
$H/v-list-web-domain "$WEB_USER" "$DOMAIN" plain >/dev/null || { echo "web domain $DOMAIN does not exist for user $WEB_USER - add it in the panel first"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$CERT" "$T/$DOMAIN.crt"
cp "$KEY"  "$T/$DOMAIN.key"
# Hestia insists on a CA file; for an Origin certificate that is Cloudflare's Origin root
curl -fsSL "$CA_URL" -o "$T/$DOMAIN.ca"
grep -q 'BEGIN CERTIFICATE' "$T/$DOMAIN.ca" || { echo "could not download the Cloudflare Origin root certificate"; exit 1; }
chmod 644 "$T"/*

openssl x509 -in "$T/$DOMAIN.crt" -noout -subject -enddate

$H/v-add-web-domain-ssl "$WEB_USER" "$DOMAIN" "$T" yes
$H/v-add-web-domain-ssl-force "$WEB_USER" "$DOMAIN"

echo "== local test"
LAN=$(hostname -I | awk '{print $1}')       # Hestia's nginx listens on the LAN address, not 127.0.0.1
curl -skI --resolve "$DOMAIN:443:$LAN" "https://$DOMAIN" | head -3
echo "done. Cloudflare SSL/TLS mode must be Full (strict)."
