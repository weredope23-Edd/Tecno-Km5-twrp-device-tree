#!/usr/bin/env bash
set -euo pipefail
IMG="${1:-out/target/product/km5n/vendor_boot.img}"
[ -f "$IMG" ] || { echo "ERROR: vendor_boot image not found: $IMG" >&2; exit 1; }
SIZE=$(stat -c '%s' "$IMG")
MAGIC=$(dd if="$IMG" bs=1 count=8 2>/dev/null | tr -d '\0')
[ "$MAGIC" = "VNDRBOOT" ] || { echo "ERROR: bad vendor_boot magic: '$MAGIC'" >&2; exit 1; }
if [ "$SIZE" -gt 67108864 ]; then
  echo "ERROR: image is larger than stock vendor_boot partition: $SIZE > 67108864" >&2
  exit 1
fi
printf 'OK: vendor_boot magic=VNDRBOOT size=%s bytes (partition limit 67108864)\n' "$SIZE"
if command -v unpack_bootimg >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  unpack_bootimg --boot_img "$IMG" --out "$TMP" >/dev/null
  echo '--- parsed header ---'
  cat "$TMP/bootconfig" 2>/dev/null || true
  find "$TMP" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
else
  echo 'NOTE: unpack_bootimg not installed; only magic/size validation performed.'
fi
