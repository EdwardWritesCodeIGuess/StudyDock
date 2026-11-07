import SwiftUI
import StudyDockCore

struct BriefView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    var task: Schoolwork
    @State private var minutes: Int
    @State private var showingTimer = false
    init(task: Schoolwork) { self.task = task; _minutes = State(initialValue: task.minutes) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("BEFORE YOU BEGIN", systemImage: "leaf").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(DockStyle.green)
                    Text("A small plan.\nA focused mind.").font(.system(size: 34, weight: .medium, design: .serif))
                    Text(task.title).font(.title3).foregroundStyle(DockStyle.muted)
                    DockCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Here’s what to do").font(.headline)
                            ForEach(BriefBuilder.points(for: task, minutes: minutes)) { point in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(DockStyle.green).frame(width: 6, height: 6).padding(.top, 7)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(point.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                        Text(point.source).font(.system(size: 10, weight: .medium)).foregroundStyle(DockStyle.muted)
                                    }
                                }
                            }
                        }
                    }
                    Text("Pulled from your notes and readable materials, with a suggested session plan. Check the original for the full instructions.")
                        .font(.caption).foregroundStyle(DockStyle.muted)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How much time do you have?").font(.headline)
                        HStack(spacing: 10) {
                            ForEach([15, 25, 45, 60], id: \.self) { duration in
                                Button { minutes = duration } label: {
                                    Text("\(duration)m").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .foregroundStyle(minutes == duration ? .white : DockStyle.ink)
                                        .background(minutes == duration ? DockStyle.green : .white, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(ResponsiveButtonStyle())
                            }
                        }
                        Stepper("\(minutes) minutes", value: $minutes, in: 5...180, step: 5).font(.subheadline)
                    }
                    Button {
                        store.startFocus(task, minutes: minutes)
                        if store.focus != nil { showingTimer = true }
                    } label: { Label("Let’s focus for \(minutes) minutes", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(store.focus != nil)
                    if store.focus != nil && !showingTimer { Text("Finish your current session before starting another.").font(.caption).foregroundStyle(DockStyle.muted) }
                }.padding(26)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.dockSheet()
        .sheet(isPresented: $showingTimer, onDismiss: { dismiss() }) { FocusView().environmentObject(store) }
    }
}

struct FocusView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var endingEarly = false
    static func clock(_ seconds: TimeInterval) -> String {
        let count = Int(ceil(seconds))
        return String(format: "%02d:%02d", count / 60, count % 60)
    }
    var body: some View {
        NavigationStack {
            if let session = store.focus {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = session.remaining(at: context.date)
                    let done = remaining <= 0
                    ScrollView {
                        VStack(spacing: 25) {
                            Label(done ? "SESSION COMPLETE" : "ONE THING AT A TIME", systemImage: done ? "checkmark.circle" : "leaf")
                                .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(DockStyle.green)
                            Text(done ? "Look at you go." : "You’ve got this.").font(.system(size: 34, weight: .medium, design: .serif))
                            Text(session.title).font(.title3).foregroundStyle(DockStyle.muted).multilineTextAlignment(.center)
                            ZStack {
                                Circle().stroke(DockStyle.line, lineWidth: 8)
                                Circle().trim(from: 0, to: max(0, min(1, 1 - remaining / session.duration)))
                                    .stroke(DockStyle.green, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                                VStack(spacing: 8) {
                                    Text(Self.clock(remaining)).font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                                    Text(done ? "NICE WORK" : session.end == nil ? "PAUSED" : "STAY WITH IT").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(DockStyle.muted)
                                }
                            }.frame(width: 245, height: 245).padding(.vertical, 15).accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(Self.clock(remaining)) remaining\(session.end == nil ? ", paused" : "")")
                            if done {
                                Text("Take a breath. Check your progress, and note what comes next.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(DockStyle.muted)
                                Button("Save session & take a break") { store.finishFocus(); if store.focus == nil { dismiss() } }.buttonStyle(PrimaryButtonStyle())
                                if let task = store.item(session.taskID), !task.completed {
                                    Button("Mark assignment done too") { store.toggleCompleted(task.id); store.finishFocus(); if store.focus == nil { dismiss() } }.disabled(store.busy.contains(task.id))
                                }
                            } else {
                                Button(session.end == nil ? "Resume session" : "Pause session", systemImage: session.end == nil ? "play.fill" : "pause.fill") { store.togglePause() }.buttonStyle(PrimaryButtonStyle())
                                Button("End session early") { endingEarly = true }.font(.subheadline).foregroundStyle(DockStyle.muted)
                            }
                        }.padding(30).frame(maxWidth: .infinity)
                    }
                }
            } else { Text("Ready when you are.").font(.title2) }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back to desk") { dismiss() } } }
        .dockSheet()
        .confirmationDialog("End this session? Your focused time will be saved.", isPresented: $endingEarly, titleVisibility: .visible) {
            Button("Save progress & end") { store.finishFocus(); if store.focus == nil { dismiss() } }
        }
    }
}
