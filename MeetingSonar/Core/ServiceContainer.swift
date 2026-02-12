//
//  ServiceContainer.swift
//  MeetingSonar
//
//  Dependency injection container for application services.
//  Provides protocol-based access to services while maintaining
//  backward compatibility with existing singleton pattern.
//
//  Design Principles:
//  - Single entry point for all service dependencies
//  - Protocol-based abstraction for testability
//  - Lazy initialization for performance
//  - Thread-safe access
//  - Support for test doubles (mocks/stubs)
//

import Foundation

// MARK: - Type Aliases

/// Typealias for smart detection mode
typealias SmartDetectionMode = SettingsManager.SmartDetectionMode

/// Dependency injection container for application services
///
/// ## Purpose
/// - Provides centralized access to all application services
/// - Enables protocol-based dependency injection for testing
/// - Maintains backward compatibility with singleton access
///
/// ## Usage
/// ```swift
/// // Production code - use protocol-based access
/// let recorder = ServiceContainer.shared.recordingService
///
/// // Test code - inject mock
/// class MockRecorder: RecordingServiceProtocol {
///     var state: RecordingState = .idle
///     func startRecording(trigger:) async throws { }
/// }
/// ServiceContainer.shared.recordingService = MockRecorder()
/// ```
@MainActor
final class ServiceContainer {

    // MARK: - Singleton

    static let shared = ServiceContainer()

    // MARK: - Protocol-Based Service Access

    /// Recording service (protocol-based access)
    var recordingService: any RecordingServiceProtocol {
        get { _recordingService ?? RecordingService.shared }
        set { _recordingService = newValue }
    }

    /// Detection service (protocol-based access)
    var detectionService: any DetectionServiceProtocol {
        get { _detectionService ?? DetectionService.shared }
        set { _detectionService = newValue }
    }

    /// Metadata manager (protocol-based access)
    var metadataManager: any MetadataManagerProtocol {
        get { _metadataManager ?? MetadataManager.shared }
        set { _metadataManager = newValue }
    }

    /// Settings manager (protocol-based access)
    var settingsManager: any SettingsManagerProtocol {
        get { _settingsManager ?? SettingsManager.shared }
        set { _settingsManager = newValue }
    }

    /// AI processing coordinator (protocol-based access)
    var aiProcessingCoordinator: any AIProcessingCoordinatorProtocol {
        get { _aiProcessingCoordinator ?? AIProcessingCoordinator.shared }
        set { _aiProcessingCoordinator = newValue }
    }

    // MARK: - Test Mode Support

    /// Mock recording service (for testing)
    private var _recordingService: (any RecordingServiceProtocol)?

    /// Mock detection service (for testing)
    private var _detectionService: (any DetectionServiceProtocol)?

    /// Mock metadata manager (for testing)
    private var _metadataManager: (any MetadataManagerProtocol)?

    /// Mock settings manager (for testing)
    private var _settingsManager: (any SettingsManagerProtocol)?

    /// Mock AI processing coordinator (for testing)
    private var _aiProcessingCoordinator: (any AIProcessingCoordinatorProtocol)?

    /// Test mode flag
    private let testMode: Bool

    /// Initialization for production or test mode
    ///
    /// - Parameter testMode: If true, allows service replacement for testing
    private init(testMode: Bool = false) {
        self.testMode = testMode
    }

    // MARK: - Factory Methods

    /// Creates a container configured for production environment
    ///
    /// - Returns: A new ServiceContainer instance with production configuration
    static func createProductionContainer() -> ServiceContainer {
        return ServiceContainer(testMode: false)
    }

    /// Creates a container configured for testing
    ///
    /// - Returns: A new ServiceContainer instance with test mode enabled
    /// - Important: Only use this in unit tests
    static func createTestContainer() -> ServiceContainer {
        return ServiceContainer(testMode: true)
    }

    // MARK: - Service Replacement (Test Only)

    /// Sets a mock recording service (test mode only)
    ///
    /// - Parameter service: The mock recording service
    /// - Precondition: testMode must be true
    func setRecordingService(_ service: any RecordingServiceProtocol) {
        precondition(testMode, "Service replacement only allowed in test mode")
        _recordingService = service
    }

    /// Sets a mock detection service (test mode only)
    ///
    /// - Parameter service: The mock detection service
    /// - Precondition: testMode must be true
    func setDetectionService(_ service: any DetectionServiceProtocol) {
        precondition(testMode, "Service replacement only allowed in test mode")
        _detectionService = service
    }

    /// Sets a mock metadata manager (test mode only)
    ///
    /// - Parameter service: The mock metadata manager
    /// - Precondition: testMode must be true
    func setMetadataManager(_ service: any MetadataManagerProtocol) {
        precondition(testMode, "Service replacement only allowed in test mode")
        _metadataManager = service
    }

    /// Sets a mock settings manager (test mode only)
    ///
    /// - Parameter service: The mock settings manager
    /// - Precondition: testMode must be true
    func setSettingsManager(_ service: any SettingsManagerProtocol) {
        precondition(testMode, "Service replacement only allowed in test mode")
        _settingsManager = service
    }

    /// Sets a mock AI processing coordinator (test mode only)
    ///
    /// - Parameter service: The mock AI processing coordinator
    /// - Precondition: testMode must be true
    func setAIProcessingCoordinator(_ service: any AIProcessingCoordinatorProtocol) {
        precondition(testMode, "Service replacement only allowed in test mode")
        _aiProcessingCoordinator = service
    }

    // MARK: - Convenience Accessors

    /// Shortcut to access recording service via protocol
    var recorder: RecordingServiceProtocol {
        return recordingService
    }

    /// Shortcut to access detection service via protocol
    var detector: DetectionServiceProtocol {
        return detectionService
    }

    /// Shortcut to access metadata manager via protocol
    var metadata: MetadataManagerProtocol {
        return metadataManager
    }

    /// Shortcut to access settings manager via protocol
    var settings: SettingsManagerProtocol {
        return settingsManager
    }

    // MARK: - Validation

    /// Validates that all required services are available
    func validateServices() throws {
        // Check critical services
        if recordingService.recordingState == .idle {
            // Service is in valid state
        }

        if settingsManager.savePath.path.isEmpty {
            throw MeetingSonarError.configuration(
                .missingRequiredSetting(key: "savePath")
            )
        }
    }

    /// Resets container state (test mode only)
    func reset() {
        precondition(testMode, "Reset only allowed in test mode")
        _recordingService = nil
        _detectionService = nil
        _metadataManager = nil
        _settingsManager = nil
        _aiProcessingCoordinator = nil
    }
}

// MARK: - SettingsManager Protocol

/// Protocol defining settings management capabilities
protocol SettingsManagerProtocol: AnyObject {

    /// Directory path where recordings are saved
    var savePath: URL { get set }

    /// Output audio format (M4A or MP3)
    var audioFormat: AudioFormat { get set }

    /// Audio encoding quality
    var audioQuality: AudioQuality { get set }

    /// Whether to include system audio
    var includeSystemAudio: Bool { get set }

    /// Whether to include microphone input
    var includeMicrophone: Bool { get set }

    /// Whether smart detection is enabled
    var smartDetectionEnabled: Bool { get set }

    /// Mode for smart detection
    var smartDetectionMode: SmartDetectionMode { get set }

    /// Selected ASR model ID
    var selectedUnifiedASRId: String { get set }

    /// Selected LLM model ID
    var selectedUnifiedLLMId: String { get set }

    /// Generate filename for a new recording
    func generateFilename(appName: String?) -> String

    /// Get full file URL for a new recording
    func generateFileURL(appName: String?) -> URL
}

// MARK: - MetadataManager Protocol

/// Protocol defining metadata management capabilities
protocol MetadataManagerProtocol: AnyObject {

    /// All recordings metadata
    var recordings: [MeetingMeta] { get set }

    /// Loads metadata from disk asynchronously
    func load() async

    /// Adds a new recording metadata
    func add(_ meta: MeetingMeta) async

    /// Updates an existing recording metadata
    func update(_ meta: MeetingMeta) async

    /// Gets recording metadata by ID
    func get(id: UUID) -> MeetingMeta?

    /// Deletes recording metadata asynchronously
    func delete(id: UUID) async throws

    /// Scans and migrates existing files asynchronously
    func scanAndMigrate() async

    /// Repairs recordings with zero duration asynchronously
    func repairZeroDurations() async

    /// Renames a recording
    func rename(id: UUID, newTitle: String) async
}

// MARK: - AIProcessingCoordinator Protocol

/// Protocol defining AI processing coordination capabilities
protocol AIProcessingCoordinatorProtocol: AnyObject, ObservableObject {

    // MARK: - Published State
    var isProcessing: Bool { get }
    var currentStage: AIProcessingCoordinator.ProcessingStage { get }
    var progress: Double { get }
    var lastError: Error? { get }

    // MARK: - Main Processing Pipeline
    func process(audioURL: URL, meetingID: UUID) async
    func processASROnly(audioURL: URL, meetingID: UUID) async -> (text: String?, transcriptURL: URL?)
    func processASROnlyWithVersion(audioURL: URL, meetingID: UUID) async -> (
        text: String?,
        url: URL?,
        version: TranscriptVersion?
    )

    // MARK: - Legacy API (Compatibility)
    func transcribeOnly(audioURL: URL, meetingID: UUID?) async throws -> (String, URL, UUID)
    func generateSummaryOnly(
        transcriptText: String,
        audioURL: URL,
        sourceTranscriptId: UUID,
        meetingID: UUID?
    ) async throws -> (String, URL, UUID)
}

// MARK: - Convenience Extensions

extension ServiceContainer {

    /// Shortcut to access AI processing coordinator via protocol
    var aiCoordinator: any AIProcessingCoordinatorProtocol {
        return aiProcessingCoordinator
    }

    /// Validates and prepares all services for operation
    ///
    /// - Returns: true if all services are ready, false otherwise
    @discardableResult
    func prepareServices() -> Bool {
        return ErrorHandler.tryOperation {
            try validateServices()
        } recovery: { error in
            LoggerService.shared.log(
                category: .general,
                level: .error,
                message: "[ServiceContainer] Service validation failed: \(error.errorDescription ?? "Unknown")"
            )
        }
    }

    /// Configures the container with all mock services (test mode only)
    ///
    /// - Parameters:
    ///   - recordingService: Mock recording service
    ///   - detectionService: Mock detection service
    ///   - metadataManager: Mock metadata manager
    ///   - settingsManager: Mock settings manager
    ///   - aiCoordinator: Mock AI processing coordinator
    func configureTestServices(
        recordingService: (any RecordingServiceProtocol)? = nil,
        detectionService: (any DetectionServiceProtocol)? = nil,
        metadataManager: (any MetadataManagerProtocol)? = nil,
        settingsManager: (any SettingsManagerProtocol)? = nil,
        aiCoordinator: (any AIProcessingCoordinatorProtocol)? = nil
    ) {
        precondition(testMode, "Test service configuration only allowed in test mode")

        if let service = recordingService {
            _recordingService = service
        }
        if let service = detectionService {
            _detectionService = service
        }
        if let service = metadataManager {
            _metadataManager = service
        }
        if let service = settingsManager {
            _settingsManager = service
        }
        if let service = aiCoordinator {
            _aiProcessingCoordinator = service
        }
    }
}
