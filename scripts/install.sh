#!/usr/bin/env bash
# Builds extensions and installs them where Tuna loads development extensions.
#
#   scripts/install.sh KeepAwake --restart
#   scripts/install.sh all --restart
#
# Pass --restart to restart Tuna: macOS cannot reload framework code in a running app.
set -euo pipefail

cd "$(dirname "$0")/.."
DEST_DIR="$HOME/Library/Application Support/Tuna/ExtensionsDev"

names=()
restart=false
for arg in "$@"; do
  case "$arg" in
    --restart) restart=true ;;
    all) for plist in */Info.plist; do names+=("${plist%/Info.plist}"); done ;;
    *) names+=("${arg%/}") ;;
  esac
done
if [[ ${#names[@]} -eq 0 ]]; then
  echo "usage: scripts/install.sh <extension folder>... | all [--restart]" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
for name in "${names[@]}"; do
  ./scripts/build.sh "$name"
  framework="${name}Tuna.framework"
  rm -rf "$DEST_DIR/$framework"
  ditto "build/$framework" "$DEST_DIR/$framework"
  echo "Installed to $DEST_DIR/$framework"
done

if $restart; then
  osascript -e 'tell application "Tuna" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -x Tuna >/dev/null || break
    sleep 0.2
  done
  open -a Tuna
  echo "Restarted Tuna"
fi
