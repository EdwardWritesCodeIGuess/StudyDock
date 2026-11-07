import Foundation
import EventKit
import UserNotifications
import StudyDockCore

enum StudyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

@MainActor
final class AppleIntegration {
    private let events = EKEventStore()

    func export(_ task: Schoolwork) async throws -> String? {
        guard task.destination != .none else {
            try await removeLinkedItem(task)
            return nil
        }
        if let old = task.exportedDestination, old != task.destination {
            try await removeLinkedItem(task)
        }
        switch task.destination {
        case .calendar:
            guard try await events.requestFullAccessToEvents() else {
                throw StudyError.message("Calendar access is off. Enable StudyDock in System Settings → Privacy & Security → Calendars, then retry.")
            }
            let existing = task.exportedDestination == .calendar ? task.externalID.flatMap(events.event(withIdentifier:)) : nil
            // Event identifiers can change after a provider refresh. Recover our own event by its stable URL.
            let predicate = events.predicateForEvents(withStart: task.due.addingTimeInterval(-366 * 86400), end: task.due.addingTimeInterval(366 * 86400), calendars: nil)
            let recovered = existing == nil ? events.events(matching: predicate).first { $0.url == task.deepLink } : nil
            let event = existing ?? recovered ?? EKEvent(eventStore: events)
            if event.calendar == nil {
                let selected = UserDefaults.standard.string(forKey: "preferredCalendar") ?? ""
                if !selected.isEmpty {
                    guard let calendar = events.calendar(withIdentifier: selected), calendar.allowsContentModifications else { throw StudyError.message("Your chosen calendar is unavailable. Choose another in StudyDock Settings.") }
                    event.calendar = calendar
                } else { event.calendar = events.defaultCalendarForNewEvents }
            }
            guard event.calendar != nil, event.calendar.allowsContentModifications else {
                throw StudyError.message("Choose a writable default calendar in Apple Calendar, then retry.")
            }
            event.title = task.subject.isEmpty ? task.title : "\(task.subject): \(task.title)"
            event.startDate = task.due
            event.endDate = task.due.addingTimeInterval(task.kind == .project ? 15 * 60 : 60 * 60)
            event.notes = exportNotes(task); event.url = task.deepLink
            event.alarms = [EKAlarm(relativeOffset: -86400), EKAlarm(relativeOffset: -3600)]
            try events.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        case .reminders:
            guard try await events.requestFullAccessToReminders() else {
                throw StudyError.message("Reminders access is off. Enable StudyDock in System Settings → Privacy & Security → Reminders, then retry.")
            }
            let existing = task.exportedDestination == .reminders ? task.externalID.flatMap { events.calendarItem(withIdentifier: $0) as? EKReminder } : nil
            let reminder: EKReminder
            if let existing { reminder = existing }
            else {
                let matches: [EKReminder] = await withCheckedContinuation { continuation in
                    events.fetchReminders(matching: events.predicateForReminders(in: nil)) { continuation.resume(returning: $0 ?? []) }
                }
                reminder = matches.first { $0.url == task.deepLink } ?? EKReminder(eventStore: events)
            }
            if reminder.calendar == nil { reminder.calendar = events.defaultCalendarForNewReminders() }
            guard reminder.calendar != nil, reminder.calendar.allowsContentModifications else {
                throw StudyError.message("Create a writable list in Apple Reminders and set it as the default, then retry.")
            }
            reminder.title = task.subject.isEmpty ? task.title : "\(task.subject): \(task.title)"
            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.due)
            components.timeZone = .current
            reminder.dueDateComponents = components
            reminder.notes = exportNotes(task); reminder.url = task.deepLink
            reminder.isCompleted = task.completed
            reminder.alarms = [EKAlarm(absoluteDate: task.due)]
            try events.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        case .none: return nil
        }
    }

    func removeLinkedItem(_ task: Schoolwork) async throws {
        guard let id = task.externalID, let destination = task.exportedDestination else { return }
        if destination == .calendar {
            guard try await events.requestFullAccessToEvents() else { throw StudyError.message("Calendar permission is needed to remove the linked event.") }
            let predicate = events.predicateForEvents(withStart: task.due.addingTimeInterval(-366 * 86400), end: task.due.addingTimeInterval(366 * 86400), calendars: nil)
            if let event = events.event(withIdentifier: id) ?? events.events(matching: predicate).first(where: { $0.url == task.deepLink }) {
                try events.remove(event, span: .thisEvent, commit: true)
            }
        } else if destination == .reminders {
            guard try await events.requestFullAccessToReminders() else { throw StudyError.message("Reminders permission is needed to remove the linked reminder.") }
            if let reminder = events.calendarItem(withIdentifier: id) as? EKReminder { try events.remove(reminder, commit: true) }
        }
    }

    private func exportNotes(_ task: Schoolwork) -> String {
        (["Added by StudyDock", task.notes] + BriefBuilder.points(for: task, minutes: task.minutes).map { "• \($0.text)" }).joined(separator: "\n\n")
    }
}

@MainActor
final class FocusNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FocusNotifications()
    private var center: UNUserNotificationCenter? {
        // Running via `swift run` has no application bundle or notification identity.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }
    func schedule(_ session: FocusSession) async -> String? {
        guard let center, let end = session.end else { return nil }
        center.delegate = self
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return "Timer notifications are off. The countdown still works; enable notifications in System Settings for a background alert." }
            let content = UNMutableNotificationContent()
            content.title = "Good work. Take a breath."
            content.body = "Your focus session for \(session.title) is complete."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            try await center.add(UNNotificationRequest(identifier: "focus-\(session.id)", content: content, trigger: trigger))
            return nil
        } catch { return "The timer is running, but its notification could not be scheduled: \(error.localizedDescription)" }
    }
    func cancel(_ session: FocusSession) {
        center?.removePendingNotificationRequests(withIdentifiers: ["focus-\(session.id)"])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
