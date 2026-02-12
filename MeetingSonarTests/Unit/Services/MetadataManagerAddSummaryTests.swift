//
//  MetadataManagerAddSummaryTests.swift
//  MeetingSonarTests
//
//  Swift Testing framework tests for MetadataManager.addSummaryVersion()
//  Tests: Concurrency, thread safety, error handling, edge cases
//

import Testing
import Foundation
@testable import MeetingSonar

/// Tests for MetadataManager.addSummaryVersion() - Critical Fix C2
@Suite("MetadataManager addSummaryVersion Tests")
@MainActor
struct MetadataManagerAddSummaryTests {

    // MARK: - Test Fixtures

    private nonisolated static func createTestMeeting() -> MeetingMeta {
        MeetingMeta(
            id: UUID(),
            filename: "20240121-1400_Test.m4a",
            title: "Test Meeting",
            source: "Zoom",
            startTime: Date(),
            duration: 1800.0,
            status: .completed
        )
    }

    private nonisolated static func createTestSummaryVersion(
        versionNumber: Int = 1,
        meetingID: UUID? = nil
    ) -> SummaryVersion {
        SummaryVersion(
            id: UUID(),
            versionNumber: versionNumber,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(
                modelId: "deepseek-chat",
                displayName: "DeepSeek Chat",
                provider: "DeepSeek"
            ),
            promptInfo: PromptVersionInfo(
                promptId: "default-summary",
                promptName: "Default Summary",
                contentPreview: "Summarize the meeting...",
                category: .llm
            ),
            filePath: "SmartNotes/test_summary.md",
            sourceTranscriptId: meetingID ?? UUID(),
            sourceTranscriptVersionNumber: 1
        )
    }

    // MARK: - Basic Functionality Tests

    @Test("addSummaryVersion adds version to existing meeting")
    func testAddSummaryVersionToExistingMeeting() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        let version = Self.createTestSummaryVersion(meetingID: meeting.id)
        await mockManager.addSummaryVersion(version, to: meeting.id)

        #expect(mockManager.recordings.first?.summaryVersions.count == 1)
        #expect(mockManager.recordings.first?.summaryVersions.first?.id == version.id)
    }

    @Test("addSummaryVersion handles non-existent meeting gracefully")
    func testAddSummaryVersionToNonExistentMeeting() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let nonExistentID = UUID()
        let version = Self.createTestSummaryVersion(meetingID: nonExistentID)

        // Should not crash
        await mockManager.addSummaryVersion(version, to: nonExistentID)

        #expect(mockManager.recordings.isEmpty)
    }

    @Test("addSummaryVersion appends multiple versions correctly")
    func testAddMultipleSummaryVersions() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Add first version
        let version1 = Self.createTestSummaryVersion(versionNumber: 1, meetingID: meeting.id)
        await mockManager.addSummaryVersion(version1, to: meeting.id)

        // Add second version
        let version2 = Self.createTestSummaryVersion(versionNumber: 2, meetingID: meeting.id)
        await mockManager.addSummaryVersion(version2, to: meeting.id)

        // Add third version
        let version3 = Self.createTestSummaryVersion(versionNumber: 3, meetingID: meeting.id)
        await mockManager.addSummaryVersion(version3, to: meeting.id)

        #expect(mockManager.recordings.first?.summaryVersions.count == 3)
        #expect(mockManager.recordings.first?.summaryVersions[0].versionNumber == 1)
        #expect(mockManager.recordings.first?.summaryVersions[1].versionNumber == 2)
        #expect(mockManager.recordings.first?.summaryVersions[2].versionNumber == 3)
    }

    // MARK: - Concurrency Tests

    @Test("Concurrent addSummaryVersion calls are thread-safe")
    func testConcurrentAddSummaryVersion() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Launch multiple concurrent add operations
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let version = Self.createTestSummaryVersion(
                        versionNumber: i,
                        meetingID: meeting.id
                    )
                    await mockManager.addSummaryVersion(version, to: meeting.id)
                }
            }
        }

        // All 10 versions should be added
        #expect(mockManager.recordings.first?.summaryVersions.count == 10)
    }

    @Test("Concurrent addSummaryVersion to different meetings")
    func testConcurrentAddToDifferentMeetings() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        // Create multiple meetings
        var meetings: [MeetingMeta] = []
        for i in 1...5 {
            let meeting = MeetingMeta(
                id: UUID(),
                filename: "20240121-1400_Meeting\(i).m4a",
                title: "Meeting \(i)",
                source: "Zoom",
                startTime: Date(),
                duration: 1800.0,
                status: .completed
            )
            meetings.append(meeting)
            await mockManager.add(meeting)
        }

        // Concurrently add versions to different meetings
        await withTaskGroup(of: Void.self) { group in
            for (index, meeting) in meetings.enumerated() {
                group.addTask {
                    for versionNum in 1...3 {
                        let version = Self.createTestSummaryVersion(
                            versionNumber: versionNum,
                            meetingID: meeting.id
                        )
                        await mockManager.addSummaryVersion(version, to: meeting.id)
                    }
                }
            }
        }

        // Each meeting should have 3 versions
        for meeting in meetings {
            let updatedMeeting = mockManager.get(id: meeting.id)
            #expect(updatedMeeting?.summaryVersions.count == 3)
        }
    }

    @Test("Interleaved add and addSummaryVersion operations")
    func testInterleavedOperations() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        // Add initial meeting
        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Perform interleaved operations
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Add summary versions
            group.addTask {
                for i in 1...5 {
                    let version = Self.createTestSummaryVersion(
                        versionNumber: i,
                        meetingID: meeting.id
                    )
                    await mockManager.addSummaryVersion(version, to: meeting.id)
                    try? await Task.sleep(nanoseconds: 10_000_000) // Small delay
                }
            }

            // Task 2: Read the meeting
            group.addTask {
                for _ in 1...10 {
                    _ = await mockManager.get(id: meeting.id)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }

            // Task 3: Update meeting
            group.addTask {
                // ✅ 修复: 读取最新的 meeting 数据以避免覆盖 Task 1 添加的 summary versions
                var currentMeeting = mockManager.get(id: meeting.id) ?? meeting
                currentMeeting.title = "Updated Title"
                await mockManager.update(currentMeeting)
            }
        }

        // Verify final state is consistent
        let finalMeeting = mockManager.get(id: meeting.id)
        #expect(finalMeeting?.summaryVersions.count == 5)
    }

    // MARK: - Edge Case Tests

    @Test("addSummaryVersion with duplicate ID handles gracefully")
    func testAddDuplicateSummaryVersionID() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        let versionID = UUID()
        let version1 = SummaryVersion(
            id: versionID,
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(modelId: "model1", displayName: "Model 1", provider: "Test"),
            promptInfo: PromptVersionInfo(promptId: "prompt1", promptName: "Prompt 1", contentPreview: "", category: .llm),
            filePath: "path1.md",
            sourceTranscriptId: meeting.id,
            sourceTranscriptVersionNumber: 1
        )

        let version2 = SummaryVersion(
            id: versionID, // Same ID
            versionNumber: 2,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(modelId: "model2", displayName: "Model 2", provider: "Test"),
            promptInfo: PromptVersionInfo(promptId: "prompt2", promptName: "Prompt 2", contentPreview: "", category: .llm),
            filePath: "path2.md",
            sourceTranscriptId: meeting.id,
            sourceTranscriptVersionNumber: 1
        )

        await mockManager.addSummaryVersion(version1, to: meeting.id)
        await mockManager.addSummaryVersion(version2, to: meeting.id)

        // Both versions should be added (mock allows duplicates)
        #expect(mockManager.recordings.first?.summaryVersions.count == 2)
    }

    @Test("addSummaryVersion preserves existing transcript versions")
    func testPreservesTranscriptVersions() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        var meeting = Self.createTestMeeting()
        meeting.transcriptVersions = [
            TranscriptVersion(
                id: UUID(),
                versionNumber: 1,
                timestamp: Date(),
                modelInfo: ModelVersionInfo(modelId: "whisper", displayName: "Whisper", provider: "OpenAI"),
                promptInfo: PromptVersionInfo(promptId: "default", promptName: "Default", contentPreview: "", category: .asr),
                filePath: "transcript.json"
            )
        ]
        await mockManager.add(meeting)

        let summaryVersion = Self.createTestSummaryVersion(meetingID: meeting.id)
        await mockManager.addSummaryVersion(summaryVersion, to: meeting.id)

        let updatedMeeting = mockManager.get(id: meeting.id)
        #expect(updatedMeeting?.transcriptVersions.count == 1)
        #expect(updatedMeeting?.summaryVersions.count == 1)
    }

    @Test("addSummaryVersion with empty file path")
    func testAddSummaryVersionWithEmptyFilePath() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        let version = SummaryVersion(
            id: UUID(),
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(modelId: "test", displayName: "Test", provider: "Test"),
            promptInfo: PromptVersionInfo(promptId: "test", promptName: "Test", contentPreview: "", category: .llm),
            filePath: "", // Empty path
            sourceTranscriptId: meeting.id,
            sourceTranscriptVersionNumber: 1
        )

        await mockManager.addSummaryVersion(version, to: meeting.id)

        #expect(mockManager.recordings.first?.summaryVersions.count == 1)
        #expect(mockManager.recordings.first?.summaryVersions.first?.filePath == "")
    }

    // MARK: - Stress Tests

    @Test("Rapid sequential addSummaryVersion calls")
    func testRapidSequentialCalls() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Rapidly add 50 versions
        for i in 1...50 {
            let version = Self.createTestSummaryVersion(versionNumber: i, meetingID: meeting.id)
            await mockManager.addSummaryVersion(version, to: meeting.id)
        }

        #expect(mockManager.recordings.first?.summaryVersions.count == 50)
    }

    @Test("addSummaryVersion after meeting deletion")
    func testAddAfterMeetingDeletion() async throws {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Delete the meeting
        try await mockManager.delete(id: meeting.id)

        // Try to add summary version to deleted meeting
        let version = Self.createTestSummaryVersion(meetingID: meeting.id)
        await mockManager.addSummaryVersion(version, to: meeting.id)

        // Should not crash, meeting should still be deleted
        #expect(mockManager.get(id: meeting.id) == nil)
    }

    // MARK: - Version Number Tests

    @Test("Version numbers are assigned correctly")
    func testVersionNumberAssignment() async {
        let mockManager = MockMetadataManager()
        mockManager.configureForTesting()

        let meeting = Self.createTestMeeting()
        await mockManager.add(meeting)

        // Add versions out of order
        let version5 = Self.createTestSummaryVersion(versionNumber: 5, meetingID: meeting.id)
        let version2 = Self.createTestSummaryVersion(versionNumber: 2, meetingID: meeting.id)
        let version10 = Self.createTestSummaryVersion(versionNumber: 10, meetingID: meeting.id)

        await mockManager.addSummaryVersion(version5, to: meeting.id)
        await mockManager.addSummaryVersion(version2, to: meeting.id)
        await mockManager.addSummaryVersion(version10, to: meeting.id)

        // Versions should be in insertion order, not versionNumber order
        let versions = mockManager.recordings.first?.summaryVersions ?? []
        #expect(versions.count == 3)
        #expect(versions[0].versionNumber == 5)
        #expect(versions[1].versionNumber == 2)
        #expect(versions[2].versionNumber == 10)
    }
}
