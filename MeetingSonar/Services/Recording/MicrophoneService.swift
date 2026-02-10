//
//  MicrophoneService.swift
//  MeetingSonar
//
//  Captures audio from the user's microphone using AVCaptureSession.
//

import Foundation
import AVFoundation
import CoreMedia

/// Protocol for receiving captured audio samples from microphone
protocol MicrophoneCaptureDelegate: AnyObject {
    /// Called when a new audio sample buffer is captured from microphone
    /// - Parameters:
    ///   - service: The microphone service instance
    ///   - sampleBuffer: The captured audio sample buffer
    func microphoneService(_ service: MicrophoneService, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
    
    /// Called when an error occurs during capture
    /// - Parameters:
    ///   - service: The microphone service instance
    ///   - error: The error that occurred
    func microphoneService(_ service: MicrophoneService, didEncounterError error: Error)
}

/// Service for capturing microphone audio using AVCaptureSession
///
/// Uses `AVCaptureSession` with `AVCaptureDeviceInput` to capture
/// audio from the user's default microphone.
final class MicrophoneService: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: MicrophoneCaptureDelegate?
    
    /// The capture session
    private var captureSession: AVCaptureSession?
    
    /// Audio device input
    private var audioInput: AVCaptureDeviceInput?
    
    /// Audio data output
    private var audioOutput: AVCaptureAudioDataOutput?
    
    /// Queue for processing audio samples
    private let audioQueue = DispatchQueue(label: "com.meetingsonar.microphone")
    
    /// Whether capture is currently active
    private(set) var isCapturing = false
    
    /// Whether capture is paused (v0.2)
    private(set) var isPaused = false
    
    /// The currently selected microphone device
    private(set) var currentDevice: AVCaptureDevice?
    
    /// Sample counter for debug logging
    private var sampleCounter = 0
    
    // MARK: - Public Methods
    
    /// Start capturing from the microphone
    /// - Parameter device: Optional specific microphone device (nil uses default)
    func startCapture(device: AVCaptureDevice? = nil) throws {
        guard !isCapturing else {
            LoggerService.shared.log(category: .audio, level: .debug, message: "Already capturing")
            return
        }

        // Reset sample counter for debug logging
        sampleCounter = 0

        // Get microphone device
        let micDevice: AVCaptureDevice
        if let device = device {
            micDevice = device
        } else if let defaultMic = AVCaptureDevice.default(for: .audio) {
            micDevice = defaultMic
        } else {
            throw MicrophoneError.noMicrophoneAvailable
        }

        currentDevice = micDevice
        LoggerService.shared.log(category: .audio, level: .debug, message: "Using device: \(micDevice.localizedName) (ID: \(micDevice.uniqueID))")
        
        // Create capture session
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Set session preset for high quality audio
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        
        // Add input
        let input = try AVCaptureDeviceInput(device: micDevice)
        guard session.canAddInput(input) else {
            throw MicrophoneError.inputNotSupported
        }
        session.addInput(input)
        audioInput = input
        
        // Add output with audio settings
        let output = AVCaptureAudioDataOutput()
        
        // Note: AVCaptureAudioDataOutput doesn't allow setting audio format directly
        // The format is determined by the input device
        // We'll handle format conversion in the mixer
        if let recommended = output.recommendedAudioSettingsForAssetWriter(writingTo: .m4a) {
            LoggerService.shared.log(category: .audio, level: .debug, message: "Recommended settings: \(recommended)")
        }
        
        output.setSampleBufferDelegate(self, queue: audioQueue)
        
        guard session.canAddOutput(output) else {
            throw MicrophoneError.outputNotSupported
        }
        session.addOutput(output)
        audioOutput = output
        
        session.commitConfiguration()
        
        // Start session on a background thread to avoid blocking
        captureSession = session
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()

            DispatchQueue.main.async {
                if session.isRunning {
                    LoggerService.shared.log(category: .audio, level: .debug, message: "Session started successfully")
                } else {
                    LoggerService.shared.log(category: .audio, level: .warning, message: "Session failed to start")
                }
            }
        }

        isCapturing = true
        LoggerService.shared.log(category: .audio, level: .info, message: "Started capturing from microphone: \(micDevice.localizedName)")
    }
    
    /// Stop capturing from the microphone
    func stopCapture() {
        guard isCapturing, let session = captureSession else {
            LoggerService.shared.log(category: .audio, level: .debug, message: "Not capturing")
            return
        }

        session.stopRunning()

        // Remove inputs and outputs
        if let input = audioInput {
            session.removeInput(input)
        }
        if let output = audioOutput {
            session.removeOutput(output)
        }

        captureSession = nil
        audioInput = nil
        audioOutput = nil
        currentDevice = nil
        isCapturing = false
        isPaused = false

        LoggerService.shared.log(category: .audio, level: .info, message: "Stopped capturing from microphone")
    }

    /// Pause capturing (v0.2 - for sleep/lock events)
    func pauseCapture() {
        guard isCapturing, !isPaused else { return }
        isPaused = true
        LoggerService.shared.log(category: .audio, level: .debug, message: "Capture paused")
    }

    /// Resume capturing (v0.2 - after sleep/lock)
    func resumeCapture() {
        guard isCapturing, isPaused else { return }
        isPaused = false
        LoggerService.shared.log(category: .audio, level: .debug, message: "Capture resumed")
    }
    
    /// Get list of available microphone devices
    func getAvailableDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }
    
    /// Switch to a different microphone device
    /// - Parameter device: The new microphone device to use
    func switchDevice(_ device: AVCaptureDevice) throws {
        guard isCapturing, let session = captureSession else {
            throw MicrophoneError.notCapturing
        }
        
        session.beginConfiguration()
        
        // Remove old input
        if let oldInput = audioInput {
            session.removeInput(oldInput)
        }
        
        // Add new input
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else {
            // Restore old input if new one fails
            if let oldInput = audioInput {
                session.addInput(oldInput)
            }
            session.commitConfiguration()
            throw MicrophoneError.inputNotSupported
        }
        
        session.addInput(newInput)
        audioInput = newInput
        currentDevice = device
        
        session.commitConfiguration()

        LoggerService.shared.log(category: .audio, level: .info, message: "Switched to microphone: \(device.localizedName)")
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension MicrophoneService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip if paused (v0.2)
        guard !isPaused else { return }
        
        // Debug: log first few samples
        sampleCounter += 1
        if sampleCounter <= 3 {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                LoggerService.shared.log(category: .audio, level: .debug, message: "Rate: \(Int(asbd.mSampleRate))Hz, Ch: \(asbd.mChannelsPerFrame), Bits: \(asbd.mBitsPerChannel), Float: \(isFloat), Interleaved: \(isInterleaved)")
            }
        }
        
        // Forward audio sample buffer to delegate
        delegate?.microphoneService(self, didCaptureSampleBuffer: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        LoggerService.shared.log(category: .audio, level: .warning, message: "Dropped audio sample buffer")
    }
}

// MARK: - Errors

/// Errors that can occur during microphone capture
enum MicrophoneError: LocalizedError {
    case noMicrophoneAvailable
    case inputNotSupported
    case outputNotSupported
    case notCapturing
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable:
            return "No microphone device is available"
        case .inputNotSupported:
            return "The microphone input is not supported"
        case .outputNotSupported:
            return "Audio output configuration is not supported"
        case .notCapturing:
            return "Microphone capture is not active"
        case .permissionDenied:
            return "Microphone access was denied. Please enable it in System Settings."
        }
    }
}


