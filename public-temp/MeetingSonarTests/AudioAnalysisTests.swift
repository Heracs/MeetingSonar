import XCTest
import AVFoundation
@testable import MeetingSonar

final class AudioAnalysisTests: XCTestCase {
    
    func testFindBestSplitPoint_Silence() throws {
        // Setup 10s of silence at 16kHz
        let sampleRate: Double = 16000
        let duration: Double = 10.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        
        buffer.frameLength = frameCount
        
        // Zero out buffer (Silence)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            channelData[i] = 0.0
        }
        
        // Analyze
        let analyzer = AudioEnergyAnalyzer()
        let splitPoint = analyzer.findBestSplitPoint(in: buffer, startTime: 0)
        
        // Logic: iterates, finds first min.
        // If all 0, first window is min.
        // Window 0.1s. Middle is 0.05s.
        XCTAssertEqual(splitPoint, 0.05, accuracy: 0.1)
    }
    
    func testFindBestSplitPoint_GapInNoise() throws {
        // Setup 10s of noise, with silence at 5.0s-5.2s
        let sampleRate: Double = 16000
        let duration: Double = 10.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        
        buffer.frameLength = frameCount
        
        let channelData = buffer.floatChannelData![0]
        
        // Fill with noise (1.0)
        for i in 0..<Int(frameCount) {
            channelData[i] = 1.0
        }
        
        // Create silence at 5.0s (Frame 80000) for 0.2s (3200 frames)
        let startFrame = Int(5.0 * sampleRate)
        let endFrame = Int(5.2 * sampleRate)
        
        for i in startFrame..<endFrame {
            channelData[i] = 0.0
        }
        
        // Analyze
        let analyzer = AudioEnergyAnalyzer()
        let splitPoint = analyzer.findBestSplitPoint(in: buffer, startTime: 0)
        
        // Expect split point ~5.1s (middle of silence)
        // Window is 0.1s. It will slide.
        // It picks best min. Logic: returns middle of BEST window.
        // Best window is at 5.0s. Middle is 5.05s.
        
        XCTAssertEqual(splitPoint, 5.05, accuracy: 0.2)
    }
    
    // Test AudioSplitter (v0.8.3 Fix: Ensure WAV output)
     func testAudioSplitter_ExportWAV() async throws {
         // 1. Create a dummy source WAV file (16kHz, 5s)
         let tempDir = FileManager.default.temporaryDirectory
         let sourceURL = tempDir.appendingPathComponent("source_test.wav")
         let outputDir = tempDir.appendingPathComponent("splitter_output")
         
         try? FileManager.default.removeItem(at: sourceURL)
         try? FileManager.default.removeItem(at: outputDir)
         try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
         
         let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
         
         do {
             // Fix: Use strict init in test too to avoid crash
             let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
             
             // Write 5s of silence
             let frameCount = AVAudioFrameCount(5.0 * 16000)
             let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
             buffer.frameLength = frameCount
             try file.write(from: buffer)
         } // file is deinit here, closing the handle
         
         // 2. Run Splitter
         let splitter = AudioSplitter()
         // API: split(audioURL: URL) async throws -> [(url: URL, start: TimeInterval, duration: TimeInterval)]
         let chunks = try await splitter.split(audioURL: sourceURL)
         
         // 3. Verify Output
         XCTAssertFalse(chunks.isEmpty)
         let firstChunk = chunks[0]
         
         XCTAssertEqual(firstChunk.url.pathExtension.lowercased(), "wav")
         XCTAssertEqual(firstChunk.start, 0)
         XCTAssertEqual(firstChunk.duration, 5.0, accuracy: 0.1)
         
         // Verify format
         let chunkFile = try AVAudioFile(forReading: firstChunk.url)
         XCTAssertEqual(chunkFile.processingFormat.sampleRate, 16000)
         XCTAssertEqual(chunkFile.processingFormat.channelCount, 1)
         
         // Cleanup (Parent of chunk is a random uuid, so we just clean the chunk for now)
         for chunk in chunks {
             try? FileManager.default.removeItem(at: chunk.url)
         }
         try? FileManager.default.removeItem(at: sourceURL)
         try? FileManager.default.removeItem(at: outputDir)
     }
}
