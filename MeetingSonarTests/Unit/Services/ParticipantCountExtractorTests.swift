import XCTest
@testable import MeetingSonar

final class ParticipantCountExtractorTests: XCTestCase {
    func testExtractsZoomEnglishParticipantCount() {
        let observation = ParticipantCountExtractor.extract(
            bundleIdentifier: "us.zoom.xos",
            texts: ["Open participants panel, closed, 1 participants"],
            now: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(observation.count, 1)
        XCTAssertEqual(observation.rawText, "Open participants panel, closed, 1 participants")
        XCTAssertEqual(observation.confidence, .high)
        XCTAssertEqual(observation.timestamp, Date(timeIntervalSince1970: 10))
    }

    func testExtractsZoomEnglishMultiParticipantCount() {
        let observation = ParticipantCountExtractor.extract(
            bundleIdentifier: "us.zoom.xos",
            texts: ["Open participants panel, closed, 3 participants"],
            now: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(observation.count, 3)
        XCTAssertEqual(observation.confidence, .high)
    }

    func testExtractsChineseParticipantCount() {
        let observation = ParticipantCountExtractor.extract(
            bundleIdentifier: "us.zoom.xos",
            texts: ["参会者 2"],
            now: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(observation.count, 2)
        XCTAssertEqual(observation.rawText, "参会者 2")
        XCTAssertEqual(observation.confidence, .medium)
    }

    func testUnknownParticipantCountDoesNotInventSinglePerson() {
        let observation = ParticipantCountExtractor.extract(
            bundleIdentifier: "com.tencent.meeting",
            texts: ["腾讯会议", "共享屏幕", "聊天"],
            now: Date(timeIntervalSince1970: 13)
        )

        XCTAssertEqual(observation.bundleIdentifier, "com.tencent.meeting")
        XCTAssertNil(observation.count)
        XCTAssertNil(observation.rawText)
        XCTAssertEqual(observation.confidence, .low)
    }
}
