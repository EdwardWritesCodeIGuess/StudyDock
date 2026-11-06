import Foundation

@main
enum CoreChecks {
    static func main() throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ title: String) {
            guard condition() else { fatalError("FAIL: \(title)") }
            passed += 1; print("PASS: \(title)")
        }
        check(WorkKind.homework.destination == .reminders && [WorkKind.quiz, .test, .project].allSatisfy { $0.destination == .calendar }, "Calendar and Reminders routing")
        let captured = CaptureParser.parse("[Math] Homework tomorrow at 5pm\n[Biology] Quiz November 20, 2027 at 9am\nHistory project")
        check(captured.count == 3 && captured[0].task.subject == "Math" && captured[1].task.kind == .quiz && captured[2].needsDate, "Bulk capture and missing-date review")
        let task = Schoolwork(title: "Worksheet", notes: "Solve problems 1–12 and show your work.", attachments: [Attachment(name: "worksheet.pdf", storedName: "test.pdf", text: "Explain the difference between mitosis and meiosis.")])
        let brief = BriefBuilder.points(for: task, minutes: 25)
        check(brief.contains { $0.source == "Your notes" && $0.text.contains("1–12") } && brief.contains { $0.source == "worksheet.pdf" }, "Sourced brief includes notes and file instructions")
        let now = Date(timeIntervalSince1970: 1000)
        var focus = FocusSession(task: task, minutes: 10, now: now)
        focus.pause(at: now.addingTimeInterval(120))
        check(focus.remaining(at: now.addingTimeInterval(1000)) == 480, "Pause excludes time spent away")
        focus.resume(at: now.addingTimeInterval(1000))
        check(focus.remaining(at: now.addingTimeInterval(1200)) == 280, "Resume preserves remaining duration")
        let restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(focus))
        check(restored.remaining(at: now.addingTimeInterval(2000)) == 0 && restored.elapsed(at: now.addingTimeInterval(2000)) == 600, "Timer survives relaunch and clamps completion")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        var state = LibrarySnapshot(); state.tasks = [task]; state.focus = focus
        try LibraryFile.write(state, to: file)
        let loaded = try LibraryFile.read(from: file)
        check(loaded.tasks == state.tasks && loaded.focus?.end == focus.end, "Atomic persistence preserves tasks, files, and timer")
        try Data("corrupt".utf8).write(to: file)
        var rejected = false
        do { _ = try LibraryFile.read(from: file) } catch { rejected = true }
        check(rejected, "Corrupt data is surfaced instead of discarded")
        print("\(passed) behavioral checks passed.")
    }
}
