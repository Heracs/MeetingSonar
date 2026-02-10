//
//  PathManagerTests.swift
//  MeetingSonarTests
//
//  Created by AI Agent on 2026-01-13.
//

import XCTest
@testable import MeetingSonar

final class PathManagerTests: XCTestCase {

    var pathManager: PathManager!
    
    override func setUpWithError() throws {
        // Use a temporary user defaults domain
        let domain = "com.meetingsonar.tests.paths"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        
        // Reset singleton state if possible (Mocking UserDefaults if PathManager allows injection would be better,
        // but for now we test the default behavior)
        pathManager = PathManager.shared
    }

    override func tearDownWithError() throws {
        // Clean up created directories if needed? 
        // For safety, we generally don't delete files in Unit Tests unless we point to a purely temp dir.
        // PathManager defaults to ~/Documents/MeetingSonar_Data. 
        // CAUTION: We should ideally inject a mock ROOT URL for tests to avoid cluttering user's documents.
        // However, PathManager is a Singleton. 
        // Let's verify defaults for now.
    }

    func testDefaultRootURL() {
        let expectedURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeetingSonar_Data")
        
        XCTAssertEqual(pathManager.rootDataURL.path, expectedURL.path, "Default root URL should match MeetingSonar_Data in Documents")
    }

    func testDirectoryStructureExistence() {
        // Act
        pathManager.ensureDataDirectories()
        
        // Assert
        let root = pathManager.rootDataURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "Root folder missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Recordings").path), "Recordings folder missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Transcripts/Raw").path), "Transcripts/Raw folder missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("SmartNotes").path), "SmartNotes folder missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Models").path), "Models folder missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Logs").path), "Logs folder missing (v0.5.1)")
    }

    func testRecordingNamingConvention() {
        // Arrange
        let source = "ZoomMeeting"
        
        // Act
        let url = pathManager.generateRecordingURL(source: source)
        let filename = url.lastPathComponent
        
        // Assert
        // Format: yyyyMMdd-HHmm_ZoomMeeting.m4a
        // Use Regex to verify format
        let pattern = #"^\d{8}-\d{4}_ZoomMeeting\.m4a$"#
        
        let range = filename.range(of: pattern, options: .regularExpression)
        XCTAssertNotNil(range, "Filename \(filename) does not match pattern yyyyMMdd-HHmm_Source.m4a")
        
        // Also verify it resides in Recordings folder
        XCTAssertTrue(url.path.contains("/Recordings/"), "URL should be inside Recordings folder")
    }
}
