#!/usr/bin/env bash
# Install ClamAV and make Hestia offer/enable it for mail. Run: sudo bash ~/enable-clamav.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"
H=/usr/local/hestia/bin
U=${WEB_USER:-webuser}; DOMAIN=${DOMAIN:-example.com}
C=/usr/local/hestia/conf/hestia.conf

echo "== 1. RAM check"; free -h | sed -n 1,2p
echo "== 2. install ClamAV"
DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon || { echo "install failed"; exit 1; }

echo "== 3. virus database (can take a few minutes)"
systemctl stop clamav-freshclam 2>/dev/null
freshclam || echo "(freshclam reported an issue - check network; continuing)"
systemctl enable --now clamav-freshclam

echo "== 4. start clamd"
systemctl enable clamav-daemon
systemctl restart clamav-daemon
for i in $(seq 1 30); do [ -S /var/run/clamav/clamd.ctl ] && break; sleep 2; done
systemctl is-active clamav-daemon
ls -l /var/run/clamav/clamd.ctl 2>&1

echo "== 5. let Exim use the clamd socket"
usermod -aG clamav Debian-exim

echo "== 6. tell Hestia an antivirus exists"
grep -q '^ANTIVIRUS_SYSTEM' $C && sed -i "s/^ANTIVIRUS_SYSTEM=.*/ANTIVIRUS_SYSTEM='clamav-daemon'/" $C || echo "ANTIVIRUS_SYSTEM='clamav-daemon'" >> $C
grep '^ANTIVIRUS_SYSTEM' $C

echo "== 7. enable antivirus on the mail domain"
$H/v-add-mail-domain-antivirus "$U" "$DOMAIN" 2>&1 | head -3
systemctl restart exim4; sleep 2; systemctl is-active exim4

echo "== 8. state"
ls -l /etc/exim4/domains/$DOMAIN/antivirus 2>&1
$H/v-list-mail-domains "$U" plain | cut -f1-5
free -h | sed -n 1,2p
echo "done"
