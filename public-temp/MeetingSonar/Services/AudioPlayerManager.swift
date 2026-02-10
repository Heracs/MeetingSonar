//
//  AudioPlayerManager.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import Foundation
import AVFoundation
import Combine

/// Manages audio playback for recorded meetings
///
/// Wraps `AVPlayer` to provide an observable interface for SwiftUI.
/// Handles loading, playing, pausing, seeking, and time tracking.
///
/// ## Usage
/// ```swift
/// let player = AudioPlayerManager.shared
/// await player.load(url: recordingURL)
/// player.play()
/// ```
@MainActor
class AudioPlayerManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether audio is currently playing
    @Published var isPlaying: Bool = false

    /// Current playback position in seconds
    @Published var currentTime: TimeInterval = 0

    /// Total duration of loaded audio in seconds
    @Published var duration: TimeInterval = 0

    /// Error message if playback fails
    @Published var error: String?

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObserver: AnyCancellable?

    // MARK: - Loading

    /// Load an audio file for playback
    ///
    /// - Parameter url: URL of the audio file to load
    ///
    /// ## Process
    /// 1. Validates file exists
    /// 2. Creates AVPlayerItem
    /// 3. Loads duration asynchronously
    /// 4. Sets up time observers
    func load(url: URL) {
        stop() // Reset previous
        
        // Validation AC-3: Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.error = "File not found at \(url.lastPathComponent)"
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        
        // Observe duration
        // Note: Duration might need async loading in newer AVFoundation, but for local files it's usually quick.
        // We can observe the item's duration property or wait for status.
        // For simplicity in v0.7.0, we use an async load task.
        Task {
            do {
                let duration = try await playerItem.asset.load(.duration)
                self.duration = duration.seconds
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "Failed to load duration: \(error)")
                self.duration = 0
            }
        }

        setupTimeObserver()
        setupItemObserver(for: playerItem)

        self.error = nil
        LoggerService.shared.log(category: .general, level: .info, message: "Loaded: \(url.lastPathComponent)")
    }
    
    /// Play or Resume
    func play() {
        guard let player = player else { return }
        
        if player.currentTime().seconds >= duration {
            // Replay from start if at end
            seek(to: 0)
        }
        
        player.play()
        isPlaying = true
    }
    
    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    /// Toggle between play and pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Seek to specific time
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime)
    }
    
    /// Skip forward or backward by specified amount
    ///
    /// - Parameter seconds: Number of seconds to skip (positive = forward, negative = backward)
    func skip(seconds: TimeInterval) {
        guard let player = player else { return }
        let newTime = player.currentTime().seconds + seconds
        seek(to: max(0, min(newTime, duration)))
    }

    /// Stop playback and release resources
    func stop() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        itemObserver?.cancel()
        itemObserver = nil
        player = nil
        
        isPlaying = false
        currentTime = 0
        duration = 0
        error = nil
    }
    
    // MARK: - Private Setup
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isPlaying else { return } // Only update if playing to avoid conflict with dragging
            self.currentTime = time.seconds
        }
    }
    
    private func setupItemObserver(for item: AVPlayerItem) {
        // Observe playback finished
        itemObserver = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.currentTime = 0
                    self?.player?.seek(to: .zero)
                }
            }
    }
}
