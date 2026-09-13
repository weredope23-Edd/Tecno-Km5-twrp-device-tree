#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-out/target/product/km5n}"
for f in "$OUT/vendor_boot.img" "$OUT/vendor_boot.img.sha256"; do
  [ -e "$f" ] || true
done
printf '%s\n' '=== KM5n TWRP output audit ==='
if [ -f "$OUT/vendor_boot.img" ]; then
  stat -c 'vendor_boot.img: %s bytes' "$OUT/vendor_boot.img"
  sha256sum "$OUT/vendor_boot.img"
else
  echo 'vendor_boot.img: MISSING'
fi
if [ -d "$OUT/recovery/root/lib/modules" ]; then
  echo "modules: $(find "$OUT/recovery/root/lib/modules" -maxdepth 1 -name '*.ko' | wc -l)"
fi
if [ -f "$OUT/recovery/root/system/etc/recovery.fstab" ]; then
  echo 'fstab: present'
  grep -E 'metadata|userdata|vendor /vendor' "$OUT/recovery/root/system/etc/recovery.fstab" || true
fi
if [ -f "$OUT/recovery/root/init.recovery.mt6768.rc" ]; then
  echo 'init.recovery.mt6768.rc: present'
fi
