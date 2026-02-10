//
//  AudioPreprocessor.swift
//  MeetingSonar
//
//  F-5.13c: Audio Preprocessor Service
//  Shared audio format conversion and preprocessing for all ASR engines
//
//  Architecture Phase 1: Service Layer
//  Created: 2025-02-05
//

import Foundation
import AVFoundation

// MARK: - Audio Preprocessor Errors

/// Errors that can occur during audio preprocessing
enum AudioPreprocessorError: LocalizedError {
    case fileNotFound(path: String)
    case invalidWAVFormat(reason: String)
    case conversionFailed(reason: String)
    case fileReadFailed(reason: String)
    case unsupportedFormat(format: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidWAVFormat(let reason):
            return "Invalid WAV format: \(reason)"
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .fileReadFailed(let reason):
            return "Failed to read audio file: \(reason)"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        }
    }
}

// MARK: - Audio Preprocessor Service

/// Service for audio format conversion and preprocessing
///
/// This service is shared by all ASR engines to avoid code duplication.
/// It handles:
/// - Converting various audio formats to 16kHz mono WAV (required by most ASR engines)
/// - Loading audio samples from WAV files
/// - Audio format validation
///
/// # Thread Safety
/// This is an `actor` ensuring thread-safe access to shared resources.
actor AudioPreprocessor {

    // MARK: - Singleton

    static let shared = AudioPreprocessor()

    private init() {}

    // MARK: - Constants

    /// Target sample rate for ASR engines (16kHz is standard)
    private let targetSampleRate: Double = 16000.0

    /// Target number of channels (mono)
    private let targetChannels: UInt32 = 1

    // MARK: - Format Conversion

    /// Convert audio file to 16kHz mono WAV format
    ///
    /// Most ASR engines (Whisper, Qwen3-ASR) require 16kHz mono WAV input.
    /// This method handles the conversion, returning either the original URL
    /// if it's already in the correct format, or a temporary file URL.
    ///
    /// - Parameters:
    ///   - audioURL: Source audio file URL
    ///   - progress: Optional progress callback (0.0 to 1.0)
    ///
    /// - Returns: URL to converted WAV file (may be the original if already correct format)
    ///
    /// - Throws: AudioPreprocessorError if conversion fails
    ///
    /// # Important
    /// If a temporary file is created, the caller is responsible for deleting it.
    /// Use `defer { try? FileManager.default.removeItem(at: tempURL) }` to ensure cleanup.
    func convertToWAV16kHz(
        audioURL: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioPreprocessorError.fileNotFound(path: audioURL.path)
        }

        let ext = audioURL.pathExtension.lowercased()

        // If already WAV, assume it's in the correct format (for now)
        // TODO: Add proper format verification
        if ext == "wav" {
            LoggerService.shared.log(
                category: .ai,
                message: "[AudioPreprocessor] Input is WAV, using as-is"
            )
            return audioURL
        }

        // Convert to required format
        LoggerService.shared.log(
            category: .ai,
            message: "[AudioPreprocessor] Converting \(audioURL.lastPathComponent) to 16kHz mono WAV"
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try await convertWithAfConvert(
            source: audioURL,
            destination: tempURL,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            progress: progress
        )

        // Verify the converted file exists
        if FileManager.default.fileExists(atPath: tempURL.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            LoggerService.shared.log(
                category: .ai,
                message: "[AudioPreprocessor] Conversion complete: \(fileSize) bytes"
            )
            return tempURL
        } else {
            throw AudioPreprocessorError.conversionFailed(reason: "Output file not created")
        }
    }

    // MARK: - Sample Loading

    /// Load audio samples from WAV file
    ///
    /// Reads a WAV file and returns normalized Float samples in the range [-1, 1].
    /// This method expects standard 16-bit PCM WAV format.
    ///
    /// - Parameter wavURL: WAV file URL (must be 16-bit PCM)
    ///
    /// - Returns: Array of Float samples normalized to [-1, 1]
    ///
    /// - Throws: AudioPreprocessorError if reading fails
    func loadWAVSamples(from wavURL: URL) async throws -> [Float] {
        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            throw AudioPreprocessorError.fileNotFound(path: wavURL.path)
        }

        let data = try Data(contentsOf: wavURL)

        // WAV header is typically 44 bytes
        let headerSize = 44
        guard data.count > headerSize else {
            throw AudioPreprocessorError.invalidWAVFormat(reason: "File too small")
        }

        // Skip WAV header to get audio data
        let audioData = data.subdata(in: headerSize..<data.count)

        // Convert Int16 samples to Float32 normalized to [-1, 1]
        var samples: [Float] = []
        samples.reserveCapacity(audioData.count / 2)

        audioData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for sample in int16Buffer {
                samples.append(Float(sample) / 32768.0)
            }
        }

        LoggerService.shared.log(
            category: .ai,
            message: "[AudioPreprocessor] Loaded \(samples.count) samples from \(wavURL.lastPathComponent)"
        )

        return samples
    }

    // MARK: - Private Conversion Methods

    /// Convert using afconvert command-line tool
    ///
    /// afconvert is Apple's built-in audio converter, fast and reliable.
    private func convertWithAfConvert(
        source: URL,
        destination: URL,
        sampleRate: Double,
        channels: UInt32,
        progress: ((Double) -> Void)?
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")

        // Format: LEI16@16000 = Little-Endian Integer 16-bit at 16kHz
        let formatString = "LEI16@\(Int(sampleRate))"

        process.arguments = [
            "-f", "WAVE",
            "-d", formatString,
            "-c", String(channels),
            source.path,
            destination.path
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            LoggerService.shared.log(
                category: .ai,
                message: "[AudioPreprocessor] afconvert successful"
            )
        } else {
            LoggerService.shared.log(
                category: .ai,
                level: .error,
                message: "[AudioPreprocessor] afconvert failed with exit code: \(process.terminationStatus)"
            )
            throw AudioPreprocessorError.conversionFailed(reason: "afconvert failed with exit code: \(process.terminationStatus)")
        }
    }
}
