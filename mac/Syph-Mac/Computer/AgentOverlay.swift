import AppKit
import SwiftUI
import Observation

/// While an employee acts on the Mac, the screen edge glows and a pill at the
/// top says who is driving and what they are doing, with a Stop button.
/// The glow never takes clicks; the pill does.
@MainActor
@Observable
final class AgentOverlay {
    var employee = ""
    var activity = ""
    var tint: Color = Palette.ice
    private(set) var visible = false

    @ObservationIgnored var onStop: (() -> Void)?
    @ObservationIgnored private var glowPanel: FloatingPanel?
    @ObservationIgnored private var pillPanel: FloatingPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(employee: String, activity: String, tint: Color) {
        hideTask?.cancel()
        self.employee = employee.isEmpty ? "Your employee" : employee
        self.activity = activity
        self.tint = tint
        guard let screen = NSScreen.main else { return }
        if glowPanel == nil {
            let glow = FloatingPanel(size: screen.frame.size, clickThrough: true)
            glow.level = .screenSaver
            glow.host(EdgeGlow(overlay: self))
            glowPanel = glow
            let pill = FloatingPanel(size: CGSize(width: 520, height: 64))
            pill.level = .screenSaver
            pill.host(DrivingPill(overlay: self))
            pillPanel = pill
        }
        glowPanel?.setFrame(screen.frame, display: true)
        let pillSize = CGSize(width: 520, height: 64)
        pillPanel?.setFrame(NSRect(x: screen.frame.midX - pillSize.width / 2,
                                   y: screen.visibleFrame.maxY - pillSize.height - 6,
                                   width: pillSize.width, height: pillSize.height), display: true)
        glowPanel?.orderFrontRegardless()
        pillPanel?.orderFrontRegardless()
        withAnimation(Motion.soft) { visible = true }
    }

    /// Lingers briefly so a burst of commands reads as one continuous session.
    func hide(after delay: Duration = .milliseconds(1400)) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            withAnimation(Motion.soft) { self.visible = false }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.glowPanel?.orderOut(nil)
            self.pillPanel?.orderOut(nil)
        }
    }
}

private struct EdgeGlow: View {
    let overlay: AgentOverlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !overlay.visible)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(
                colors: [overlay.tint, Palette.mint, Palette.violet, overlay.tint.opacity(0.4), overlay.tint],
                center: .center, angle: .degrees(t * 40))
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 3)
                    .blur(radius: 10)
                    .opacity(0.9)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 1.5)
                    .opacity(0.85)
            }
            .padding(2)
        }
        .opacity(overlay.visible ? 1 : 0)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct DrivingPill: View {
    let overlay: AgentOverlay

    var body: some View {
        HStack(spacing: 12) {
            AgentOrb(mood: .working, tint: overlay.tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(overlay.employee) is using your Mac")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(overlay.activity)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Button {
                overlay.onStop?()
            } label: {
                Label("Stop", systemImage: "stop.fill").font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle(tint: Palette.coral, compact: true))
            .help("Stop and switch computer control off")
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Palette.void.opacity(0.5)
            }
            .clipShape(Capsule(style: .continuous))
        )
        .overlay(Capsule(style: .continuous).strokeBorder(overlay.tint.opacity(0.5), lineWidth: 0.8))
        .shadow(color: overlay.tint.opacity(0.35), radius: 18, y: 4)
        .scaleEffect(overlay.visible ? 1 : 0.9)
        .opacity(overlay.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
