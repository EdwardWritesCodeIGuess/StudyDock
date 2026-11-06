import SwiftUI

@main
struct StudyDockApp: App {
    @StateObject private var store = StudyStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    init() {
        #if os(macOS) && SWIFT_PACKAGE
        // SwiftPM executables need explicit activation when packaged outside Xcode.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Dashboard().environmentObject(store)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 650)
                .onAppear { capturePreviewIfRequested() }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1150, height: 850)
        #endif
    }
    #if os(macOS)
    private func capturePreviewIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--demo"), let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }), let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: args[index + 1])) }
            NSApplication.shared.terminate(nil)
        }
    }
    #endif
}
