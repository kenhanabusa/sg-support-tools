# sg-support-tools

Support utilities for collecting reboot/debug evidence safely.

## Included tool
- `sg-collect-reboot-bundle.sh` (v0.1.1)

## v0.1.1 improvements
- Reboot evidence 강화: `uptime -s`, `who -b`, `last -x`, `journalctl --list-boots`
- IPMI evidence: `ipmitool mc info`, `ipmitool sel elist/list` (best-effort)
- Journal scope 강화: previous boot (`-b -1`) の `err` / `kern` を厚めに収集
- Time window support: `SG_SINCE_HOURS` (default: `12`)

## Usage
```bash
./sg-collect-reboot-bundle.sh
```

Optional output directory:
```bash
OUT_BASE=/path/to/output ./sg-collect-reboot-bundle.sh
```

Optional journal window:
```bash
SG_SINCE_HOURS=24 ./sg-collect-reboot-bundle.sh
```

## Output
- `sg_reboot_bundle_<hostname>_<timestamp>.tar.gz`

## Notes
- Read-only collection only
- No install/remove actions
- No destructive operations
