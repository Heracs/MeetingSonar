//
//  MockMetadataManager.swift
//  MeetingSonar
//
//  Mock implementation of MetadataManagerProtocol for testing.
//

import Foundation

/// Mock metadata manager for unit testing
///
/// ## Usage
/// ```swift
/// let mockMetadata = MockMetadataManager()
/// mockMetadata.recordings = [testRecording]
/// XCTAssertEqual(mockMetadata.recordings.count, 1)
/// ```
@MainActor
final class MockMetadataManager: MetadataManagerProtocol {

    // MARK: - Properties

    var recordings: [MeetingMeta] = []

    /// Whether load was called
    private(set) var loadCalled = false

    /// Whether add was called
    private(set) var addCalled = false

    /// Whether update was called
    private(set) var updateCalled = false

    /// Whether delete was called
    private(set) var deleteCalled = false

    /// Last added recording
    private(set) var lastAddedRecording: MeetingMeta?

    /// Last updated recording
    private(set) var lastUpdatedRecording: MeetingMeta?

    /// Last deleted ID
    private(set) var lastDeletedId: UUID?

    /// Error to throw from delete (nil for success)
    var deleteError: Error?

    /// Error to throw from load (nil for success)
    var loadError: Error?

    /// Error to throw from add (nil for success)
    var addError: Error?

    // MARK: - Protocol Methods

    func load() async {
        loadCalled = true

        if let error = loadError {
            // In a real test, we'd handle this appropriately
            // For now, we just track that it was called
        }
    }

    func add(_ meta: MeetingMeta) async {
        addCalled = true
        lastAddedRecording = meta

        if let error = addError {
            // In a real test, we'd handle this appropriately
            // For now, we just track that it was called
        } else {
            recordings.append(meta)
        }
    }

    func update(_ meta: MeetingMeta) async {
        updateCalled = true
        lastUpdatedRecording = meta

        if let index = recordings.firstIndex(where: { $0.id == meta.id }) {
            recordings[index] = meta
        }
    }

    func get(id: UUID) -> MeetingMeta? {
        return recordings.first { $0.id == id }
    }

    func delete(id: UUID) async throws {
        deleteCalled = true
        lastDeletedId = id

        if let error = deleteError {
            throw error
        }

        // Check if the item exists
        let exists = recordings.contains(where: { $0.id == id })
        if !exists {
            throw MeetingSonarError.storage(.fileNotFound(path: id.uuidString))
        }

        recordings.removeAll { $0.id == id }
    }

    func scanAndMigrate() async {
        // Mock implementation - no-op
    }

    func repairZeroDurations() async {
        // Mock implementation - no-op
    }

    func rename(id: UUID, newTitle: String) async {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            recordings[index].title = newTitle
        }
    }

    // MARK: - Test Helpers

    /// Configure for testing (clears all state)
    func configureForTesting() {
        reset()
    }

    /// Reset all tracking state
    func reset() {
        recordings = []
        loadCalled = false
        addCalled = false
        updateCalled = false
        deleteCalled = false
        lastAddedRecording = nil
        lastUpdatedRecording = nil
        lastDeletedId = nil
        deleteError = nil
        loadError = nil
        addError = nil
    }

    /// Create a test recording with default values
    /// - Parameter title: Optional title for the test recording
    /// - Returns: A new MeetingMeta instance for testing
    static func createTestRecording(title: String = "Test Recording") -> MeetingMeta {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "test_\(UUID().uuidString).m4a"
        return MeetingMeta(
            id: UUID(),
            filename: filename,
            title: title,
            source: "Manual",
            startTime: Date(),
            duration: 60.0,
            status: .completed
        )
    }
}
