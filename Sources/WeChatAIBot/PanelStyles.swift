#if canImport(SwiftUI)
import SwiftUI

enum PanelTheme {
    static let ink = Color(red: 0.12, green: 0.15, blue: 0.19)
    static let muted = Color(red: 0.47, green: 0.50, blue: 0.55)
    static let accent = Color(red: 0.29, green: 0.35, blue: 0.84)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let line = Color(red: 0.90, green: 0.92, blue: 0.94)
}

struct PanelButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary, quiet }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(kind == .primary ? .white : configuration.role == .destructive ? .red : PanelTheme.ink)
            .background(kind == .primary ? PanelTheme.accent : kind == .quiet ? .clear : .white,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(kind == .secondary ? PanelTheme.line : .clear, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.36)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PanelTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(PanelTheme.canvas.opacity(enabled ? 0.8 : 0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? PanelTheme.accent.opacity(0.6) : PanelTheme.line, lineWidth: 1))
            .focused($focused)
            .opacity(enabled ? 1 : 0.5)
    }
}

struct PanelLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(PanelTheme.muted)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PanelGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            configuration.label.font(.system(size: 16, weight: .semibold)).foregroundStyle(PanelTheme.ink)
            configuration.content
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(PanelTheme.line.opacity(0.8), lineWidth: 1))
    }
}
#endif
