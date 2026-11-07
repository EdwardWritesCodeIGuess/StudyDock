import Foundation

/// Earlier recognizers can report a new result for just the latest phrase.
/// Keep phrases before the updated part of the recording.
public struct DictationTranscript {
    public struct Segment {
        public let start: TimeInterval
        public let text: String

        public init(start: TimeInterval, text: String) {
            self.start = start
            self.text = text
        }
    }

    private var segments: [Segment] = []
    private var untimed = ""

    public init() {}

    public mutating func update(_ incoming: [Segment], formattedText: String) {
        let timed = incoming.filter { $0.start.isFinite && $0.start >= 0 && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
        guard let first = timed.first, let last = timed.last, last.start > 0 else {
            if !formattedText.isEmpty { untimed = formattedText }
            return
        }

        // Allow minor timestamp jitter when a recognizer revises a phrase.
        segments.removeAll { $0.start >= first.start - 0.06 }
        segments.append(contentsOf: timed)
        segments.sort { $0.start < $1.start }
    }

    public var text: String {
        segments.isEmpty ? untimed : segments.map(\.text).joined(separator: " ")
    }

    public static func appending(_ transcript: String, to draft: String) -> String {
        guard !transcript.isEmpty else { return draft }
        guard !draft.isEmpty else { return transcript }
        return draft + (draft.last?.isNewline == true ? "" : "\n") + transcript
    }
}
