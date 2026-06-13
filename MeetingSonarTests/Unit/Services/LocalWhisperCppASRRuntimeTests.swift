import XCTest
@testable import MeetingSonar

final class LocalWhisperCppASRRuntimeTests: XCTestCase {
    func testValidateRejectsMissingExecutable() async throws {
        let config = AIProviderConfig.localWhisperCpp(
            displayName: "Local Whisper",
            executablePath: "/tmp/missing-whisper-cli",
            modelPath: "/tmp/missing-model.bin"
        )

        let runtime = LocalWhisperCppASRRuntime(config: config)
        let result = try await runtime.validate()

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("whisper-cli"))
    }
}
