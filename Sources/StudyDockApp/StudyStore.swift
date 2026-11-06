import Foundation
import SwiftUI
import StudyDockCore

@MainActor
final class StudyStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var busy = Set<UUID>()
    @Published var message: String?
    @Published private(set) var readOnly = false
    let directory: URL
    private let file: URL
    private let integration = AppleIntegration()
    private let demo: Bool
    var attachmentsDirectory: URL { directory.appendingPathComponent("Attachments", isDirectory: true) }
    var tasks: [Schoolwork] { snapshot.tasks }
    var focus: FocusSession? { snapshot.focus }

    init(demo: Bool = false) {
        self.demo = demo
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(demo ? "StudyDock-Preview" : "StudyDock", isDirectory: true)
        file = directory.appendingPathComponent("library.json")
        if demo { snapshot.tasks = Self.samples(); snapshot.automaticExport = false }
        else {
            do { snapshot = try LibraryFile.read(from: file) }
            catch {
                readOnly = true
                message = "Your saved library could not be read. It has been preserved at \(file.path). Restart after restoring a valid copy. \(error.localizedDescription)"
            }
        }
    }

    func item(_ id: UUID) -> Schoolwork? { tasks.first { $0.id == id } }
    var todayFocusMinutes: Int {
        snapshot.history.filter { Calendar.current.isDateInToday($0.finishedAt) }.reduce(0) { $0 + $1.seconds } / 60
    }
    @discardableResult
    private func commit(_ change: (inout LibrarySnapshot) -> Void) -> Bool {
        guard !readOnly else { return false }
        var updated = snapshot
        change(&updated)
        do {
            if !demo { try LibraryFile.write(updated, to: file) }
            snapshot = updated
            return true
        } catch { message = "Could not save your change: \(error.localizedDescription)"; return false }
    }
    @discardableResult
    func save(_ task: Schoolwork) -> Bool {
        guard !busy.contains(task.id) else { message = "Wait for this item to finish syncing, then try again."; return false }
        var validated = task
        validated.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        validated.minutes = min(180, max(5, task.minutes))
        guard !validated.title.isEmpty else { return false }
        let success = commit { state in
            if let i = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[i] = validated }
            else { state.tasks.append(validated) }
        }
        if success && snapshot.automaticExport { Task { await sync(task.id) } }
        return success
    }
    func setAutomaticExport(_ value: Bool) { commit { $0.automaticExport = value } }
    func toggleCompleted(_ id: UUID) {
        guard var task = item(id) else { return }
        task.completed.toggle(); save(task)
    }
    func sync(_ id: UUID) async {
        guard !demo, !readOnly, !busy.contains(id), let task = item(id) else { return }
        busy.insert(id); defer { busy.remove(id) }
        do {
            let externalID = try await integration.export(task)
            commit { state in
                guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
                state.tasks[index].externalID = externalID
                state.tasks[index].exportedDestination = task.destination == .none ? nil : task.destination
                state.tasks[index].lastExportedAt = Date()
                state.tasks[index].syncError = nil
            }
        } catch {
            commit { state in
                guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
                state.tasks[index].syncError = error.localizedDescription
            }
            message = "“\(task.title)” is saved in StudyDock. \(error.localizedDescription)"
        }
    }
    func delete(_ id: UUID) async -> Bool {
        guard !busy.contains(id), let task = item(id) else { return false }
        busy.insert(id); defer { busy.remove(id) }
        do {
            if !demo { try await integration.removeLinkedItem(task) }
            guard commit({ $0.tasks.removeAll { $0.id == id } }) else { return false }
            cleanUp(task.attachments)
            return true
        } catch { message = "Could not remove the linked item. Your schoolwork is still saved. \(error.localizedDescription)"; return false }
    }
    func cleanUp(_ attachments: [Attachment]) {
        let used = Set(tasks.flatMap(\.attachments).map(\.storedName))
        for attachment in attachments where !used.contains(attachment.storedName) {
            try? FileManager.default.removeItem(at: attachmentURL(attachment))
        }
    }
    func attachmentURL(_ attachment: Attachment) -> URL { attachmentsDirectory.appendingPathComponent(attachment.storedName) }

    func startFocus(_ task: Schoolwork, minutes: Int) {
        guard focus == nil else { message = "Finish your current focus session before starting another."; return }
        let session = FocusSession(task: task, minutes: min(180, max(5, minutes)))
        if commit({ $0.focus = session }) { schedule(session) }
    }
    func togglePause() {
        guard var session = focus else { return }
        if session.end == nil { session.resume(at: Date()) }
        else { session.pause(at: Date()) }
        if commit({ $0.focus = session }) {
            FocusNotifications.shared.cancel(session)
            if session.end != nil { schedule(session) }
        }
    }
    func finishFocus() {
        guard let session = focus else { return }
        let record = FocusRecord(id: session.id, taskID: session.taskID, seconds: Int(session.elapsed(at: Date())))
        if commit({ state in
            if !state.history.contains(where: { $0.id == session.id }) && record.seconds > 0 { state.history.append(record) }
            state.focus = nil
        }) { FocusNotifications.shared.cancel(session) }
    }
    private func schedule(_ session: FocusSession) {
        guard !demo else { return }
        Task {
            let warning = await FocusNotifications.shared.schedule(session)
            guard focus?.id == session.id, focus?.end == session.end else { FocusNotifications.shared.cancel(session); return }
            if let warning { message = warning }
        }
    }

    static func samples() -> [Schoolwork] {
        let now = Date()
        return [
            Schoolwork(title: "Quadratic equations · practice set", subject: "MATH", due: now.addingTimeInterval(7200), notes: "Solve problems 1–12 on page 84.\nShow your work and check each answer by substitution.", minutes: 25),
            Schoolwork(title: "Cell biology quiz", subject: "BIOLOGY", kind: .quiz, due: now.addingTimeInterval(86400), notes: "Review organelles and their functions.\nCompare plant and animal cells.\nPractice drawing a labeled cell from memory.", minutes: 30),
            Schoolwork(title: "The Great Gatsby · chapter 4", subject: "ENGLISH", due: now.addingTimeInterval(90000), notes: "Read chapter 4 and find three examples of symbolism.", minutes: 20),
            Schoolwork(title: "Our changing planet", subject: "GEOGRAPHY", kind: .project, due: now.addingTimeInterval(3 * 86400), notes: "Prepare a five-slide presentation explaining one climate solution.", minutes: 45)
        ]
    }
}
