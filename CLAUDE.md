# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the project
xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build

# Run tests
xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS'

# Run specific test
xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/TestCaseName/testMethodName

# Clean build
xcodebuild clean -project MeetingSonar.xcodeproj -scheme MeetingSonar
```

## Project Overview

MeetingSonar is a macOS menu bar app for intelligent meeting recording. It captures system audio via ScreenCaptureKit (no virtual drivers needed), mixes with microphone input, and uses local/online AI models (Whisper for ASR, Qwen/Llama for LLM) to generate transcripts and summaries.

**Current Version**: v0.10.0 (Build 480+) - Cloud AI Architecture
**Minimum OS**: macOS 13.0 (Ventura)

## Architecture

### Layer Structure

```
┌─────────────────────────────────────────┐
│     UI Layer (SwiftUI + AppKit)         │
│  Menu Bar | Dashboard | Overlay | Prefs  │
└───────────────────┬─────────────────────┘
                    │
┌───────────────────┴─────────────────────┐
│        Services (Business Logic)        │
│  Recording | AI | Detection | Metadata  │
└───────────────────┬─────────────────────┘
                    │
┌───────────────────┴─────────────────────┐
│            Data Layer                   │
│  PathManager | Settings | ModelManager  │
└─────────────────────────────────────────┘
```

### Directory Structure (Updated 2026-02-06)

```
MeetingSonar/
├── Core/                          # Core components
│   ├── ServiceContainer.swift
│   └── MeetingSonarError.swift
├── Models/                        # Data models
│   ├── MeetingMeta.swift
│   ├── CloudAIModelConfig.swift   # Unified cloud AI configuration
│   └── TranscriptResult.swift     # ASR transcription result types
├── Services/
│   ├── Recording/                 # Audio recording services
│   │   ├── RecordingService.swift
│   │   ├── AudioCaptureService.swift
│   │   ├── MicrophoneService.swift
│   │   └── AudioMixerService.swift
│   ├── AudioProcessing/           # Audio processing utilities
│   │   ├── AudioSplitter.swift    # Audio file splitting
│   │   └── AudioEnergyAnalyzer.swift
│   ├── AI/                        # AI processing services
│   │   ├── AIProcessingCoordinator.swift
│   │   ├── ASRService.swift
│   │   ├── ASREngineFactory.swift
│   │   ├── CloudAIModelManager.swift
│   │   └── Providers/             # Cloud service providers (renamed from Engines/)
│   │       ├── CloudServiceProvider.swift
│   │       ├── AliyunServiceProvider.swift
│   │       └── ZhipuServiceProvider.swift
│   ├── Detection/
│   │   └── DetectionService.swift
│   └── MetadataManager.swift
├── Views/                         # SwiftUI views
└── Utilities/
    └── SettingsManager.swift
```

### Key Services (Singleton Pattern)

| Service | File | Responsibility |
|---------|------|----------------|
| `RecordingService` | `Services/Recording/RecordingService.swift` | Coordinates audio capture, mixing, and encoding. Manages state: idle → recording → paused |
| `AudioCaptureService` | `Services/Recording/AudioCaptureService.swift` | System audio capture via ScreenCaptureKit |
| `AudioMixerService` | `Services/Recording/AudioMixerService.swift` | Real-time mixing of system + mic audio (48kHz stereo, 20ms chunks) |
| `AIProcessingCoordinator` | `Services/AI/AIProcessingCoordinator.swift` | Pipeline: ASR → persist → LLM → persist. Cloud API orchestration |
| `DetectionService` | `Services/Detection/DetectionService.swift` | Smart meeting detection via window title + CoreAudio log monitoring |
| `MetadataManager` | `Services/MetadataManager.swift` | JSON-based metadata store (`~/Documents/MeetingSonar_Data/metadata.json`) |
| `CloudAIModelManager` | `Services/AI/CloudAIModelManager.swift` | Unified cloud AI model configuration (Actor for thread-safety) |
| `SettingsManager` | `Utilities/SettingsManager.swift` | UserDefaults + Security-Scoped Bookmarks for paths |

### Audio Processing Pipeline

```
User starts recording
  ↓
RecordingService.startRecording(trigger:)
  ↓
Parallel launch:
├─ AudioCaptureService.startCapture() → System audio (ScreenCaptureKit)
└─ MicrophoneService.startCapture()   → Mic input (AVFoundation)
  ↓
AudioMixerService receives both streams
  ↓ Real-time mixing (20ms intervals, vDSP acceleration)
  ↓
RecordingService.writeSampleBuffer()
  ↓ AVAssetWriter encoding
  ↓
Output: 48kHz stereo AAC M4A file
```

### AI Processing Pipeline (Cloud-Only Architecture)

```
Audio file (M4A)
  ↓
AudioSplitter.split()  // Convert M4A to WAV chunks
  ↓
ASRService (Cloud API via CloudServiceProvider)
  ├─ Get user-selected model from CloudAIModelManager
  ├─ Call cloud ASR API (Aliyun/Zhipu/OpenAI)
  ├─ Parse TranscriptionResult
  └─ Save JSON/TXT to Transcripts/Raw/
  ↓
MetadataManager.update()  // Persist immediately
  ↓
AIProcessingCoordinator (Cloud LLM via CloudServiceProvider)
  ├─ Get user-selected model from CloudAIModelManager
  ├─ Call cloud LLM API with transcript
  ├─ Smart chunking if exceeds context window
  ├─ Generate summary
  └─ Save Markdown to SmartNotes/
```

**Architecture change (v0.10.0)**: Removed local model support (Whisper.cpp, Llama.cpp, Python bridge).
Now uses **exclusively cloud AI APIs** for ASR and LLM processing.

### Data Organization

```
~/Documents/MeetingSonar_Data/
├── Recordings/           # {YYYYMMDD}-{HHmm}_{Source}.m4a
├── Transcripts/
│   ├── Raw/              # {BaseName}_transcript_{Timestamp}.json
│   └── Cleansed/         # (reserved)
├── SmartNotes/           # {BaseName}_summary_{Timestamp}.md
├── Models/               # Downloaded AI models (.gguf, .bin)
├── Logs/                 # User-visible logs
└── metadata.json         # Metadata index (sorted by startTime desc)
```

## Core Data Models

```swift
struct MeetingMeta {
    let id: UUID
    let filename: String
    var displayTitle: String?
    var source: String           // "Zoom", "Mic", etc.
    let startTime: Date
    var duration: TimeInterval
    var status: ProcessingStatus // recording/pending/processing/completed/failed
    var transcriptVersions: [TranscriptVersion]  // Supports multiple versions
    var summaryVersions: [SummaryVersion]        // Supports multiple versions
}

enum RecordingState {
    case idle
    case recording
    case paused  // Triggered by sleep/lock
}

enum RecordingTrigger {
    case manual           // User click
    case auto             // Detection triggered
    case smartReminder    // Notification triggered
}
```

## Key Design Decisions (TechArch.md)

| ADR | Decision |
|-----|----------|
| **ADR-001** | `CloudAIModelManager` (Actor) manages cloud AI configurations with Keychain storage for API keys |
| **ADR-002** | Map-Reduce for long transcripts: split → summarize chunks → merge summaries |
| **ADR-003** | Max recording duration: 2 hours (7200s). Prefer ScreenCaptureKit over virtual drivers |
| **ADR-004** | Cloud-only AI: use online OpenAI-compatible APIs (Aliyun, Zhipu, DeepSeek). Progressive processing (ASR → persist → LLM) |
| **ADR-006** | Removed local model support (Whisper.cpp, Llama.cpp, MLX) in v0.10.0 |
| **ADR-005** | Lightweight JSON metadata store instead of Core Data |

## Thread Safety

- **@MainActor classes**: `RecordingService`, `MetadataManager`, `SettingsManager`
- **Actor classes**: `CloudAIModelManager`, `PromptManager` (Actor for thread-safe operations)
- **⚠️ Known Issue**: `DetectionService` lacks `@MainActor` annotation but performs UI updates via notifications
- **Delegate pattern**: Audio pipeline uses delegates (AudioCaptureDelegate, AudioMixerDelegate)

## Communication Patterns

1. **Combine**: For reactive data flow (e.g., `MetadataManager.$recordings` → DashboardView)
2. **NotificationCenter**: For broadcast events (`.recordingDidStart`, `.recordingDidStop`, etc.)

## External Dependencies

**None** — v0.10.0+ uses pure cloud APIs, no local frameworks needed.

**Historical note**: Prior versions used `whisper.xcframework` and `llama.xcframework` for local inference.

## Coding Standards

Follow `.cursor/rules/swift-dev.mdc`:
- Use `actor` for shared resources, serial queues for thread boundaries
- Public APIs require `///` documentation with thread/actor semantics
- Functions > 60 lines should be split
- Use `// MARK: -` for code grouping
- Proper error handling: `do { try ... } catch { ... }`, NOT `try?`

## Feature IDs

When working on features, reference the ID from `Documents/FeatureTracking.md` (e.g., `F-10.0`, `F-5.0a`). Never delete Feature IDs from the tracking document.

## Critical Files for Understanding

- `MeetingSonar/MeetingSonarApp.swift` — App entry point, menu bar lifecycle
- `Services/Recording/RecordingService.swift` — Recording orchestration
- `Services/Recording/AudioMixerService.swift` — Real-time audio mixing engine
- `Services/AI/AIProcessingCoordinator.swift` — AI pipeline coordination (cloud APIs)
- `Services/AI/CloudAIModelManager.swift` — Unified cloud AI configuration
- `Services/MetadataManager.swift` — Metadata CRUD and migration
- `Models/MeetingMeta.swift` — Core data models
- `Models/CloudAIModelConfig.swift` — Cloud AI configuration model
- `Services/AI/PromptManager.swift` — Prompt template management (Actor)
