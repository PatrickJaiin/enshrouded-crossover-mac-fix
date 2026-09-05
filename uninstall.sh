#!/bin/bash
# Restore CrossOver's original MoltenVK and remove the env vars added by install.sh.
# Usage: ./uninstall.sh [bottle-name]     (default: Steam)
set -euo pipefail
BOTTLE="${1:-Steam}"

CX_APP=""
for c in "/Applications/CrossOver.app" "$HOME/Applications/CrossOver.app"; do
  [ -d "$c" ] && CX_APP="$c" && break
done
[ -n "$CX_APP" ] || CX_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver'" 2>/dev/null | head -1)"
[ -n "$CX_APP" ] && [ -d "$CX_APP" ] || { echo "CrossOver.app not found" >&2; exit 1; }

TARGET="$CX_APP/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib"
if [ -f "$TARGET.cx-orig" ]; then
  mv -f "$TARGET.cx-orig" "$TARGET"
  echo "Restored original libMoltenVK.dylib"
else
  echo "No backup found at $TARGET.cx-orig; reinstall CrossOver to restore the stock library."
fi

CONF="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/cxbottle.conf"
if [ -f "$CONF" ]; then
  cp -p "$CONF" "$CONF.bak-uninstall-$(date +%Y%m%d%H%M%S)"
  TMP="$(mktemp)"
  grep -vE '^"(MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM|MVK_CONFIG_FAST_MATH_ENABLED|MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS|MVK_CONFIG_USE_MTLHEAP|DISABLE_VK_LAYER_VALVE_steam_overlay_1|DISABLE_VK_LAYER_VALVE_steam_fossilize_1)"' "$CONF" > "$TMP"
  mv -f "$TMP" "$CONF"
  echo "Removed env vars from bottle '$BOTTLE'"
fi
echo "Restart Steam inside CrossOver for the change to take effect."
