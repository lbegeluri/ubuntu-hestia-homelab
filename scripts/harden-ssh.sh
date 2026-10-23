#!/usr/bin/env bash
# Harden SSH on a fresh Ubuntu server: key-only login, no root login, AllowUsers, automatic security updates.
#
#   ADMIN_USER=sysadmin sudo -E bash harden-ssh.sh
#   ADMIN_USER=sysadmin EXTRA_ALLOW="webuser@127.0.0.1" sudo -E bash harden-ssh.sh
#
# ! Keep your current SSH session open and test a NEW login before closing it.
# ! This script does not install ufw or fail2ban: HestiaCP brings its own firewall and fail2ban.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

ADMIN_USER=${ADMIN_USER:?set ADMIN_USER to your Linux sudo user}
EXTRA_ALLOW=${EXTRA_ALLOW:-}          # extra AllowUsers entries, e.g. "webuser@127.0.0.1" for Hestia's File Manager
KEYS=/home/$ADMIN_USER/.ssh/authorized_keys

grep -q 'ssh-' "$KEYS" 2>/dev/null || { echo "no public key found in $KEYS - add one first or you will lock yourself out"; exit 1; }

echo "== 1. packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get -y -q install openssh-server unattended-upgrades

echo "== 2. sshd hardening (00- file wins over cloud-init's 50- file)"
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
AllowUsers $ADMIN_USER $EXTRA_ALLOW
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sshd -t
systemctl reload ssh
passwd -l root >/dev/null
echo "effective settings:"
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers|maxauthtries) '

echo "== 3. automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

echo "== done. Open a second terminal and run: ssh $ADMIN_USER@<server>   (keep this session until that works)"
[ -f /var/run/reboot-required ] && echo "!! reboot required (kernel update)"
exit 0
