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

private typealias PanelValueState<Value> = SwiftUI.State<Value>

struct PanelNumberField: View {
    let title: String
    @Binding private var rawValue: String
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    private var normalizesOnBlur = false
    @PanelValueState private var text: String
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, unit: String = "") {
        self.init(title, text: Binding(get: { String(value.wrappedValue) }, set: { raw in
            if let number = Int(raw) { value.wrappedValue = min(range.upperBound, max(range.lowerBound, number)) }
        }), in: range, step: step, unit: unit)
        normalizesOnBlur = true
    }
    init(_ title: String, text: Binding<String>, in range: ClosedRange<Int>, step: Int = 1, unit: String = "") {
        self.title = title; _rawValue = text; self.range = range; self.step = step; self.unit = unit
        _text = PanelValueState(initialValue: text.wrappedValue)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(PanelTheme.muted)
            HStack(spacing: 0) {
                Button { adjust(-step) } label: {
                    Image(systemName: "minus").frame(width: 42, height: 44).contentShape(Rectangle())
                }.disabled(Int(text).map { $0 <= range.lowerBound } ?? false).accessibilityLabel("减少" + title)
                TextField(title, text: $text)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).focused($focused)
                    .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                    .onSubmit { if normalizesOnBlur { text = rawValue } }
                    .onChange(of: text) { _, current in rawValue = current }
                    .onChange(of: focused) { _, active in
                        if !active && normalizesOnBlur { text = rawValue }
                    }
                    .onChange(of: rawValue) { _, current in if !focused { text = current } }
                if !unit.isEmpty { Text(unit).font(.system(size: 12)).foregroundStyle(PanelTheme.muted).padding(.horizontal, 8) }
                Button { adjust(step) } label: {
                    Image(systemName: "plus").frame(width: 42, height: 44).contentShape(Rectangle())
                }.disabled(Int(text).map { $0 >= range.upperBound } ?? false).accessibilityLabel("增加" + title)
            }
            .buttonStyle(.plain).foregroundStyle(PanelTheme.ink)
            .background(PanelTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? PanelTheme.accent : PanelTheme.line, lineWidth: 1))
            .help("\(range.lowerBound)–\(range.upperBound)\(unit)")
        }.frame(maxWidth: .infinity, alignment: .leading).opacity(enabled ? 1 : 0.5)
    }
    private func adjust(_ delta: Int) {
        let base = min(range.upperBound, max(range.lowerBound, Int(text) ?? Int(rawValue) ?? range.lowerBound))
        let next = min(range.upperBound, max(range.lowerBound, base + delta))
        rawValue = String(next); text = String(next)
    }
}

struct PanelTextEditorStyle: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).lineSpacing(5).scrollContentBackground(.hidden)
            .focused($focused).padding(12)
            .background(PanelTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? PanelTheme.accent : PanelTheme.line, lineWidth: 1))
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
