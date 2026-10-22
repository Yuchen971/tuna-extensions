#!/usr/bin/env bash
# Builds the extension and installs it where Tuna loads development extensions.
# Pass --restart to restart Tuna: macOS cannot reload framework code in a running app.
set -euo pipefail

cd "$(dirname "$0")/.."
DEST_DIR="$HOME/Library/Application Support/Tuna/ExtensionsDev"

./scripts/build.sh
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/CardinalTuna.framework"
ditto build/CardinalTuna.framework "$DEST_DIR/CardinalTuna.framework"
echo "Installed to $DEST_DIR/CardinalTuna.framework"

if [[ "${1:-}" == "--restart" ]]; then
  osascript -e 'tell application "Tuna" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -x Tuna >/dev/null || break
    sleep 0.2
  done
  open -a Tuna
  echo "Restarted Tuna"
fi
