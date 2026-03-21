# Dict8

Voice-to-text transcription and AI enhancement for macOS.

## Features

- **Speech to Text** -- Transcribe voice using Parakeet V3 (local, on-device via Apple Neural Engine), Whisper, or cloud providers
- **AI Enhancement** -- Automatically enhance transcriptions with customizable AI prompts
- **Per-App Configs** -- Different transcription/enhancement settings per application
- **Screen Context** -- OCR the active window to give AI context about what you're working on
- **Streaming** -- Real-time word-by-word transcription
- **History** -- Searchable transcription history with export

## Build

Requires macOS 14.0+ and Xcode 16.0+ on Apple Silicon.

```bash
# Clone and build (Parakeet-only, no whisper.cpp needed)
git clone https://github.com/pde-rent/dict8.git
cd dict8
./build-native.sh
```

Or use the Makefile:
```bash
make build-no-whisper
```

## Models

After launching, download Parakeet V3 from Settings -> Speech to Text. Models are cached at `~/.local/share/dict8/models/`.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This project is a fork of VoiceInk by [Beingpax](https://github.com/Beingpax).

### Core Technology
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Used for Parakeet model implementation

### Essential Dependencies
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-update framework
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - User-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) - Launch at login functionality
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) - Media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) - File compression and decompression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) - A modern macOS library for getting selected text
- [Swift Atomics](https://github.com/apple/swift-atomics) - Low-level atomic operations for thread-safe concurrent programming
