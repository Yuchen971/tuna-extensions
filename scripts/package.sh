#!/usr/bin/env bash
# Builds one extension and zips its framework for a GitHub release, e.g.
# dist/KeepAwakeTuna-0.1.0.zip. The version comes from the folder's Info.plist.
#
#   scripts/package.sh KeepAwake
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="${1:?usage: scripts/package.sh <extension folder, e.g. KeepAwake>}"
NAME="${NAME%/}"

./scripts/build.sh "$NAME"
PRODUCT="${NAME}Tuna"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NAME/Info.plist")"
ZIP="dist/$PRODUCT-$VERSION.zip"

mkdir -p dist
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "build/$PRODUCT.framework" "$ZIP"
echo "Packaged $ZIP"
