import Foundation

struct LocalWhisperCppASRRuntime: ASRRuntime {
    let config: AIProviderConfig
    private let detector: WhisperCppDetector
    private let audioPreparation: ASRAudioPreparationService
    private let parser: WhisperCppJSONParser

    init(
        config: AIProviderConfig,
        detector: WhisperCppDetector = WhisperCppDetector(),
        audioPreparation: ASRAudioPreparationService = ASRAudioPreparationService(),
        parser: WhisperCppJSONParser = WhisperCppJSONParser()
    ) {
        self.config = config
        self.detector = detector
        self.audioPreparation = audioPreparation
        self.parser = parser
    }

    var configID: UUID { config.id }
    var providerKey: String { config.providerKey }
    var modelName: String { config.asr?.modelName ?? config.displayName }

    func validate() async throws -> AIProviderValidationResult {
        detector.validate(config: config)
    }

    func transcribe(
        audioURL: URL,
        context: ASRRuntimeContext,
        progress: (@Sendable (ASRProgressEvent) async -> Void)?
    ) async throws -> TranscriptionResult {
        guard let command = config.asr?.localCommand else {
            throw AIProviderRuntimeError.invalidConfiguration("Missing whisper.cpp command config")
        }

        await progress?(.preparingAudio)
        let prepared = try await audioPreparation.prepareSingleWAV(from: audioURL)
        defer {
            do {
                try audioPreparation.cleanup(jobDirectory: prepared.jobDirectory)
            } catch {
                LoggerService.shared.log(
                    category: .audio,
                    level: .warning,
                    message: "[LocalWhisperCppASRRuntime] Failed to clean ASR job: \(error.localizedDescription)"
                )
            }
        }

        let started = Date()
        let outputBaseURL = prepared.jobDirectory.appendingPathComponent("input.wav")
        let jsonURL = outputBaseURL.appendingPathExtension("json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = [
            "--model", command.modelPath,
            "--file", prepared.wavURL.path,
            "--output-json",
            "--output-file", outputBaseURL.path,
            "--language", context.language
        ] + command.extraArguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "whisper.cpp failed"
            LoggerService.shared.log(category: .ai, level: .error, message: "[LocalWhisperCppASRRuntime] \(message)")
            throw AIProviderRuntimeError.localCommandFailed(message)
        }

        let data = try Data(contentsOf: jsonURL)
        await progress?(.transcribing(progress: 1.0))
        return try parser.parse(
            data: data,
            language: context.language,
            processingTime: Date().timeIntervalSince(started)
        )
    }
}
