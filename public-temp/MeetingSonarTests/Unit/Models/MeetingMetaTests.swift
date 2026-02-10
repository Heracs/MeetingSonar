//
//  MeetingMetaTests.swift
//  MeetingSonarTests
//
//  Unit tests for MeetingMeta model.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class MeetingMetaTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        // Arrange & Act
        let meta = MeetingMeta(
            filename: "test.m4a",
            source: "Test",
            startTime: Date(),
            duration: 60.0
        )

        // Assert
        XCTAssertNotNil(meta.id)
        XCTAssertEqual(meta.filename, "test.m4a")
        XCTAssertEqual(meta.source, "Test")
        XCTAssertEqual(meta.duration, 60.0)
        XCTAssertEqual(meta.status, .pending)
        XCTAssertEqual(meta.title, "test.m4a") // title defaults to filename
        XCTAssertFalse(meta.hasTranscript)
        XCTAssertFalse(meta.hasSummary)
    }

    func testInitializationWithAllParameters() {
        // Arrange
        let id = UUID()
        let date = Date()
        let title = "Custom Title"

        // Act
        let meta = MeetingMeta(
            id: id,
            filename: "test.m4a",
            title: title,
            source: "Zoom",
            startTime: date,
            duration: 120.0,
            status: .completed
        )

        // Assert
        XCTAssertEqual(meta.id, id)
        XCTAssertEqual(meta.filename, "test.m4a")
        XCTAssertEqual(meta.title, title)
        XCTAssertEqual(meta.displayTitle, title)
        XCTAssertEqual(meta.source, "Zoom")
        XCTAssertEqual(meta.startTime, date)
        XCTAssertEqual(meta.duration, 120.0)
        XCTAssertEqual(meta.status, .completed)
    }

    // MARK: - Computed Properties Tests

    func testTitleProperty() {
        // Arrange & Act
        var meta = MeetingMeta(
            filename: "20240121-1400_Zoom.m4a",
            source: "Zoom",
            startTime: Date(),
            duration: 60.0
        )

        // Assert - default title is filename
        XCTAssertEqual(meta.title, "20240121-1400_Zoom.m4a")

        // Act - set custom title
        meta.title = "My Meeting"

        // Assert - title should be custom value
        XCTAssertEqual(meta.title, "My Meeting")
        XCTAssertEqual(meta.displayTitle, "My Meeting")
    }

    func testHasTranscriptProperty() {
        // Arrange & Act
        var meta = SampleData.sampleMeetingMeta

        // Assert - no transcript initially
        XCTAssertFalse(meta.hasTranscript)

        // Act - add transcript
        meta.transcriptVersions = [
            TranscriptVersion(
                id: UUID(),
                versionNumber: 1,
                timestamp: Date(),
                modelInfo: ModelVersionInfo(modelId: "whisper", displayName: "Whisper", provider: "OpenAI"),
                promptInfo: PromptVersionInfo(promptId: "default-asr", promptName: "Default ASR", contentPreview: "", category: .asr),
                filePath: "transcript.json"
            )
        ]

        // Assert
        XCTAssertTrue(meta.hasTranscript)
    }

    func testHasSummaryProperty() {
        // Arrange & Act
        var meta = SampleData.sampleMeetingMeta

        // Assert - no summary initially
        XCTAssertFalse(meta.hasSummary)

        // Act - add summary
        meta.summaryVersions = [
            SummaryVersion(
                id: UUID(),
                versionNumber: 1,
                timestamp: Date(),
                modelInfo: ModelVersionInfo(modelId: "llama", displayName: "Llama", provider: "Local"),
                promptInfo: PromptVersionInfo(promptId: "default-summary", promptName: "Default Summary", contentPreview: "", category: .llm),
                filePath: "summary.md",
                sourceTranscriptId: UUID(),
                sourceTranscriptVersionNumber: 1
            )
        ]

        // Assert
        XCTAssertTrue(meta.hasSummary)
    }

    // MARK: - Codable Tests

    func testEncodingAndDecoding() {
        // Arrange
        let original = SampleData.sampleMeetingMetaWithSummary

        // Act - encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let encoderOutput: Result<Data, Error> = Result { try encoder.encode(original) }

        // Assert
        switch encoderOutput {
        case .success(let data):
            // Act - decode
            let decoder = JSONDecoder()
            let decoderOutput: Result<MeetingMeta, Error> = Result { try decoder.decode(MeetingMeta.self, from: data) }

            switch decoderOutput {
            case .success(let decoded):
                // Assert
                XCTAssertEqual(decoded.id, original.id)
                XCTAssertEqual(decoded.filename, original.filename)
                XCTAssertEqual(decoded.title, original.title)
                XCTAssertEqual(decoded.source, original.source)
                XCTAssertEqual(decoded.startTime, original.startTime)
                XCTAssertEqual(decoded.duration, original.duration)
                XCTAssertEqual(decoded.status, original.status)
                XCTAssertEqual(decoded.transcriptVersions.count, original.transcriptVersions.count)
                XCTAssertEqual(decoded.summaryVersions.count, original.summaryVersions.count)
            case .failure(let error):
                XCTFail("Failed to decode: \(error)")
            }
        case .failure(let error):
            XCTFail("Failed to encode: \(error)")
        }
    }

    func testLegacyDataMigration() {
        // Arrange - legacy JSON with hasTranscript and hasSummary
        let legacyJSON = SampleData.legacyMeetingMetaJSON.data(using: .utf8)!

        // Act - decode
        let decoder = JSONDecoder()
        let output: Result<MeetingMeta, Error> = Result { try decoder.decode(MeetingMeta.self, from: legacyJSON) }

        // Assert
        switch output {
        case .success(let meta):
            XCTAssertEqual(meta.id, UUID(uuidString: "12345678-1234-1234-1234-123456789abc"))
            XCTAssertEqual(meta.filename, "20240121-1400_ZoomMeeting.m4a")
            XCTAssertEqual(meta.source, "Zoom")
            XCTAssertEqual(meta.duration, 1800.0)
            XCTAssertEqual(meta.status, .completed)

            // Verify legacy migration created transcript and summary versions
            XCTAssertTrue(meta.hasTranscript, "Legacy hasTranscript should migrate to transcriptVersions")
            XCTAssertTrue(meta.hasSummary, "Legacy hasSummary should migrate to summaryVersions")
            XCTAssertEqual(meta.transcriptVersions.count, 1)
            XCTAssertEqual(meta.summaryVersions.count, 1)

            // Verify migrated data structure
            let transcript = meta.transcriptVersions.first
            XCTAssertNotNil(transcript)
            XCTAssertEqual(transcript?.modelInfo.displayName, "Whisper (Legacy)")

            let summary = meta.summaryVersions.first
            XCTAssertNotNil(summary)
            XCTAssertEqual(summary?.modelInfo.displayName, "Llama (Legacy)")
        case .failure(let error):
            XCTFail("Failed to decode legacy JSON: \(error)")
        }
    }

    // MARK: - Hashable Tests

    func testHashableConsistency() {
        // Arrange
        let meta1 = SampleData.sampleMeetingMeta
        let meta2 = SampleData.sampleMeetingMeta

        // Assert - same content should have same hash value
        XCTAssertEqual(meta1.hashValue, meta2.hashValue)
    }

    func testHashableWithDifferentContent() {
        // Arrange
        var meta1 = SampleData.sampleMeetingMeta
        var meta2 = SampleData.sampleMeetingMeta
        meta2.title = "Different Title"

        // Assert - different content should have different hash value
        XCTAssertNotEqual(meta1.hashValue, meta2.hashValue)
    }

    func testSetOperations() {
        // Arrange
        let meta1 = SampleData.sampleMeetingMeta
        let meta2 = SampleData.sampleMeetingMeta
        let meta3 = SampleData.createMeetingMeta(source: "Different")

        // Act
        let set: Set<MeetingMeta> = [meta1, meta2, meta3]

        // Assert - meta1 and meta2 are equal, so set should only have 2 elements
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - ProcessingStatus Enum Tests

    func testProcessingStatusAllCases() {
        // Arrange & Act
        let allCases: [MeetingMeta.ProcessingStatus] = [
            .recording,
            .pending,
            .processing,
            .completed,
            .failed
        ]

        // Assert - all cases should be codable
        for status in allCases {
            let encoder = JSONEncoder()
            let encoded = try? encoder.encode(status)
            XCTAssertNotNil(encoded, "Failed to encode \(status)")

            let decoder = JSONDecoder()
            let decoded = try? decoder.decode(MeetingMeta.ProcessingStatus.self, from: encoded!)
            XCTAssertEqual(decoded, status, "Failed to decode \(status)")
        }
    }

    // MARK: - Supporting Types Tests

    func testTranscriptVersionCodable() {
        // Arrange
        let version = TranscriptVersion(
            id: UUID(),
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(modelId: "whisper-large-v3", displayName: "Whisper-large-v3", provider: "OpenAI"),
            promptInfo: PromptVersionInfo(promptId: "default-asr", promptName: "Default ASR", contentPreview: "", category: .asr),
            filePath: "Transcripts/Raw/test.json"
        )

        // Act
        let encoder = JSONEncoder()
        let output: Result<TranscriptVersion, Error> = Result {
            let data = try encoder.encode(version)
            return try decoder().decode(TranscriptVersion.self, from: data)
        }

        // Assert
        switch output {
        case .success(let decoded):
            XCTAssertEqual(decoded.id, version.id)
            XCTAssertEqual(decoded.modelInfo.modelId, version.modelInfo.modelId)
            XCTAssertEqual(decoded.filePath, version.filePath)
        case .failure(let error):
            XCTFail("Codable failed: \(error)")
        }
    }

    func testSummaryVersionCodable() {
        // Arrange
        let version = SummaryVersion(
            id: UUID(),
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(modelId: "llama-3.1-8b", displayName: "Llama-3.1-8B", provider: "Local"),
            promptInfo: PromptVersionInfo(promptId: "default-summary", promptName: "Default Summary", contentPreview: "", category: .llm),
            filePath: "SmartNotes/test.md",
            sourceTranscriptId: UUID(),
            sourceTranscriptVersionNumber: 1
        )

        // Act
        let encoder = JSONEncoder()
        let output: Result<SummaryVersion, Error> = Result {
            let data = try encoder.encode(version)
            return try decoder().decode(SummaryVersion.self, from: data)
        }

        // Assert
        switch output {
        case .success(let decoded):
            XCTAssertEqual(decoded.id, version.id)
            XCTAssertEqual(decoded.modelInfo.modelId, version.modelInfo.modelId)
            XCTAssertEqual(decoded.filePath, version.filePath)
            XCTAssertEqual(decoded.sourceTranscriptId, version.sourceTranscriptId)
        case .failure(let error):
            XCTFail("Codable failed: \(error)")
        }
    }

    // MARK: - Edge Cases Tests

    func testZeroDuration() {
        // Arrange & Act
        let meta = MeetingMeta(
            filename: "test.m4a",
            source: "Test",
            startTime: Date(),
            duration: 0.0
        )

        // Assert
        XCTAssertEqual(meta.duration, 0.0)
    }

    func testEmptySource() {
        // Arrange & Act
        let meta = MeetingMeta(
            filename: "test.m4a",
            source: "",
            startTime: Date(),
            duration: 60.0
        )

        // Assert
        XCTAssertEqual(meta.source, "")
        XCTAssertEqual(meta.title, "test.m4a")
    }

    func testVeryLongTitle() {
        // Arrange
        let longTitle = String(repeating: "A", count: 1000)

        // Act
        let meta = MeetingMeta(
            filename: "test.m4a",
            title: longTitle,
            source: "Test",
            startTime: Date(),
            duration: 60.0
        )

        // Assert
        XCTAssertEqual(meta.title, longTitle)
        XCTAssertEqual(meta.displayTitle, longTitle)
    }

    // MARK: - Helper Methods

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
