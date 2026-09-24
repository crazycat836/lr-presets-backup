import SwiftUI

// 墨水線條＋紙張質感的配色（設計稿「Mac 備份 Redesign」，oklch 已換算成 sRGB）。
struct Palette {
    let bg, paper, ink, muted, faint, faint2, well, accent, sel, ok, warn, warnBg, bad, scrim: Color

    static let light = Palette(
        bg: Color(hex: 0xf5f3ee), paper: Color(hex: 0xfbfaf7), ink: Color(hex: 0x22201c),
        muted: Color(hex: 0x6e6960), faint: Color(hex: 0x22201c, opacity: 0.1), faint2: Color(hex: 0x22201c, opacity: 0.25),
        well: Color(hex: 0xf0ede6), accent: Color(hex: 0xd26538), sel: Color(hex: 0xd26538, opacity: 0.12),
        ok: Color(hex: 0x3e8651), warn: Color(hex: 0xb77610), warnBg: Color(hex: 0xe6b55d, opacity: 0.14),
        bad: Color(hex: 0xc13c36), scrim: Color(hex: 0x22201c, opacity: 0.3))

    static let dark = Palette(
        bg: Color(hex: 0x151518), paper: Color(hex: 0x1d1d21), ink: Color(hex: 0xece9e3),
        muted: Color(hex: 0x9d988f), faint: Color(hex: 0xece9e3, opacity: 0.1), faint2: Color(hex: 0xece9e3, opacity: 0.25),
        well: Color(hex: 0x131316), accent: Color(hex: 0xeb9854), sel: Color(hex: 0xeb9854, opacity: 0.14),
        ok: Color(hex: 0x76c788), warn: Color(hex: 0xe8b45e), warnBg: Color(hex: 0xe8b45e, opacity: 0.08),
        bad: Color(hex: 0xef7f74), scrim: Color.black.opacity(0.55))
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// 字體只用 Mac 內建：標題用楷體（Kaiti TC；重灌後尚未下載時系統自動退回蘋方），等寬用 SF Mono。
enum InkFont {
    static func hand(_ size: CGFloat) -> Font { .custom("STKaitiTC-Bold", size: size) }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    // 紙張卡片：淺底 + 1.6pt 墨線框
    func inkCard(padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)) -> some View {
        modifier(InkCard(insets: padding))
    }
}

private struct InkCard: ViewModifier {
    @Environment(\.palette) private var p
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(p.paper))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.ink, lineWidth: 1.6))
    }
}

// 按鈕：主要（墨色實心）、外框（墨線）、小型（淡框）。主要與外框 hover 時往左上浮起並露出強調色影子。
struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, small }
    var kind: Kind = .primary
    var fill: Color?  // 覆蓋主要按鈕底色（破壞性確認用紅色）

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(kind: kind, fill: fill, configuration: configuration)
    }
}

private struct InkButtonBody: View {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    let kind: InkButtonStyle.Kind
    let fill: Color?
    let configuration: ButtonStyleConfiguration
    private let hovering = State(initialValue: false)

    var body: some View {
        let lift = kind != .small && isEnabled && hovering.wrappedValue && !configuration.isPressed
        label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(p.accent)
                    .offset(x: 3, y: 3)
                    .opacity(lift ? 1 : 0)
            )
            .offset(x: lift ? -2 : 0, y: lift ? -2 : 0)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.15), value: lift)
            .onHover { hovering.wrappedValue = $0 }
    }

    private var radius: CGFloat { kind == .small ? 9 : 12 }

    @ViewBuilder private var label: some View {
        switch kind {
        case .primary:
            configuration.label
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(p.bg)
                .padding(.vertical, 12).padding(.horizontal, 20)
                .background(RoundedRectangle(cornerRadius: radius).fill(fill ?? p.ink))
        case .outline:
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.ink)
                .padding(.vertical, 11).padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: radius).fill(p.paper))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(p.ink, lineWidth: 1.6))
        case .small:
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.ink)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(hovering.wrappedValue && isEnabled ? p.ink : p.faint2, lineWidth: 1.5))
        }
    }
}

// 右上角的深淺色切換膠囊
struct ThemeToggle: View {
    @Environment(\.palette) private var p
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().strokeBorder(p.muted, lineWidth: 1.5)
                    Circle().trim(from: 0.25, to: 0.75).fill(p.muted)
                }
                .frame(width: 12, height: 12)
                Text(isDark ? "深色" : "淺色")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(p.muted)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .overlay(Capsule().strokeBorder(p.faint2, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("切換深淺色")
    }
}
