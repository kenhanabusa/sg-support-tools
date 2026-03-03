# sg-support-tools

Support utilities for collecting reboot/debug evidence safely.

## Included tool
- `sg-collect-reboot-bundle.sh` (v0.1.2)

## v0.1.2 focus
- Main goal: determine reboot cause immediately after reboot.
- Reboot certainty evidence: `uptime -s`, `who -b`, `last -x`, `journalctl --list-boots`.
- IPMI SEL improvements:
  - Save `ipmitool sel elist` / `ipmitool sel list`
  - Collect `ipmitool sel get <ID>` records into `77_ipmi_sel_get_records.txt`
  - Candidate IDs = tail N IDs from `sel list` + IDs containing `Unknown #0xff` in `sel elist`
- MCE/EDAC/RAS extraction from both previous/current boot kernel journal.
- rasdaemon evidence bundle (best-effort):
  - `ras-mc-ctl --summary`, `ras-mc-ctl --errors`
  - `journalctl -u rasdaemon -b` and `-b -1`
  - `/var/log/rasdaemon/` list and tail snapshot

## Usage
```bash
./sg-collect-reboot-bundle.sh
```

Recommended right after reboot (within 10 minutes):
```bash
SG_SINCE_MIN=180 SG_SEL_GET_N=40 ./sg-collect-reboot-bundle.sh
```

Optional output directory:
```bash
OUT_BASE=/path/to/output ./sg-collect-reboot-bundle.sh
```

Compatibility with existing variable:
```bash
SG_SINCE_HOURS=12 ./sg-collect-reboot-bundle.sh
```

## Output
- `sg_reboot_bundle_<hostname>_<timestamp>.tar.gz`

## rasdaemon pre-setup (recommended)
Install and enable rasdaemon beforehand on your host, then verify it is active before incidents.

Example commands (choose for your distro):
```bash
# Debian/Ubuntu
sudo apt-get install -y rasdaemon
sudo systemctl enable --now rasdaemon

# RHEL/Rocky/Alma
sudo dnf install -y rasdaemon
sudo systemctl enable --now rasdaemon

# SLES
sudo zypper install -y rasdaemon
sudo systemctl enable --now rasdaemon
```

Quick check:
```bash
systemctl status rasdaemon --no-pager
```

## Notes
- Read-only collection only
- No install/remove actions during bundle collection
- No destructive operations
