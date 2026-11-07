import XCTest
@testable import StudyDockCore

final class StudyDockTests: XCTestCase {
    func testHomeworkGoesToRemindersAndAssessmentsToCalendar() {
        XCTAssertEqual(WorkKind.homework.destination, .reminders)
        for kind in [WorkKind.quiz, .test, .project] { XCTAssertEqual(kind.destination, .calendar) }
    }
    func testCaptureCreatesSeparateReviewableTasksWithSubjects() {
        let tasks = CaptureParser.parse("[Math] Practice due November 20, 2027 at 5pm\n\n[Biology] Quiz November 21, 2027 at 9am\nHistory project")
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].task.subject, "Math")
        XCTAssertFalse(tasks[0].needsDate)
        XCTAssertEqual(tasks[0].task.destination, .reminders)
        XCTAssertEqual(tasks[1].task.kind, .quiz)
        XCTAssertEqual(tasks[1].task.destination, .calendar)
        XCTAssertTrue(tasks[2].needsDate)
        XCTAssertEqual(tasks[2].task.kind, .project)
    }
    func testRelativeDatesUseProvidedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10))!
        let result = CaptureParser.parse("Math practice tomorrow", now: now, calendar: calendar)[0]
        XCTAssertEqual(calendar.component(.day, from: result.task.due), 7)
        XCTAssertEqual(calendar.component(.hour, from: result.task.due), 17)
        XCTAssertFalse(result.needsDate)
    }
    func testExamRecognitionDoesNotMatchUnrelatedWords() {
        XCTAssertEqual(CaptureParser.parse("Review examples")[0].task.kind, .homework)
        XCTAssertEqual(CaptureParser.parse("Chemistry exam")[0].task.kind, .test)
    }
    func testMissingDateAlwaysRequiresReview() {
        XCTAssertTrue(CaptureParser.parse("Read chapter five")[0].needsDate)
        XCTAssertTrue(CaptureParser.parse("   \n\n").isEmpty)
    }
    func testBriefIncludesInstructionsAndSource() {
        let task = Schoolwork(title: "Practice", notes: "Solve questions 1–12 and show your work.", attachments: [Attachment(name: "Worksheet.pdf", storedName: "abc.pdf", text: "Explain the difference between mitosis and meiosis.")])
        let points = BriefBuilder.points(for: task, minutes: 25)
        XCTAssertTrue(points.contains { $0.text.contains("1–12") && $0.source == "Your notes" })
        XCTAssertTrue(points.contains { $0.text.contains("mitosis") && $0.source == "Worksheet.pdf" })
        XCTAssertTrue(points.last!.text.contains("22 minutes"))
    }
    func testBriefDeduplicatesInstructionsAndLimitsLength() {
        let line = "Complete the worksheet before class."
        let task = Schoolwork(title: "Work", notes: Array(repeating: line, count: 10).joined(separator: "\n"))
        let points = BriefBuilder.points(for: task, minutes: 15)
        XCTAssertEqual(points.filter { $0.text == line }.count, 1)
        XCTAssertLessThanOrEqual(points.count, 6)
    }
    func testUnreadableAttachmentPromptsOpeningOriginal() {
        let task = Schoolwork(title: "Worksheet", attachments: [Attachment(name: "scan.pdf", storedName: "scan.pdf")])
        XCTAssertTrue(BriefBuilder.points(for: task, minutes: 25).contains { $0.text.contains("Open scan.pdf") })
    }
    func testFocusSurvivesSleepWithoutTickCounting() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let session = FocusSession(task: Schoolwork(title: "Study"), minutes: 25, now: now)
        let restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.remaining(at: now.addingTimeInterval(1000)), 500)
        XCTAssertEqual(restored.remaining(at: now.addingTimeInterval(2000)), 0)
        XCTAssertEqual(restored.elapsed(at: now.addingTimeInterval(2000)), 1500)
    }
    func testPauseAndResumeExcludeBreakTime() {
        let now = Date(timeIntervalSince1970: 1000)
        var session = FocusSession(task: Schoolwork(title: "Study"), minutes: 10, now: now)
        session.pause(at: now.addingTimeInterval(120))
        XCTAssertEqual(session.remaining(at: now.addingTimeInterval(500)), 480)
        session.resume(at: now.addingTimeInterval(500))
        XCTAssertEqual(session.remaining(at: now.addingTimeInterval(600)), 380)
        XCTAssertEqual(session.elapsed(at: now.addingTimeInterval(600)), 220)
    }
    func testLibraryRoundTripPreservesLinksAttachmentsAndTimer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        var state = LibrarySnapshot()
        var task = Schoolwork(title: "Test", kind: .test, attachments: [Attachment(name: "notes.pdf", storedName: "xyz.pdf", text: "Read chapter 3.")])
        task.externalID = "event-123"; task.exportedDestination = .calendar
        state.tasks = [task]; state.focus = FocusSession(task: task, minutes: 25)
        try LibraryFile.write(state, to: file)
        let restored = try LibraryFile.read(from: file)
        XCTAssertEqual(restored.tasks, state.tasks)
        XCTAssertEqual(restored.focus?.end, state.focus?.end)
        XCTAssertEqual(restored.tasks[0].attachments[0].text, "Read chapter 3.")
    }
    func testCorruptedAndFutureLibrariesAreNotSilentlyDiscarded() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("bad json".utf8).write(to: file)
        XCTAssertThrowsError(try LibraryFile.read(from: file))
        var future = LibrarySnapshot(); future.version = 99
        try JSONEncoder().encode(future).write(to: file)
        XCTAssertThrowsError(try LibraryFile.read(from: file))
    }
}

final class DictationTranscriptTests: XCTestCase {
    func testLaterPhraseKeepsEarlierSentencesAndReplacesItsOwnRevision() {
        var transcript = DictationTranscript()
        transcript.update([.init(start: 0, text: "Math"), .init(start: 0.3, text: "is due Friday.")],
                          formattedText: "Math is due Friday.")
        transcript.update([.init(start: 3, text: "History"), .init(start: 3.2, text: "test"), .init(start: 3.5, text: "Tuesday.")],
                          formattedText: "History test Tuesday.")
        transcript.update([.init(start: 3.01, text: "History"), .init(start: 3.22, text: "test Thursday.")],
                          formattedText: "History test Thursday.")
        XCTAssertEqual(transcript.text, "Math is due Friday. History test Thursday.")
    }

    func testRecordingAppendsToTypedAndPreviouslyDictatedText() {
        let first = DictationTranscript.appending("Math due Friday.", to: "Existing notes")
        XCTAssertEqual(DictationTranscript.appending("History test Thursday.", to: first),
                       "Existing notes\nMath due Friday.\nHistory test Thursday.")
    }
}
