import SwiftUI
import StudyDockCore

enum DockStyle {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.23)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let green = Color(red: 0.22, green: 0.42, blue: 0.32)
    static let mint = Color(red: 0.83, green: 0.91, blue: 0.77)
    static let muted = Color(red: 0.44, green: 0.48, blue: 0.46)
    static let line = Color(red: 0.87, green: 0.88, blue: 0.84)
    static func color(_ kind: WorkKind) -> Color {
        switch kind {
        case .homework: return green
        case .quiz: return Color(red: 0.66, green: 0.38, blue: 0.16)
        case .test: return Color(red: 0.45, green: 0.38, blue: 0.68)
        case .project: return Color(red: 0.22, green: 0.43, blue: 0.62)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var light = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 20).padding(.vertical, 13)
            .background(light ? DockStyle.mint : DockStyle.ink, in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(light ? DockStyle.ink : .white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DockCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(DockStyle.line, lineWidth: 0.7))
    }
}

struct KindBadge: View {
    var kind: WorkKind
    var body: some View {
        Label(kind.title, systemImage: kind.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DockStyle.color(kind))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(DockStyle.color(kind).opacity(0.10), in: Capsule())
    }
}

extension View {
    func dockSheet() -> some View {
        self.frame(idealWidth: 620, idealHeight: 720)
            .background(DockStyle.paper).foregroundStyle(DockStyle.ink)
            .preferredColorScheme(.light)
    }
}
