import Foundation

public enum WorkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case homework, quiz, test, project
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .homework: return "text.book.closed"
        case .quiz: return "bolt.fill"
        case .test: return "checkmark.seal"
        case .project: return "square.stack.3d.up"
        }
    }
    public var destination: ExportDestination { self == .homework ? .reminders : .calendar }
}

public enum ExportDestination: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar, reminders, none
    public var id: String { rawValue }
    public var title: String { self == .none ? "Only in StudyDock" : "Apple \(rawValue.capitalized)" }
}

public struct Attachment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var storedName: String
    public var text: String
    public var note: String?
    public init(id: UUID = UUID(), name: String, storedName: String, text: String = "", note: String? = nil) {
        self.id = id; self.name = name; self.storedName = storedName; self.text = text; self.note = note
    }
}

public struct Schoolwork: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var subject: String
    public var kind: WorkKind
    public var due: Date
    public var notes: String
    public var minutes: Int
    public var completed: Bool
    public var destination: ExportDestination
    public var attachments: [Attachment]
    public var externalID: String?
    public var exportedDestination: ExportDestination?
    public var syncError: String?
    public var lastExportedAt: Date?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, subject: String = "", kind: WorkKind = .homework,
                due: Date = Date(), notes: String = "", minutes: Int = 25,
                completed: Bool = false, destination: ExportDestination? = nil, attachments: [Attachment] = []) {
        self.id = id; self.title = title; self.subject = subject; self.kind = kind
        self.due = due; self.notes = notes; self.minutes = minutes; self.completed = completed
        self.destination = destination ?? kind.destination; self.attachments = attachments; self.createdAt = Date()
    }
    public var deepLink: URL { URL(string: "studydock://task/\(id.uuidString)")! }
}

public struct FocusSession: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var taskID: UUID
    public var title: String
    public var duration: TimeInterval
    public var end: Date?
    public var pausedRemaining: TimeInterval
    public var startedAt: Date
    public init(task: Schoolwork, minutes: Int, now: Date = Date()) {
        taskID = task.id; title = task.title; duration = Double(minutes * 60)
        end = now.addingTimeInterval(duration); pausedRemaining = duration; startedAt = now
    }
    public func remaining(at now: Date) -> TimeInterval { max(0, end.map { $0.timeIntervalSince(now) } ?? pausedRemaining) }
    public func elapsed(at now: Date) -> TimeInterval { max(0, min(duration, duration - remaining(at: now))) }
    public mutating func pause(at now: Date) { pausedRemaining = remaining(at: now); end = nil }
    public mutating func resume(at now: Date) { end = now.addingTimeInterval(pausedRemaining) }
}

public struct FocusRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var seconds: Int
    public var finishedAt: Date
    public init(id: UUID, taskID: UUID, seconds: Int, finishedAt: Date = Date()) {
        self.id = id; self.taskID = taskID; self.seconds = seconds; self.finishedAt = finishedAt
    }
}

public struct LibrarySnapshot: Codable, Sendable {
    public var version = 1
    public var tasks: [Schoolwork] = []
    public var focus: FocusSession?
    public var history: [FocusRecord] = []
    public var automaticExport = true
    public init() {}
}

public enum LibraryFile {
    public static func read(from url: URL) throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibrarySnapshot() }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }
    public static func write(_ snapshot: LibrarySnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
