import SwiftUI

/// The animated centrepiece. One view, four visual states, driven by a single
/// `TimelineView` clock so every layer stays in phase.
///
/// `level` (0...1) is live mic amplitude while listening and live playback
/// amplitude while speaking, so the motion tracks the actual voice rather than
/// running a canned loop.
enum OrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

struct VoiceOrb: View {
    var state: OrbState
    var level: CGFloat
    /// 0...1 through the trailing-silence window. Drawn as a closing ring so the
    /// user can see the turn is about to send instead of being cut off blind.
    var silenceProgress: CGFloat = 0

    // Smoothed level — raw metering is jittery and makes the orb twitch.
    @State private var smoothed: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                outerGlow(t)
                ripples(t)
                core(t)
                if state == .speaking || state == .listening {
                    waveRing(t)
                }
                if state == .thinking {
                    thinkingArc(t)
                }
                if state == .listening && silenceProgress > 0.02 {
                    silenceRing
                }
            }
            .onChange(of: level) { _, new in
                // Attack fast, release slow — feels responsive without flicker.
                let k: CGFloat = new > smoothed ? 0.45 : 0.12
                smoothed += (new - smoothed) * k
            }
        }
        .frame(width: 260, height: 260)
        .animation(.easeInOut(duration: 0.55), value: state)
    }

    // MARK: layers

    private var tint: Color {
        switch state {
        case .idle:      return Color(red: 0.42, green: 0.47, blue: 0.62)
        case .listening: return Color(red: 0.35, green: 0.72, blue: 0.98)
        case .thinking:  return Color(red: 0.62, green: 0.52, blue: 0.98)
        case .speaking:  return Color(red: 0.40, green: 0.86, blue: 0.78)
        }
    }

    /// Soft bloom behind everything; breathes slowly at idle, swells with voice.
    private func outerGlow(_ t: TimeInterval) -> some View {
        let breathe = 1 + 0.04 * sin(t * 1.1)
        let energy = 1 + smoothed * 0.42
        return Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0.10), .clear],
                    center: .center, startRadius: 8, endRadius: 150
                )
            )
            .scaleEffect(breathe * energy)
            .blur(radius: 22)
    }

    /// Expanding rings. Each is offset in phase so they emit in sequence.
    private func ripples(_ t: TimeInterval) -> some View {
        let active = state == .listening || state == .speaking
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let scale = 0.85 + phase * (active ? 0.85 : 0.35)
                let fade = (1 - phase) * (active ? 0.5 : 0.16)
                Circle()
                    .strokeBorder(tint.opacity(fade), lineWidth: 1.2)
                    .scaleEffect(scale)
            }
        }
    }

    /// Glassy centre disc with a moving specular highlight.
    private func core(_ t: TimeInterval) -> some View {
        let pulse = 1 + (state == .idle ? 0.02 * sin(t * 1.4) : smoothed * 0.16)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.55),
                                 Color.black.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.45), .clear],
                        center: UnitPoint(x: 0.34 + 0.05 * cos(t * 0.8),
                                          y: 0.28 + 0.05 * sin(t * 0.8)),
                        startRadius: 1, endRadius: 62
                    )
                )
            Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
        .frame(width: 132, height: 132)
        .scaleEffect(pulse)
        .shadow(color: tint.opacity(0.55), radius: 26)
    }

    /// Radial bars around the core — the "voice" waveform.
    private func waveRing(_ t: TimeInterval) -> some View {
        let bars = 56
        return Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) * 0.30
            for i in 0..<bars {
                let frac = Double(i) / Double(bars)
                let angle = frac * 2 * .pi
                // Two travelling waves at different rates so it never looks periodic.
                let w = sin(frac * 9 + t * 3.4) * 0.55 + sin(frac * 5 - t * 2.1) * 0.45
                let amp = (0.16 + smoothed * 0.9) * (0.5 + 0.5 * w)
                let len = base * 0.30 * amp
                guard len > 0.4 else { continue }
                let p1 = CGPoint(x: c.x + cos(angle) * base, y: c.y + sin(angle) * base)
                let p2 = CGPoint(x: c.x + cos(angle) * (base + len),
                                 y: c.y + sin(angle) * (base + len))
                var path = Path()
                path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path,
                           with: .color(tint.opacity(0.55 + 0.45 * amp)),
                           style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            }
        }
    }

    /// Closes clockwise as the trailing silence elapses; completing it sends.
    private var silenceRing: some View {
        Circle()
            .trim(from: 0, to: silenceProgress)
            .stroke(tint.opacity(0.9),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .scaleEffect(1.02)
            .animation(.linear(duration: 1.0 / 30), value: silenceProgress)
    }

    /// Two counter-rotating arcs while the backend works.
    private func thinkingArc(_ t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let dir: Double = i == 0 ? 1 : -1
                Circle()
                    .trim(from: 0, to: i == 0 ? 0.22 : 0.14)
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0), tint, tint.opacity(0)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(t * (i == 0 ? 150 : 95) * dir))
                    .scaleEffect(i == 0 ? 0.78 : 0.92)
            }
        }
    }
}

/// Full-screen backdrop: near-black with a slow drifting colour wash so the
/// screen never looks like a flat dead rectangle.
struct AuroraBackground: View {
    var tint: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // The gradient (flexible) drives layout; the blobs are an overlay so
            // their fixed 460pt frame can't widen the parent past the screen —
            // which otherwise pushes sibling content off both edges.
            LinearGradient(
                colors: [Color(white: 0.055), .black, Color(white: 0.02)],
                startPoint: .top, endPoint: .bottom
            )
            .overlay {
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        let s = Double(i) * 1.7
                        Circle()
                            .fill(RadialGradient(colors: [tint.opacity(0.22), .clear],
                                                 center: .center, startRadius: 0, endRadius: 260))
                            .frame(width: 460, height: 460)
                            .offset(x: CGFloat(cos(t * 0.11 + s) * 130),
                                    y: CGFloat(sin(t * 0.08 + s) * 190) + (i == 0 ? -160 : 200))
                            .blur(radius: 60)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: tint)
        }
    }
}
