//
//  MeetingMeta.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import Foundation

/// Represents the metadata for a single meeting recording.
/// Corresponds to F-6.0 (Metadata Index).
struct MeetingMeta: Codable, Identifiable, Hashable, Sendable {
    
    // MARK: - Core Properties
    
    /// Unique identifier for the recording
    let id: UUID
    
    /// The actual filename on disk (including extension, e.g., "20240121-1400_Zoom.m4a")
    /// This is the key link to the physical file.
    let filename: String
    
    /// User-friendly title. Defaults to filename if not set.
    /// Can be renamed by user without changing the physical filename.
    var displayTitle: String?
    
    /// Source of audio (e.g., "Zoom", "Teams", "System Audio", "Mic")
    var source: String
    
    /// Time when recording started
    let startTime: Date
    
    /// Duration in seconds
    var duration: TimeInterval
    
    /// Current processing status
    var status: ProcessingStatus
    
    /// Versions of transcriptions
    var transcriptVersions: [TranscriptVersion] = []
    
    /// Versions of summaries
    var summaryVersions: [SummaryVersion] = []
    
    // MARK: - Enums
    
    enum ProcessingStatus: String, Codable, Sendable {
        case recording      // Actively recording
        case pending        // Recorded, waiting for processing
        case processing     // AI is currently processing this file
        case completed      // Processing finished
        case failed         // Processing failed
    }
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case id, filename, displayTitle, source, startTime, duration, status
        case transcriptVersions, summaryVersions
        // Removed legacy keys to avoid Encodable synthesis errors
    }
    
    enum LegacyKeys: String, CodingKey {
        case hasTranscript, hasSummary
    }
    
    // MARK: - Migration Init
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode core properties
        let _id = try container.decode(UUID.self, forKey: .id)
        let _filename = try container.decode(String.self, forKey: .filename)
        let _displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        let _source = try container.decode(String.self, forKey: .source)
        let _startTime = try container.decode(Date.self, forKey: .startTime)
        let _duration = try container.decode(TimeInterval.self, forKey: .duration)
        let _status = try container.decode(ProcessingStatus.self, forKey: .status)
        
        // Load new fields if present
        var _transcriptVersions = try container.decodeIfPresent([TranscriptVersion].self, forKey: .transcriptVersions) ?? []
        var _summaryVersions = try container.decodeIfPresent([SummaryVersion].self, forKey: .summaryVersions) ?? []
        
        // Legacy Migration
        // Try to decode using legacy keys
        if let legacyContainer = try? decoder.container(keyedBy: LegacyKeys.self) {
            let legacyHasTranscript = try legacyContainer.decodeIfPresent(Bool.self, forKey: .hasTranscript) ?? false
            let legacyHasSummary = try legacyContainer.decodeIfPresent(Bool.self, forKey: .hasSummary) ?? false

            if _transcriptVersions.isEmpty && legacyHasTranscript {
                // Assume the existing file corresponds to the default v1
                let v1 = TranscriptVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: _startTime.addingTimeInterval(_duration), // Approximate
                    modelInfo: ModelVersionInfo(
                        modelId: "legacy",
                        displayName: "Whisper (Legacy)",
                        provider: "Legacy"
                    ),
                    promptInfo: PromptVersionInfo(
                        promptId: "default",
                        promptName: "Default",
                        contentPreview: "",
                        category: .asr
                    ),
                    filePath: "Transcripts/Raw/\(_filename.deletingPathExtension)_transcript.json"
                )
                _transcriptVersions.append(v1)
            }

            if _summaryVersions.isEmpty && legacyHasSummary {
                let v1 = SummaryVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: Date(), // Can't know exact time
                    modelInfo: ModelVersionInfo(
                        modelId: "legacy",
                        displayName: "Llama (Legacy)",
                        provider: "Legacy"
                    ),
                    promptInfo: PromptVersionInfo(
                        promptId: "default",
                        promptName: "Default",
                        contentPreview: "",
                        category: .llm
                    ),
                    filePath: "SmartNotes/\(_filename.deletingPathExtension)_summary.md",
                    sourceTranscriptId: _transcriptVersions.first?.id ?? UUID(),
                    sourceTranscriptVersionNumber: 1
                )
                _summaryVersions.append(v1)
            }
        }

        // Version number migration: ensure all versions have valid version numbers
        if !_transcriptVersions.isEmpty {
            _transcriptVersions = _transcriptVersions.enumerated().map { index, version in
                var newVersion = version
                // If versionNumber is 0 or missing, use index + 1
                if newVersion.versionNumber <= 0 {
                    // We need to create a new version with proper version number
                    // Since TranscriptVersion is a struct with let properties, we recreate it
                    newVersion = TranscriptVersion(
                        id: version.id,
                        versionNumber: index + 1,
                        timestamp: version.timestamp,
                        modelInfo: version.modelInfo,
                        promptInfo: version.promptInfo,
                        filePath: version.filePath,
                        statistics: version.statistics
                    )
                }
                return newVersion
            }
        }

        if !_summaryVersions.isEmpty {
            _summaryVersions = _summaryVersions.enumerated().map { index, version in
                var newVersion = version
                if newVersion.versionNumber <= 0 {
                    newVersion = SummaryVersion(
                        id: version.id,
                        versionNumber: index + 1,
                        timestamp: version.timestamp,
                        modelInfo: version.modelInfo,
                        promptInfo: version.promptInfo,
                        filePath: version.filePath,
                        sourceTranscriptId: version.sourceTranscriptId,
                        sourceTranscriptVersionNumber: version.sourceTranscriptVersionNumber > 0
                            ? version.sourceTranscriptVersionNumber
                            : 1,
                        statistics: version.statistics
                    )
                }
                return newVersion
            }
        }
        
        // Initialize self properties
        self.id = _id
        self.filename = _filename
        self.displayTitle = _displayTitle
        self.source = _source
        self.startTime = _startTime
        self.duration = _duration
        self.status = _status
        self.transcriptVersions = _transcriptVersions
        self.summaryVersions = _summaryVersions
    }
    
    // MARK: - Default Init (for creating new records)
    
    init(id: UUID = UUID(), filename: String, title: String? = nil, source: String, startTime: Date, duration: TimeInterval, status: ProcessingStatus = .pending) {
        self.id = id
        self.filename = filename
        self.displayTitle = title
        self.source = source
        self.startTime = startTime
        self.duration = duration
        self.status = status
    }
    
    // MARK: - Computed Properties
    
    /// The title to display in UI
    var title: String {
        get { displayTitle ?? filename }
        set { displayTitle = newValue }
    }
    
    /// Backward compatibility for checking if transcript exists
    var hasTranscript: Bool {
        return !transcriptVersions.isEmpty
    }
    
    /// Backward compatibility for checking if summary exists
    var hasSummary: Bool {
        return !summaryVersions.isEmpty
    }
}

// MARK: - String Extensions

extension String {
    /// 删除路径扩展名
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}