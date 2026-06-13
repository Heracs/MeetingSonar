import XCTest
@testable import MeetingSonar

@MainActor
final class DetectionStateTypesTests: XCTestCase {
    func testRecordingContextKeepsParticipantMetadata() {
        let startedAt = Date(timeIntervalSince1970: 1_717_000_000)

        let context = RecordingContext(
            triggerAppBundleID: "us.zoom.xos",
            triggerAppName: "zoom.us",
            triggerSource: .windowTitle,
            triggerTimestamp: startedAt,
            participantCount: 1,
            participantCountConfidence: .high
        )

        XCTAssertEqual(context.triggerAppBundleID, "us.zoom.xos")
        XCTAssertEqual(context.triggerAppName, "zoom.us")
        XCTAssertEqual(context.triggerSource, .windowTitle)
        XCTAssertEqual(context.triggerTimestamp, startedAt)
        XCTAssertEqual(context.participantCount, 1)
        XCTAssertEqual(context.participantCountConfidence, .high)
    }

    func testExistingRecordingContextInitializerStillWorks() {
        let context = RecordingContext(
            triggerAppBundleID: "com.microsoft.teams2",
            triggerAppName: "MSTeams",
            triggerSource: .micUsage,
            triggerTimestamp: Date(timeIntervalSince1970: 1_717_000_001)
        )

        XCTAssertNil(context.participantCount)
        XCTAssertNil(context.participantCountConfidence)
    }
}
