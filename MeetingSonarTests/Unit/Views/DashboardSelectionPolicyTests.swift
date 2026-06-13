//
//  DashboardSelectionPolicyTests.swift
//  MeetingSonarTests
//
//  Tests selection behavior after deleting recordings from the dashboard.
//

import Foundation
import Testing
@testable import MeetingSonar

@Suite("Dashboard Selection Policy Tests")
struct DashboardSelectionPolicyTests {

    @Test("Deleting selected recording selects newest remaining recording")
    func testDeletingSelectedRecordingSelectsNewestRemaining() {
        let deletedID = UUID()
        let olderID = UUID()
        let newerID = UUID()

        let remaining = [
            SampleData.createMeetingMeta(
                id: olderID,
                filename: "older.m4a",
                startTime: Date(timeIntervalSince1970: 100)
            ),
            SampleData.createMeetingMeta(
                id: newerID,
                filename: "newer.m4a",
                startTime: Date(timeIntervalSince1970: 200)
            )
        ]

        let nextSelection = DashboardSelectionPolicy.selectionAfterDeleting(
            currentSelection: deletedID,
            deletedID: deletedID,
            remainingRecordings: remaining
        )

        #expect(nextSelection == newerID)
    }

    @Test("Deleting unselected recording keeps current selection")
    func testDeletingUnselectedRecordingKeepsCurrentSelection() {
        let selectedID = UUID()
        let deletedID = UUID()

        let remaining = [
            SampleData.createMeetingMeta(
                id: selectedID,
                filename: "selected.m4a",
                startTime: Date(timeIntervalSince1970: 100)
            )
        ]

        let nextSelection = DashboardSelectionPolicy.selectionAfterDeleting(
            currentSelection: selectedID,
            deletedID: deletedID,
            remainingRecordings: remaining
        )

        #expect(nextSelection == selectedID)
    }

    @Test("Deleting final selected recording clears selection")
    func testDeletingFinalSelectedRecordingClearsSelection() {
        let deletedID = UUID()

        let nextSelection = DashboardSelectionPolicy.selectionAfterDeleting(
            currentSelection: deletedID,
            deletedID: deletedID,
            remainingRecordings: []
        )

        #expect(nextSelection == nil)
    }
}
