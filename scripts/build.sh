#!/usr/bin/env bash
# Builds build/<Name>Tuna.framework, the bundle Tuna loads, for one extension folder.
#
#   scripts/build.sh KeepAwake
#
# TunaKit is compiled with Swift 6.4, so this needs a Swift 6.4+ toolchain. Set
# TOOLCHAIN to its identifier (default: the newest toolchain from swift.org).
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="${1:?usage: scripts/build.sh <extension folder, e.g. KeepAwake>}"
NAME="${NAME%/}"
[[ -f "$NAME/Info.plist" ]] || { echo "No extension folder named $NAME" >&2; exit 1; }

PRODUCT="${NAME}Tuna"
TOOLCHAIN="${TOOLCHAIN:-swift}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
FRAMEWORK="build/$PRODUCT.framework"

swift_cmd() {
  xcrun --toolchain "$TOOLCHAIN" swift "$@"
}

swift_cmd build -c release --arch arm64 --product "$PRODUCT"
bin_path="$(swift_cmd build -c release --arch arm64 --show-bin-path)"

rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK/Versions/A/Resources"
cp "$bin_path/lib$PRODUCT.dylib" "$FRAMEWORK/Versions/A/$PRODUCT"
install_name_tool -id "@rpath/$PRODUCT.framework/Versions/A/$PRODUCT" \
  "$FRAMEWORK/Versions/A/$PRODUCT"
cp "$NAME/Info.plist" "$FRAMEWORK/Versions/A/Resources/Info.plist"
ln -s A "$FRAMEWORK/Versions/Current"
ln -s "Versions/Current/$PRODUCT" "$FRAMEWORK/$PRODUCT"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"

# Tuna loads extensions without library validation, so an ad-hoc signature is enough.
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$FRAMEWORK"
echo "Built $FRAMEWORK"
