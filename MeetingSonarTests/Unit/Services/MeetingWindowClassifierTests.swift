import XCTest
@testable import MeetingSonar

@MainActor
final class MeetingWindowClassifierTests: XCTestCase {
    private let tencent = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.tencent.meeting",
        processName: "TencentMeeting",
        logProcessAliases: ["TencentMeeting", "腾讯会议", "wemeet", "com.tencent.meeting"],
        meetingWindowPatterns: [],
        excludeWindowPatterns: []
    )

    private let teams = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.microsoft.teams2",
        processName: "MSTeams",
        logProcessAliases: ["MSTeams"],
        meetingWindowPatterns: ["| Microsoft Teams"],
        excludeWindowPatterns: ["Calendar | Microsoft Teams"]
    )

    func testFeishuConfiguredMeetingWindowTitleIsMeetingUI() throws {
        let monitor = ApplicationMonitor()
        let feishu = try XCTUnwrap(
            monitor.monitoredApps.first { $0.bundleIdentifier == "com.electron.lark.iron" }
        )

        let windows = [
            AXWindowContentSnapshot(title: "飞书会议", strings: [])
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: feishu, windows: windows), .meetingUI)
    }

    func testFeishuMainWindowTitleIsNotMeetingUI() throws {
        let monitor = ApplicationMonitor()
        let feishu = try XCTUnwrap(
            monitor.monitoredApps.first { $0.bundleIdentifier == "com.electron.lark.iron" }
        )

        let windows = [
            AXWindowContentSnapshot(title: "飞书", strings: [])
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: feishu, windows: windows), .mainWindow)
    }

    func testTencentMainWindowIsMainWindowNotMeetingUI() {
        let windows = [
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: [
                    "QApplication.wemeet://page/home.DialogWidget.MainWidget",
                    "暂无会议"
                ]
            )
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: tencent, windows: windows), .mainWindow)
    }

    func testTencentPreJoinDialogIsPreJoin() {
        let windows = [
            AXWindowContentSnapshot(
                title: "加入会议",
                strings: [
                    "QApplication.BaseDialog.DialogWidget.join_meeting_dialog.QFLineEdit.QLineEdit",
                    "请输入会议号",
                    "自动连接音频"
                ]
            ),
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: ["QApplication.wemeet://page/home.DialogWidget.MainWidget"]
            )
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: tencent, windows: windows), .preJoin)
    }

    func testTencentWaitingRoomWithoutMeetingLayoutIsPreJoin() {
        let windows = [
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: [
                    "QApplication.wemeet://page/inmeeting_revision.DialogWidget.MainWidget",
                    "WaittingRoomWnd",
                    "AudioBtnTextLabel"
                ]
            )
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: tencent, windows: windows), .preJoin)
    }

    func testTencentMeetingLayoutIsMeetingUIWithoutMicEvidence() {
        let windows = [
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: [
                    "QApplication.wemeet://page/inmeeting_revision.DialogWidget.MainWidget",
                    "InMeetingLayoutContainerQtView",
                    "MeetingMainContainerContribute.AudioGridWidget.PureAudioWidget.SpeakingMembersStatic",
                    "正在讲话: "
                ]
            ),
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: [
                    "QApplication.wemeet://page/home.DialogWidget.MainWidget",
                    "Eric的快速会议",
                    "进行中"
                ]
            )
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: tencent, windows: windows), .meetingUI)
    }

    func testTencentPostLeaveMainWindowIsMainWindow() {
        let windows = [
            AXWindowContentSnapshot(
                title: "腾讯会议",
                strings: [
                    "QApplication.wemeet://page/home.DialogWidget.MainWidget",
                    "暂无会议"
                ]
            )
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: tencent, windows: windows), .mainWindow)
    }

    func testGenericClassifierKeepsExistingTeamsTitleBehavior() {
        let meeting = [
            AXWindowContentSnapshot(title: "test | Microsoft Teams", strings: [])
        ]
        let main = [
            AXWindowContentSnapshot(title: "Calendar | Microsoft Teams", strings: [])
        ]

        XCTAssertEqual(MeetingWindowClassifier.windowState(for: teams, windows: meeting), .meetingUI)
        XCTAssertEqual(MeetingWindowClassifier.windowState(for: teams, windows: main), .mainWindow)
    }
}
