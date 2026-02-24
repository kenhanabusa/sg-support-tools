# sg-support-tools

Support utilities for collecting reboot/debug evidence safely.

## Included tool
- `sg-collect-reboot-bundle.sh`

## What it does
- Collects read-only diagnostics (system/journal/hardware/GPU if available)
- Copies a small safe subset of config files
- Produces: `sg_reboot_bundle_<hostname>_<timestamp>.tar.gz`

## Usage
```bash
./sg-collect-reboot-bundle.sh
```

Optional output directory:
```bash
OUT_BASE=/path/to/output ./sg-collect-reboot-bundle.sh
```

## Notes
- No install/remove actions
- No destructive operations
- Read-only collection only
