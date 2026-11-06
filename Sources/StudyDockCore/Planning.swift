import Foundation

public struct CaptureCandidate: Identifiable, Sendable {
    public var id = UUID()
    public var task: Schoolwork
    public var needsDate: Bool
}

public enum CaptureParser {
    /// Each nonempty line becomes a reviewable item. Ambiguous dates are never silently exported.
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [CaptureCandidate] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        return text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let lower = line.lowercased()
            let kind: WorkKind = lower.range(of: #"\b(test|exam|midterm|final)\b"#, options: .regularExpression) != nil ? .test
                : lower.range(of: #"\bquiz\b"#, options: .regularExpression) != nil ? .quiz
                : lower.range(of: #"\b(project|presentation)\b"#, options: .regularExpression) != nil ? .project : .homework
            var subject = ""
            var title = line
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                subject = String(line[line.index(after: line.startIndex)..<end])
                title = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            }
            let match = detector?.matches(in: line, range: NSRange(line.startIndex..., in: line)).first
            var detected = match?.date
            // Resolve relative days against the injected clock, including deterministic tests.
            for (word, offset) in [("tomorrow", 1), ("today", 0)] where lower.contains(word) {
                let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
                let components = detected.map { calendar.dateComponents([.hour, .minute], from: $0) }
                let hasTime = lower.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b|\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
                detected = calendar.date(bySettingHour: hasTime ? (components?.hour ?? 17) : 17,
                                         minute: hasTime ? (components?.minute ?? 0) : 0, second: 0, of: day)
            }
            let fallback = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
            let task = Schoolwork(title: title, subject: subject, kind: kind, due: detected ?? fallback)
            return CaptureCandidate(task: task, needsDate: detected == nil)
        }
    }
}

public struct BriefPoint: Identifiable, Equatable, Sendable {
    public var id: String { source + text }
    public var text: String
    public var source: String
    public init(_ text: String, source: String) { self.text = text; self.source = source }
}

public enum BriefBuilder {
    /// Extracts instructions rather than inventing requirements. Source labels remain visible.
    public static func points(for task: Schoolwork, minutes: Int) -> [BriefPoint] {
        var points: [BriefPoint] = []
        let opening: String
        switch task.kind {
        case .homework: opening = "Work on \(task.title). Mark the questions you need help with."
        case .quiz, .test: opening = "Review \(task.title), then test yourself without looking at your notes."
        case .project: opening = "Move \(task.title) forward by finishing one concrete part."
        }
        points.append(BriefPoint(opening, source: "Session plan"))
        var seen = Set<String>()
        let sources = [("Your notes", task.notes)] + task.attachments.map { ($0.name, $0.text) }
        for (source, text) in sources {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count > 12 }
            let ranked = lines.enumerated().sorted { a, b in
                let first = score(a.element), second = score(b.element)
                return first == second ? a.offset < b.offset : first > second
            }
            var sourceCount = 0
            for (_, line) in ranked {
                let clean = line.replacingOccurrences(of: #"^[\s•\-*]+"#, with: "", options: .regularExpression)
                guard seen.insert(clean.lowercased()).inserted else { continue }
                let clipped = clean.count > 230 ? String(clean.prefix(227)) + "…" : clean
                points.append(BriefPoint(clipped, source: source)); sourceCount += 1
                if sourceCount >= 2 || points.count >= 5 { break }
            }
            if points.count >= 5 { break }
        }
        if !task.attachments.isEmpty && points.count == 1 {
            points.append(BriefPoint("Open \(task.attachments.map(\.name).joined(separator: ", ")) and check the instructions before you start.", source: "Attached files"))
        }
        points.append(BriefPoint("Spend about \(max(1, minutes - 3)) minutes working, then use the last \(min(3, minutes)) to check your progress and write the next step.", source: "Session plan"))
        return points
    }
    private static func score(_ line: String) -> Int {
        let lower = line.lowercased()
        return ["complete", "solve", "read", "write", "review", "submit", "chapter", "pages", "problem", "explain", "compare", "study", "prepare", "due", "learn"]
            .reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
    }
}
