import Foundation

enum ParticipantCountExtractor {
    static func extract(
        bundleIdentifier: String,
        texts: [String],
        now: Date = Date()
    ) -> ParticipantCountObservation {
        for text in texts {
            if let count = matchEnglishParticipants(in: text) {
                return ParticipantCountObservation(
                    bundleIdentifier: bundleIdentifier,
                    count: count,
                    rawText: text,
                    confidence: .high,
                    timestamp: now
                )
            }

            if let count = matchChineseParticipants(in: text) {
                return ParticipantCountObservation(
                    bundleIdentifier: bundleIdentifier,
                    count: count,
                    rawText: text,
                    confidence: .medium,
                    timestamp: now
                )
            }
        }

        return ParticipantCountObservation(
            bundleIdentifier: bundleIdentifier,
            count: nil,
            rawText: nil,
            confidence: .low,
            timestamp: now
        )
    }

    private static func matchEnglishParticipants(in text: String) -> Int? {
        let pattern = #"(?i)\b(\d{1,4})\s+participants?\b"#
        return firstIntegerMatch(in: text, pattern: pattern)
    }

    private static func matchChineseParticipants(in text: String) -> Int? {
        let patterns = [
            #"参会者\s*(\d{1,4})"#,
            #"(\d{1,4})\s*位参会者"#,
            #"(\d{1,4})\s*人参会"#
        ]

        for pattern in patterns {
            if let count = firstIntegerMatch(in: text, pattern: pattern) {
                return count
            }
        }
        return nil
    }

    private static func firstIntegerMatch(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[valueRange])
    }
}
