#!/bin/bash
# Cuts a new Transi release: bumps the version in Info.plist, builds and
# signs the app via build-app.sh, zips the built bundle, tags the commit,
# and publishes a GitHub release with the zip attached.
#
# Usage: scripts/release.sh <version>
#   <version> is a plain CFBundleShortVersionString, e.g. 1.2.0 (no "v" prefix
#   — the git tag and GitHub release get the "v" prefix added automatically).
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi
VERSION="$1"

# Always operate from the repo root, regardless of where this was invoked from.
cd "$(dirname "$0")/.."

# --- 1. Verify the working tree is clean ------------------------------------
# This script commits a version bump; starting from a dirty tree would sweep
# unrelated changes into that commit, so confirm before proceeding.
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: working tree is not clean:"
    git status --short
    read -r -p "Continue anyway? [y/N] " REPLY
    case "$REPLY" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

PLIST="Resources/Info.plist"

# --- 2. Bump CFBundleShortVersionString and CFBundleVersion in Info.plist ---
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEW_BUILD=$((CURRENT_BUILD + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
echo "Bumped $PLIST -> CFBundleShortVersionString=$VERSION, CFBundleVersion=$NEW_BUILD"

# --- 3. Build, sign (with the local "Transi Dev" identity), and install ----
./scripts/build-app.sh release

# --- 4. Zip the built app as the GitHub release asset -----------------------
# dist/ is a scratch output directory for release artifacts, separate from
# build.noindex/ (the app bundle build-app.sh produces and installs from).
DIST_DIR="dist"
mkdir -p "$DIST_DIR"
ZIP_NAME="Transi-${VERSION}-Apple-Silicon.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -ck --keepParent build.noindex/Transi.app "$ZIP_PATH"
echo "Created $ZIP_PATH"

# --- 5. Commit the version bump and tag the release -------------------------
git add "$PLIST"
git commit -m "Release $VERSION"
git tag "v$VERSION"
echo "Committed the version bump and tagged v$VERSION"

# --- 6. Push, then publish the GitHub release with the zip attached ----------
# The tag must be on GitHub before `gh release create` will attach to it, so
# the push comes first. Cutting a release means pushing it (owner's rule:
# "push" = push and release).
git push origin main "v$VERSION"

gh release create "v$VERSION" "$ZIP_PATH" \
    --title "Transi $VERSION" \
    --notes "Release $VERSION."

RELEASE_URL=$(gh release view "v$VERSION" --json url --jq .url)
echo "Published: $RELEASE_URL"
