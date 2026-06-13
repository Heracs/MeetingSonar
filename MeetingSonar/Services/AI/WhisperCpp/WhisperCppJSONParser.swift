import Foundation

struct WhisperCppJSONParser: Sendable {
    func parse(data: Data, language: String, processingTime: TimeInterval) throws -> TranscriptionResult {
        let root = try JSONDecoder().decode(WhisperRoot.self, from: data)
        let segments = root.transcription.map {
            ASRTranscriptSegment(
                startTime: Self.seconds(from: $0.timestamps.from),
                endTime: Self.seconds(from: $0.timestamps.to),
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let text = segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        return TranscriptionResult(
            text: text,
            segments: segments,
            language: language,
            processingTime: processingTime
        )
    }

    private static func seconds(from timestamp: String) -> TimeInterval {
        let normalized = timestamp.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return 0
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private struct WhisperRoot: Decodable {
        let transcription: [WhisperSegment]
    }

    private struct WhisperSegment: Decodable {
        let timestamps: WhisperTimestamps
        let text: String
    }

    private struct WhisperTimestamps: Decodable {
        let from: String
        let to: String
    }
}
