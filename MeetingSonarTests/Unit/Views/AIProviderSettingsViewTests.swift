import XCTest
@testable import MeetingSonar

final class AIProviderSettingsViewTests: XCTestCase {
    func testWhisperConfigRequiresExecutableAndModel() {
        let validator = AIProviderConfigFormValidator()
        let result = validator.validateWhisperCpp(
            displayName: "Local Whisper",
            executablePath: "",
            modelPath: ""
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("whisper-cli"))
    }
}
