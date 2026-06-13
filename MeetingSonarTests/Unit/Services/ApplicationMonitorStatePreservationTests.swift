import XCTest
@testable import MeetingSonar

@MainActor
final class ApplicationMonitorStatePreservationTests: XCTestCase {
    func testSamePIDKeepsInMeetingDuringProcessRefresh() {
        let oldState = ApplicationMonitor.MeetingState.inMeeting(pid: 1234)
        let next = ApplicationMonitor.resolvedProcessRefreshState(existing: oldState, runningPID: 1234)

        XCTAssertEqual(next, .inMeeting(pid: 1234))
    }

    func testDifferentPIDDowngradesToRunning() {
        let oldState = ApplicationMonitor.MeetingState.inMeeting(pid: 1234)
        let next = ApplicationMonitor.resolvedProcessRefreshState(existing: oldState, runningPID: 5678)

        XCTAssertEqual(next, .running(pid: 5678))
    }
}
