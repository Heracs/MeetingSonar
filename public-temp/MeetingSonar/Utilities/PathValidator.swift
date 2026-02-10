//
//  PathValidator.swift
//  MeetingSonar
//
//  Security: Path validation utilities to prevent path traversal attacks
//

import Foundation

/// Utilities for validating and sanitizing file paths
///
/// ## Security Features
/// - Path traversal prevention
/// - Directory boundary validation
/// - Safe path construction
/// - File system sandbox compliance
enum PathValidator {

    // MARK: - Validation Errors

    /// Errors that can occur during path validation
    enum ValidationError: LocalizedError {
        case pathTraversalAttempt(suspiciousPath: String)
        case outsideAllowedRoot(allowedRoot: URL, actualPath: URL)
        case invalidPathCharacter(path: String)
        case pathTooLong(path: String)
        case fileNotFound(path: String)

        var errorDescription: String? {
            switch self {
            case .pathTraversalAttempt(let path):
                return "Path traversal attempt detected: \(path)"
            case .outsideAllowedRoot(let root, let actual):
                return "Path is outside allowed root: \(actual.path). Root: \(root.path)"
            case .invalidPathCharacter(let path):
                return "Invalid path characters: \(path)"
            case .pathTooLong(let path):
                return "Path is too long: \(path)"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            }
        }
    }

    // MARK: - Path Traversal Detection

    /// Detects path traversal attempts in a file path string
    ///
    /// - Parameter pathString: The file path string to validate
    /// - Returns: True if the path contains suspicious patterns
    private static func containsPathTraversal(_ pathString: String) -> Bool {
        // Check for common path traversal patterns
        let traversalPatterns = [
            "../",
            "..\\",  // Windows-style
            "~/../", // Escaping home directory
            "%2e%2e", // URL encoded ".."
            "%252e%252e", // Double encoded ".."
            "%c0%ae", // Various encoding attacks
            "%af", // URL encoding attacks
            "%5c", // Backslash encoding
        ]

        for pattern in traversalPatterns {
            if localizedCaseContains(pathString, pattern) {
                return true
            }
        }

        return false
    }

    // MARK: - Validation

    /// Validates a file path string for security issues
    ///
    /// - Parameter pathString: The file path string to validate
    /// - Throws: ValidationError if validation fails
    /// - Returns: The sanitized path if valid
    static func validatePathString(_ pathString: String) throws -> String {
        // Check for path traversal
        if containsPathTraversal(pathString) {
            throw ValidationError.pathTraversalAttempt(suspiciousPath: pathString)
        }

        // Check for invalid characters (null bytes, control characters)
        if pathString.contains("\0") || pathString.contains("\r") || pathString.contains("\n") {
            throw ValidationError.invalidPathCharacter(path: pathString)
        }

        // Check path length
        if pathString.count > 1024 { // PATH_MAX is typically 1024
            throw ValidationError.pathTooLong(path: pathString)
        }

        return pathString
    }

    /// Validates that a URL is within allowed directory boundaries
    ///
    /// - Parameters:
    ///   - url: The URL to validate
    ///   - allowedRoot: The root directory that bounds the allowed path space
    /// - Throws: ValidationError if the URL is outside the allowed root
    /// - Returns: True if validation passes
    @discardableResult
    static func validateURL(_ url: URL, within allowedRoot: URL) throws -> Bool {
        // Standardize both paths for comparison
        let standardizedURL = url.standardizedFileURL
        let standardizedRoot = allowedRoot.standardizedFileURL

        // Check if url starts with root
        guard standardizedURL.path.hasPrefix(standardizedRoot.path) else {
            throw ValidationError.outsideAllowedRoot(allowedRoot: standardizedRoot, actualPath: standardizedURL)
        }

        return true
    }

    /// Validates that a file exists at the given URL
    ///
    /// - Parameter url: The file URL to check
    /// - Throws: ValidationError if file doesn't exist
    static func validateFileExists(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.fileNotFound(path: url.path)
        }
    }

    /// Safely constructs a URL by appending path components
    ///
    /// - Parameters:
    ///   - base: The base URL
    ///   - component: The path component to append
    /// - Returns: A safe URL constructed from the components
    /// - Throws: ValidationError if component contains invalid characters
    static func safeAppendingPathComponent(to base: URL, component: String) throws -> URL {
        let validatedComponent = try validatePathString(component)

        // Additional check: ensure component doesn't contain path separators that could escape
        if validatedComponent.contains("/") || validatedComponent.contains("\\") {
            throw ValidationError.invalidPathCharacter(path: component)
        }

        return base.appendingPathComponent(validatedComponent)
    }

    /// Validates that a path is within the application's data directory
    ///
    /// - Parameter url: The URL to validate
    /// - Throws: ValidationError if the URL is outside the app's data directory
    static func validateAppDataPath(_ url: URL) throws {
        let appDataRoot = PathManager.shared.rootDataURL
        try validateURL(url, within: appDataRoot)
    }

    // MARK: - Helpers

    /// Case-insensitive string comparison for security checks
    private static func localizedCaseContains(_ text: String, _ pattern: String) -> Bool {
        return text.range(of: pattern, options: .caseInsensitive) != nil
    }
}
