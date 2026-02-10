//
//  KeychainService.swift
//  MeetingSonar
//
//  F-9.3: Secure API Key storage using macOS Keychain
//

import Foundation
import Security

/// Errors that can occur during Keychain operations
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return String(format: String(localized: "error.keychain.saveFailed.%@"), "\(status)")
        case .loadFailed(let status):
            return String(format: String(localized: "error.keychain.loadFailed.%@"), "\(status)")
        case .deleteFailed(let status):
            return String(format: String(localized: "error.keychain.deleteFailed.%@"), "\(status)")
        case .invalidData:
            return String(localized: "error.keychain.invalidData")
        }
    }
}

/// Service for securely storing API Keys in macOS Keychain
@MainActor
final class KeychainService {
    
    static let shared = KeychainService()
    
    private let service = "com.meetingsonar.apikeys"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save API Key to Keychain
    /// - Parameters:
    ///   - key: API Key string
    ///   - modelID: Unique model identifier
    ///   - modelType: Type of model (ASR/LLM)
    /// - Throws: KeychainError if save fails
    func save(key: String, for modelID: String, modelType: OnlineModelType) throws {
        let account = "\(modelType.rawValue)_\(modelID)"
        
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Delete existing item first (if any)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        
        LoggerService.shared.log(
            category: .general,
            message: "[KeychainService] Saved API Key for \(account)"
        )
    }
    
    /// Load API Key from Keychain
    /// - Parameters:
    ///   - modelID: Unique model identifier
    ///   - modelType: Type of model (ASR/LLM)
    /// - Returns: API Key string, or nil if not found
    func load(for modelID: String, modelType: OnlineModelType) -> String? {
        let account = "\(modelType.rawValue)_\(modelID)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne

        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete API Key from Keychain
    /// - Parameters:
    ///   - modelID: Unique model identifier
    ///   - modelType: Type of model (ASR/LLM)
    /// - Throws: KeychainError if delete fails
    func delete(for modelID: String, modelType: OnlineModelType) throws {
        let account = "\(modelType.rawValue)_\(modelID)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        
        LoggerService.shared.log(
            category: .general,
            message: "[KeychainService] Deleted API Key for \(account)"
        )
    }
    
    /// Check if API Key exists in Keychain
    /// - Parameters:
    ///   - modelID: Unique model identifier
    ///   - modelType: Type of model (ASR/LLM)
    /// - Returns: True if key exists
    func hasKey(for modelID: String, modelType: OnlineModelType) -> Bool {
        return load(for: modelID, modelType: modelType) != nil
    }
}
