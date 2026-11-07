import SwiftUI
import UniformTypeIdentifiers
import StudyDockCore

struct CaptureView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Schoolwork
    @StateObject private var recorder = DictationRecorder()
    @State private var understanding = false
    @State private var mode = 0
    @State private var dump = ""
    @State private var candidates: [CaptureCandidate] = []
    @State private var importing = false
    @State private var processingFiles = false
    @State private var localError: String?
    @State private var imported: [Attachment] = []
    @State private var dropTargeted = false
    private let editing: Bool

    init(task: Schoolwork? = nil) {
        editing = task != nil
        _draft = State(initialValue: task ?? Schoolwork(title: "", due: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(editing ? "A little fine-tuning." : "Get it out of your head.").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Homework lands in Reminders. Quizzes, tests, and projects land in Calendar.")
                        .font(.subheadline).foregroundStyle(DockStyle.muted)
                    if !editing {
                        Picker("Add mode", selection: $mode) { Text("One item").tag(0); Text("Talk or paste").tag(1) }.pickerStyle(.segmented)
                    }
                    if mode == 0 { singleItem } else { bulkItems }
                    if let localError { Label(localError, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.caption) }
                }.padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "Save changes" : (mode == 1 ? "Add \(candidates.count) items" : "Add item")) { save() }
                        .fontWeight(.semibold).disabled(!canSave || processingFiles || store.readOnly)
                }
            }
        }.dockSheet()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): localError = error.localizedDescription
            }
        }
        .onDisappear { recorder.stop(); store.cleanUp(imported) }
    }
    private var canSave: Bool {
        if mode == 0 { return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.busy.contains(draft.id) }
        return !candidates.isEmpty && candidates.allSatisfy { !$0.needsDate && !$0.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var singleItem: some View {
        VStack(alignment: .leading, spacing: 20) {
            DockCard {
                VStack(alignment: .leading, spacing: 18) {
                    field("WHAT’S ON YOUR PLATE?") { TextField("e.g. Chapter 5 practice questions", text: $draft.title).textFieldStyle(.roundedBorder) }
                    field("SUBJECT") { TextField("e.g. Biology", text: $draft.subject).textFieldStyle(.roundedBorder) }
                    Picker("Type", selection: $draft.kind) { ForEach(WorkKind.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: draft.kind) { _, kind in draft.destination = kind.destination }
                    DatePicker(draft.kind == .quiz || draft.kind == .test ? "When is it?" : "Due", selection: $draft.due)
                    Stepper("Focus session: \(draft.minutes) min", value: $draft.minutes, in: 5...180, step: 5)
                    Picker("Send to", selection: $draft.destination) { ForEach(ExportDestination.allCases) { Text($0.title).tag($0) } }
                }.font(.subheadline)
            }
            field("NOTES & INSTRUCTIONS") {
                TextEditor(text: $draft.notes).font(.body).frame(minHeight: 110).padding(8)
                    .scrollContentBackground(.hidden).background(.white, in: RoundedRectangle(cornerRadius: 12))
                Text("Paste the assignment instructions here. They’ll help shape your session brief.").font(.caption).foregroundStyle(DockStyle.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR MATERIALS").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(DockStyle.muted)
                Button { importing = true } label: {
                    VStack(spacing: 10) {
                        if processingFiles { ProgressView(); Text("Reading your materials…") }
                        else {
                            Image(systemName: "arrow.down.doc").font(.title2)
                            Text("Drop files here, or choose files").fontWeight(.medium)
                            Text("PDFs, images, notes & other class materials · up to 50 MB each").font(.caption)
                        }
                    }.padding(24).frame(maxWidth: .infinity)
                        .background(dropTargeted ? DockStyle.mint : DockStyle.mint.opacity(0.20), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(DockStyle.green.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
                }.buttonStyle(.plain).disabled(processingFiles)
                    .dropDestination(for: URL.self) { urls, _ in guard !processingFiles else { return false }; importFiles(urls); return true } isTargeted: { dropTargeted = $0 }
                ForEach(draft.attachments) { file in
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(DockStyle.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name).font(.subheadline)
                            if let note = file.note { Text(note).font(.caption).foregroundStyle(DockStyle.muted) }
                        }
                        Spacer()
                        Button { draft.attachments.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel("Remove \(file.name)")
                    }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    private var bulkItems: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Talk it through, paste a list, or type naturally. Review the suggested tasks before adding.").font(.subheadline)
            Button(recorder.recording ? "Stop dictation" : "Dictate schoolwork", systemImage: recorder.recording ? "stop.circle" : "mic") {
                if recorder.recording { recorder.stop() } else { Task { await recorder.start() } }
            }
            .onChange(of: recorder.text) { _, value in dump = value }
            if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("[Math] Practice set due tomorrow at 5pm\n[Biology] Quiz on November 12 at 9am\n[History] Project due November 20 at 3pm")
                .font(.caption).foregroundStyle(DockStyle.muted).textSelection(.enabled)
            TextEditor(text: $dump).frame(minHeight: 160).padding(8).scrollContentBackground(.hidden).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: dump) { _, _ in candidates = [] }
            Button(understanding ? "Understanding…" : "Review these items", systemImage: "text.badge.checkmark") {
                recorder.stop(); understanding = true
                Task {
                    defer { understanding = false }
                    do { candidates = try await VoiceTaskAI.extract(dump) } catch { localError = error.localizedDescription }
                }
            }.buttonStyle(PrimaryButtonStyle()).disabled(understanding || recorder.recording || dump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !candidates.isEmpty {
                Text("Check every date and type before adding. You can attach files to each item afterward.").font(.caption).foregroundStyle(DockStyle.muted)
            }
            ForEach($candidates) { $candidate in
                DockCard {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Title", text: $candidate.task.title).textFieldStyle(.roundedBorder)
                        TextField("Subject", text: $candidate.task.subject).textFieldStyle(.roundedBorder)
                        Picker("Type", selection: $candidate.task.kind) { ForEach(WorkKind.allCases) { Text($0.title).tag($0) } }
                            .onChange(of: candidate.task.kind) { _, kind in candidate.task.destination = kind.destination }
                        DatePicker("Date & time", selection: $candidate.task.due)
                            .onChange(of: candidate.task.due) { _, _ in candidate.needsDate = false }
                        if candidate.needsDate {
                            Text("No date found. Choose one above, or confirm the displayed date.").font(.caption).foregroundStyle(.orange)
                            Button("Use this date") { candidate.needsDate = false }
                        }
                        HStack {
                            Label(candidate.task.destination.title, systemImage: candidate.task.destination == .reminders ? "checklist" : "calendar").font(.caption).foregroundStyle(DockStyle.green)
                            Spacer()
                            Button("Remove", role: .destructive) { candidates.removeAll { $0.id == candidate.id } }.font(.caption)
                        }
                    }
                }
            }
        }
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(DockStyle.muted)
            content()
        }
    }
    private func importFiles(_ urls: [URL]) {
        processingFiles = true
        Task {
            defer { processingFiles = false }
            for url in urls {
                do {
                    let file = try await AttachmentImporter.importFile(url, into: store.attachmentsDirectory)
                    draft.attachments.append(file); imported.append(file)
                } catch { localError = error.localizedDescription }
            }
        }
    }
    private func save() {
        if mode == 0 {
            let previous = store.item(draft.id)?.attachments ?? []
            if store.save(draft) { store.cleanUp(previous); dismiss() }
        } else {
            var saved = Set<UUID>()
            for candidate in candidates {
                if store.save(candidate.task) { saved.insert(candidate.id) }
                else { break }
            }
            candidates.removeAll { saved.contains($0.id) }
            if candidates.isEmpty { dismiss() }
            else { localError = "Some items could not be saved. Your remaining items are still here." }
        }
    }
}
