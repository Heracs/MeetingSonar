//
//  SampleData.swift
//  MeetingSonarTests
//
//  Test fixtures for unit tests.
//

import Foundation
@testable import MeetingSonar

/// Test data fixtures for unit tests
enum SampleData {

    // MARK: - MeetingMeta Samples

    static func createMeetingMeta(
        id: UUID = UUID(),
        filename: String = "20240121-1400_Test.m4a",
        title: String? = nil,
        source: String = "Test",
        startTime: Date = Date(),
        duration: TimeInterval = 60.0,
        status: MeetingMeta.ProcessingStatus = .pending
    ) -> MeetingMeta {
        return MeetingMeta(
            id: id,
            filename: filename,
            title: title,
            source: source,
            startTime: startTime,
            duration: duration,
            status: status
        )
    }

    static var sampleMeetingMeta: MeetingMeta {
        let date = Date(timeIntervalSince1970: 1705856400) // 2024-01-21 14:00:00
        return MeetingMeta(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            filename: "20240121-1400_ZoomMeeting.m4a",
            title: "Weekly Team Standup",
            source: "Zoom",
            startTime: date,
            duration: 1800.0, // 30 minutes
            status: .completed
        )
    }

    static var sampleMeetingMetaWithTranscript: MeetingMeta {
        var meta = sampleMeetingMeta
        meta.transcriptVersions = [
            TranscriptVersion(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                versionNumber: 1,
                timestamp: Date(timeIntervalSince1970: 1705858200),
                modelInfo: ModelVersionInfo(
                    modelId: "whisper-large-v3",
                    displayName: "Whisper-large-v3",
                    provider: "OpenAI"
                ),
                promptInfo: PromptVersionInfo(
                    promptId: "default-asr",
                    promptName: "Default ASR",
                    contentPreview: "Transcribe the following audio...",
                    category: .asr
                ),
                filePath: "Transcripts/Raw/12345678-1234-1234-1234-123456789abc.json"
            )
        ]
        return meta
    }

    static var sampleMeetingMetaWithSummary: MeetingMeta {
        var meta = sampleMeetingMetaWithTranscript
        meta.summaryVersions = [
            SummaryVersion(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                versionNumber: 1,
                timestamp: Date(timeIntervalSince1970: 1705858300),
                modelInfo: ModelVersionInfo(
                    modelId: "llama-3.1-8b",
                    displayName: "Llama-3.1-8B",
                    provider: "Local"
                ),
                promptInfo: PromptVersionInfo(
                    promptId: "default-summary",
                    promptName: "Default Summary",
                    contentPreview: "Summarize the following meeting transcript...",
                    category: .llm
                ),
                filePath: "SmartNotes/12345678-1234-1234-1234-123456789abc.md",
                sourceTranscriptId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                sourceTranscriptVersionNumber: 1
            )
        ]
        return meta
    }

    static var legacyMeetingMetaJSON: String {
        return """
        {
            "id": "12345678-1234-1234-1234-123456789abc",
            "filename": "20240121-1400_ZoomMeeting.m4a",
            "source": "Zoom",
            "startTime": 1705856400,
            "duration": 1800.0,
            "status": "completed",
            "hasTranscript": true,
            "hasSummary": true
        }
        """
    }

    // MARK: - Transcript Samples

    static var sampleTranscriptJSON: String {
        return """
        {
            "language": "zh",
            "segments": [
                {
                    "id": 0,
                    "start": 0.0,
                    "end": 2.5,
                    "text": "大家好，欢迎参加今天的会议。"
                },
                {
                    "id": 1,
                    "start": 2.5,
                    "end": 5.0,
                    "text": "我们今天讨论项目进展。"
                }
            ]
        }
        """
    }

    // MARK: - Path Samples

    static var testRootURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSonar_Tests")
            .appendingPathComponent(UUID().uuidString)
    }

    static var testRecordingURL: URL {
        testRootURL
            .appendingPathComponent("Recordings")
            .appendingPathComponent("20240121-1400_Test.m4a")
    }

    // MARK: - Date Samples

    static var sampleDate: Date {
        Date(timeIntervalSince1970: 1705856400) // 2024-01-21 14:00:00 UTC
    }

    static var sampleDateString: String {
        "2024-01-21T14:00:00Z"
    }

    // MARK: - Audio Format Samples

    static var supportedFormats: [AudioFormat] {
        [.m4a, .mp3]
    }

    static var supportedQualities: [AudioQuality] {
        [.low, .medium, .high]
    }

    // MARK: - Recording State Samples

    static var recordingStates: [RecordingState] {
        [.idle, .recording, .paused]
    }

    static var processingStatuses: [MeetingMeta.ProcessingStatus] {
        [.recording, .pending, .processing, .completed, .failed]
    }
}
