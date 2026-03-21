# Building Dict8 with Parakeet-Only (Native ARM64)

This guide explains how to build Dict8 using only Parakeet models via FluidAudio on Apple Silicon (M1/M2/M3/M4), without requiring whisper.cpp or Rosetta.

## ⚡ One-Command Build

For your M4 Mac (or any Apple Silicon), simply run:

```bash
git clone https://github.com/pde-rent/Dict8.git
cd Dict8
./build-native.sh
```

**That's it!** The script will:
- ✓ Verify you're on native ARM64
- ✓ Build for native ARM64 (NO Rosetta)
- ✓ Set Parakeet V3 as default model
- ✓ Build without code signing for local use
- ✓ Output the completed app

## Why This Works

- **FluidAudio** is a Swift package that uses CoreML models running on the Apple Neural Engine (ANE)
- **Parakeet TDT v3** is supported via FluidAudio
- **No whisper.cpp needed** - Parakeet uses a completely different inference engine
- **No Rosetta** - Everything runs natively on ARM64

## Prerequisites

- macOS 14.0 or later
- Xcode 16.0 or later (CLI only - no GUI needed)
- Apple Silicon (M1/M2/M3/M4)
- Git (for cloning)

## Build Options (Alternative Methods)

### Option 1: Using Native Build Script (Recommended - No Xcode GUI)

```bash
# Clone repository
git clone https://github.com/pde-rent/Dict8.git
cd Dict8

# Build using native ARM64 script
./build-native.sh
```

The script automatically:
- Detects your architecture (ARM64)
- Builds for native Apple Silicon (no Rosetta)
- Sets Parakeet V3 as default model
- Builds without code signing for local use

### Option 2: Using Makefile

```bash
# Clone repository
git clone https://github.com/pde-rent/Dict8.git
cd Dict8

# Build with Makefile (no whisper.cpp download)
make build-no-whisper
```

### Option 3: Using Xcode (GUI)

1. Clone repository:
   ```bash
    git clone https://github.com/pde-rent/Dict8.git
    cd Dict8
   ```

2. Open in Xcode:
   ```bash
    open Dict8.xcodeproj
   ```

3. Build and run (Product → Run, or Cmd+R)

4. In the app, download Parakeet models from settings

2. Remove whisper framework from project:
   ```bash
   # In Xcode:
   # 1. Open Dict8.xcodeproj
   # 2. Select Dict8 project → Target → Dict8
   # 3. Go to "Frameworks, Libraries, and Embedded Content"
   # 4. Remove whisper.xcframework
   # 5. Build → Clean Build Folder (Cmd+Shift+K)
   ```

3. Open in Xcode:
   ```bash
   open Dict8.xcodeproj
   ```

4. Build and run (Product → Run, or Cmd+R)

5. In the app, download Parakeet models from the settings

### Option 2: Command Line Build

```bash
# Clone the repo
git clone https://github.com/pde-rent/Dict8.git
cd Dict8

# Remove whisper dependency from project (need to edit .pbxproj)
# This step is easier in Xcode - use Option 1 for manual removal

# Build without whisper
xcodebuild -project Dict8.xcodeproj -scheme Dict8 \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Downloading Parakeet Models

Once the app is built:

1. Launch Dict8
2. Go to Settings → AI Models
3. Select "Parakeet" models:
   - **Parakeet V2**: English-only, highest recall
   - **Parakeet V3**: Multilingual (25 European languages)
4. Click download - models are ~500-700MB each
5. Models are stored in: `~/.local/share/dict8/models/`

## Parakeet Model Details

### Parakeet V2 (English-only)
- Model: `FluidInference/parakeet-tdt-0.6b-v2-coreml`
- Language: English only
- Recall: Highest (best for accuracy)
- Size: ~500MB

### Parakeet V3 (Multilingual)
- Model: `FluidInference/parakeet-tdt-0.6b-v3-coreml`
- Languages: English + 25 European languages
- Recall: Good (slightly lower than V2)
- Size: ~700MB

## Performance (M4 Pro)

- **Real-time Factor**: ~190x (1 hour of audio in ~19 seconds)
- **Backend**: CoreML on Apple Neural Engine (ANE)
- **Memory**: ~2GB RAM for model + ~100MB per minute of audio

## Troubleshooting

### "whisper.xcframework not found" error
You still have the whisper.framework reference in your project. Remove it in Xcode:
- Project → Target → Frameworks, Libraries, and Embedded Content
- Select whisper.xcframework → Remove

### Build fails with "Undefined symbols"
Check that you haven't accidentally included code that requires WhisperContext. Only use ParakeetModel.

### Models won't download
Check network connectivity or set a proxy:
```bash
export https_proxy=http://your-proxy:8080
open Dict8.app
```

## Comparison: whisper.cpp vs FluidAudio

| Feature | whisper.cpp | FluidAudio (Parakeet) |
|---------|-------------|----------------------|
| Architecture | C++/ggml | Swift/CoreML |
| Backend | CPU/GPU/MPS | ANE (Apple Neural Engine) |
| Rosetta required | No (but needs xcodebuild) | No (native ARM64) |
| Models supported | Whisper only | Parakeet only |
| Power efficiency | Medium | High (ANE-optimized) |
| Memory usage | Higher | Lower |

## Notes

- Dict8 supports both Whisper and Parakeet models, but they use separate inference engines
- You can have both installed, but if you only need Parakeet, you can remove the whisper.cpp dependency
- The app will automatically use the appropriate engine based on which model you select
