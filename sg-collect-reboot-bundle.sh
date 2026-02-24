#!/usr/bin/env bash
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_BASE="${OUT_BASE:-$PWD}"
WORK_DIR="$(mktemp -d -p "${TMPDIR:-/tmp}" sg_reboot_bundle_${HOST}_${TS}_XXXXXX)"
BUNDLE_DIR="${WORK_DIR}/sg_reboot_bundle_${HOST}_${TS}"
mkdir -p "$BUNDLE_DIR"

run_cmd() {
  local name="$1"; shift
  {
    echo "# cmd: $*"
    "$@"
  } >"${BUNDLE_DIR}/${name}.txt" 2>&1 || true
}

copy_file() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a -- "$src" "$dst" 2>/dev/null || true
  fi
}

# read-only diagnostics
run_cmd uname uname -a
run_cmd os_release cat /etc/os-release
run_cmd uptime uptime
run_cmd date date -Is
run_cmd lsblk lsblk -a -o NAME,SIZE,TYPE,MODEL,FSTYPE,MOUNTPOINTS
run_cmd mount mount
run_cmd df df -h
run_cmd free free -h
run_cmd lscpu lscpu
run_cmd cmdline cat /proc/cmdline
run_cmd dmesg_tail sh -lc 'dmesg | tail -n 300'
run_cmd journal_boot sh -lc 'journalctl -b -0 --no-pager -n 500'
run_cmd journal_prev sh -lc 'journalctl -b -1 --no-pager -n 500'
run_cmd systemctl_failed sh -lc 'systemctl --failed --no-pager || true'
run_cmd lsmod lsmod
run_cmd lspci sh -lc 'lspci -nn || true'

if command -v nvidia-smi >/dev/null 2>&1; then
  run_cmd nvidia_smi nvidia-smi
  run_cmd nvidia_smi_q sh -lc 'nvidia-smi --query-gpu=index,name,driver_version,pstate,temperature.gpu,power.draw,utilization.gpu,memory.total,memory.used --format=csv,noheader || true'
fi

# key config snapshots (copy only)
copy_file /etc/default/grub "${BUNDLE_DIR}/files/etc/default/grub"
copy_file /etc/fstab "${BUNDLE_DIR}/files/etc/fstab"
copy_file /etc/systemd/logind.conf "${BUNDLE_DIR}/files/etc/systemd/logind.conf"
copy_file /etc/modprobe.d/blacklist.conf "${BUNDLE_DIR}/files/etc/modprobe.d/blacklist.conf"
copy_file /etc/modprobe.d/nvidia.conf "${BUNDLE_DIR}/files/etc/modprobe.d/nvidia.conf"

cat > "${BUNDLE_DIR}/meta.txt" <<META
host=${HOST}
timestamp=${TS}
collector=sg-collect-reboot-bundle.sh
pwd=$(pwd)
user=$(id -un)
META

OUT_TAR="${OUT_BASE}/sg_reboot_bundle_${HOST}_${TS}.tar.gz"
tar -C "$WORK_DIR" -czf "$OUT_TAR" "$(basename "$BUNDLE_DIR")"

echo "[OK] bundle: $OUT_TAR"

rm -rf -- "$WORK_DIR"
