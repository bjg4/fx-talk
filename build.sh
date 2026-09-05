#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="$project_dir/.build"
output_dir="$project_dir/dist"
cd "$project_dir"
swift test --scratch-path "$build_dir"
python3 device/generate_signals.py
python3 device/test_device.py
swift build -c release --scratch-path "$build_dir"
# Package outside synced folders, which can attach Finder metadata during signing.
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/fx-talk-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
bundle="$package_dir/FX Talk.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$output_dir"
cp "$build_dir/release/FXTalk" "$bundle/Contents/MacOS/FXTalk"
cp packaging/Info.plist "$bundle/Contents/Info.plist"
cp ThirdParty/Tingle-LICENSE.txt "$bundle/Contents/Resources/ThirdPartyLicenses.txt"
cp LICENSE "$bundle/Contents/Resources/FXTalk-LICENSE.txt"
cp NOTICE.md "$bundle/Contents/Resources/NOTICE.md"
swift packaging/MakeIcon.swift "$package_dir/AppIcon.iconset"
iconutil -c icns "$package_dir/AppIcon.iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --deep --timestamp=none --sign "${FX_TALK_SIGN_IDENTITY:--}" "$bundle"
codesign --verify --deep --strict "$bundle"
ditto --norsrc --noextattr "$bundle" "$output_dir/FX Talk.app"
ditto -c -k --norsrc --noextattr --keepParent "$bundle" "$output_dir/FX Talk.zip"
print "Built $output_dir/FX Talk.app and $output_dir/FX Talk.zip"
