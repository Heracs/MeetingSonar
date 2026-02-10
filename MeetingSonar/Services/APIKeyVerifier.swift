//
//  APIKeyVerifier.swift
//  MeetingSonar
//
//  F-9.3: API Key verification logic for online service providers
//

import Foundation

/// Verification result
enum VerificationResult {
    case success
    case failure(String)
}

/// Service for verifying API Keys
@MainActor
final class APIKeyVerifier {
    
    static let shared = APIKeyVerifier()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Verify API Key by making a test request to the service provider
    /// - Parameters:
    ///   - config: Model configuration to verify
    ///   - apiKey: API Key to verify
    ///   - type: Model type (ASR/LLM)
    /// - Returns: Verification result
    func verify(config: OnlineModelConfig, apiKey: String, type: OnlineModelType) async -> VerificationResult {
        
        LoggerService.shared.log(
            category: .general,
            message: "[APIKeyVerifier] Verifying \(config.provider.displayName) \(type.rawValue) model"
        )
        
        // Construct URL
        let baseURL = config.baseURL
        let path = config.provider.verificationPath(for: type)
        
        guard let url = URL(string: baseURL + path) else {
            return .failure("无效的 Base URL")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization header (provider-specific)
        switch config.provider {
        case .zhipu:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .deepseek:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .aliyun:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Create minimal test payload
        let testPayload = createTestPayload(for: config, type: type)
        request.httpBody = testPayload
        
        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("无效的响应")
            }
            
            // Check status code
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                LoggerService.shared.log(
                    category: .general,
                    message: "[APIKeyVerifier] Verification successful"
                )
                return .success
            } else {
                // Parse error message
                let errorMessage = parseErrorMessage(from: data, provider: config.provider)
                return .failure("验证失败 (\(httpResponse.statusCode)): \(errorMessage)")
            }
            
        } catch {
            LoggerService.shared.log(
                category: .error,
                message: "[APIKeyVerifier] Verification error: \(error.localizedDescription)"
            )
            return .failure("网络错误: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func createTestPayload(for config: OnlineModelConfig, type: OnlineModelType) -> Data? {
        var payload: [String: Any] = [:]
        
        switch (config.provider, type) {
        case (.zhipu, .llm), (.deepseek, .llm):
            // Minimal LLM completion request
            payload = [
                "model": config.modelName,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ],
                "max_tokens": 1
            ]
            
        case (.aliyun, .llm):
            // Qwen LLM format
            payload = [
                "model": config.modelName,
                "input": [
                    "messages": [
                        ["role": "user", "content": "Hi"]
                    ]
                ],
                "parameters": [
                    "max_tokens": 1
                ]
            ]
            
        case (_, .asr):
            // For ASR, we'll use a minimal payload
            // Note: Real ASR verification would require an audio file
            // For now, we'll just test authentication
            payload = [
                "model": config.modelName
            ]
        }
        
        return try? JSONSerialization.data(withJSONObject: payload)
    }
    
    private func parseErrorMessage(from data: Data, provider: OnlineServiceProvider) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "未知错误"
        }
        
        // Try common error message fields
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        
        if let message = json["message"] as? String {
            return message
        }
        
        if let errorMsg = json["error_msg"] as? String {
            return errorMsg
        }
        
        return "未知错误"
    }
}
