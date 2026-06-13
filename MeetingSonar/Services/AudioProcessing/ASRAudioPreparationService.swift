import AVFoundation
import Foundation

final class ASRAudioPreparationService: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createJobDirectory(jobID: UUID = UUID()) throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = caches
            .appendingPathComponent("MeetingSonar", isDirectory: true)
            .appendingPathComponent("ASRJobs", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func estimatedWAVBytes(duration: TimeInterval) -> UInt64 {
        let sampleRate = 16_000.0
        let channels = 1.0
        let bytesPerSample = 2.0
        let headerBytes = 44.0
        return UInt64((duration * sampleRate * channels * bytesPerSample + headerBytes).rounded())
    }

    func cleanup(jobDirectory: URL) throws {
        if fileManager.fileExists(atPath: jobDirectory.path) {
            try fileManager.removeItem(at: jobDirectory)
        }
    }

    func cleanupStaleJobs(olderThan age: TimeInterval = 24 * 60 * 60) {
        guard let root = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appendingPathComponent("MeetingSonar", isDirectory: true)
        .appendingPathComponent("ASRJobs", isDirectory: true) else {
            return
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            LoggerService.shared.log(
                category: .audio,
                level: .warning,
                message: "[ASRAudioPreparationService] Failed to list stale ASR jobs: \(error.localizedDescription)"
            )
            return
        }

        let cutoff = Date().addingTimeInterval(-age)
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values?.contentModificationDate ?? .distantPast
            guard date < cutoff else { continue }

            do {
                try fileManager.removeItem(at: url)
            } catch {
                LoggerService.shared.log(
                    category: .audio,
                    level: .warning,
                    message: "[ASRAudioPreparationService] Failed to remove stale ASR job: \(error.localizedDescription)"
                )
            }
        }
    }

    func prepareSingleWAV(from audioURL: URL, jobID: UUID = UUID()) async throws -> (wavURL: URL, jobDirectory: URL) {
        let jobDirectory = try createJobDirectory(jobID: jobID)
        let outputURL = jobDirectory.appendingPathComponent("input.wav")

        do {
            let splitter = AudioSplitter()
            try await splitter.exportWAV(audioURL: audioURL, outputURL: outputURL)
            return (outputURL, jobDirectory)
        } catch {
            try? cleanup(jobDirectory: jobDirectory)
            LoggerService.shared.log(
                category: .audio,
                level: .error,
                message: "[ASRAudioPreparationService] WAV conversion failed: \(error.localizedDescription)"
            )
            throw ASREngineError.audioConversionFailed(reason: error.localizedDescription)
        }
    }
}
