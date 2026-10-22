#!/usr/bin/env bash
# Builds build/CardinalTuna.framework, the bundle Tuna loads.
#
# TunaKit is compiled with Swift 6.4, so this needs a Swift 6.4+ toolchain. Set
# TOOLCHAIN to its identifier (default: the newest toolchain from swift.org).
set -euo pipefail

cd "$(dirname "$0")/.."
TOOLCHAIN="${TOOLCHAIN:-swift}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
FRAMEWORK="build/CardinalTuna.framework"

swift_cmd() {
  xcrun --toolchain "$TOOLCHAIN" swift "$@"
}

swift_cmd build -c release --arch arm64 --product CardinalTuna
bin_path="$(swift_cmd build -c release --arch arm64 --show-bin-path)"

rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK/Versions/A/Resources"
cp "$bin_path/libCardinalTuna.dylib" "$FRAMEWORK/Versions/A/CardinalTuna"
install_name_tool -id @rpath/CardinalTuna.framework/Versions/A/CardinalTuna \
  "$FRAMEWORK/Versions/A/CardinalTuna"
cp Resources/Info.plist "$FRAMEWORK/Versions/A/Resources/Info.plist"
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/CardinalTuna "$FRAMEWORK/CardinalTuna"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"

# Tuna loads extensions without library validation, so an ad-hoc signature is enough.
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$FRAMEWORK"
echo "Built $FRAMEWORK"
