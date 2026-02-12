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
}