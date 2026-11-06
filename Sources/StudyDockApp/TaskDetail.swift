import SwiftUI
import QuickLook
import StudyDockCore

struct TaskDetail: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    var taskID: UUID
    @State private var editing = false
    @State private var preparing = false
    @State private var deleting = false
    @State private var preview: URL?
    var body: some View {
        NavigationStack {
            if let task = store.item(taskID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { KindBadge(kind: task.kind); Spacer(); Text(task.subject.uppercased()).font(.caption).tracking(1).foregroundStyle(DockStyle.muted) }
                        Text(task.title).font(.system(size: 30, weight: .medium, design: .serif))
                        Label(task.due.formatted(date: .complete, time: .shortened), systemImage: "calendar").font(.subheadline)
                        HStack(spacing: 12) {
                            Button("Start a focus session", systemImage: "timer") { preparing = true }.buttonStyle(PrimaryButtonStyle()).disabled(store.focus != nil || task.completed)
                            Button(task.completed ? "Reopen" : "Mark done") { store.toggleCompleted(task.id) }.disabled(store.busy.contains(task.id))
                        }
                        DockCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(task.destination.title, systemImage: task.destination == .reminders ? "checklist" : "calendar").font(.headline)
                                if store.busy.contains(task.id) { ProgressView("Updating…") }
                                else if let error = task.syncError { Text(error).font(.caption).foregroundStyle(.orange) }
                                else if let last = task.lastExportedAt { Text("Last sent \(last.formatted(date: .abbreviated, time: .shortened)).").font(.caption).foregroundStyle(DockStyle.muted) }
                                else if task.destination != .none { Text("Ready to add when syncing is enabled.").font(.caption).foregroundStyle(DockStyle.muted) }
                                if task.destination != .none {
                                    Button(task.externalID == nil ? "Add now" : "Update linked item", systemImage: "arrow.triangle.2.circlepath") { Task { await store.sync(task.id) } }.disabled(store.busy.contains(task.id))
                                }
                            }
                        }
                        if !task.notes.isEmpty {
                            DockCard { VStack(alignment: .leading, spacing: 12) { Text("The assignment").font(.headline); Text(task.notes).font(.body).textSelection(.enabled) } }
                        }
                        if !task.attachments.isEmpty {
                            Text("Your materials").font(.system(size: 21, weight: .medium, design: .serif))
                            ForEach(task.attachments) { file in
                                Button { preview = store.attachmentURL(file) } label: {
                                    DockCard {
                                        HStack {
                                            Image(systemName: "doc.text").font(.title2).foregroundStyle(DockStyle.green)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(file.name).font(.subheadline)
                                                if let note = file.note { Text(note).font(.caption).foregroundStyle(DockStyle.muted) }
                                            }
                                            Spacer(); Image(systemName: "arrow.up.right")
                                        }
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                        Button("Delete schoolwork", role: .destructive) { deleting = true }.disabled(store.busy.contains(task.id)).padding(.top, 12)
                    }.padding(24)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.disabled(store.busy.contains(task.id)) }
                }
                .sheet(isPresented: $editing) { CaptureView(task: task).environmentObject(store) }
                .sheet(isPresented: $preparing) { BriefView(task: task).environmentObject(store) }
                .quickLookPreview($preview)
                .confirmationDialog("Delete this schoolwork and its linked Calendar event or Reminder?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete item and linked entry", role: .destructive) { Task { if await store.delete(taskID) { dismiss() } } }
                }
            } else { Text("This item is no longer in your library.") }
        }.dockSheet()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: StudyStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Make yourself at home.").font(.system(size: 30, weight: .medium, design: .serif))
                DockCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Automatically add and update schoolwork", isOn: Binding(get: { store.snapshot.automaticExport }, set: store.setAutomaticExport))
                        Label("Homework → Apple Reminders", systemImage: "checklist")
                        Label("Quizzes, tests & projects → Apple Calendar", systemImage: "calendar")
                        Text("Uses your default calendar and reminder list. You’ll be asked for permission when you first add an item. Calendar events get alerts one day and one hour before; homework reminders alert at the due time.").font(.caption).foregroundStyle(DockStyle.muted)
                        Text("Changes flow from StudyDock to Apple apps. Edits made in Calendar or Reminders aren’t imported back. Turning this on affects future saves; use Add now in an existing item to send it.").font(.caption).foregroundStyle(DockStyle.muted)
                    }
                }
                DockCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Your materials stay with you", systemImage: "lock.shield").font(.headline)
                        Text("Your tasks and files are saved on this device. Briefs pull instructions from your notes, PDF text, and locally recognized text in scans and images. No account or AI subscription is needed.")
                        Text("StudyDock’s library does not currently sync between devices. Calendar and Reminders entries can sync through the Apple accounts you use for those apps.")
                        Text("Briefs are a quick starting point. Open the original material for the full assignment.")
                    }.font(.subheadline).foregroundStyle(DockStyle.muted)
                }
                Text("StudyDock 1.0  ·  A calmer place for schoolwork.").font(.caption).foregroundStyle(DockStyle.muted)
            }.padding(28).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
    }
}
