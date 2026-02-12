import Foundation
import AVFoundation

extension MetadataManager {

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