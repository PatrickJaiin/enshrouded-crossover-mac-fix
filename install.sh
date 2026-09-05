#!/bin/bash
# Enshrouded on macOS via CrossOver: swap CrossOver's bundled MoltenVK for a
# patched build (MoltenVK 1.4.3 main + SPIRV-Cross 83fa691c) and add tuning
# env vars to a CrossOver bottle.
#
# Usage:  ./install.sh [bottle-name]      (default bottle: Steam)
#
# What it does:
#   1. Finds CrossOver.app (/Applications or ~/Applications).
#   2. Backs up lib64/libMoltenVK.dylib as libMoltenVK.dylib.cx-orig (once).
#   3. Installs the patched libMoltenVK.dylib (downloaded from the GitHub
#      release unless a copy sits next to this script) and ad-hoc signs it.
#   4. Appends MoltenVK / Steam tuning env vars to the bottle's cxbottle.conf.
#
# Undo with ./uninstall.sh

set -euo pipefail

REPO="PatrickJaiin/enshrouded-crossover-mac-fix"
ASSET_URL="https://github.com/${REPO}/releases/latest/download/libMoltenVK.dylib"
SHA_URL="https://github.com/${REPO}/releases/latest/download/libMoltenVK.dylib.sha256"
BOTTLE="${1:-Steam}"
HERE="$(cd "$(dirname "$0")" && pwd)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- locate CrossOver -------------------------------------------------------
CX_APP=""
for c in "/Applications/CrossOver.app" "$HOME/Applications/CrossOver.app"; do
  [ -d "$c" ] && CX_APP="$c" && break
done
[ -n "$CX_APP" ] || CX_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver'" 2>/dev/null | head -1)"
[ -n "$CX_APP" ] && [ -d "$CX_APP" ] || die "CrossOver.app not found. Install CrossOver first."

CX_VER="$(defaults read "$CX_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
LIB_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib64"
TARGET="$LIB_DIR/libMoltenVK.dylib"
[ -f "$TARGET" ] || die "Expected $TARGET to exist. Is this a supported CrossOver version? (tested on 26.2)"
say "CrossOver $CX_VER at $CX_APP"

case "$CX_VER" in
  26.*|25.*|24.*) ;;
  *) warn "Only CrossOver 24-26 were considered. Continuing anyway." ;;
esac

# --- get the patched dylib ---------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ -f "$HERE/libMoltenVK.dylib" ]; then
  say "Using libMoltenVK.dylib next to the script"
  cp "$HERE/libMoltenVK.dylib" "$WORK/libMoltenVK.dylib"
  [ -f "$HERE/libMoltenVK.dylib.sha256" ] && cp "$HERE/libMoltenVK.dylib.sha256" "$WORK/"
else
  say "Downloading patched MoltenVK from GitHub release"
  curl -fsSL -o "$WORK/libMoltenVK.dylib" "$ASSET_URL" || die "download failed: $ASSET_URL"
  curl -fsSL -o "$WORK/libMoltenVK.dylib.sha256" "$SHA_URL" || warn "could not fetch checksum file"
fi

if [ -f "$WORK/libMoltenVK.dylib.sha256" ]; then
  EXPECTED="$(awk '{print $1}' "$WORK/libMoltenVK.dylib.sha256")"
  ACTUAL="$(shasum -a 256 "$WORK/libMoltenVK.dylib" | awk '{print $1}')"
  [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch (expected $EXPECTED, got $ACTUAL)"
  say "Checksum OK"
fi

file "$WORK/libMoltenVK.dylib" | grep -q "Mach-O" || die "downloaded file is not a Mach-O dylib"

# --- back up and install -----------------------------------------------------
if [ ! -f "$TARGET.cx-orig" ]; then
  say "Backing up original to libMoltenVK.dylib.cx-orig"
  cp -p "$TARGET" "$TARGET.cx-orig"
else
  say "Backup libMoltenVK.dylib.cx-orig already exists, keeping it"
fi

say "Installing patched libMoltenVK.dylib"
cp "$WORK/libMoltenVK.dylib" "$TARGET.new"
chmod 755 "$TARGET.new"
codesign --force --sign - "$TARGET.new" >/dev/null 2>&1 || warn "ad-hoc codesign failed (usually still loads)"
mv -f "$TARGET.new" "$TARGET"
xattr -c "$TARGET" 2>/dev/null || true

# --- bottle env vars -----------------------------------------------------------
CONF="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/cxbottle.conf"
if [ -f "$CONF" ]; then
  say "Adding tuning env vars to bottle '$BOTTLE'"
  cp -p "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"
  grep -q '^\[EnvironmentVariables\]' "$CONF" || printf '\n[EnvironmentVariables]\n' >> "$CONF"
  add_env() {
    if grep -q "^\"$1\"" "$CONF"; then
      echo "    $1 already set, leaving as is"
    else
      printf '"%s" = "%s"\n' "$1" "$2" >> "$CONF"
      echo "    $1 = $2"
    fi
  }
  # Keep the game's Vulkan pipeline cache under its 1 GiB limit (LZFSE).
  add_env MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM 1
  # Metal fast-math; the game's shaders otherwise force "precise" everywhere.
  add_env MVK_CONFIG_FAST_MATH_ENABLED 1
  # Don't block the render thread on every queue submit.
  add_env MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS 0
  add_env MVK_CONFIG_USE_MTLHEAP 1
  # Steam's Vulkan layers add overhead to every present; the overlay won't work.
  add_env DISABLE_VK_LAYER_VALVE_steam_overlay_1 1
  add_env DISABLE_VK_LAYER_VALVE_steam_fossilize_1 1
else
  warn "Bottle '$BOTTLE' not found at $CONF; skipped env vars. Re-run with the bottle name as argument."
fi

cat <<EOF

Done.

Next:
  1. Quit Steam inside CrossOver completely (Steam > Exit), then start it again
     from CrossOver so the new env vars apply.
  2. Launch Enshrouded. The first session rebuilds all shaders in the
     background and stutters; that's expected. Play for ~25 minutes or until
     the "Compiling shaders" indicator disappears so the cache gets saved.
  3. Sessions after that load the cache and run smoothly.

A CrossOver update will overwrite the patched library; just run this script again.
Undo: ./uninstall.sh $BOTTLE
EOF
