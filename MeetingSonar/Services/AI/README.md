# AI Processing Module

## Pipeline Overview

```
AudioFile (.m4a)
    │
    ▼
AIProviderConfigStore  Resolve selected ASR provider
    │
    ▼
ASRRuntime
    ├─► LocalWhisperCppASRRuntime
    │      └─ ASRAudioPreparationService creates temporary 16kHz mono WAV
    └─► CloudASRRuntimeAdapter
           └─ Existing cloud provider path, including provider-specific chunks
    │
    ▼
VersionManager.createTranscriptVersion
    │
    ▼
AIProcessingCoordinator   Orchestrates full pipeline (@MainActor)
    │
    ▼
AIProviderConfigStore  Resolve selected LLM provider
    │
    ▼
LLMRuntime
    └─► CloudLLMRuntimeAdapter
           └─ Existing cloud LLM provider path
    │
    ▼
VersionManager.createSummaryVersion
```

MeetingSonar keeps the original recording as AAC M4A. WAV files are temporary ASR artifacts under
`~/Library/Caches/MeetingSonar/ASRJobs/` and should be cleaned after processing. MeetingSonar does
not install or update whisper.cpp; it only invokes a user-configured external `whisper-cli`.

## Key Files

| File | Role | Isolation |
|------|------|-----------|
| `AIProviderConfigStore.swift` | Provider config storage and migration bridge from cloud configs | `Actor` |
| `AIProviderRuntimeFactory.swift` | Creates ASR/LLM runtimes from selected provider configs | value type |
| `Runtimes/ASRRuntime.swift` | ASR runtime protocol, context, progress, result aliases | protocol/types |
| `Runtimes/LLMRuntime.swift` | LLM runtime protocol, messages, result types | protocol/types |
| `Runtimes/CloudASRRuntimeAdapter.swift` | Adapter around existing cloud ASR path | runtime type |
| `Runtimes/CloudLLMRuntimeAdapter.swift` | Adapter around existing cloud LLM path | runtime type |
| `WhisperCpp/WhisperCppDetector.swift` | External whisper.cpp executable/model detection and validation | value type |
| `WhisperCpp/WhisperCppJSONParser.swift` | Parses whisper.cpp JSON output to `TranscriptionResult` | value type |
| `WhisperCpp/LocalWhisperCppASRRuntime.swift` | Local ASR runtime that invokes external `whisper-cli` | runtime type |
| `AIProcessingCoordinator.swift` | Pipeline orchestration, progress state | `@MainActor` |
| `ASRService.swift` | ASR engine lifecycle, model resolution | `@MainActor` |
| `ASREngineFactory.swift` | Engine creation + `OnlineASREngine` impl | `OnlineASREngine` is `Actor` |
| `CloudAIModelManager.swift` | Compatibility storage for existing cloud AI model configs and API keys | `Actor` |
| `PromptManager.swift` | Prompt template management | `Actor` |
| `Providers/ZhipuServiceProvider.swift` | Zhipu AI API calls | `Actor` |
| `Providers/AliyunServiceProvider.swift` | Aliyun API calls | `Actor` |
| `../AudioProcessing/ASRAudioPreparationService.swift` | Temporary WAV conversion/cache cleanup for ASR runtimes | class |
| `VersionManager.swift` | Canonical transcript/summary version persistence | `@MainActor` |
| `Recording/RecordingService.swift` | Recording lifecycle and auto-processing trigger | `@MainActor` |
| `StreamingSummaryViewModel.swift` | Streaming LLM UI flow, persisted through `VersionManager` | `@MainActor` |
| `LLMService.swift` | `SummaryResult` data type only; no legacy LLM actor | n/a |

## Processing Contract

`AIProcessingCoordinator.process(audioURL:meetingID:)` is the canonical batch full-pipeline entry point.
It returns `AIProcessingResult` on success and throws on failure. Callers must use `do/catch`; reaching
the line after `try await process(...)` is the success signal.

Metadata status is part of the contract:

- Full processing sets metadata to `.processing` at start.
- Full processing sets metadata to `.failed` and rethrows when ASR, LLM, or persistence fails.
- Full processing completion is persisted by `VersionManager.createSummaryVersion`, which appends
  the summary version and sets metadata to `.completed`.
- ASR-only processing sets metadata to `.processing`, then `.completed` on successful transcript
  persistence or `.failed` on failure.
- ASR runtime selection comes from `SettingsManager.selectedUnifiedASRId` and provider-backed
  `availableASRModels`.
- LLM runtime selection comes from `SettingsManager.selectedUnifiedLLMId` and provider-backed
  `availableLLMModels`.

Do not create a random meeting ID for a recorded file. Summary persistence must use the explicit
`meetingID` supplied by UI/recording metadata, or resolve an existing metadata record by filename.

## Removed Legacy Paths

The old prompt-era app delegate path (`showAIProcessingPrompt` / `startAIProcessing`) has been removed.
Recording completion is routed through `RecordingService` auto-processing settings and manual dashboard
actions. New code must not use `MetadataManager.updateAIStatus(...hasTranscript:hasSummary:)` for fresh
AI output; that legacy helper was removed. Use `VersionManager` so `hasTranscript` / `hasSummary`
remain derived from version arrays.

`LLMService` no longer provides an actor or placeholder `generateSummary` implementation. Batch LLM
generation is performed by `AIProcessingCoordinator` through a selected `LLMRuntime`.

The old local Whisper/Llama primary path remains removed. The v0.13 local scope is only an external
whisper.cpp ASR provider configured by the user.

## Actor Boundary: ASR Chunk Progress

The ASR progress callback chain crosses actor boundaries:

```
OnlineASREngine (Actor)
    │  calls chunkProgress?(.chunk(current, total))
    │  ↓ @Sendable closure
ASRService (@MainActor)
    │  wraps in Task { @MainActor in handler(stage) }
    │  ↓
AIProcessingCoordinator (@MainActor)
    │  updates @Published currentStage, progressDetail
    │  ↓ SwiftUI observation
DetailView
    │  shows progress only when processingMeetingID == current recordingID
```

Key type: `ASRChunkStage` enum (defined in `ASRService.swift`)
- `.splitting` — audio being split into chunks
- `.chunk(current:total:)` — processing chunk N of M
- `.chunkFailed(current:total:error:)` — chunk N failed, continuing

## Recording Scope Isolation

`AIProcessingCoordinator.processingMeetingID` scopes progress UI to a specific recording.
DetailView only shows progress indicators when `processingMeetingID == recordingID`.
When user switches recordings, `handleRecordingChanged()` resets streaming state.

## Streaming Summary

StreamingSummaryView uses `.task(id: streamingTriggerID)` + `.id(streamingTriggerID)` pattern
to force view re-creation when re-triggered. Incrementing `streamingTriggerID` resets all `@State`
and re-executes the `.task` closure.

Streaming summary persistence also goes through `VersionManager.createSummaryVersion`. A streaming
summary requires an existing meeting metadata record and a source transcript version; it must not
fall back to using `meetingID` as `sourceTranscriptId`.

## Cloud Provider Constraints

API-specific limits are codified in provider files as constants (e.g., `ZhipuASRLimits`).
Always check these before changing chunk sizes or request parameters.
