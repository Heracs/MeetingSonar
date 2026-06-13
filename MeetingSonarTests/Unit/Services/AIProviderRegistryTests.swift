import Foundation
import Testing
@testable import MeetingSonar

@Suite("AIProviderRegistry Tests")
struct AIProviderRegistryTests {
    @Test("built in providers expose implemented v0.13 capabilities")
    func builtInProvidersExposeImplementedCapabilities() {
        let registry = AIProviderRegistry.builtIn

        let whisper = registry.definition(for: "local.whispercpp")
        #expect(whisper?.kind == .localCommand)
        #expect(whisper?.capabilities == [.asr])
        #expect(whisper?.asrTransports == [.localCommand])

        let zhipu = registry.definition(for: "cloud.zhipu")
        #expect(zhipu?.kind == .cloudAPI)
        #expect(zhipu?.capabilities.contains(.asr) == true)
        #expect(zhipu?.capabilities.contains(.llm) == true)
        #expect(zhipu?.asrTransports.contains(.syncMultipart) == true)

        let deepseek = registry.definition(for: "cloud.deepseek")
        #expect(deepseek?.capabilities == [.llm])
        #expect(deepseek?.llmTransports == [.openAICompatible])
    }

    @Test("provider config increments revision when changed")
    func providerConfigRevisionChanges() {
        var config = AIProviderConfig.localWhisperCpp(
            displayName: "Local Whisper",
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/model.bin"
        )

        let originalRevision = config.revision
        config.touch()

        #expect(config.revision == originalRevision + 1)
        #expect(config.updatedAt >= config.createdAt)
    }
}
