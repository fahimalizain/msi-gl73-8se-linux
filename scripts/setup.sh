#!/usr/bin/env bash
# setup.sh - Idempotent installer for MSI GL73 8SE fan control (isw + ec_sys).
# Usage: sudo ./setup.sh
set -euo pipefail

ISW_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/isw"

echo "==> Checking isw repo (clone it first: git clone https://github.com/YoyPa/isw.git isw)"
[ -x "$ISW_SRC/isw" ] || { echo "ERROR: $ISW_SRC/isw not found"; exit 1; }

echo "==> ec_sys kernel module config"
echo "options ec_sys write_support=1" > /etc/modprobe.d/ec_sys.conf
echo "ec_sys"                         > /etc/modules-load.d/ec_sys.conf

echo "==> Loading ec_sys with write support"
modprobe ec_sys write_support=1
grep -q ec_sys <(lsmod) || { echo "ERROR: ec_sys did not load (Secure Boot lockdown?)"; exit 1; }

echo "==> Installing isw"
install -m 0755 "$ISW_SRC/isw" /usr/bin/isw
install -m 0644 "$ISW_SRC/etc/isw.conf" /etc/isw.conf
install -m 0644 "$ISW_SRC/usr/lib/systemd/system/isw@.service" /etc/systemd/system/isw@.service

echo "==> Applying GL73 8SE profile (17C6EMS1) to the EC"
isw -cw 17C6EMS1

echo "==> Enabling boot service"
systemctl daemon-reload
systemctl enable --now isw@17C6EMS1

echo "==> Verifying"
isw -r 1

echo "Done. Fans should be audibly spinning up."