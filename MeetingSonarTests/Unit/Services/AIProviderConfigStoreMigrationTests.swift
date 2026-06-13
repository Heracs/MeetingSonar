import XCTest
@testable import MeetingSonar

@MainActor
final class AIProviderConfigStoreMigrationTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await CloudAIModelManager.shared.resetAllData()
        await AIProviderConfigStore.shared.resetAllDataForTests()
        UserDefaults.standard.removeObject(forKey: "aiProviderConfigs_v1")
        UserDefaults.standard.removeObject(forKey: "selectedUnifiedASRId")
        UserDefaults.standard.removeObject(forKey: "selectedUnifiedLLMId")
    }

    override func tearDown() async throws {
        await AIProviderConfigStore.shared.resetAllDataForTests()
        await CloudAIModelManager.shared.resetAllData()
        try await super.tearDown()
    }

    func testMigratesZhipuCloudConfigWithASRAndLLM() async throws {
        let oldConfig = CloudAIModelConfig.default(for: .zhipu, capabilities: [.asr, .llm])
        try await CloudAIModelManager.shared.addModel(oldConfig, apiKey: "test-key")
        UserDefaults.standard.set(oldConfig.id.uuidString, forKey: "selectedUnifiedASRId")
        UserDefaults.standard.set(oldConfig.id.uuidString, forKey: "selectedUnifiedLLMId")

        let configs = await AIProviderConfigStore.shared.loadConfigsMigratingIfNeeded()

        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.providerKey, "cloud.zhipu")
        XCTAssertEqual(configs.first?.enabledCapabilities, [.asr, .llm])
        XCTAssertEqual(configs.first?.asr?.transport, .syncMultipart)
        XCTAssertEqual(configs.first?.llm?.transport, .zhipuNative)
    }

    func testMigratesDeepSeekAsLLMOnly() async throws {
        let oldConfig = CloudAIModelConfig.default(for: .deepseek, capabilities: [.llm])
        try await CloudAIModelManager.shared.addModel(oldConfig, apiKey: "test-key")

        let configs = await AIProviderConfigStore.shared.loadConfigsMigratingIfNeeded()

        XCTAssertEqual(configs.first?.providerKey, "cloud.deepseek")
        XCTAssertEqual(configs.first?.enabledCapabilities, [.llm])
        XCTAssertNil(configs.first?.asr)
        XCTAssertEqual(configs.first?.llm?.transport, .openAICompatible)
    }
}
