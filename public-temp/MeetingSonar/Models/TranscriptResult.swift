//
//  TranscriptResult.swift
//  MeetingSonar
//
//  Result type for online ASR transcription
//

import Foundation

/// Result of online ASR transcription
struct TranscriptResult: Sendable {
    /// Individual transcription segments
    let segments: [Segment]

    /// Full transcribed text
    let fullText: String

    /// Audio duration in seconds
    let duration: TimeInterval

    /// Processing time in seconds
    let processingTime: TimeInterval

    /// Individual transcription segment
    struct Segment: Sendable {
        /// Start time in seconds
        let start: TimeInterval

        /// End time in seconds
        let end: TimeInterval

        /// Transcribed text for this segment
        let text: String
    }
}

// Note: SummaryResult is defined in LLMService.swift
