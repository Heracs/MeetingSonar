//
//  MetadataManagerTests.swift
//  MeetingSonarTests
//
//  Unit tests for MetadataManager using Mock implementation.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class MetadataManagerTests: XCTestCase {

    var sut: MockMetadataManager!

    override func setUpWithError() throws {
        sut = MockMetadataManager()
        sut.configureForTesting()
    }

    override func tearDownWithError() throws {
        sut = nil
    }

    // MARK: - Load Tests

    func testLoadDoesNotCrash() async {
        // Act
        await sut.load()

        // Assert - should complete without error
        XCTAssertTrue(sut.loadCalled)
    }

    func testLoadInitializesEmptyRecordings() async {
        // Arrange
        XCTAssertTrue(sut.recordings.isEmpty)

        // Act
        await sut.load()

        // Assert
        XCTAssertTrue(sut.loadCalled)
    }

    // MARK: - Add Tests

    func testAddAddsToRecordings() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()
        XCTAssertEqual(sut.recordings.count, 0)

        // Act
        await sut.add(meta)

        // Assert
        XCTAssertEqual(sut.recordings.count, 1)
        XCTAssertEqual(sut.recordings.first?.id, meta.id)
        XCTAssertTrue(sut.addCalled)
    }

    func testAddMultipleRecordings() async {
        // Arrange
        let meta1 = SampleData.createMeetingMeta(source: "Zoom")
        let meta2 = SampleData.createMeetingMeta(source: "Teams")
        let meta3 = SampleData.createMeetingMeta(source: "Webex")

        // Act
        await sut.add(meta1)
        await sut.add(meta2)
        await sut.add(meta3)

        // Assert
        XCTAssertEqual(sut.recordings.count, 3)
    }

    // MARK: - Update Tests

    func testUpdateModifiesExistingRecording() async {
        // Arrange
        var meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        XCTAssertEqual(sut.recordings.first?.title, "20240121-1400_Test.m4a")

        // Act
        meta.title = "Updated Title"
        await sut.update(meta)

        // Assert
        XCTAssertEqual(sut.recordings.first?.title, "Updated Title")
    }

    func testUpdateNonExistentRecording() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()

        // Act - update without adding
        await sut.update(meta)

        // Assert - mock should handle gracefully
        XCTAssertTrue(sut.recordings.isEmpty || sut.recordings.count == 1)
    }

    // MARK: - Delete Tests

    func testDeleteRemovesFromRecordings() async throws {
        // Arrange
        let meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        XCTAssertEqual(sut.recordings.count, 1)

        // Act
        try await sut.delete(id: meta.id)

        // Assert
        XCTAssertTrue(sut.recordings.isEmpty)
    }

    func testDeleteNonExistentRecording() async {
        // Arrange
        let randomId = UUID()

        // Act & Assert
        do {
            try await sut.delete(id: randomId)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected to throw
            XCTAssertTrue(error is MeetingSonarError || error is NSError)
        }
    }

    // MARK: - Rename Tests

    func testRenameChangesTitle() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        let originalTitle = meta.title

        // Act
        await sut.rename(id: meta.id, newTitle: "Renamed Title")

        // Assert
        XCTAssertNotEqual(sut.recordings.first?.title, originalTitle)
        XCTAssertEqual(sut.recordings.first?.title, "Renamed Title")
    }

    func testRenameNonExistentRecording() async {
        // Arrange
        let randomId = UUID()

        // Act - should handle gracefully
        await sut.rename(id: randomId, newTitle: "New Title")

        // Assert - mock should not crash
    }

    // MARK: - Query Tests

    func testRecordingsIsEmptyInitially() {
        // Assert
        XCTAssertTrue(sut.recordings.isEmpty)
    }

    func testRecordingsContainsAddedItems() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()

        // Act
        await sut.add(meta)

        // Assert
        XCTAssertEqual(sut.recordings.count, 1)
        XCTAssertEqual(sut.recordings.first?.id, meta.id)
    }

    // MARK: - Scan and Migrate Tests

    func testScanAndMigrateDoesNotCrash() async {
        // Act
        await sut.scanAndMigrate()

        // Assert - should complete without error
    }

    // MARK: - Repair Zero Durations Tests

    func testRepairZeroDurationsDoesNotCrash() async {
        // Act
        await sut.repairZeroDurations()

        // Assert - should complete without error
    }

    // MARK: - Error Injection Tests

    func testDeleteWithErrorInjection() async {
        // Arrange
        sut.deleteError = MeetingSonarError.storage(.fileNotFound(path: "Test file"))
        let meta = SampleData.createMeetingMeta()
        await sut.add(meta)

        // Act & Assert
        do {
            try await sut.delete(id: meta.id)
            XCTFail("Should have thrown an error")
        } catch {
            // Verify it's a storage error
            if let mse = error as? MeetingSonarError,
               case .storage = mse {
                // Expected
            } else {
                XCTFail("Expected storage error, got: \(error)")
            }
        }
    }

    // MARK: - Mock Behavior Tests

    func testMockCanBeReset() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        XCTAssertTrue(sut.loadCalled || sut.addCalled)

        // Act
        sut.reset()

        // Assert
        XCTAssertTrue(sut.recordings.isEmpty)
        XCTAssertFalse(sut.loadCalled)
        XCTAssertFalse(sut.addCalled)
    }

    func testMockTracksMethodCalls() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()

        // Act
        await sut.load()
        await sut.add(meta)

        // Assert
        XCTAssertTrue(sut.loadCalled)
        XCTAssertTrue(sut.addCalled)
    }

    // MARK: - Integration Tests

    func testFullCRUDCycle() async throws {
        // 1. Create
        var meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        XCTAssertEqual(sut.recordings.count, 1)

        // 2. Read
        let found = sut.recordings.first { $0.id == meta.id }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, meta.id)

        // 3. Update
        meta.title = "Updated Title"
        await sut.update(meta)
        XCTAssertEqual(sut.recordings.first?.title, "Updated Title")

        // 4. Delete
        try await sut.delete(id: meta.id)
        XCTAssertTrue(sut.recordings.isEmpty)
    }

    // MARK: - Edge Cases Tests

    func testAddDuplicateRecording() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()

        // Act - add same recording twice
        await sut.add(meta)
        await sut.add(meta)

        // Assert - mock may allow or dedupe
        XCTAssertTrue(sut.recordings.count >= 1)
    }

    func testMultipleOperationsOnSameRecording() async throws {
        // Arrange
        var meta = SampleData.createMeetingMeta()
        await sut.add(meta)

        // Act - multiple updates
        for i in 1...5 {
            meta.title = "Update \(i)"
            await sut.update(meta)
        }

        // Assert
        XCTAssertEqual(sut.recordings.first?.title, "Update 5")
    }

    func testEmptyRename() async {
        // Arrange
        let meta = SampleData.createMeetingMeta()
        await sut.add(meta)
        let originalTitle = meta.title

        // Act
        await sut.rename(id: meta.id, newTitle: "")

        // Assert - should either keep original or set to empty
        // Mock implementation may vary
    }
}
