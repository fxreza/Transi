#!/bin/bash
# Build QTranslate.app from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/QTranslateMac"
APP="build/QTranslate.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/QTranslateMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon. Regenerate with: swift scripts/make-icon.swift
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warning: Resources/AppIcon.icns missing — run 'swift scripts/make-icon.swift'"
fi

# Sign with a stable local identity so TCC (Accessibility / Screen Recording)
# grants survive rebuilds. Ad-hoc signing (the fallback below) gets a new
# signature hash on every build, so macOS treats each rebuild as a different
# app and silently drops previously granted permissions. See README.md >
# "Permissions survive rebuilds" for the one-time setup of this identity.
SIGN_IDENTITY="${QTRANSLATE_SIGN_IDENTITY:-QTranslate Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with local identity: $SIGN_IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc (no '$SIGN_IDENTITY' identity found in keychain)."
    echo "Accessibility/Screen Recording permissions will reset on every rebuild"
    echo "until you create a stable identity — see README.md > Permissions."
fi

echo "Built $APP"

# Install into /Applications, replacing any previous copy, so the app you launch
# from Spotlight/Finder is always the one you just built. Skip with
# QTRANSLATE_NO_INSTALL=1 if you only want the local build/ copy.
INSTALLED="/Applications/QTranslate.app"
if [ "${QTRANSLATE_NO_INSTALL:-0}" = "1" ]; then
    echo "Skipped install (QTRANSLATE_NO_INSTALL=1)."
    echo "Run:  open $APP"
else
    # Only ever replace our own app — never clobber an unrelated bundle that
    # happens to share the name.
    if [ -e "$INSTALLED" ]; then
        EXISTING_ID=$(defaults read "$INSTALLED/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
        if [ "$EXISTING_ID" != "com.sam.qtranslate-mac" ]; then
            echo "Refusing to replace $INSTALLED — it is not QTranslate"
            echo "(bundle id: '${EXISTING_ID:-unknown}'). Remove it by hand first."
            exit 1
        fi
    fi

    # The running copy holds its executable open; quit it before swapping, and
    # bring it back afterwards if it was running.
    WAS_RUNNING=0
    if pgrep -f "$INSTALLED/Contents/MacOS/QTranslateMac" >/dev/null 2>&1; then
        WAS_RUNNING=1
        osascript -e 'tell application "QTranslate" to quit' >/dev/null 2>&1 || true
        pkill -f "$INSTALLED/Contents/MacOS/QTranslateMac" >/dev/null 2>&1 || true
        sleep 1
    fi

    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    echo "Installed $INSTALLED"

    if [ "$WAS_RUNNING" = "1" ]; then
        open "$INSTALLED"
        echo "Relaunched the running copy."
    else
        echo "Run:  open $INSTALLED"
    fi
fi

echo "Then grant Accessibility permission in System Settings > Privacy & Security."
