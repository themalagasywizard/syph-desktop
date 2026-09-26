import SwiftUI
import AppKit

enum Brand {
    static let name = "Syph"
    static let company = "Syph Software"
}

/// Tokens carried over from the Syph entry surfaces on iPhone: a near-black
/// void, cool hairlines, an ice-blue signal and mint for "done".
enum Palette {
    static let void = Color(hex: 0x050507)
    static let voidRaised = Color(hex: 0x0A0B0F)
    static let panel = Color(hex: 0x0E1015)
    static let panelHigh = Color(hex: 0x141720)
    static let field = Color.white.opacity(0.035)
    static let fieldFocused = Color.white.opacity(0.065)
    static let hairline = Color.white.opacity(0.075)
    static let hairlineStrong = Color.white.opacity(0.16)

    static let text = Color(hex: 0xF4F5F7)
    static let textSecondary = Color(hex: 0xF4F5F7).opacity(0.60)
    static let textTertiary = Color(hex: 0xF4F5F7).opacity(0.36)
    static let textFaint = Color(hex: 0xF4F5F7).opacity(0.18)

    static let ice = Color(hex: 0x9DB8FF)
    static let iceDeep = Color(hex: 0x4A63D9)
    static let mint = Color(hex: 0x7FDCB8)
    static let amber = Color(hex: 0xE3A55F)
    static let coral = Color(hex: 0xFF8A80)
    static let violet = Color(hex: 0xB79CFF)

    static let signal = LinearGradient(colors: [ice, iceDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aurora = AngularGradient(colors: [ice, mint, violet, iceDeep, ice], center: .center)

    static func status(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "active", "running", "working", "approved", "succeeded", "done", "completed", "verified": return mint
        case "waiting_for_approval", "waiting", "blocked", "ask", "queued", "delivered": return amber
        case "error", "failed", "rejected", "denied", "expired", "cancelled": return coral
        case "paused", "sleeping", "off": return textTertiary
        default: return ice
        }
    }

    /// A stable hue per employee so each one has a recognisable presence.
    static func hue(for id: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hues: [Double] = [0.62, 0.55, 0.47, 0.72, 0.80, 0.08, 0.40]
        let h = hues[Int(hash % UInt64(hues.count))]
        return Color(hue: h, saturation: 0.45, brightness: 1.0)
    }
}

enum Motion {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let soft = Animation.spring(response: 0.55, dampingFraction: 0.9)
    static let glide = Animation.easeInOut(duration: 0.35)
}

enum Typo {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default) }
    static let title = Font.system(size: 22, weight: .semibold)
    static let headline = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13.5)
    static let callout = Font.system(size: 12.5)
    static let caption = Font.system(size: 11.5)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Surfaces

/// AppKit vibrancy, for surfaces that should pick up what is behind the window.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

struct Card: ViewModifier {
    var radius: CGFloat = 14
    var padding: CGFloat = 16
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(highlighted ? 0.055 : 0.028))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(highlighted ? 0.22 : 0.10), Color.white.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
    }
}

extension View {
    func card(radius: CGFloat = 14, padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(Card(radius: radius, padding: padding, highlighted: highlighted))
    }

    func hairlineBottom() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }
}

// MARK: - Buttons

struct SignalButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(Palette.void)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 9)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Color.white, Palette.ice], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: Palette.ice.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Palette.text
    var compact = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : (hovering ? 0.07 : 0.04)))
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.75))
            .onHover { hovering = $0 }
            .animation(Motion.snappy, value: hovering)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = Palette.textSecondary
    var size: CGFloat = 28
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(hovering ? Palette.text : tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help.isEmpty ? symbol : help)
    }
}

// MARK: - Small parts

struct Eyebrow: View {
    let text: String
    var color: Color = Palette.textTertiary
    var body: some View {
        Text(text.uppercased())
            .font(Typo.eyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing = false
    var size: CGFloat = 7
    @State private var pulse = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle().fill(color.opacity(0.35))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(pulse ? 1 : 0.4)
                    .opacity(pulse ? 0 : 1)
            }
            Circle().fill(color).frame(width: size, height: size)
                .shadow(color: color.opacity(0.8), radius: pulsing ? 5 : 0)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct Chip: View {
    let text: String
    var color: Color = Palette.textSecondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }
}

struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4.5).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4.5).strokeBorder(Palette.hairline, lineWidth: 0.75))
    }
}

struct Monogram: View {
    let employee: Employee
    var size: CGFloat = 28

    var body: some View {
        let tint = Palette.hue(for: employee.id)
        Text(employee.initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.13)))
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
    }
}

struct SyphTextField: View {
    let title: String
    @Binding var text: String
    var secure = false
    var symbol: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
            }
            Group {
                if secure { SecureField(title, text: $text) } else { TextField(title, text: $text) }
            }
            .textFieldStyle(.plain)
            .font(Typo.body)
            .foregroundStyle(Palette.text)
            .focused($focused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(focused ? Palette.fieldFocused : Palette.field))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Palette.ice.opacity(0.55) : Palette.hairline, lineWidth: focused ? 1 : 0.75)
        )
        .animation(Motion.snappy, value: focused)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 0.75).frame(width: 64, height: 64)
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.ice)
            }
            Text(title).font(Typo.headline).foregroundStyle(Palette.text)
            Text(detail).font(Typo.callout).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Time

enum TimeText {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = iso.date(from: raw) ?? isoPlain.date(from: raw) { return d }
        // Python emits microseconds and sometimes no zone.
        var trimmed = raw
        if let dot = raw.firstIndex(of: ".") {
            let tail = raw[dot...]
            let zone = tail.firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" }).map { String(tail[$0...]) } ?? "Z"
            trimmed = String(raw[..<dot]) + zone
        } else if !raw.contains("Z") && !raw.contains("+") {
            trimmed = raw + "Z"
        }
        return isoPlain.date(from: trimmed)
    }

    static func relative(_ raw: String?) -> String {
        guard let date = date(raw) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 45 && seconds > -45 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func clock(_ raw: String?) -> String {
        guard let date = date(raw) else { return "" }
        return date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }
}
