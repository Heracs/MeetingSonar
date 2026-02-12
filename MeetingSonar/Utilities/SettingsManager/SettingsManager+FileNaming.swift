import Foundation

extension SettingsManager {

    // MARK: - File Naming

    /// Generate filename for a new recording
    /// - Parameter appName: Name of the application being recorded (optional)
    /// - Returns: Filename in format `{AppName}_{YYYY-MM-DD}_{HH-mm-ss}.{ext}`
    func generateFilename(appName: String? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let name = appName ?? "Recording"
        let sanitizedName = name.replacingOccurrences(of: " ", with: "_")

        return "\(sanitizedName)_\(timestamp).\(audioFormat.fileExtension)"
    }

    /// Get full file URL for a new recording
    ///
    /// - Parameter appName: Optional application name for the filename
    /// - Returns: A validated URL within the configured save path
    func generateFileURL(appName: String? = nil) -> URL {
        let filename = generateFilename(appName: appName)

        do {
            return try PathValidator.safeAppendingPathComponent(to: savePath, component: filename)
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "[Settings] Failed to generate file URL: \(error.localizedDescription)")
            // Fallback to unsafe construction
            return savePath.appendingPathComponent(filename)
        }
    }
}
