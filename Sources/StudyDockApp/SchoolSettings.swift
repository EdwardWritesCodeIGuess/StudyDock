import SwiftUI
import EventKit

struct ClassSlot: Codable, Identifiable {
    var id = UUID()
    var subject = ""
    var day = "A"
    var hour = 9
    var minute = 0
}
enum SchoolSchedule {
    static var slots: [ClassSlot] {
        get { (UserDefaults.standard.data(forKey: "classes").flatMap { try? JSONDecoder().decode([ClassSlot].self, from: $0) }) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "classes") }
    }
    static func day(on date: Date) -> String? {
        let c = Calendar.current
        guard !c.isDateInWeekend(date) else { return nil }
        let stored = UserDefaults.standard.object(forKey: "aDayAnchor") as? Double
        let anchor = Date(timeIntervalSince1970: stored ?? Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        var cursor = c.startOfDay(for: min(anchor, date)), count = 0
        let end = c.startOfDay(for: max(anchor, date))
        while cursor < end {
            if !c.isDateInWeekend(cursor) { count += 1 }
            guard let next = c.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count % 2 == 0 ? "A" : "B"
    }
    static func classTime(subject: String, on date: Date) -> Date? {
        guard let slot = slots.first(where: { !$0.subject.isEmpty && $0.subject.localizedCaseInsensitiveCompare(subject) == .orderedSame && $0.day == day(on: date) }) else { return nil }
        return Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: date)
    }
    static var context: String {
        "A/B rotation skips weekends, not holidays. Upcoming rotation: " + (0..<14).compactMap { offset -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()), let day = day(on: date) else { return nil }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            return "\(formatter.string(from: date)) \(day)"
        }.joined(separator: "; ") + ". Classes: " + slots.map { "\($0.subject), \($0.day) day, \($0.hour):\(String(format: "%02d", $0.minute))" }.joined(separator: "; ")
    }
}
struct SchoolSettings: View {
    @State private var slots = SchoolSchedule.slots
    @AppStorage("aDayAnchor") private var anchor = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
    @AppStorage("preferredCalendar") private var preferredCalendar = ""
    @State private var calendars: [EKCalendar] = []
    @State private var error: String?
    private let events = EKEventStore()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your school day").font(.title2)
            DatePicker("A known A day", selection: Binding(get: { Date(timeIntervalSince1970: anchor) }, set: { anchor = $0.timeIntervalSince1970 }), displayedComponents: .date)
            Text("Today: \(SchoolSchedule.day(on: Date()).map { "\($0) day" } ?? "Weekend"). Rotation skips weekends. Adjust the anchor after holidays or schedule changes.").font(.caption)
            ForEach($slots) { $slot in
                VStack(alignment: .leading) {
                    TextField("Class / subject", text: $slot.subject)
                    Picker("Day", selection: $slot.day) { Text("A").tag("A"); Text("B").tag("B") }.pickerStyle(.segmented)
                    HStack {
                        Stepper("Hour: \(slot.hour)", value: $slot.hour, in: 0...23)
                        Stepper("Minute: \(slot.minute)", value: $slot.minute, in: 0...59)
                        Button("Remove") { slots.removeAll { $0.id == slot.id } }
                    }
                }.padding(12).background(DockStyle.paper, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Add class", systemImage: "plus") { slots.append(ClassSlot()) }
            Divider()
            Text("Calendar destination").font(.headline)
            Button("Choose from my calendars") {
                Task {
                    do {
                        guard try await events.requestFullAccessToEvents() else { error = "Allow Calendar access in Settings to choose a calendar."; return }
                        calendars = events.calendars(for: .event).filter(\.allowsContentModifications)
                    } catch { self.error = error.localizedDescription }
                }
            }
            Picker("Default calendar", selection: $preferredCalendar) {
                Text("Apple Calendar default").tag("")
                ForEach(calendars, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("New events use this calendar. Existing events keep their current calendar.").font(.caption)
        }.onAppear {
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess { calendars = events.calendars(for: .event).filter(\.allowsContentModifications) }
        }.onChange(of: slots.map { "\($0.id)\($0.subject)\($0.day)\($0.hour)\($0.minute)" }) { _, _ in SchoolSchedule.slots = slots }
    }
}
struct HelpView: View {
    private let steps = [
        ("1", "Empty your head", "Choose Add schoolwork. Add one item, paste a list, or use the microphone to talk through everything on your plate."),
        ("2", "Review your plan", "AI separates your words into homework, quizzes, tests, and projects. Check the titles, subjects, and dates, then add the items. Estimated dates always need your confirmation."),
        ("3", "Let your schedule help", "In Settings, enter your A/B classes and a known A day. When you give a due date without a time, StudyDock suggests the matching class start. Weekends are skipped; reset the anchor after holidays."),
        ("4", "Keep your materials close", "Attach PDFs, photos, and notes to an item. Open the original any time. Before a focus session, read the short brief and choose how long to work."),
        ("5", "Find it in Apple apps", "Homework goes to Reminders. Quizzes, tests, and projects go to your chosen calendar. Grant access when asked. Changes flow from StudyDock to those apps."),
        ("6", "Choose your AI", "Apple Intelligence runs locally on supported devices with its model enabled. Local server mode connects to your own compatible model server. NVIDIA and custom cloud providers are optional and use your own key. Cloud mode sends the capture text and class schedule to that provider." )
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A calmer way to get it done.").font(.system(size: 32, weight: .medium, design: .serif))
                Text("Your guide to StudyDock").foregroundStyle(DockStyle.muted)
                ForEach(steps, id: \.0) { step in
                    DockCard { HStack(alignment: .top, spacing: 18) {
                        Text(step.0).font(.title).foregroundStyle(DockStyle.green)
                        VStack(alignment: .leading, spacing: 10) { Text(step.1).font(.headline); Text(step.2).font(.subheadline) }
                    } }
                }
                Text("Your library stays on this device. Calendar and Reminders can sync through your Apple accounts. The StudyDock library itself does not yet sync across devices.").font(.caption).foregroundStyle(DockStyle.muted)
            }.padding(28).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
    }
}
