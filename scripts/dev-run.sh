#!/bin/zsh
# Dev loop: build → sign with stable Developer ID → install to /Applications → launch via `open`.
# Usage: scripts/dev-run.sh [--drag-test]
set -e
cd "$(dirname "$0")/.."

xcodebuild -project HoverBar.xcodeproj -scheme HoverBar -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD FAILED" && exit 1

APP=$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/HoverBar-"*/Build/Products/Debug/HoverBar.app | head -1)
./scripts/sign-dev.sh "$APP" >/dev/null
pkill -x HoverBar 2>/dev/null || true
sleep 1
rm -rf /Applications/HoverBar.app
cp -R "$APP" /Applications/HoverBar.app
rm -f "$HOME/Library/Logs/HoverBar.log"

if [[ "$1" == "--drag-test" ]]; then
  open -a /Applications/HoverBar.app --env HOVERBAR_DRAG_TEST=1
else
  open -a /Applications/HoverBar.app
fi
echo "launched from /Applications"
