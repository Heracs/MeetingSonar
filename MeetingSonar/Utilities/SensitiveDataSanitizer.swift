//
//  SensitiveDataSanitizer.swift
//  MeetingSonar
//
//  Security: Utilities for sanitizing sensitive data before logging
//

import Foundation

/// Utilities for sanitizing sensitive data before logging
///
/// ## Security Features
/// - URL sanitization (removes query parameters with potential secrets)
/// - API key masking
/// - Request/response body redaction
/// - Sensitive header filtering
enum SensitiveDataSanitizer {

    // MARK: - URL Sanitization

    /// Sanitizes a URL string for logging by removing potentially sensitive components
    ///
    /// - Parameter urlString: The URL string to sanitize
    /// - Returns: A sanitized URL safe for logging
    ///
    /// ## What Gets Redacted
    /// - Query parameters (common names for API keys, tokens, passwords)
    /// - Fragments (can contain sensitive data)
    /// - User info (username:password)
    ///
    /// ## Example
    /// ```
    /// "https://api.example.com/v1/endpoint?api_key=secret123&user=john"
    /// // Becomes: "https://api.example.com/v1/endpoint?api_key=***"
    /// ```
    static func sanitizeURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            // If URL parsing fails, return a truncated version
            return urlString.prefix(200).appending("...")
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil  // Remove all query parameters
        components?.fragment = nil  // Remove fragment
        components?.user = nil  // Remove username
        components?.password = nil  // Remove password

        if let sanitized = components?.url?.absoluteString {
            return sanitized
        }

        // Fallback: just return scheme and host
        if let scheme = url.scheme, let host = url.host {
            return "\(scheme)://\(host)/..."
        }

        return urlString.prefix(200).appending("...")
    }

    /// Sanitizes a URL for logging
    ///
    /// - Parameter url: The URL to sanitize
    /// - Returns: A sanitized URL safe for logging
    static func sanitizeURL(_ url: URL) -> String {
        return sanitizeURL(url.absoluteString)
    }

    // MARK: - API Key Masking

    /// Masks an API key for logging
    ///
    /// - Parameter apiKey: The API key to mask
    /// - Returns: A masked version showing only first 8 and last 4 characters
    ///
    /// ## Example
    /// ```
    /// "sk-1234567890abcdef1234"
    /// // Becomes: "sk-12345...1234"
    /// ```
    static func maskAPIKey(_ apiKey: String) -> String {
        guard apiKey.count > 12 else {
            return String(repeating: "*", count: min(apiKey.count, 12))
        }

        let prefix = String(apiKey.prefix(8))
        let suffix = String(apiKey.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    /// Masks a bearer token for logging
    ///
    /// - Parameter token: The bearer token to mask
    /// - Returns: A masked version
    static func maskBearerToken(_ token: String) -> String {
        return maskAPIKey(token)
    }

    // MARK: - Request/Response Body Redaction

    /// Returns a safe representation of a request body for logging
    ///
    /// - Parameters:
    ///   - data: The request body data
    ///   - maxLength: Maximum length to return (default: 200)
    /// - Returns: A safe string representation for logging
    ///
    /// ## Behavior
    /// - Returns content length instead of content for potentially sensitive data
    /// - Truncates at maxLength if content is logged
    static func sanitizeRequestBody(_ data: Data, maxLength: Int = 200) -> String {
        let byteCount = data.count

        // For small data, return a preview
        if byteCount <= 100, let preview = String(data: data, encoding: .utf8) {
            return "\(preview.prefix(maxLength))... (\(byteCount) bytes)"
        }

        // For larger data, just return size
        return "Request body: \(byteCount) bytes"
    }

    /// Returns a safe representation of a response body for logging
    ///
    /// - Parameters:
    ///   - data: The response body data
    ///   - maxLength: Maximum length to return (default: 200)
    /// - Returns: A safe string representation for logging
    static func sanitizeResponseBody(_ data: Data, maxLength: Int = 200) -> String {
        let byteCount = data.count

        // Try to decode as JSON to check for sensitive fields
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var sanitized: [String: Any] = [:]

            // Redact known sensitive fields
            let sensitiveKeys = ["api_key", "apiKey", "token", "password", "secret", "key", "authorization", "credential"]

            for (key, value) in json {
                if sensitiveKeys.contains(key.lowercased()) {
                    sanitized[key] = "***"
                } else if let stringValue = value as? String {
                    sanitized[key] = String(stringValue.prefix(maxLength))
                } else {
                    sanitized[key] = value
                }
            }

            if let sanitizedData = try? JSONSerialization.data(withJSONObject: sanitized),
               let sanitizedStr = String(data: sanitizedData, encoding: .utf8) {
                return sanitizedStr.prefix(maxLength) + "..."
            }
        }

        // Fallback: just return size or truncated preview
        if byteCount <= 500, let preview = String(data: data, encoding: .utf8) {
            return preview.prefix(maxLength) + "... (\(byteCount) bytes)"
        }

        return "Response body: \(byteCount) bytes"
    }

    // MARK: - Header Sanitization

    /// Sanitizes HTTP headers for logging
    ///
    /// - Parameter headers: The HTTP headers dictionary
    /// - Returns: A sanitized dictionary for logging
    ///
    /// ## Redacted Headers
    /// - Authorization
    /// - Proxy-Authorization
    /// - Cookie
    /// - Set-Cookie
    /// - X-API-Key
    /// - X-Auth-Token
    static func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]

        let sensitiveHeaders = [
            "authorization",
            "proxy-authorization",
            "cookie",
            "set-cookie",
            "x-api-key",
            "x-auth-token",
            "x-csrf-token",
            "xsrf-token"
        ]

        for (key, value) in headers {
            if sensitiveHeaders.contains(key.lowercased()) {
                sanitized[key] = "***"
            } else {
                sanitized[key] = value
            }
        }

        return sanitized
    }

    // MARK: - Error Message Sanitization

    /// Sanitizes error messages for logging
    ///
    /// - Parameter errorMessage: The error message to sanitize
    /// - Returns: A sanitized version
    ///
    /// ## What Gets Redacted
    /// - API keys in error messages
    /// - Tokens in error messages
    /// - Passwords in error messages
    static func sanitizeErrorMessage(_ errorMessage: String) -> String {
        var sanitized = errorMessage

        // Redact common patterns
        let patterns = [
            ("api[_-]?key\\s*[=:]\\s*[\\w-]+", "api_key=***"),
            ("token\\s*[=:]\\s*[\\w.-]+", "token=***"),
            ("password\\s*[=:]\\s*\\S+", "password=***"),
            ("bearer\\s+[\\w.-]+", "Bearer ***"),
            ("sk-[\\w-]+", "sk-***"), // OpenAI API key pattern
        ]

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(sanitized.startIndex..., in: sanitized)
                sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: replacement)
            }
        }

        return sanitized
    }

    // MARK: - Path Sanitization

    /// Sanitizes a file path for logging
    ///
    /// - Parameter path: The file path to sanitize
    /// - Returns: A sanitized path (removes user directory for privacy)
    ///
    /// ## Example
    /// ```
    /// "/Users/username/Documents/MeetingSonar_Data/Recordings/recording.m4a"
    /// // Becomes: "~/Documents/MeetingSonar_Data/Recordings/recording.m4a"
    /// ```
    static func sanitizePath(_ path: String) -> String {
        // Replace user's home directory with ~
        if let home = FileManager.default.homeDirectoryForCurrentUser.path as String?,
           path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }

        return path
    }

    /// Sanitizes a URL file path for logging
    ///
    /// - Parameter url: The file URL to sanitize
    /// - Returns: A sanitized path string
    static func sanitizePath(_ url: URL) -> String {
        return sanitizePath(url.path)
    }
}
