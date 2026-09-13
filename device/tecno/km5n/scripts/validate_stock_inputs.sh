#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/recovery/root/lib/modules"
required=(modules.load.recovery modules.softdep clk-mt6768.ko mtk-scpsys-mt6768.ko mediatek-drm.ko novatek_nt36xxx.ko)
for f in "${required[@]}"; do test -e "$MOD/$f" || { echo "MISSING: $f"; exit 1; }; done
printf 'KM5n stock recovery inputs OK (%s kernel modules)\n' "$(find "$MOD" -maxdepth 1 -name '*.ko' | wc -l)"
