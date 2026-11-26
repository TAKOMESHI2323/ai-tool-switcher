#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

swift build -c release

app_bundle="$project_root/build/AI Tool Switcher.app"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp ".build/release/AIToolSwitcher" "$app_bundle/Contents/MacOS/AIToolSwitcher"
cp "Resources/Info.plist" "$app_bundle/Contents/Info.plist"

echo "Built: $app_bundle"
