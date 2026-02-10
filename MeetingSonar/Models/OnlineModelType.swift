//
//  OnlineModelType.swift
//  MeetingSonar
//
//  F-9.3: Online model type enumeration
//

import Foundation

/// Type of online AI model
enum OnlineModelType: String, Codable, Sendable {
    case asr = "asr"
    case llm = "llm"

    var displayName: String {
        switch self {
        case .asr:
            return String(localized: "onlineModelType.asr")
        case .llm:
            return String(localized: "onlineModelType.llm")
        }
    }
}
