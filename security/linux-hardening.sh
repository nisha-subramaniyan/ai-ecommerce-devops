#!/usr/bin/env bash
# linux-hardening.sh - basic, SAFE hardening for an Ubuntu/Debian server. Idempotent.
#   sudo ./security/linux-hardening.sh --dry-run     show what would change
#   sudo ./security/linux-hardening.sh               apply
# Does NOT disable password SSH login for you (that is done by Ansible once your key is installed) so you cannot lock yourself out.
set -euo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }
do_it() { if [ $DRY -eq 1 ]; then echo "[dry-run] $*"; else echo "[apply]   $*"; eval "$@"; fi; }

echo "1. Automatic security updates"
do_it "apt-get install -y unattended-upgrades"

echo "2. Firewall: deny incoming by default; allow SSH + web"
do_it "apt-get install -y ufw"
do_it "ufw default deny incoming && ufw default allow outgoing"
do_it "ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 8080/tcp"
do_it "ufw --force enable"

echo "3. Brute-force protection (fail2ban)"
do_it "apt-get install -y fail2ban && systemctl enable --now fail2ban"

echo "4. Kernel network hardening (sysctl)"
do_it "printf '%s\n' 'net.ipv4.conf.all.rp_filter=1' 'net.ipv4.tcp_syncookies=1' 'net.ipv4.conf.all.accept_redirects=0' 'net.ipv4.icmp_echo_ignore_broadcasts=1' > /etc/sysctl.d/99-hardening.conf && sysctl --system >/dev/null"

echo "5. Sensible permissions on sensitive files"
do_it "chmod 600 /etc/ssh/sshd_config 2>/dev/null || true"
do_it "chmod 640 /var/log/auth.log 2>/dev/null || true"

echo "6. Audit: users with empty passwords (should be none)"
awk -F: '($2=="") {print "  EMPTY PASSWORD: "$1}' /etc/shadow || true

echo "Done."
