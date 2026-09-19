#!/usr/bin/env bash
#
# Installs and enables the systemd timer for the nightly Postgres backup.
# Run once, as root:  sudo bash /opt/hardenthis/backup/install-timer.sh
#
set -euo pipefail

DIR="/opt/hardenthis/backup"

install -m 644 "$DIR/hardenthis-backup.service" /etc/systemd/system/hardenthis-backup.service
install -m 644 "$DIR/hardenthis-backup.timer"   /etc/systemd/system/hardenthis-backup.timer

systemctl daemon-reload
systemctl enable --now hardenthis-backup.timer

echo "=== TIMER_INSTALLED ==="
systemctl list-timers hardenthis-backup.timer --no-pager
