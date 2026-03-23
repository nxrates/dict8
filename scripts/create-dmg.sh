#!/bin/bash
# Dict8 DMG Installer Creator
# Builds a universal (Intel + Apple Silicon) Release binary and packages it as a DMG.
#
# Usage:
#   ./scripts/create-dmg.sh                     # Ad-hoc signed (colleagues must right-click → Open)
#   ./scripts/create-dmg.sh --sign "Developer ID Application: Your Name (TEAMID)"
#                                                # Developer ID signed + notarized (opens without warning)
#   ./scripts/create-dmg.sh --no-whisper         # Build without whisper.cpp (Parakeet-only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DMG_STAGING="$BUILD_DIR/dmg-staging"
APP_NAME="Dict8"
SIGN_IDENTITY="-"
NOTARIZE=false
NO_WHISPER=false
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --app-password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        --no-whisper)
            NO_WHISPER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --sign IDENTITY     Code sign with Developer ID (default: ad-hoc)"
            echo "  --notarize          Notarize the DMG with Apple (requires --sign, --apple-id, --team-id, --app-password)"
            echo "  --apple-id EMAIL    Apple ID for notarization"
            echo "  --team-id ID        Team ID for notarization"
            echo "  --app-password PWD  App-specific password for notarization (or @keychain:LABEL)"
            echo "  --no-whisper        Build without whisper.cpp (Parakeet-only, arm64-only)"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                                           # Ad-hoc signed universal build"
            echo "  $0 --no-whisper                              # Parakeet-only arm64 build"
            echo "  $0 --sign 'Developer ID Application: ...'   # Properly signed build"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "======================================"
echo "  Dict8 DMG Installer Builder"
echo "======================================"
echo ""

# --- Prerequisites ---
echo "[1/6] Checking prerequisites..."
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found. Install Xcode."; exit 1; }
command -v hdiutil >/dev/null 2>&1 || { echo "Error: hdiutil not found."; exit 1; }
echo "  OK"
echo ""

# --- Extract version from project ---
VERSION=$(cd "$PROJECT_DIR" && xcodebuild -project Dict8.xcodeproj -scheme Dict8 -showBuildSettings 2>/dev/null \
    | grep "MARKETING_VERSION" | head -1 | awk '{print $NF}')
BUILD_NUMBER=$(cd "$PROJECT_DIR" && xcodebuild -project Dict8.xcodeproj -scheme Dict8 -showBuildSettings 2>/dev/null \
    | grep "CURRENT_PROJECT_VERSION" | head -1 | awk '{print $NF}')

if [ -z "$VERSION" ]; then
    VERSION="0.0"
fi
if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER="0"
fi

echo "[2/6] Version: $VERSION (build $BUILD_NUMBER)"
echo ""

# --- Clean & build ---
echo "[3/6] Building $APP_NAME (Release, universal)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ "$NO_WHISPER" = true ]; then
    echo "  Mode: Parakeet-only (arm64)"
    ARCHS="arm64"
    EXTRA_FLAGS="ONLY_ACTIVE_ARCH=YES"
else
    echo "  Mode: Universal (arm64 + x86_64)"
    ARCHS="arm64 x86_64"
    EXTRA_FLAGS=""

    # Ensure whisper framework is built
    DEPS_DIR="$HOME/Dict8-Dependencies"
    FRAMEWORK_PATH="$DEPS_DIR/whisper.cpp/build-apple/whisper.xcframework"
    if [ ! -d "$FRAMEWORK_PATH" ]; then
        echo "  Building whisper.xcframework first..."
        (cd "$PROJECT_DIR" && make setup)
    fi
fi

ENTITLEMENTS="$PROJECT_DIR/Dict8/Dict8.local.entitlements"

xcodebuild \
    -project "$PROJECT_DIR/Dict8.xcodeproj" \
    -scheme Dict8 \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -arch $ARCHS \
    $EXTRA_FLAGS \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    DSTROOT="$BUILD_DIR/dst" \
    INSTALL_PATH="/Applications" \
    clean build 2>&1 | tail -5

# Find the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -path "*/Release/*" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo ""
    echo "Error: Build failed — $APP_NAME.app not found."
    echo "Run with full output to debug:"
    echo "  xcodebuild -project Dict8.xcodeproj -scheme Dict8 -configuration Release ..."
    exit 1
fi

echo "  Built: $APP_PATH"
echo ""

# --- Verify universal binary (if applicable) ---
if [ "$NO_WHISPER" = false ]; then
    echo "[3b] Verifying universal binary..."
    MAIN_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
    ARCHS_IN_BINARY=$(lipo -info "$MAIN_BINARY" 2>/dev/null || echo "unknown")
    echo "  $ARCHS_IN_BINARY"
    echo ""
fi

# --- Re-sign the app bundle (ensures all nested frameworks are signed) ---
echo "[4/6] Code signing..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "  Signing: ad-hoc (colleagues will need to right-click → Open on first launch)"
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH"
else
    echo "  Signing: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        --timestamp \
        "$APP_PATH"
fi
echo "  Done"
echo ""

# --- Strip extended attributes ---
xattr -cr "$APP_PATH" 2>/dev/null || true

# --- Create DMG ---
echo "[5/6] Creating DMG..."

DMG_NAME="${APP_NAME}-${VERSION}-universal"
if [ "$NO_WHISPER" = true ]; then
    DMG_NAME="${APP_NAME}-${VERSION}-arm64"
fi
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
DMG_TEMP="$BUILD_DIR/${DMG_NAME}-temp.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app to staging
ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"

# Create Applications symlink for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Calculate DMG size (app size + 20MB padding)
APP_SIZE_KB=$(du -sk "$DMG_STAGING/$APP_NAME.app" | awk '{print $1}')
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))

# Create compressed read-only DMG directly from staging folder
rm -f "$DMG_PATH"
hdiutil create \
    -srcfolder "$DMG_STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# Sign the DMG itself (if using Developer ID)
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

echo "  Created: $DMG_PATH"
DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo "  Size: $DMG_SIZE"
echo ""

# --- Notarize (optional) ---
if [ "$NOTARIZE" = true ]; then
    echo "[6/6] Notarizing with Apple..."
    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
        echo "  Error: Notarization requires --apple-id, --team-id, and --app-password"
        exit 1
    fi

    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    echo "  Notarized and stapled!"
else
    echo "[6/6] Skipping notarization (use --notarize for Gatekeeper-friendly distribution)"
fi

echo ""
echo "======================================"
echo "  BUILD COMPLETE"
echo "======================================"
echo ""
echo "  DMG: $DMG_PATH"
echo "  Version: $VERSION (build $BUILD_NUMBER)"
if [ "$NO_WHISPER" = true ]; then
    echo "  Arch: arm64 (Apple Silicon only)"
else
    echo "  Arch: Universal (Intel + Apple Silicon)"
fi
echo ""

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "  NOTE: This build is ad-hoc signed."
    echo "  Recipients must right-click the app → Open on first launch"
    echo "  to bypass Gatekeeper."
    echo ""
    echo "  For seamless distribution, sign with a Developer ID:"
    echo "    $0 --sign 'Developer ID Application: Your Name (TEAMID)'"
fi

echo ""
echo "  To install: open $DMG_PATH"
echo "              Then drag Dict8 to Applications."
