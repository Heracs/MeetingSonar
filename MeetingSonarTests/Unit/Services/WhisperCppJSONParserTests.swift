import XCTest
@testable import MeetingSonar

final class WhisperCppJSONParserTests: XCTestCase {
    func testParsesSegmentsFromWhisperJSON() throws {
        let json = """
        {
          "transcription": [
            { "timestamps": { "from": "00:00:00,000", "to": "00:00:02,500" }, "text": " 你好 " },
            { "timestamps": { "from": "00:00:02,500", "to": "00:00:04,000" }, "text": "世界" }
          ]
        }
        """.data(using: .utf8)!

        let result = try WhisperCppJSONParser().parse(data: json, language: "zh", processingTime: 1.2)

        XCTAssertEqual(result.text, "你好 世界")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startTime, 0, accuracy: 0.01)
        XCTAssertEqual(result.segments[0].endTime, 2.5, accuracy: 0.01)
    }
}
