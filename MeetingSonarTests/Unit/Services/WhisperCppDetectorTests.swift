import XCTest
@testable import MeetingSonar

final class WhisperCppDetectorTests: XCTestCase {
    func testDetectsExecutableCandidate() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("whisper-cli")
        try "#!/bin/sh\necho whisper help\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let detector = WhisperCppDetector(candidatePaths: [executable.path])
        XCTAssertEqual(detector.detectExecutable()?.path, executable.path)

        try FileManager.default.removeItem(at: temp)
    }

    func testRejectsMissingModel() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let executable = temp.appendingPathComponent("whisper-cli")
        try "#!/bin/sh\necho whisper help\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let config = AIProviderConfig.localWhisperCpp(
            displayName: "Local",
            executablePath: executable.path,
            modelPath: "/tmp/missing.bin"
        )

        let result = WhisperCppDetector().validate(config: config)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("model"))

        try FileManager.default.removeItem(at: temp)
    }
}
