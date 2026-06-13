import XCTest
@testable import MeetingSonar

final class AIProviderRuntimeFactoryTests: XCTestCase {
    func testCreatesWhisperASRRuntimeForLocalCommandConfig() async throws {
        let config = AIProviderConfig.localWhisperCpp(
            displayName: "Local Whisper",
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml.bin"
        )

        let runtime = try AIProviderRuntimeFactory().makeASRRuntime(config: config)

        XCTAssertEqual(runtime.configID, config.id)
        XCTAssertEqual(runtime.providerKey, "local.whispercpp")
        XCTAssertEqual(runtime.modelName, "ggml.bin")
    }

    func testRejectsLLMRuntimeForASROnlyConfig() throws {
        let config = AIProviderConfig.localWhisperCpp(
            displayName: "Local Whisper",
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml.bin"
        )

        XCTAssertThrowsError(try AIProviderRuntimeFactory().makeLLMRuntime(config: config))
    }
}
