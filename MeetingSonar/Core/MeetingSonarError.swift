//
//  MeetingSonarError.swift
//  MeetingSonar
//
//  Unified error type hierarchy for the MeetingSonar application.
//  Provides consistent error handling, user-friendly messages, and recovery suggestions.
//
//  Design Principles:
//  - Single entry point for all application errors
//  - Hierarchical structure for categorization
//  - Localized user-facing messages
//  - Actionable recovery suggestions
//  - Underlying error preservation for debugging
//

import Foundation

/// The unified error type for MeetingSonar application
///
/// ## Error Categories
/// - `recording`: Audio recording and capture errors
/// - `aiProcessing`: AI model loading and processing errors
/// - `storage`: File system and metadata errors
/// - `network`: Online API and network errors
/// - `permission`: System permission errors
/// - `configuration`: Application configuration errors
/// - `unknown`: Unexpected errors that don't fit other categories
///
/// ## Usage
/// ```swift
/// func startRecording() throws {
///     guard hasPermission else {
///         throw MeetingSonarError.recording(.permissionDenied(.microphone))
///     }
/// }
///
/// // Error handling
/// do {
///     try startRecording()
/// } catch let error as MeetingSonarError {
///     print(error.errorDescription)  // User-friendly message
///     print(error.recoverySuggestion)  // Actionable suggestion
/// }
/// ```
enum MeetingSonarError: LocalizedError {

    // MARK: - Recording Errors

    /// Errors related to audio recording and capture
    case recording(RecordingError)

    public enum RecordingError {
        /// Recording is already in progress
        case alreadyRecording

        /// No active recording to stop
        case notRecording

        /// Required permission not granted
        case permissionDenied(PermissionType)

        /// Audio device failure
        case audioDeviceFailed(underlying: Error)

        /// Audio capture failed to start
        case captureFailed(reason: String)

        /// Audio mixer error
        case mixerError(underlying: Error)

        /// File writer error
        case fileWriterError(underlying: Error)

        /// Maximum recording duration exceeded
        case maxDurationExceeded(maxSeconds: TimeInterval)

        /// Recording was interrupted
        case interrupted(reason: String)
    }

    // MARK: - AI Processing Errors

    /// Errors related to AI model operations
    case aiProcessing(AIError)

    public enum AIError {
        /// Model not found locally
        case modelNotFound(ModelType)

        /// Model download failed
        case modelDownloadFailed(ModelType, underlying: Error)

        /// Model load failed
        case modelLoadFailed(ModelType, underlying: Error)

        /// Transcription failed
        case transcriptionFailed(underlying: Error)

        /// Summary generation failed
        case summaryGenerationFailed(underlying: Error)

        /// Model unavailable (not downloaded and offline mode)
        case modelUnavailable(ModelType)

        /// Insufficient memory for model
        case insufficientMemory(required: UInt64, available: UInt64)

        /// Processing timeout
        case processingTimeout(duration: TimeInterval)

        /// Invalid model configuration
        case invalidConfiguration(reason: String)
    }

    // MARK: - Storage Errors

    /// Errors related to file system and data persistence
    case storage(StorageError)

    public enum StorageError {
        /// Path validation failed
        case pathInvalid(reason: String)

        /// Path not accessible (no read/write permission)
        case pathNotAccessible(path: String)

        /// Insufficient disk space
        case diskInsufficient(required: UInt64, available: UInt64)

        /// File corrupted or invalid format
        case fileCorrupted(filename: String, reason: String?)

        /// File not found
        case fileNotFound(path: String)

        /// Metadata load failed
        case metadataLoadFailed(underlying: Error)

        /// Metadata save failed
        case metadataSaveFailed(underlying: Error)

        /// Directory creation failed
        case directoryCreationFailed(path: String, underlying: Error)
    }

    // MARK: - Network Errors

    /// Errors related to online API calls
    case network(NetworkError)

    public enum NetworkError {
        /// Network connection unavailable
        case offline

        /// Request timeout
        case timeout(duration: TimeInterval)

        /// Server returned error
        case serverError(code: Int, message: String)

        /// API key invalid or missing
        case apiKeyInvalid

        /// API key verification failed
        case apiKeyVerificationFailed(underlying: Error)

        /// Rate limit exceeded
        case rateLimitExceeded(retryAfter: TimeInterval?)

        /// Invalid response format
        case invalidResponseFormat(reason: String)

        /// Request failed
        case requestFailed(underlying: Error)
    }

    // MARK: - Permission Errors

    /// Errors related to system permissions
    case permission(PermissionError)

    public enum PermissionError {
        /// Screen recording permission denied
        case screenRecordingDenied

        /// Microphone permission denied
        case microphoneDenied

        /// File system access denied
        case fileSystemAccessDenied(path: String)

        /// Accessibility permission denied (for window detection)
        case accessibilityDenied

        /// Permission request failed
        case requestFailed(PermissionType, underlying: Error)
    }

    // MARK: - Configuration Errors

    /// Errors related to application configuration
    case configuration(ConfigurationError)

    public enum ConfigurationError {
        /// Invalid setting value
        case invalidSetting(key: String, value: Any?, reason: String)

        /// Missing required setting
        case missingRequiredSetting(key: String)

        /// Settings corrupted
        case settingsCorrupted(underlying: Error)

        /// Incompatible configuration
        case incompatibleConfiguration(reason: String)
    }

    // MARK: - Unknown Errors

    /// Unexpected errors that don't fit other categories
    case unknown(underlying: Error)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .recording(let error):
            return L10nError.recording(error)

        case .aiProcessing(let error):
            return L10nError.aiProcessing(error)

        case .storage(let error):
            return L10nError.storage(error)

        case .network(let error):
            return L10nError.network(error)

        case .permission(let error):
            return L10nError.permission(error)

        case .configuration(let error):
            return L10nError.configuration(error)

        case .unknown(let error):
            return L10nError.unknown(error)
        }
    }

    public var failureReason: String? {
        switch self {
        case .recording(.alreadyRecording):
            return "A recording is already in progress"

        case .recording(.notRecording):
            return "No recording is currently active"

        case .recording(.permissionDenied(let type)):
            return "Required permission for \(type.rawValue) has not been granted"

        case .recording(.audioDeviceFailed(let error)):
            return "Audio device encountered an error: \(error.localizedDescription)"

        case .recording(.captureFailed(let reason)):
            return "Audio capture failed: \(reason)"

        case .aiProcessing(.modelNotFound(let type)):
            return "The required AI model \(type.displayName) is not installed"

        case .aiProcessing(.modelDownloadFailed(let type, _)):
            return "Failed to download AI model \(type.displayName)"

        case .storage(.pathInvalid(let reason)):
            return "The specified path is invalid: \(reason)"

        case .storage(.diskInsufficient(let required, let available)):
            let requiredMB = required / 1_048_576
            let availableMB = available / 1_048_576
            return "Insufficient disk space: \(requiredMB)MB required, \(availableMB)MB available"

        case .network(.offline):
            return "Network connection is unavailable"

        case .network(.serverError(let code, let message)):
            return "Server error \(code): \(message)"

        case .permission(.screenRecordingDenied):
            return "Screen recording permission is required"

        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"

        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .recording(.alreadyRecording):
            return L10nError.Recovery.stopCurrentRecording

        case .recording(.notRecording):
            return L10nError.Recovery.startNewRecording

        case .recording(.permissionDenied(.microphone)):
            return L10nError.Recovery.grantMicrophonePermission

        case .recording(.permissionDenied(.screenRecording)):
            return L10nError.Recovery.grantScreenRecordingPermission

        case .aiProcessing(.modelNotFound(let type)):
            return L10nError.Recovery.downloadModel(type.displayName)

        case .aiProcessing(.modelUnavailable(let type)):
            return L10nError.Recovery.downloadModel(type.displayName)

        case .storage(.diskInsufficient):
            return L10nError.Recovery.freeDiskSpace

        case .network(.offline):
            return L10nError.Recovery.checkNetworkConnection

        case .permission(.screenRecordingDenied):
            return L10nError.Recovery.enableScreenRecording

        case .permission(.microphoneDenied):
            return L10nError.Recovery.enableMicrophone

        case .permission(.accessibilityDenied):
            return L10nError.Recovery.enableAccessibility

        default:
            return L10nError.Recovery.contactSupport
        }
    }

    // MARK: - Helper Types

    /// Permission types that may be requested
    public enum PermissionType: String {
        case microphone = "Microphone"
        case screenRecording = "Screen Recording"
        case fileSystem = "File System"
        case accessibility = "Accessibility"
    }

    /// Extract the underlying error if available
    public var underlyingError: Error? {
        switch self {
        case .recording(.audioDeviceFailed(let error)),
             .recording(.mixerError(let error)),
             .recording(.fileWriterError(let error)):
            return error

        case .aiProcessing(.modelDownloadFailed(_, let error)),
             .aiProcessing(.modelLoadFailed(_, let error)),
             .aiProcessing(.transcriptionFailed(let error)),
             .aiProcessing(.summaryGenerationFailed(let error)):
            return error

        case .storage(.metadataLoadFailed(let error)),
             .storage(.metadataSaveFailed(let error)),
             .storage(.directoryCreationFailed(_, let error)):
            return error

        case .network(.requestFailed(let error)),
             .network(.apiKeyVerificationFailed(let error)):
            return error

        case .permission(.requestFailed(_, let error)):
            return error

        case .configuration(.settingsCorrupted(let error)):
            return error

        case .unknown(let error):
            return error

        default:
            return nil
        }
    }

    // MARK: - Automatic Logging

    /// Automatically logs this error to the logging system
    ///
    /// This method provides automatic error logging with rich context information.
    /// It captures:
    /// - Error category and description
    /// - Failure reason (if available)
    /// - Recovery suggestion (if available)
    /// - Underlying error (if available)
    /// - Stack trace information
    ///
    /// ## Usage
    /// ```swift
    /// do {
    ///     try startRecording()
    /// } catch {
    ///     error.asMeetingSonarError().log()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - category: The logging category (defaults to matching the error type)
    ///   - level: The log level (defaults to .error)
    ///   - context: Additional context information (function, file, line)
    ///   - userInfo: Custom key-value pairs for debugging
    func log(
        category: ErrorLogCategory? = nil,
        level: ErrorLogLevel = .error,
        context: LogContext = .captured(),
        userInfo: [String: Any]? = nil
    ) {
        // Determine appropriate category based on error type
        let logCategory = (category ?? defaultCategory(for: self)).toLoggerServiceCategory

        // Build rich log message
        var logMessage = buildLogMessage(context: context, userInfo: userInfo)

        // Log the message
        LoggerService.shared.log(
            category: logCategory,
            level: level.toLoggerServiceLevel,
            message: logMessage
        )

        // Log underlying error separately for debugging
        if let underlying = underlyingError {
            LoggerService.shared.log(
                category: logCategory,
                level: .debug,
                message: "[Underlying Error] \(underlying.localizedDescription)"
            )
        }
    }

    /// Returns the default ErrorLogCategory for a given error type
    private func defaultCategory(for error: MeetingSonarError) -> ErrorLogCategory {
        switch error {
        case .recording:
            return .recording
        case .aiProcessing:
            return .ai
        case .storage:
            return .general
        case .network:
            return .general
        case .permission:
            return .permission
        case .configuration:
            return .general
        case .unknown:
            return .general
        }
    }

    /// Builds a detailed log message for this error
    private func buildLogMessage(context: LogContext, userInfo: [String: Any]?) -> String {
        var components: [String] = []

        // Error category and description
        if let description = errorDescription {
            components.append("[Error] \(description)")
        }

        // Failure reason (technical details)
        if let reason = failureReason {
            components.append("[Reason] \(reason)")
        }

        // Recovery suggestion
        if let suggestion = recoverySuggestion {
            components.append("[Recovery] \(suggestion)")
        }

        // Source context (function, file, line)
        if !context.function.isEmpty {
            components.append("[Source] \(context.function)()")
        }

        // File and line
        components.append("[\(context.file):\(context.line)]")

        // Custom user info
        if let userInfo = userInfo, !userInfo.isEmpty {
            let infoString = userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            components.append("[Info] \(infoString)")
        }

        return components.joined(separator: " | ")
    }
}

// MARK: - Logging Support Types

/// Logger categories for error logging (maps to LogCategory in LoggerService.swift)
enum ErrorLogCategory {
    case recording
    case ai
    case permission
    case general

    /// Converts to LogCategory
    var toLoggerServiceCategory: LogCategory {
        switch self {
        case .recording: return .recording
        case .ai: return .ai
        case .permission: return .permission
        case .general: return .general
        }
    }
}

/// Log levels for error logging (maps to LogLevel in LoggerService.swift)
enum ErrorLogLevel {
    case debug
    case info
    case warning
    case error

    /// Converts to LogLevel
    var toLoggerServiceLevel: LogLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}

/// Source context for error logging
struct LogContext {
    let function: String
    let file: String
    let line: Int

    /// Captures the current call site context
    static func captured(
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) -> LogContext {
        // Extract just filename from full path
        let filename = (file as NSString).lastPathComponent
        return LogContext(
            function: function,
            file: filename,
            line: line
        )
    }
}

// MARK: - Error Handling Utilities

/// Unified error handling with automatic logging
///
/// ## Usage
/// ```swift
/// // Simple error handling with logging
/// let result = ErrorHandler.try {
///     try startRecording()
/// }
///
/// // With custom context
/// let result = ErrorHandler.try {
///     try processAudio()
/// } context: "processAudio"
///
/// // With recovery action
/// ErrorHandler.try {
///     try saveFile()
/// } recovery: { error in
///     showErrorMessage(error)
/// }
/// ```
enum ErrorHandler {

    /// Executes a throwing operation and logs any errors
    ///
    /// - Parameters:
    ///   - operation: The throwing operation to execute
    ///   - category: The logging category (auto-detected if nil)
    ///   - context: Additional context information
    ///   - recovery: Optional recovery action
    /// - Returns: The operation result if successful, nil if error occurred
    @discardableResult
    static func tryOperation<T>(
        _ operation: () throws -> T,
        category: ErrorLogCategory? = nil,
        context: LogContext = .captured(),
        recovery: ((MeetingSonarError) -> Void)? = nil
    ) -> T? {
        do {
            return try operation()
        } catch {
            let mse = error.asMeetingSonarError()
            mse.log(category: category, context: context)
            recovery?(mse)
            return nil
        }
    }

    /// Executes an async throwing operation and logs any errors
    ///
    /// - Parameters:
    ///   - operation: The async throwing operation to execute
    ///   - category: The logging category (auto-detected if nil)
    ///   - context: Additional context information
    ///   - recovery: Optional recovery action
    /// - Returns: The operation result if successful, nil if error occurred
    @discardableResult
    static func tryOperation<T>(
        _ operation: () async throws -> T,
        category: ErrorLogCategory? = nil,
        context: LogContext = .captured(),
        recovery: ((MeetingSonarError) -> Void)? = nil
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            let mse = error.asMeetingSonarError()
            mse.log(category: category, context: context)
            recovery?(mse)
            return nil
        }
    }

    /// Executes a throwing operation without return value
    ///
    /// - Parameters:
    ///   - operation: The throwing operation to execute
    ///   - category: The logging category (auto-detected if nil)
    ///   - context: Additional context information
    ///   - recovery: Optional recovery action
    /// - Returns: True if successful, false if error occurred
    @discardableResult
    static func tryOperation(
        _ operation: () throws -> Void,
        category: ErrorLogCategory? = nil,
        context: LogContext = .captured(),
        recovery: ((MeetingSonarError) -> Void)? = nil
    ) -> Bool {
        do {
            try operation()
            return true
        } catch {
            let mse = error.asMeetingSonarError()
            mse.log(category: category, context: context)
            recovery?(mse)
            return false
        }
    }

    /// Executes an async throwing operation without return value
    ///
    /// - Parameters:
    ///   - operation: The async throwing operation to execute
    ///   - category: The logging category (auto-detected if nil)
    ///   - context: Additional context information
    ///   - recovery: Optional recovery action
    /// - Returns: True if successful, false if error occurred
    @discardableResult
    static func tryOperation(
        _ operation: () async throws -> Void,
        category: ErrorLogCategory? = nil,
        context: LogContext = .captured(),
        recovery: ((MeetingSonarError) -> Void)? = nil
    ) async -> Bool {
        do {
            try await operation()
            return true
        } catch {
            let mse = error.asMeetingSonarError()
            mse.log(category: category, context: context)
            recovery?(mse)
            return false
        }
    }
}

// MARK: - Convenient Error Handling Patterns

extension ErrorHandler {

    /// Handle errors with a user-friendly alert
    ///
    /// ## Usage
    /// ```swift
    /// ErrorHandler.tryOperation(
    ///     throw MeetingSonarError.recording(.alreadyRecording)
    /// ) recovery: { error in
    ///     ErrorHandler.showAlert(for: error)
    /// }
    /// ```
    static func showAlert(for error: MeetingSonarError) {
        // This would integrate with NSAlert in production
        // For now, just log the alert
        LoggerService.shared.log(
            category: .ui,
            level: .info,
            message: "[UI Alert] \(error.errorDescription ?? "Error")"
        )
    }

    /// Wrap a completion handler with error handling
    ///
    /// ## Usage
    /// ```swift
    /// someAsyncOperation(completion: ErrorHandler.wrapCompletion { result in
    ///     // Handle result
    /// })
    /// ```
    static func wrapCompletion<T>(
        _ handler: @escaping (Result<T, Error>) -> Void
    ) -> (Result<T, Error>) -> Void {
        return { result in
            switch result {
            case .success(let value):
                handler(.success(value))

            case .failure(let error):
                let mse = error.asMeetingSonarError()
                mse.log()
                handler(.failure(mse))
            }
        }
    }
}

// MARK: - Localized Error Messages (L10n Integration)

/// Localized error messages namespace
///
/// Provides internationalized error messages for all MeetingSonar error types.
/// Uses String(localized:) to fetch localized strings from Localizable.xcstrings.
enum L10nError {
    enum Recording {
        static func alreadyRecording() -> String {
            String(localized: "error.recording.alreadyRecording")
        }
        static func notRecording() -> String {
            String(localized: "error.recording.notRecording")
        }
        static func permissionDenied(_ type: MeetingSonarError.PermissionType) -> String {
            String(localized: "error.recording.permissionDenied.\(type.rawValue)")
        }
        static func audioDeviceFailed(_ error: Error) -> String {
            String(localized: "error.recording.audioDeviceFailed.\(error.localizedDescription)")
        }
        static func captureFailed(_ reason: String) -> String {
            String(localized: "error.recording.captureFailed.\(reason)")
        }
        static func mixerError(_ error: Error) -> String {
            String(localized: "error.recording.mixerError.\(error.localizedDescription)")
        }
        static func fileWriterError(_ error: Error) -> String {
            String(localized: "error.recording.fileWriterError.\(error.localizedDescription)")
        }
        static func maxDurationExceeded(_ maxSeconds: TimeInterval) -> String {
            String(localized: "error.recording.maxDurationExceeded.\(Int(maxSeconds))")
        }
        static func interrupted(_ reason: String) -> String {
            String(localized: "error.recording.interrupted.\(reason)")
        }
    }

    enum AI {
        static func modelNotFound(_ model: String) -> String {
            String(localized: "error.ai.modelNotFound.\(model)")
        }
        static func modelDownloadFailed(_ model: String) -> String {
            String(localized: "error.ai.modelDownloadFailed.\(model)")
        }
        static func modelLoadFailed(_ model: String) -> String {
            String(localized: "error.ai.modelLoadFailed.\(model)")
        }
        static func transcriptionFailed(_ error: Error) -> String {
            String(localized: "error.ai.transcriptionFailed.\(error.localizedDescription)")
        }
        static func summaryGenerationFailed(_ error: Error) -> String {
            String(localized: "error.ai.summaryGenerationFailed.\(error.localizedDescription)")
        }
        static func processingFailed(_ reason: String) -> String {
            String(localized: "error.ai.processingFailed.\(reason)")
        }
        static func insufficientMemory(_ required: UInt64, _ available: UInt64) -> String {
            String(localized: "error.ai.insufficientMemory.\(required / 1_048_576).\(available / 1_048_576)")
        }
        static func processingTimeout(_ duration: TimeInterval) -> String {
            String(localized: "error.ai.processingTimeout.\(Int(duration))")
        }
        static func invalidConfiguration(_ reason: String) -> String {
            String(localized: "error.ai.invalidConfiguration.\(reason)")
        }
    }

    enum Storage {
        static func pathInvalid(_ reason: String) -> String {
            String(localized: "error.storage.pathInvalid.\(reason)")
        }
        static func pathNotAccessible(_ path: String) -> String {
            String(localized: "error.storage.pathNotAccessible.\(path)")
        }
        static func diskInsufficient() -> String {
            String(localized: "error.storage.diskInsufficient")
        }
        static func fileCorrupted(_ filename: String) -> String {
            String(localized: "error.storage.fileCorrupted.\(filename)")
        }
        static func fileNotFound(_ path: String) -> String {
            String(localized: "error.storage.fileNotFound.\(path)")
        }
        static func metadataLoadFailed(_ error: Error) -> String {
            String(localized: "error.storage.metadataLoadFailed.\(error.localizedDescription)")
        }
        static func metadataSaveFailed(_ error: Error) -> String {
            String(localized: "error.storage.metadataSaveFailed.\(error.localizedDescription)")
        }
        static func directoryCreationFailed(_ path: String) -> String {
            String(localized: "error.storage.directoryCreationFailed.\(path)")
        }
    }

    enum Network {
        static func offline() -> String {
            String(localized: "error.network.offline")
        }
        static func timeout(_ duration: TimeInterval) -> String {
            String(localized: "error.network.timeout.\(Int(duration))")
        }
        static func serverError(_ code: Int, _ message: String) -> String {
            String(localized: "error.network.serverError.\(code).\(message)")
        }
        static func apiKeyInvalid() -> String {
            String(localized: "error.network.apiKeyInvalid")
        }
        static func apiKeyVerificationFailed(_ error: Error) -> String {
            String(localized: "error.network.apiKeyVerificationFailed.\(error.localizedDescription)")
        }
        static func rateLimitExceeded(_ retryAfter: TimeInterval?) -> String {
            if let retryAfter = retryAfter {
                return String(localized: "error.network.rateLimitExceededWithRetry.\(Int(retryAfter))")
            }
            return String(localized: "error.network.rateLimitExceeded")
        }
        static func invalidResponseFormat(_ reason: String) -> String {
            String(localized: "error.network.invalidResponseFormat.\(reason)")
        }
        static func requestFailed(_ error: Error) -> String {
            String(localized: "error.network.requestFailed.\(error.localizedDescription)")
        }
    }

    enum Permission {
        static func screenRecordingDenied() -> String {
            String(localized: "error.permission.screenRecordingDenied")
        }
        static func microphoneDenied() -> String {
            String(localized: "error.permission.microphoneDenied")
        }
        static func fileSystemAccessDenied(_ path: String) -> String {
            String(localized: "error.permission.fileSystemAccessDenied.\(path)")
        }
        static func accessibilityDenied() -> String {
            String(localized: "error.permission.accessibilityDenied")
        }
        static func requestFailed(_ type: MeetingSonarError.PermissionType) -> String {
            String(localized: "error.permission.requestFailed.\(type.rawValue)")
        }
    }

    enum Configuration {
        static func invalidSetting(_ key: String, _ reason: String) -> String {
            String(localized: "error.configuration.invalidSetting.\(key).\(reason)")
        }
        static func missingRequiredSetting(_ key: String) -> String {
            String(localized: "error.configuration.missingRequiredSetting.\(key)")
        }
        static func settingsCorrupted(_ error: Error) -> String {
            String(localized: "error.configuration.settingsCorrupted.\(error.localizedDescription)")
        }
        static func incompatibleConfiguration(_ reason: String) -> String {
            String(localized: "error.configuration.incompatibleConfiguration.\(reason)")
        }
    }

    enum Recovery {
        static let stopCurrentRecording = String(localized: "recovery.stopCurrentRecording")
        static let startNewRecording = String(localized: "recovery.startNewRecording")
        static let grantMicrophonePermission = String(localized: "recovery.grantMicrophonePermission")
        static let grantScreenRecordingPermission = String(localized: "recovery.grantScreenRecordingPermission")
        static func downloadModel(_ modelName: String) -> String {
            return String(localized: "recovery.downloadModel.\(modelName)")
        }
        static let freeDiskSpace = String(localized: "recovery.freeDiskSpace")
        static let checkNetworkConnection = String(localized: "recovery.checkNetworkConnection")
        static let enableScreenRecording = String(localized: "recovery.enableScreenRecording")
        static let enableMicrophone = String(localized: "recovery.enableMicrophone")
        static let enableAccessibility = String(localized: "recovery.enableAccessibility")
        static let contactSupport = String(localized: "recovery.contactSupport")
    }

    // Message generators
    static func recording(_ error: MeetingSonarError.RecordingError) -> String {
        switch error {
        case .alreadyRecording:
            return Recording.alreadyRecording()
        case .notRecording:
            return Recording.notRecording()
        case .permissionDenied(let type):
            return Recording.permissionDenied(type)
        case .audioDeviceFailed(let error):
            return Recording.audioDeviceFailed(error)
        case .captureFailed(let reason):
            return Recording.captureFailed(reason)
        case .mixerError(let error):
            return Recording.mixerError(error)
        case .fileWriterError(let error):
            return Recording.fileWriterError(error)
        case .maxDurationExceeded(let maxSeconds):
            return Recording.maxDurationExceeded(maxSeconds)
        case .interrupted(let reason):
            return Recording.interrupted(reason)
        }
    }

    static func aiProcessing(_ error: MeetingSonarError.AIError) -> String {
        switch error {
        case .modelNotFound(let type):
            return AI.modelNotFound(type.displayName)
        case .modelDownloadFailed(let type, _):
            return AI.modelDownloadFailed(type.displayName)
        case .modelLoadFailed(let type, _):
            return AI.modelLoadFailed(type.displayName)
        case .transcriptionFailed(let error):
            return AI.transcriptionFailed(error)
        case .summaryGenerationFailed(let error):
            return AI.summaryGenerationFailed(error)
        case .modelUnavailable(let type):
            return AI.modelNotFound(type.displayName)
        case .insufficientMemory(let required, let available):
            return AI.insufficientMemory(required, available)
        case .processingTimeout(let duration):
            return AI.processingTimeout(duration)
        case .invalidConfiguration(let reason):
            return AI.invalidConfiguration(reason)
        }
    }

    static func storage(_ error: MeetingSonarError.StorageError) -> String {
        switch error {
        case .pathInvalid(let reason):
            return Storage.pathInvalid(reason)
        case .pathNotAccessible(let path):
            return Storage.pathNotAccessible(path)
        case .diskInsufficient:
            return Storage.diskInsufficient()
        case .fileCorrupted(let filename, _):
            return Storage.fileCorrupted(filename)
        case .fileNotFound(let path):
            return Storage.fileNotFound(path)
        case .metadataLoadFailed(let error):
            return Storage.metadataLoadFailed(error)
        case .metadataSaveFailed(let error):
            return Storage.metadataSaveFailed(error)
        case .directoryCreationFailed(let path, _):
            return Storage.directoryCreationFailed(path)
        }
    }

    static func network(_ error: MeetingSonarError.NetworkError) -> String {
        switch error {
        case .offline:
            return Network.offline()
        case .timeout(let duration):
            return Network.timeout(duration)
        case .serverError(let code, let message):
            return Network.serverError(code, message)
        case .apiKeyInvalid:
            return Network.apiKeyInvalid()
        case .apiKeyVerificationFailed(let error):
            return Network.apiKeyVerificationFailed(error)
        case .rateLimitExceeded(let retryAfter):
            return Network.rateLimitExceeded(retryAfter)
        case .invalidResponseFormat(let reason):
            return Network.invalidResponseFormat(reason)
        case .requestFailed(let error):
            return Network.requestFailed(error)
        }
    }

    static func permission(_ error: MeetingSonarError.PermissionError) -> String {
        switch error {
        case .screenRecordingDenied:
            return Permission.screenRecordingDenied()
        case .microphoneDenied:
            return Permission.microphoneDenied()
        case .fileSystemAccessDenied(let path):
            return Permission.fileSystemAccessDenied(path)
        case .accessibilityDenied:
            return Permission.accessibilityDenied()
        case .requestFailed(let type, _):
            return Permission.requestFailed(type)
        }
    }

    static func configuration(_ error: MeetingSonarError.ConfigurationError) -> String {
        switch error {
        case .invalidSetting(let key, _, let reason):
            return Configuration.invalidSetting(key, reason)
        case .missingRequiredSetting(let key):
            return Configuration.missingRequiredSetting(key)
        case .settingsCorrupted(let error):
            return Configuration.settingsCorrupted(error)
        case .incompatibleConfiguration(let reason):
            return Configuration.incompatibleConfiguration(reason)
        }
    }

    static func unknown(_ error: Error) -> String {
        String(localized: "error.unknown.\(error.localizedDescription)")
    }
}

// MARK: - Error Conversion Extensions

extension Error {
    /// Convert any Error to MeetingSonarError
    ///
    /// If the error is already a MeetingSonarError, it is returned as-is.
    /// Otherwise, it is wrapped in `.unknown`.
    func asMeetingSonarError() -> MeetingSonarError {
        if let mse = self as? MeetingSonarError {
            return mse
        }
        return .unknown(underlying: self)
    }

    /// Check if this Error is a specific MeetingSonarError case
    ///
    /// ## Usage
    /// ```swift
    /// if error.isMeetingSonarError(.recording(.alreadyRecording)) {
    ///     // Handle already recording case
    /// }
    /// ```
    ///
    /// ## Note
    /// Since MeetingSonarError has associated values, this uses pattern matching
    /// to check if the error is of the same case, regardless of associated values.
    func isMeetingSonarError(_ errorCase: MeetingSonarError) -> Bool {
        guard let mse = self as? MeetingSonarError else {
            return false
        }

        // Pattern match on the top-level case
        switch (mse, errorCase) {
        case (.recording, .recording),
             (.aiProcessing, .aiProcessing),
             (.storage, .storage),
             (.network, .network),
             (.permission, .permission),
             (.configuration, .configuration),
             (.unknown, .unknown):
            return true
        default:
            return false
        }
    }

    /// Check if this Error is a MeetingSonarError and matches a predicate
    func isMeetingSonarError(where predicate: (MeetingSonarError) -> Bool) -> Bool {
        guard let mse = self as? MeetingSonarError else {
            return false
        }
        return predicate(mse)
    }
}

// MARK: - Convenience Initializers

extension MeetingSonarError {
    /// Create a recording error for permission denied
    static func permissionDenied(_ type: PermissionType) -> MeetingSonarError {
        .recording(.permissionDenied(type))
    }

    /// Create an AI processing error for model not found
    static func modelNotFound(_ type: ModelType) -> MeetingSonarError {
        .aiProcessing(.modelNotFound(type))
    }

    /// Create a storage error for invalid path
    static func invalidPath(reason: String) -> MeetingSonarError {
        .storage(.pathInvalid(reason: reason))
    }

    /// Create a network error for offline
    static func offline() -> MeetingSonarError {
        .network(.offline)
    }
}
