import Foundation

struct WhisperCppDetector: @unchecked Sendable {
    let candidatePaths: [String]
    private let fileManager: FileManager

    init(
        candidatePaths: [String] = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            NSString(string: "~/whisper.cpp/build/bin/whisper-cli").expandingTildeInPath,
            NSString(string: "~/whisper.cpp/main").expandingTildeInPath
        ],
        fileManager: FileManager = .default
    ) {
        self.candidatePaths = candidatePaths
        self.fileManager = fileManager
    }

    func detectExecutable() -> URL? {
        candidatePaths
            .map { URL(fileURLWithPath: $0) }
            .first { url in
                fileManager.fileExists(atPath: url.path) && fileManager.isExecutableFile(atPath: url.path)
            }
    }

    func validate(config: AIProviderConfig) -> AIProviderValidationResult {
        guard let command = config.asr?.localCommand else {
            return AIProviderValidationResult(isValid: false, message: "Missing local command config")
        }
        guard fileManager.fileExists(atPath: command.executablePath) else {
            return AIProviderValidationResult(isValid: false, message: "whisper-cli executable not found")
        }
        guard fileManager.isExecutableFile(atPath: command.executablePath) else {
            return AIProviderValidationResult(isValid: false, message: "whisper-cli is not executable")
        }
        guard fileManager.fileExists(atPath: command.modelPath) else {
            return AIProviderValidationResult(isValid: false, message: "whisper.cpp model file not found")
        }
        guard URL(fileURLWithPath: command.modelPath).pathExtension == "bin" else {
            return AIProviderValidationResult(isValid: false, message: "whisper.cpp model must be a .bin file")
        }
        return AIProviderValidationResult(isValid: true, message: "Whisper.cpp configuration is valid")
    }
}
