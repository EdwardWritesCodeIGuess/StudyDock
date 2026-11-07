import SwiftUI
import StudyDockCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case dashboard = "My desk", upcoming = "Coming up", all = "All schoolwork", completed = "Completed", settings = "Settings", help = "How to use"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .upcoming: return "calendar"
        case .all: return "tray.full"
        case .completed: return "checkmark.circle"
        case .settings: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        }
    }
}

struct Dashboard: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: LibraryFilter? = .dashboard
    @State private var query = ""
    @State private var adding = false
    @State private var selected: Schoolwork?
    @State private var preparing: Schoolwork?
    @State private var showingFocus = false
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    private var active: [Schoolwork] { store.tasks.filter { !$0.completed }.sorted { $0.due < $1.due } }
    private var visible: [Schoolwork] {
        store.tasks.filter { task in
            let matches: Bool
            switch filter ?? .dashboard {
            case .completed: matches = task.completed
            case .all: matches = true
            case .upcoming: matches = !task.completed && task.due >= Calendar.current.startOfDay(for: Date())
            default: matches = !task.completed
            }
            return matches && (query.isEmpty || [task.title, task.subject, task.notes].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted { $0.due < $1.due }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(DockStyle.green)
                    Text("StudyDock").font(.system(size: 23, weight: .bold, design: .rounded))
                }.padding(.top, 22).padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR WORKSPACE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(DockStyle.muted).padding(.horizontal, 18).padding(.bottom, 8)
                    ForEach(LibraryFilter.allCases) { item in
                        Button { filter = item; compactColumn = .detail } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).frame(width: 20)
                                Text(item.rawValue)
                                Spacer()
                                if item == .all { Text("\(store.tasks.count)").font(.caption) }
                            }.font(.system(size: 13, weight: filter == item ? .semibold : .regular))
                                .padding(12).foregroundStyle(filter == item ? DockStyle.green : DockStyle.muted)
                                .background(filter == item ? DockStyle.mint.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 11))
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: filter)
                        }.buttonStyle(ResponsiveButtonStyle())
                    }
                }.padding(.horizontal, 12)
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "leaf").font(.title3)
                    Text("A little progress,\nevery day.").font(.system(size: 15, weight: .medium, design: .serif))
                    Text("One task. One focused session.").font(.caption).foregroundStyle(DockStyle.muted)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(DockStyle.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 16)).padding(16)
            }.background(DockStyle.paper).navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 260)
        } detail: {
            NavigationStack {
                Group {
                    if filter == .help { HelpView() }
                    else if filter == .settings { SettingsView() }
                    else { desk }
                }
                .background(DockStyle.paper)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: { Label("Add schoolwork", systemImage: "plus") }
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
            }
        }
        .tint(DockStyle.green).foregroundStyle(DockStyle.ink).preferredColorScheme(.light)
        .sheet(isPresented: $adding) { CaptureView().environmentObject(store) }
        .sheet(item: $selected) { task in TaskDetail(taskID: task.id).environmentObject(store) }
        .sheet(item: $preparing) { task in BriefView(task: task).environmentObject(store) }
        .sheet(isPresented: $showingFocus) { FocusView().environmentObject(store) }
        .alert("StudyDock", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
        .onOpenURL { url in
            if url.scheme == "studydock", let id = UUID(uuidString: url.lastPathComponent), let item = store.item(id) { selected = item }
        }
    }

    private var desk: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                            .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(DockStyle.muted)
                        Text(filter == .dashboard ? "Clear desk. Clear mind." : (filter ?? .dashboard).rawValue)
                            .font(.system(size: 32, weight: .medium, design: .serif))
                        Text(filter == .dashboard ? "Everything you need to do, with a place to start." : "A little organization goes a long way.")
                            .font(.subheadline).foregroundStyle(DockStyle.muted)
                    }
                    Spacer(minLength: 0)
                }
                if let session = store.focus {
                    Button { showingFocus = true } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack {
                                Image(systemName: "timer")
                                VStack(alignment: .leading) {
                                    Text(session.remaining(at: context.date) == 0 ? "Session complete" : "Your focus session")
                                    Text(session.title).font(.caption).lineLimit(1)
                                }
                                Spacer()
                                Text(FocusView.clock(session.remaining(at: context.date))).monospacedDigit().font(.title2)
                                Image(systemName: "arrow.up.right")
                            }.padding(20).foregroundStyle(DockStyle.ink).background(DockStyle.mint, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }.buttonStyle(ResponsiveButtonStyle())
                }
                if filter == .dashboard {
                    HStack(spacing: 12) {
                        metric("DUE TODAY", value: "\(active.filter { Calendar.current.isDateInToday($0.due) }.count)", symbol: "sun.max")
                        metric("ON YOUR DESK", value: "\(active.count)", symbol: "tray")
                        metric("FOCUSED", value: "\(store.todayFocusMinutes)m", symbol: "hourglass")
                    }
                    focusCard
                }
                HStack {
                    Text(filter == .dashboard ? "On your radar" : "Your schoolwork").font(.system(size: 21, weight: .medium, design: .serif))
                    Spacer()
                    Text("\(visible.count) items").font(.caption).foregroundStyle(DockStyle.muted)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(DockStyle.muted)
                    TextField("Find a task, subject, or note", text: $query).textFieldStyle(.plain)
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
                if visible.isEmpty {
                    DockCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "tray").font(.largeTitle).foregroundStyle(DockStyle.green)
                            Text(query.isEmpty ? "Give your schoolwork a home." : "No matching schoolwork.").font(.title3)
                            Text(query.isEmpty ? "Add an assignment, a quiz date, or paste your whole to-do list. We’ll help you take it one session at a time." : "Try another subject or a shorter search.").font(.subheadline).foregroundStyle(DockStyle.muted)
                            if query.isEmpty { Button("Add your first item") { adding = true }.buttonStyle(PrimaryButtonStyle()) }
                        }.padding(.vertical, 15)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visible) { task in
                            WorkRow(task: task, busy: store.busy.contains(task.id), open: { selected = task }, complete: { store.toggleCompleted(task.id) })
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Homework → Reminders  ·  Quizzes, tests & projects → Calendar")
                }.font(.caption).foregroundStyle(DockStyle.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(28).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
    }
    private func metric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: symbol); Spacer(minLength: 0) }.foregroundStyle(DockStyle.green)
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: value)
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(DockStyle.muted)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Label("A GOOD PLACE TO START", systemImage: "sparkle").font(.system(size: 10, weight: .bold)).tracking(1.6); Spacer() }
                .foregroundStyle(DockStyle.mint)
            Text(active.first?.title ?? "Small steps. Real progress.").font(.system(size: 27, weight: .medium, design: .serif))
            Text(active.first == nil ? "Drop your work here. Come back with a plan." : "Get a quick brief, pick your time, and give one thing your attention.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.72))
            HStack {
                Button { if let first = active.first { preparing = first } else { adding = true } } label: {
                    Label(active.isEmpty ? "Add schoolwork" : "Plan a focus session", systemImage: "arrow.right")
                }.buttonStyle(PrimaryButtonStyle(light: true)).disabled(store.focus != nil)
                Spacer(minLength: 0)
                Image(systemName: "leaf.circle").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(DockStyle.mint.opacity(0.7)).accessibilityHidden(true)
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .background(DockStyle.ink, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct WorkRow: View {
    var task: Schoolwork
    var busy: Bool
    var open: () -> Void
    var complete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @GestureState private var swipeDistance: CGFloat = 0
    #endif

    var body: some View {
        #if os(iOS)
        content
            .offset(x: reduceMotion ? 0 : -min(swipeDistance, 115))
            .background(alignment: .trailing) {
                if swipeDistance > 0 {
                    Label(task.completed ? "Reopen" : "Complete",
                          systemImage: task.completed ? "arrow.uturn.backward" : "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DockStyle.green)
                        .padding(.trailing, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .background(DockStyle.mint.opacity(swipeDistance >= 100 ? 1 : 0.55),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .animation(reduceMotion || swipeDistance > 0 ? nil : .easeOut(duration: 0.16), value: swipeDistance)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating($swipeDistance) { value, distance, _ in
                        if !busy && value.translation.width < 0
                            && -value.translation.width > 1.5 * abs(value.translation.height) {
                            distance = -value.translation.width
                        }
                    }
                    .onEnded { value in
                        if !busy && value.translation.width < -100
                            && -value.translation.width > 1.5 * abs(value.translation.height) {
                            complete()
                        }
                    }
            )
            .sensoryFeedback(.selection, trigger: task.completed)
        #else
        content
        #endif
    }

    private var content: some View {
        HStack(spacing: 14) {
            Button(action: complete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 23, weight: .light))
                    .foregroundStyle(task.completed ? DockStyle.green : DockStyle.line)
            }.buttonStyle(ResponsiveButtonStyle()).disabled(busy).accessibilityLabel(task.completed ? "Mark incomplete" : "Mark complete")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if !task.subject.isEmpty { Text(task.subject.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(DockStyle.muted) }
                        KindBadge(kind: task.kind)
                    }
                    Text(task.title).font(.system(size: 15, weight: .medium)).strikethrough(task.completed).multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        Label(task.due.formatted(.dateTime.month(.abbreviated).day().hour().minute()), systemImage: "calendar")
                            .foregroundStyle(task.due < Date() && !task.completed ? Color.red.opacity(0.75) : DockStyle.muted)
                        if !task.attachments.isEmpty { Label("\(task.attachments.count)", systemImage: "paperclip") }
                        if task.syncError != nil { Label("Needs sync", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                        if busy { ProgressView().controlSize(.mini) }
                    }.font(.system(size: 11)).foregroundStyle(DockStyle.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(ResponsiveButtonStyle())
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(DockStyle.muted).accessibilityHidden(true)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DockStyle.line, lineWidth: 0.6))
    }
}
