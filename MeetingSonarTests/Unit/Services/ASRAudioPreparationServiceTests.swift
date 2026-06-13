import AVFoundation
import XCTest
@testable import MeetingSonar

final class ASRAudioPreparationServiceTests: XCTestCase {
    func testCreatesCacheJobDirectoryOutsideRecordings() throws {
        let service = ASRAudioPreparationService()
        let directory = try service.createJobDirectory(
            jobID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        XCTAssertTrue(directory.path.contains("/Library/Caches/MeetingSonar/ASRJobs/"))
        XCTAssertFalse(directory.path.contains("MeetingSonar_Data/Recordings"))

        try service.cleanup(jobDirectory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEstimatedWAVBytesUsesSixteenKhzMonoInt16() {
        let service = ASRAudioPreparationService()
        let bytes = service.estimatedWAVBytes(duration: 60)

        XCTAssertEqual(bytes, 1_920_044, accuracy: 2_000)
    }
}
