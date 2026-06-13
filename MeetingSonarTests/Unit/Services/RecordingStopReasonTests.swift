import XCTest
@testable import MeetingSonar

@MainActor
final class RecordingStopReasonTests: XCTestCase {
    func testMockRecordingServiceKeepsStopReason() async throws {
        let mock = MockRecordingService()
        try await mock.startRecording(trigger: .auto, appName: "zoom.us")

        mock.stopRecording(reason: .autoStop)

        XCTAssertEqual(mock.lastStopReason, .autoStop)
        XCTAssertFalse(mock.isRecording)
    }

    func testMeetingMetaDecodesWithoutDetectionInfo() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "filename": "legacy.m4a",
          "source": "Zoom",
          "startTime": "2026-06-12T01:00:00Z",
          "duration": 12,
          "status": "pending",
          "transcriptVersions": [],
          "summaryVersions": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(MeetingMeta.self, from: json)

        XCTAssertNil(meta.detectionInfo)
    }
}
