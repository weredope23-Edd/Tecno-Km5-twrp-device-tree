#!/usr/bin/env bash
set -euo pipefail

# KM5n lightweight port helper.
# Purpose: keep stock vendor_boot v4 structure and replace only the recovery
# ramdisk component. The actual TWRP ramdisk must be supplied separately.
# This intentionally does NOT rebuild the Android/TWRP source tree.

usage() {
  echo "Usage: $0 <stock_vendor_boot.img> <twrp_recovery_ramdisk.cpio[.gz|.lz4|.lz4.gz]> <output_vendor_boot.img>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
STOCK=$1
TWRP_RAMDISK=$2
OUT=$3

command -v magiskboot >/dev/null || { echo 'ERROR: magiskboot not found'; exit 1; }
[[ -s "$STOCK" ]] || { echo "ERROR: stock image missing: $STOCK"; exit 1; }
[[ -s "$TWRP_RAMDISK" ]] || { echo "ERROR: TWRP ramdisk missing: $TWRP_RAMDISK"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$STOCK" "$WORK/boot.img"
cd "$WORK"

magiskboot unpack -h boot.img

# v4 vendor_boot contains vendor_ramdisk_recovery.cpio as a named component.
if [[ ! -e vendor_ramdisk_recovery.cpio ]]; then
  echo 'ERROR: vendor_boot v4 recovery component not found.' >&2
  echo 'Extracted files:' >&2
  ls -lah >&2
  exit 1
fi

# Preserve the stock component format where possible. magiskboot's unpacked
# recovery component is the safest canonical input for a repack operation.
cp "$TWRP_RAMDISK" vendor_ramdisk_recovery.cpio

# repack reconstructs the vendor_boot image while preserving the original
# kernel/header/vendor ramdisk components.
magiskboot repack boot.img
cp new-boot.img "$OUT"

SIZE=$(stat -c '%s' "$OUT")
if (( SIZE > 67108864 )); then
  echo "ERROR: output vendor_boot is $SIZE bytes (> 64 MiB)" >&2
  exit 1
fi

echo "OK: $OUT ($SIZE bytes)"
