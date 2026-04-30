//
//  AudioMergeService.swift
//  MeetingSonar
//
//  F-0.10.17: Audio merge service
//  Merges multiple recording files into a single M4A file using AVMutableComposition.
//

import Foundation
import AVFoundation

// MARK: - Errors

/// 音频合并错误
enum AudioMergeError: LocalizedError {
    /// 选择不足 2 条录音
    case insufficientRecordings
    /// 某录音文件不存在
    case fileNotFound(String)
    /// 某文件没有音频轨道
    case noAudioTrack(String)
    /// 导出失败
    case exportFailed(String)
    /// 导出被取消
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .insufficientRecordings:
            return String(localized: "merge.error.insufficientRecordings",
                          defaultValue: "请至少选择 2 条录音进行合并")
        case .fileNotFound(let filename):
            return "录音文件不存在：\(filename)"
        case .noAudioTrack(let filename):
            return "文件没有音频轨道：\(filename)"
        case .exportFailed(let reason):
            return "导出失败：\(reason)"
        case .exportCancelled:
            return String(localized: "merge.error.exportCancelled",
                          defaultValue: "合并操作已取消")
        }
    }
}

// MARK: - Merge Result

/// 合并结果
struct AudioMergeResult: Sendable {
    /// 输出文件 URL
    let outputURL: URL
    /// 合并后总时长
    let duration: TimeInterval
    /// 新录音的元数据（已创建但未持久化）
    let metadata: MeetingMeta
}

// MARK: - AudioMergeService

/// 音频合并服务
/// 使用 AVMutableComposition 将多个录音文件拼接为一个新文件。
/// 无状态设计，所有方法为 static。
enum AudioMergeService {

    /// 合并多个录音文件
    /// - Parameter recordings: 要合并的录音元数据（≥2 条）
    /// - Returns: 合并结果，包含新文件 URL、时长和元数据
    /// - Throws: AudioMergeError
    static func merge(recordings: [MeetingMeta]) async throws -> AudioMergeResult {
        // 1. 验证
        guard recordings.count >= 2 else {
            throw AudioMergeError.insufficientRecordings
        }

        // 2. 按 startTime 升序排序
        let sorted = recordings.sorted { $0.startTime < $1.startTime }

        // 3. 验证所有文件存在
        let recordingsDir = PathManager.shared.recordingsURL
        for meta in sorted {
            let url = recordingsDir.appendingPathComponent(meta.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AudioMergeError.fileNotFound(meta.filename)
            }
        }

        // 4. 创建 composition 并拼接
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMergeError.exportFailed("无法创建音频轨道")
        }

        var insertTime = CMTime.zero

        for meta in sorted {
            let url = recordingsDir.appendingPathComponent(meta.filename)
            let asset = AVURLAsset(url: url)

            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceTrack = tracks.first else {
                throw AudioMergeError.noAudioTrack(meta.filename)
            }

            let duration = try await asset.load(.duration)

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: insertTime
            )

            insertTime = CMTimeAdd(insertTime, duration)
        }

        // 5. 生成输出文件名
        let outputURL = generateOutputURL(for: sorted)

        // 6. 导出
        try await exportComposition(composition, to: outputURL)

        // 7. 读取实际时长
        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration = try await outputAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(outputDuration)

        // 8. 创建元数据
        let earliest = sorted[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let dateStr = formatter.string(from: earliest.startTime)
        let displayTitle = "\(earliest.source) \(dateStr)（合并）"

        let metadata = MeetingMeta(
            id: UUID(),
            filename: outputURL.lastPathComponent,
            title: displayTitle,
            source: earliest.source,
            startTime: earliest.startTime,
            duration: durationSeconds,
            status: .pending
        )

        LoggerService.shared.log(
            category: .audio,
            level: .info,
            message: "[AudioMergeService] 合并完成：\(sorted.count) 个文件 → \(outputURL.lastPathComponent)，时长 \(Int(durationSeconds))s"
        )

        return AudioMergeResult(
            outputURL: outputURL,
            duration: durationSeconds,
            metadata: metadata
        )
    }

    // MARK: - Private Helpers

    /// 生成输出文件 URL，处理文件名冲突
    private static func generateOutputURL(for sortedRecordings: [MeetingMeta]) -> URL {
        let earliest = sortedRecordings[0]
        let baseName = earliest.filename.deletingPathExtension
        let recordingsDir = PathManager.shared.recordingsURL

        // 尝试 _Merged, _Merged_2, _Merged_3...
        let firstCandidate = recordingsDir.appendingPathComponent("\(baseName)_Merged.m4a")
        if !FileManager.default.fileExists(atPath: firstCandidate.path) {
            return firstCandidate
        }

        var counter = 2
        while true {
            let candidate = recordingsDir.appendingPathComponent("\(baseName)_Merged_\(counter).m4a")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    /// 导出 composition 为 M4A 文件
    private static func exportComposition(_ composition: AVMutableComposition, to outputURL: URL) async throws {
        // 移除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // 优先尝试 passthrough（不重编码）
        let presetName = AVAssetExportPresetPassthrough
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            // 退回到 AppleM4A preset
            try await exportWithPreset(composition, preset: AVAssetExportPresetAppleM4A, to: outputURL)
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return
        case .cancelled:
            throw AudioMergeError.exportCancelled
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "未知错误"
            // Passthrough 失败，尝试 AppleM4A
            LoggerService.shared.log(
                category: .audio,
                level: .warning,
                message: "[AudioMergeService] Passthrough 导出失败：\(errorMsg)，尝试 AppleM4A"
            )
            try await exportWithPreset(composition, preset: AVAssetExportPresetAppleM4A, to: outputURL)
        default:
            throw AudioMergeError.exportFailed("导出状态异常：\(exportSession.status.rawValue)")
        }
    }

    /// 使用指定 preset 导出
    private static func exportWithPreset(_ composition: AVMutableComposition, preset: String, to outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw AudioMergeError.exportFailed("无法创建 \(preset) 导出会话")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return
        case .cancelled:
            throw AudioMergeError.exportCancelled
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "未知错误"
            throw AudioMergeError.exportFailed(errorMsg)
        default:
            throw AudioMergeError.exportFailed("导出状态异常：\(exportSession.status.rawValue)")
        }
    }
}
