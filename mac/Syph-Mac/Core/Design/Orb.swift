import SwiftUI

/// The presence of an AI employee. Calm when idle, a travelling signal while
/// it works, amber breathing when it needs you, dim when paused.
struct AgentOrb: View {
    enum Mood: Equatable { case idle, working, attention, paused, offline }

    var mood: Mood = .idle
    var tint: Color = Palette.ice
    var size: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || mood == .paused || mood == .offline)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvas in
                draw(in: &context, size: canvas, time: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch mood {
        case .attention: return Palette.amber
        case .paused, .offline: return Palette.textTertiary
        default: return tint
        }
    }

    private func draw(in context: inout GraphicsContext, size canvas: CGSize, time t: Double) {
        let s = min(canvas.width, canvas.height)
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = s / 2
        let breathe = mood == .attention ? (sin(t * 3.2) + 1) / 2 : (sin(t * 1.3) + 1) / 2

        // Halo
        let halo = Path(ellipseIn: CGRect(x: 0, y: 0, width: s, height: s))
        context.fill(halo, with: .radialGradient(
            Gradient(colors: [color.opacity(0.10 + 0.14 * breathe), color.opacity(0.0)]),
            center: center, startRadius: radius * 0.1, endRadius: radius))

        // Hairline ring
        let ringRect = CGRect(x: radius * 0.16, y: radius * 0.16, width: s - radius * 0.32, height: s - radius * 0.32)
        context.stroke(Path(ellipseIn: ringRect), with: .color(Color.white.opacity(mood == .offline ? 0.08 : 0.16)), lineWidth: max(0.6, s / 90))

        // Travelling arc
        if mood != .paused && mood != .offline {
            let speed = mood == .working ? 2.6 : 0.5
            let start = Angle.radians(t * speed)
            let sweep = mood == .working ? 0.34 : 0.22
            var arc = Path()
            arc.addArc(center: center, radius: ringRect.width / 2, startAngle: start,
                       endAngle: start + .radians(.pi * 2 * sweep), clockwise: false)
            context.stroke(arc, with: .linearGradient(
                Gradient(colors: [color.opacity(0), color, .white]),
                startPoint: CGPoint(x: center.x - radius, y: center.y), endPoint: CGPoint(x: center.x + radius, y: center.y)),
                style: StrokeStyle(lineWidth: max(1.1, s / 40), lineCap: .round))

            if mood == .working {
                // Second, counter-rotating inner orbit.
                let inner = ringRect.insetBy(dx: radius * 0.18, dy: radius * 0.18)
                var arc2 = Path()
                let start2 = Angle.radians(-t * 1.7)
                arc2.addArc(center: center, radius: inner.width / 2, startAngle: start2, endAngle: start2 + .radians(1.1), clockwise: false)
                context.stroke(arc2, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: max(0.8, s / 70), lineCap: .round))
            }
        }

        // Core node
        let core = radius * (0.15 + 0.03 * breathe)
        var glow = context
        glow.addFilter(.blur(radius: radius * 0.18))
        glow.fill(Path(ellipseIn: CGRect(x: center.x - core * 1.6, y: center.y - core * 1.6, width: core * 3.2, height: core * 3.2)),
                  with: .color(color.opacity(mood == .offline ? 0.1 : 0.7)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                     with: .color(mood == .paused || mood == .offline ? Palette.textTertiary : Palette.text))
    }
}

/// The Syph mark: a hairline ring with one luminous node.
struct SyphMark: View {
    var size: CGFloat = 22
    var body: some View {
        AgentOrb(mood: .idle, tint: Palette.ice, size: size)
    }
}

struct Wordmark: View {
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: size * 0.7) {
            SyphMark(size: size * 2)
            Text(Brand.name.uppercased())
                .font(.system(size: size, weight: .medium))
                .tracking(size * 0.5)
                .foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
    }
}

/// The canvas behind everything: void black, one cold halo drifting at the top
/// and a faint horizon grid — depth without noise.
struct Backdrop: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.void))
                let drift = CGFloat(sin(t / 9)) * size.width * 0.08
                let halo = CGPoint(x: size.width * 0.62 + drift, y: -size.height * 0.05)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [Palette.iceDeep.opacity(0.26 * intensity), Palette.iceDeep.opacity(0.05 * intensity), .clear]),
                    center: halo, startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
                let low = CGPoint(x: size.width * 0.12 - drift, y: size.height * 1.05)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [Palette.mint.opacity(0.07 * intensity), .clear]),
                    center: low, startRadius: 0, endRadius: size.width * 0.55))

                // Perspective horizon lines, very faint.
                var grid = Path()
                let horizon = size.height * 0.78
                for i in 0..<7 {
                    let y = horizon + pow(CGFloat(i) / 6, 2) * (size.height - horizon)
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(Color.white.opacity(0.018 * intensity)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension AgentOrb.Mood {
    init(employee: Employee, working: WorkingRun?, waiting: Bool) {
        if employee.isPaused { self = .paused }
        else if waiting { self = .attention }
        else if working?.active == true { self = .working }
        else { self = .idle }
    }
}
