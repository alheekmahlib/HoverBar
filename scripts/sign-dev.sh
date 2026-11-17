#!/bin/zsh
# Signs the locally built HoverBar.app with the stable Developer ID identity so
# Accessibility / Screen Recording grants survive rebuilds (ad-hoc signatures
# change on every build and lose their TCC grants).
set -e

APP="${1:-$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/HoverBar-"*/Build/Products/Debug/HoverBar.app 2>/dev/null | head -1)}"
IDENTITY="Developer ID Application: Hawazen Mahmood (Y9R8TJ3LS7)"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: scripts/sign-dev.sh [path-to-HoverBar.app]" >&2
  exit 1
fi

codesign --force --sign "$IDENTITY" "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier"
echo "signed: $APP"
