#!/usr/bin/env bash
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d_%H%M%S)"
SINCE_MIN_DEFAULT=180
if [[ -n "${SG_SINCE_MIN:-}" ]]; then
  SINCE_MIN="${SG_SINCE_MIN}"
elif [[ -n "${SG_SINCE_HOURS:-}" ]]; then
  SINCE_MIN="$((SG_SINCE_HOURS * 60))"
else
  SINCE_MIN="${SINCE_MIN_DEFAULT}"
fi
SEL_GET_N="${SG_SEL_GET_N:-40}"
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

run_cmd_sh() {
  local name="$1"; shift
  {
    echo "# cmd: $*"
    bash -lc "$*"
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

# Core host context
run_cmd 00_uname uname -a
run_cmd 01_os_release cat /etc/os-release
run_cmd 02_date date -Is
run_cmd 03_uptime uptime
run_cmd 04_uptime_start uptime -s
run_cmd 05_who_b who -b
run_cmd 06_last_x last -x -n 120
run_cmd 07_journal_list_boots journalctl --list-boots --no-pager

# System state
run_cmd 10_lsblk lsblk -a -o NAME,SIZE,TYPE,MODEL,FSTYPE,MOUNTPOINTS
run_cmd 11_mount mount
run_cmd 12_df df -h
run_cmd 13_free free -h
run_cmd 14_lscpu lscpu
run_cmd 15_cmdline cat /proc/cmdline
run_cmd_sh 16_dmesg_tail 'dmesg | tail -n 800'
run_cmd 17_systemctl_failed systemctl --failed --no-pager
run_cmd 18_lsmod lsmod
run_cmd_sh 19_lspci 'lspci -nn || true'

# Journal ranges: current boot, previous boot, and recent window
run_cmd_sh 20_journal_boot_all 'journalctl -b 0 --no-pager -n 2000'
run_cmd_sh 21_journal_prev_all 'journalctl -b -1 --no-pager -n 4000'
run_cmd_sh 22_journal_prev_err 'journalctl -b -1 -p err --no-pager -n 2500'
run_cmd_sh 23_journal_prev_kern 'journalctl -b -1 -k --no-pager -n 3000'
run_cmd_sh 24_journal_since_window "journalctl --since '-${SINCE_MIN} min' --no-pager -n 3000"
run_cmd_sh 25_journal_since_kern "journalctl -k --since '-${SINCE_MIN} min' --no-pager -n 2000"

# MCE/EDAC/RAS extraction from current and previous boot kernel logs
run_cmd_sh 30_mce_edac_ras_prev "journalctl -k -b -1 --no-pager | egrep -i 'mce|hardware error|edac|ras|corrected|uncorrected'"
run_cmd_sh 31_mce_edac_ras_curr "journalctl -k -b --no-pager | egrep -i 'mce|hardware error|edac|ras|corrected|uncorrected'"

# GPU context
if command -v nvidia-smi >/dev/null 2>&1; then
  run_cmd 40_nvidia_smi nvidia-smi
  run_cmd_sh 41_nvidia_smi_q 'nvidia-smi --query-gpu=index,name,driver_version,pstate,temperature.gpu,power.draw,utilization.gpu,memory.total,memory.used --format=csv,noheader || true'
fi

# IPMI SEL / BMC (best-effort)
if command -v ipmitool >/dev/null 2>&1; then
  run_cmd_sh 70_ipmi_mc_info 'ipmitool mc info || true'
  run_cmd_sh 71_ipmi_sel_elist 'ipmitool sel elist || true'
  run_cmd_sh 72_ipmi_sel_list 'ipmitool sel list || true'

  SEL_GET_OUT="${BUNDLE_DIR}/77_ipmi_sel_get_records.txt"
  {
    echo '# cmd: ipmitool sel get <ID>'
    echo "# source: tail -n ${SEL_GET_N} IDs from sel list + IDs having Unknown #0xff in sel elist"
  } >"${SEL_GET_OUT}"

  list_ids="$(awk '{print $1}' "${BUNDLE_DIR}/72_ipmi_sel_list.txt" 2>/dev/null | sed 's/|$//' | grep -E '^[0-9A-Fa-fx]+$' | tail -n "${SEL_GET_N}" || true)"
  unknown_ids="$(grep -i 'Unknown #0xff' "${BUNDLE_DIR}/71_ipmi_sel_elist.txt" 2>/dev/null | awk -F'|' '{print $1}' | xargs -r -n1 echo | grep -E '^[0-9A-Fa-fx]+$' || true)"
  ids="$(printf '%s\n%s\n' "$list_ids" "$unknown_ids" | awk 'NF{if(!seen[$0]++) print $0}')"

  if [[ -n "$ids" ]]; then
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      {
        echo
        echo "===== ipmitool sel get ${id} ====="
        ipmitool sel get "$id" || true
      } >>"${SEL_GET_OUT}" 2>&1
    done <<<"$ids"
  else
    echo '# no candidate SEL IDs found' >>"${SEL_GET_OUT}"
  fi
fi

# rasdaemon evidence (best-effort)
if command -v ras-mc-ctl >/dev/null 2>&1; then
  run_cmd_sh 80_ras_mc_summary 'ras-mc-ctl --summary || true'
  run_cmd_sh 81_ras_mc_errors 'ras-mc-ctl --errors || true'
fi

if command -v journalctl >/dev/null 2>&1; then
  run_cmd_sh 82_rasdaemon_journal_curr 'journalctl -u rasdaemon -b --no-pager || true'
  run_cmd_sh 83_rasdaemon_journal_prev 'journalctl -u rasdaemon -b -1 --no-pager || true'
fi

if [[ -d /var/log/rasdaemon ]]; then
  run_cmd_sh 84_rasdaemon_logdir_list 'ls -la /var/log/rasdaemon || true'
  {
    echo '# tail -n 200 /var/log/rasdaemon/* (regular files only)'
    find /var/log/rasdaemon -maxdepth 1 -type f -print | while IFS= read -r f; do
      echo
      echo "===== ${f} (tail -n 200) ====="
      tail -n 200 "$f" || true
    done
  } >"${BUNDLE_DIR}/85_rasdaemon_logdir_tail.txt" 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  run_cmd_sh 86_rasdaemon_systemctl_status 'systemctl status rasdaemon --no-pager || true'
fi

# Key configs (copy-only)
copy_file /etc/default/grub "${BUNDLE_DIR}/files/etc/default/grub"
copy_file /etc/fstab "${BUNDLE_DIR}/files/etc/fstab"
copy_file /etc/systemd/logind.conf "${BUNDLE_DIR}/files/etc/systemd/logind.conf"
copy_file /etc/modprobe.d/blacklist.conf "${BUNDLE_DIR}/files/etc/modprobe.d/blacklist.conf"
copy_file /etc/modprobe.d/nvidia.conf "${BUNDLE_DIR}/files/etc/modprobe.d/nvidia.conf"

cat > "${BUNDLE_DIR}/meta.txt" <<META
host=${HOST}
timestamp=${TS}
collector=sg-collect-reboot-bundle.sh
version=0.1.2
since_min=${SINCE_MIN}
since_hours_compat=${SG_SINCE_HOURS:-}
sel_get_n=${SEL_GET_N}
pwd=$(pwd)
user=$(id -un)
META

OUT_TAR="${OUT_BASE}/sg_reboot_bundle_${HOST}_${TS}.tar.gz"
tar -C "$WORK_DIR" -czf "$OUT_TAR" "$(basename "$BUNDLE_DIR")"

echo "[OK] bundle: $OUT_TAR"

rm -rf -- "$WORK_DIR"
