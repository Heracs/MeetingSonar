import Foundation

extension MetadataManager {

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
}