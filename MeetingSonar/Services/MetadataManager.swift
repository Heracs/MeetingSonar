//
//  MetadataManager.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import Foundation
import AVFoundation

/// Manages the `metadata.json` index and provides CRUD operations for recordings.
/// Implements F-6.0 (Metadata Index).
@MainActor
final class MetadataManager: ObservableObject, MetadataManagerProtocol {
    
    // MARK: - Singleton
    
    static let shared = MetadataManager()
    
    // MARK: - Properties
    
    /// In-memory cache of metadata
    @Published var recordings: [MeetingMeta] = []
    
    private let fileManager = FileManager.default
    private let indexFileName = "metadata.json"
    
    /// Path to the metadata.json file
    private var indexFileURL: URL {
        PathManager.shared.rootDataURL.appendingPathComponent(indexFileName)
    }
    
    /// Path to the Recordings directory
    private var recordingsDir: URL {
        PathManager.shared.recordingsURL
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load data immediately upon initialization context permitting,
        // but strict async loading is usually better. 
        // For actor, we'll expose a `load()` method or call it in first access logic if needed.
        // We will call load() explicitly during App Launch.
    }
    
    // MARK: - Core Operations

    /// Load metadata from disk asynchronously
    func load() async {
        let url = indexFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] No index file found at \(url.path)")
            return
        }

        do {
            let data = try await Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([MeetingMeta].self, from: data)

            // Sort by Date Descending by default
            self.recordings = loaded.sorted(by: { $0.startTime > $1.startTime })

            LoggerService.shared.log(category: .general, level: .info, message: "[MetadataManager] Loaded \(self.recordings.count) recordings from index.")
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "[MetadataManager] Failed to load index: \(error)")
        }
    }

    /// Save metadata to disk asynchronously
    func save() async {
        let url = indexFileURL
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(self.recordings)
            try await data.write(to: url, options: .atomic)
             LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Index saved.")
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "[MetadataManager] Failed to save index: \(error)")
        }
    }
    
    // MARK: - CRUD Operations

    /// Retrieve a single recording by ID
    func get(id: UUID) -> MeetingMeta? {
        return recordings.first(where: { $0.id == id })
    }

    /// Add a new recording to the index asynchronously
    func add(_ meta: MeetingMeta) async {
        // Append to beginning (newest first)
        recordings.insert(meta, at: 0)
        await save()
    }

    /// Update an existing recording asynchronously
    func update(_ meta: MeetingMeta) async {
        if let index = recordings.firstIndex(where: { $0.id == meta.id }) {
            recordings[index] = meta
            await save()
        }
    }

    /// Update status for a specific file by filename (useful for loose coupling)
    func updateStatus(filename: String, status: MeetingMeta.ProcessingStatus) async {
        if let index = recordings.firstIndex(where: { $0.filename == filename }) {
            recordings[index].status = status
            await save()
        }
    }

    /// Delete a recording (Index + Files) asynchronously (F-6.4)
    /// v0.8.4: Enhanced to delete all transcript/summary versions and log results
    func delete(id: UUID) async throws {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else {
            return
        }

        let meta = recordings[index]

        // 1. Delete transcript files (all versions)
        for version in meta.transcriptVersions {
            let url = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
            deleteFile(at: url, type: "Transcript")

            // Also try to delete matching .txt file if exists
            let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
            deleteFile(at: txtURL, type: "Transcript TXT")
        }

        // 2. Delete summary files (all versions)
        for version in meta.summaryVersions {
            let url = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
            deleteFile(at: url, type: "Summary")
        }

        // 3. Delete audio file
        let audioURL = recordingsDir.appendingPathComponent(meta.filename)
        deleteFile(at: audioURL, type: "Audio")

        // 4. Remove from index and save
        recordings.remove(at: index)
        await save()

        LoggerService.shared.log(
            category: .general,
            message: "[MetadataManager] Completed deletion of recording: \(meta.filename)"
        )
    }
    
    /// Helper: Delete a single file with logging
    /// - Parameters:
    ///   - url: Full path to the file
    ///   - type: File type for logging (e.g., "Audio", "Transcript", "Summary")
    private func deleteFile(at url: URL, type: String) {
        guard fileManager.fileExists(atPath: url.path) else {
            // File doesn't exist, skip silently (not an error)
            return
        }
        
        do {
            try fileManager.removeItem(at: url)
            LoggerService.shared.log(
                category: .general,
                message: "[MetadataManager] Deleted \(type): \(url.lastPathComponent)"
            )
        } catch {
            LoggerService.shared.log(
                category: .general,
                level: .error,
                message: "[MetadataManager] Failed to delete \(type): \(url.lastPathComponent), error: \(error.localizedDescription)"
            )
        }
    }
    
    /// Rename display title (F-6.4)
    func rename(id: UUID, newTitle: String) async {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            recordings[index].title = newTitle
            await save()
        }
    }

    /// Update AI processing status and flags asynchronously
    func updateAIStatus(filename: String, status: MeetingMeta.ProcessingStatus, hasTranscript: Bool, hasSummary: Bool) async {
        if let index = recordings.firstIndex(where: { $0.filename == filename }) {
            recordings[index].status = status

            // If legacy flag passed true, ensure at least one version exists (Migration/Fallback)
            if hasTranscript && recordings[index].transcriptVersions.isEmpty {
                // Auto-create a version pointer for legacy flow compatibility
                let v = TranscriptVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: Date(),
                    modelInfo: ModelVersionInfo(modelId: "unknown", displayName: "Unknown", provider: "Unknown"),
                    promptInfo: PromptVersionInfo(promptId: "default", promptName: "Default", contentPreview: "", category: .asr),
                    filePath: "Transcripts/Raw/\(recordings[index].filename.deletingPathExtension)_transcript.json" // Best guess
                )
                recordings[index].transcriptVersions.append(v)
            }

            if hasSummary && recordings[index].summaryVersions.isEmpty {
                 let v = SummaryVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: Date(),
                    modelInfo: ModelVersionInfo(modelId: "unknown", displayName: "Unknown", provider: "Unknown"),
                    promptInfo: PromptVersionInfo(promptId: "default", promptName: "Default", contentPreview: "", category: .llm),
                    filePath: "SmartNotes/\(recordings[index].filename.deletingPathExtension)_summary.md",
                    sourceTranscriptId: recordings[index].transcriptVersions.first?.id ?? UUID(),
                    sourceTranscriptVersionNumber: recordings[index].transcriptVersions.first?.versionNumber ?? 1
                )
                recordings[index].summaryVersions.append(v)
            }

            await save()
            LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Updated AI status for \(filename): \(status)")
        }
    }

    /// Update recording metadata when recording ends (Duration + Status) asynchronously
    func updateRecordingEnd(filename: String, duration: TimeInterval, status: MeetingMeta.ProcessingStatus) async {
        if let index = recordings.firstIndex(where: { $0.filename == filename }) {
            recordings[index].duration = duration
            recordings[index].status = status
            await save()
            LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Updated recording end for \(filename): duration=\(duration), status=\(status)")
        }
    }

    /// Add a summary version to a specific meeting
    /// - Parameters:
    ///   - version: The summary version to add
    ///   - meetingID: The meeting ID
    func addSummaryVersion(_ version: SummaryVersion, to meetingID: UUID) async {
        guard let index = recordings.firstIndex(where: { $0.id == meetingID }) else {
            LoggerService.shared.log(
                category: .general,
                level: .warning,
                message: "[MetadataManager] Cannot add summary version: meeting \(meetingID) not found"
            )
            return
        }

        recordings[index].summaryVersions.append(version)
        await save()

        LoggerService.shared.log(
            category: .general,
            level: .debug,
            message: "[MetadataManager] Added summary version \(version.versionNumber) to meeting \(meetingID)"
        )
    }

    // MARK: - Migration (F-6.0)

    /// Scan Recordings directory and add missing files to index asynchronously
    func scanAndMigrate() async {
        LoggerService.shared.log(category: .general, level: .info, message: "[MetadataManager] Starting scanAndMigrate...")
        let folder = recordingsDir

        // Ensure folder exists
        guard fileManager.fileExists(atPath: folder.path) else { return }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])

            // Filter audio files
            let audioFiles = fileURLs.filter { ["m4a", "wav"].contains($0.pathExtension.lowercased()) }

            var newCount = 0

            for url in audioFiles {
                let filename = url.lastPathComponent

                // Check if already in index
                if recordings.contains(where: { $0.filename == filename }) {
                    continue
                }

                // Create Meta for missing file
                let values = try url.resourceValues(forKeys: [.creationDateKey])
                let creationDate = values.creationDate ?? Date()

                // Infer source from filename if possible (Format: yyyyMMdd-HHmm_Source.m4a)
                // If not standard, use "Imported"
                let source = parseSourceFromFilename(filename) ?? "Imported"

                // Read actual duration from audio file using AVAsset
                let duration = readAudioDuration(from: url)

                let meta = MeetingMeta(
                    id: UUID(),
                    filename: filename,
                    title: nil, // Use filename
                    source: source,
                    startTime: creationDate,
                    duration: duration,
                    status: .completed // Assume old files are done
                )
                // Version flags will be populated by verifySidecarFiles

                recordings.append(meta)
                newCount += 1
            }

            if newCount > 0 {
                // Re-sort
                recordings.sort(by: { $0.startTime > $1.startTime })
                LoggerService.shared.log(category: .general, level: .info, message: "[MetadataManager] Migrated \(newCount) new files into index.")
            }

            // F-7 debug fix: Always re-scan sidecar files (Transcripts/Summaries) to ensure flags are consistent
            // This handles cases where files were generated but metadata wasn't updated (or app crashed)
            await verifySidecarFiles()

            // Repair any existing recordings with duration=0
            await repairZeroDurations()

            if newCount > 0 {
                await save()
            } else {
                 // verifySidecarFiles might have changed things, so save if modified.
                 // Ideally verifySidecarFiles tracks changes. For simplicity, just save.
                 await save()
                 LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Index refreshed.")
            }

        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "[MetadataManager] Scan failed: \(error)")
        }
    }
    
    /// Read audio file duration using AVAsset (synchronous)
    private func readAudioDuration(from url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        // Use synchronous duration property (deprecated but works for local files)
        // For local files, this is fast and acceptable
        let duration = asset.duration
        let seconds = CMTimeGetSeconds(duration)
        if seconds.isFinite && seconds > 0 {
            return seconds
        }
        return 0
    }
    
    /// Repair recordings that have duration=0 by reading actual file duration asynchronously
    func repairZeroDurations() async {
        var repaired = 0
        for i in 0..<recordings.count {
            if recordings[i].duration == 0 && recordings[i].status != .recording {
                let url = recordingsDir.appendingPathComponent(recordings[i].filename)
                if fileManager.fileExists(atPath: url.path) {
                    let duration = readAudioDuration(from: url)
                    if duration > 0 {
                        recordings[i].duration = duration
                        repaired += 1
                        LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Repaired duration for \(recordings[i].filename): \(Int(duration))s")
                    }
                }
            }
        }
        if repaired > 0 {
            await save()
            LoggerService.shared.log(category: .general, level: .info, message: "[MetadataManager] Repaired \(repaired) recordings with duration=0")
        }
    }

    /// Check for existence of Transcript and Summary files and update metadata flags asynchronously
    private func verifySidecarFiles() async {
        var changed = false
        for i in 0..<recordings.count {
            let meta = recordings[i]
            let basename = (meta.filename as NSString).deletingPathExtension

            // 1. Check Transcript
            let hasT = checkForTranscript(basename)
            if hasT && meta.transcriptVersions.isEmpty {
                // Create migration version
                let v = TranscriptVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: meta.startTime.addingTimeInterval(meta.duration),
                    modelInfo: ModelVersionInfo(modelId: "legacy", displayName: "Whisper (Legacy)", provider: "Legacy"),
                    promptInfo: PromptVersionInfo(promptId: "default", promptName: "Default", contentPreview: "", category: .asr),
                    filePath: "Transcripts/Raw/\(basename)_transcript.json" // Rough guess, but effectively we just need to know it exists
                )
                recordings[i].transcriptVersions.append(v)
                changed = true
                LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Auto-migrated transcript version for \(meta.filename)")
            }

            // 2. Check Summary
            let hasS = checkForSummary(basename)
            if hasS && meta.summaryVersions.isEmpty {
                 let v = SummaryVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: meta.startTime.addingTimeInterval(meta.duration + 60),
                    modelInfo: ModelVersionInfo(modelId: "legacy", displayName: "Llama (Legacy)", provider: "Legacy"),
                    promptInfo: PromptVersionInfo(promptId: "default", promptName: "Default", contentPreview: "", category: .llm),
                    filePath: "SmartNotes/\(basename)_summary.md",
                    sourceTranscriptId: recordings[i].transcriptVersions.first?.id ?? UUID(),
                    sourceTranscriptVersionNumber: recordings[i].transcriptVersions.first?.versionNumber ?? 1
                )
                recordings[i].summaryVersions.append(v)
                changed = true
                LoggerService.shared.log(category: .general, level: .debug, message: "[MetadataManager] Auto-migrated summary version for \(meta.filename)")
            }
        }

        if changed {
            await save()
        }
    }
    
    private func checkForTranscript(_ basename: String) -> Bool {
        let transcriptsDir = PathManager.shared.transcriptsURL
        // Candidates
        let paths = [
            transcriptsDir.appendingPathComponent("Cleansed").appendingPathComponent("\(basename).json"),
            transcriptsDir.appendingPathComponent("Raw").appendingPathComponent("\(basename)_transcript.json"),
             transcriptsDir.appendingPathComponent("Raw").appendingPathComponent("\(basename).json")
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path.path) { return true }
        }
        return false
    }
    
    private func checkForSummary(_ basename: String) -> Bool {
        let notesDir = PathManager.shared.smartNotesURL
        // Candidates
        let paths = [
            notesDir.appendingPathComponent("\(basename)_Summary.md"),
            notesDir.appendingPathComponent("\(basename)_summary.md")
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path.path) { return true }
        }
        return false
    }
    
    private func parseSourceFromFilename(_ filename: String) -> String? {
        // Simple heuristic for standardized filenames
        // "20240121-1400_Zoom.m4a" -> "Zoom"
        let base = (filename as NSString).deletingPathExtension
        let components = base.components(separatedBy: "_")
        if components.count > 1 {
            return components.last
        }
        return nil
    }
}
