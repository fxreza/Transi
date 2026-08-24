#!/bin/bash
# Build Transi.app from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Transi"
APP="build.noindex/Transi.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Transi"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# MIT requires the copyright notices of the bundled dependencies to travel with
# any distribution, so the .app carries them too — not just the repo.
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD-PARTY-LICENSES.md "$APP/Contents/Resources/THIRD-PARTY-LICENSES.md"

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
#
# TRANSI_DIST=1 signs ad-hoc instead. The "Transi Dev" certificate is
# self-signed and lives only in this Mac's keychain, so on any OTHER Mac its
# chain cannot be built and the signature reads as invalid — TCC then refuses to
# register the app, which is why Screen Recording / Accessibility grants do not
# stick there even when added by hand. An ad-hoc signature validates anywhere.
# The usual downside of ad-hoc (a new hash every build resets permissions) does
# not apply to a machine that only ever receives the finished bundle.
SIGN_IDENTITY="${TRANSI_SIGN_IDENTITY:-Transi Dev}"
if [ "${TRANSI_DIST:-0}" = "1" ]; then
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc for distribution to another Mac (TRANSI_DIST=1)."
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
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
# TRANSI_NO_INSTALL=1 if you only want the local build.noindex/ copy.
INSTALLED="/Applications/Transi.app"
if [ "${TRANSI_DIST:-0}" = "1" ]; then
    # A dist build is for another machine; installing it here would replace the
    # locally-signed copy and drop this Mac's own permission grants.
    echo "Skipped install (TRANSI_DIST=1). Copy $APP to the other Mac."
    echo "There: move it to /Applications, then run"
    echo "  xattr -dr com.apple.quarantine /Applications/Transi.app"
    exit 0
fi
if [ "${TRANSI_NO_INSTALL:-0}" = "1" ]; then
    echo "Skipped install (TRANSI_NO_INSTALL=1)."
    echo "Run:  open $APP"
else
    # Only ever replace our own app — never clobber an unrelated bundle that
    # happens to share the name.
    if [ -e "$INSTALLED" ]; then
        EXISTING_ID=$(defaults read "$INSTALLED/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
        if [ "$EXISTING_ID" != "com.fxreza.transi" ]; then
            echo "Refusing to replace $INSTALLED — it is not Transi"
            echo "(bundle id: '${EXISTING_ID:-unknown}'). Remove it by hand first."
            exit 1
        fi
    fi

    # The running copy holds its executable open; quit it before swapping, and
    # bring it back afterwards if it was running.
    WAS_RUNNING=0
    if pgrep -f "$INSTALLED/Contents/MacOS/Transi" >/dev/null 2>&1; then
        WAS_RUNNING=1
        osascript -e 'tell application "Transi" to quit' >/dev/null 2>&1 || true
        pkill -f "$INSTALLED/Contents/MacOS/Transi" >/dev/null 2>&1 || true
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
