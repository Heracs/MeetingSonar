# AI Processing Module

## Pipeline Overview

```
AudioFile (.m4a)
    │
    ▼
AudioSplitter          Split into ≤30s WAV chunks (Zhipu API limit)
    │
    ▼
OnlineASREngine        Per-chunk cloud ASR (Actor)
    │                  Reports progress via ASRChunkStage callback
    ▼
AIProcessingCoordinator   Orchestrates full pipeline (@MainActor)
    │
    ├─► Persist transcript to disk
    │
    ▼
LLM Summary            Via CloudServiceProvider (streaming or batch)
    │
    └─► Persist summary to disk
```

## Key Files

| File | Role | Isolation |
|------|------|-----------|
| `AIProcessingCoordinator.swift` | Pipeline orchestration, progress state | `@MainActor` |
| `ASRService.swift` | ASR engine lifecycle, model resolution | `@MainActor` |
| `ASREngineFactory.swift` | Engine creation + `OnlineASREngine` impl | `OnlineASREngine` is `Actor` |
| `CloudAIModelManager.swift` | Cloud AI model config storage | `Actor` |
| `PromptManager.swift` | Prompt template management | `Actor` |
| `Providers/ZhipuServiceProvider.swift` | Zhipu AI API calls | `Actor` |
| `Providers/AliyunServiceProvider.swift` | Aliyun API calls | `Actor` |

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

## Cloud Provider Constraints

API-specific limits are codified in provider files as constants (e.g., `ZhipuASRLimits`).
Always check these before changing chunk sizes or request parameters.
