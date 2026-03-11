#!/usr/bin/env bash
set -euo pipefail

# SG Reboot Watch installer (local-only)
# - Detect reboot by uptime -s change
# - On reboot: run sg-collect-reboot-bundle.sh (v0.1.2) and save tar.gz locally
# - systemd timer every 5 minutes
#
# Usage:
#   sudo ./sg-reboot-watch-install.sh
#
# Uninstall:
#   sudo ./sg-reboot-watch-install.sh --uninstall

UNINSTALL=0
if [ "${1:-}" = "--uninstall" ]; then UNINSTALL=1; fi

SG_DIR=/opt/sg/reboot-watch
BUNDLE_DIR=/var/tmp/sg-bundles
STATE_DIR=/var/lib/sg-reboot-watch
ENV_DIR=/etc/sg
ENV_FILE=/etc/sg/reboot-watch.env
LOG_FILE=/var/log/sg-reboot-watch.log
SERVICE=/etc/systemd/system/sg-reboot-watch.service
TIMER=/etc/systemd/system/sg-reboot-watch.timer

if [ "$UNINSTALL" = "1" ]; then
  systemctl disable --now sg-reboot-watch.timer 2>/dev/null || true
  rm -f "$SERVICE" "$TIMER"
  systemctl daemon-reload
  echo "[OK] removed systemd units"
  echo "[INFO] kept data:"
  echo "  - $LOG_FILE"
  echo "  - $BUNDLE_DIR"
  echo "  - $STATE_DIR"
  echo "  - $SG_DIR"
  echo "If you want to delete them too:"
  echo "  sudo rm -rf $LOG_FILE $BUNDLE_DIR $STATE_DIR $SG_DIR $ENV_DIR/reboot-watch.env"
  exit 0
fi

mkdir -p "$SG_DIR" "$BUNDLE_DIR" "$STATE_DIR" "$ENV_DIR"
chmod 700 "$STATE_DIR"
chmod 755 "$BUNDLE_DIR"

# Config (safe defaults)
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
# Minutes window for v0.1.2 collection after reboot detection
SG_SINCE_MIN=360
# How many SEL records to "sel get" (v0.1.2)
SG_SEL_GET_N=80
EOF
  chmod 600 "$ENV_FILE"
fi

# Ensure collector v0.1.2 exists (download if missing)
COLLECTOR="$SG_DIR/sg-collect-reboot-bundle.sh"
if [ ! -x "$COLLECTOR" ]; then
  echo "[INFO] collector not found; downloading v0.1.2..."
  curl -fsSL -o "$COLLECTOR" \
    "https://github.com/kenhanabusa/sg-support-tools/releases/download/v0.1.2/sg-collect-reboot-bundle.sh"
  chmod 755 "$COLLECTOR"
fi

# watcher
cat > "$SG_DIR/sg-reboot-watch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/sg/reboot-watch.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE" || true

STATE_DIR="/var/lib/sg-reboot-watch"
STATE_FILE="$STATE_DIR/boot.txt"
LOG_FILE="/var/log/sg-reboot-watch.log"
BUNDLE_DIR="/var/tmp/sg-bundles"
COLLECTOR="/opt/sg/reboot-watch/sg-collect-reboot-bundle.sh"

mkdir -p "$STATE_DIR" "$BUNDLE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE" || true

now(){ date -Is; }

boot="$(uptime -s 2>/dev/null || true)"
[ -n "$boot" ] || { echo "$(now) [WARN] uptime -s empty" >>"$LOG_FILE"; exit 0; }

if [ ! -f "$STATE_FILE" ]; then
  echo "$boot" > "$STATE_FILE"
  echo "$(now) [INIT] boot=$boot" >>"$LOG_FILE"
  exit 0
fi

prev="$(cat "$STATE_FILE" 2>/dev/null || true)"
if [ "$boot" != "$prev" ]; then
  echo "$boot" > "$STATE_FILE"
  echo "$(now) [ALERT] reboot detected prev=$prev now=$boot" >>"$LOG_FILE"

  run_ts="$(date +%Y%m%d_%H%M%S)"
  work="$BUNDLE_DIR/run_${run_ts}"
  mkdir -p "$work"
  cd "$work"

  SG_SINCE_MIN="${SG_SINCE_MIN:-360}" SG_SEL_GET_N="${SG_SEL_GET_N:-80}" "$COLLECTOR" >>"$LOG_FILE" 2>&1 || true

  tarball="$(ls -t sg_reboot_bundle_*.tar.gz 2>/dev/null | head -n 1 || true)"
  echo "$(now) [ALERT] bundle=$work/$tarball" >>"$LOG_FILE"
else
  echo "$(now) [OK] no reboot boot=$boot" >>"$LOG_FILE"
fi
EOF
chmod 755 "$SG_DIR/sg-reboot-watch.sh"

# systemd
cat > "$SERVICE" <<EOF
[Unit]
Description=SG Reboot Watch (detect reboot and save bundle locally)
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
ExecStart=$SG_DIR/sg-reboot-watch.sh
EOF

cat > "$TIMER" <<EOF
[Unit]
Description=Run SG Reboot Watch every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now sg-reboot-watch.timer

echo "[OK] installed"
systemctl status --no-pager sg-reboot-watch.timer | sed -n '1,20p'
echo
echo "[INFO] log: $LOG_FILE"
echo "[INFO] bundles: $BUNDLE_DIR"
