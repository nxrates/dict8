# Building Dict8

This guide provides detailed instructions for building Dict8 from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.4 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)

## Quick Start with Makefile (Recommended)

The easiest way to build Dict8 is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone the repository
git clone https://github.com/pde-rent/dict8.git
cd Dict8

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the Dict8 Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make run` - Launch the built Dict8 app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/Dict8-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/pde-rent/dict8.git
cd Dict8
make local
open ~/Downloads/Dict8.app
```

This builds Dict8 with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `Dict8.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

---

## Creating a DMG Installer

To build a DMG for distribution to colleagues:

```bash
# Apple Silicon only (Parakeet engine, faster build)
make dmg-no-whisper

# Universal (Intel + Apple Silicon, requires whisper.cpp)
make dmg
```

The DMG is output to `build/release/Dict8-<version>-arm64.dmg` (or `-universal.dmg`).

### Uploading a New Release to GitLab

After building the DMG, upload it to the company GitLab (`git.volcanly.me/du-v2/dict8`):

```bash
# Set your GitLab token (should already be in your .zshrc as GITLAB_TOKEN)
export GITLAB_TOKEN="your-token"

# 1. Upload the DMG to the Package Registry
VERSION="1.70"  # update to match the new version
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --upload-file "build/release/Dict8-${VERSION}-arm64.dmg" \
  "https://git.volcanly.me/api/v4/projects/du-v2%2Fdict8/packages/generic/dict8/${VERSION}/Dict8-${VERSION}-arm64.dmg"

# 2. Create a release (optional, for a clean release page)
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --request POST \
  --data "{
    \"tag_name\": \"v${VERSION}\",
    \"name\": \"Dict8 v${VERSION}\",
    \"ref\": \"main\",
    \"description\": \"## Dict8 v${VERSION}\n\nDownload the DMG below and drag Dict8 to Applications.\n\nFirst launch: right-click the app → Open.\",
    \"assets\": {
      \"links\": [{
        \"name\": \"Dict8-${VERSION}-arm64.dmg\",
        \"url\": \"https://git.volcanly.me/api/v4/projects/du-v2%2Fdict8/packages/generic/dict8/${VERSION}/Dict8-${VERSION}-arm64.dmg\",
        \"link_type\": \"package\"
      }]
    }
  }" \
  "https://git.volcanly.me/api/v4/projects/du-v2%2Fdict8/releases"
```

The download link for colleagues:
```
https://git.volcanly.me/du-v2/dict8/-/releases
```

### First Launch (Ad-hoc Signed Apps)

Since we don't have an Apple Developer ID, the app is ad-hoc signed. Recipients must **right-click → Open** on first launch to bypass Gatekeeper. After that, it opens normally.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building Dict8

1. Clone the Dict8 repository:
```bash
git clone https://github.com/pde-rent/dict8.git
cd Dict8
```

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked

For more help, please check the [issues](https://github.com/pde-rent/dict8/issues) section or create a new issue. 