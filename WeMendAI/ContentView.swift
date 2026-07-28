import SwiftUI

/// Full-screen voice call with the mediator.
///
/// Tap the orb to start; it sends itself once you stop talking (trailing-silence
/// VAD in AudioRecorder), so there is no mic button and no "stop" tap.
///
/// No server field, no engine picker, no latency table on screen — those live in a
/// hidden settings sheet (long-press the status line) so the main surface reads like
/// a product rather than a test harness. Voice is fixed to Sesame CSM.
struct ContentView: View {
    @StateObject private var audio = AudioRecorder()
    @AppStorage("serverURL") private var serverURL = Config.defaultServerURL

    @State private var phase: Phase = .idle
    @State private var transcript: [Line] = []
    @State private var client: VoiceClient?
    @State private var error: String?
    @State private var showSettings = false
    @State private var lastTurnSeconds: Double?

    private enum Phase: Equatable {
        case idle, listening, thinking, speaking

        var orb: OrbState {
            switch self {
            case .idle: .idle
            case .listening: .listening
            case .thinking: .thinking
            case .speaking: .speaking
            }
        }

        var caption: String {
            switch self {
            case .idle: "Tap to talk"
            case .listening: "Listening"      // auto-sends when you stop

            // CSM runs ~2.4x slower than realtime, so this is a genuine wait.
            // Naming it keeps a 20s pause from reading as a hang.
            case .thinking: "Thinking"
            case .speaking: "Speaking"
            }
        }
    }

    private struct Line: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    private var tint: Color {
        switch phase {
        case .idle: Color(red: 0.42, green: 0.47, blue: 0.62)
        case .listening: Color(red: 0.35, green: 0.72, blue: 0.98)
        case .thinking: Color(red: 0.62, green: 0.52, blue: 0.98)
        case .speaking: Color(red: 0.40, green: 0.86, blue: 0.78)
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(tint: tint)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                VoiceOrb(state: phase.orb, level: audio.level,
                         silenceProgress: audio.silenceProgress)
                    .onTapGesture { Task { await tapOrb() } }
                    .accessibilityLabel(phase == .listening ? "Listening, tap to send"
                                                            : "Tap to talk")
                caption
                Spacer(minLength: 8)
                transcriptView
                controls
            }
            .padding(.horizontal, 24)

            if let error {
                errorToast(error)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(serverURL: $serverURL, lastTurnSeconds: lastTurnSeconds)
        }
        .task { await connect() }
    }

    // MARK: chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WeMendAI").font(.title3.weight(.semibold))
                Text("Mediator").font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.07), in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var caption: some View {
        VStack(spacing: 6) {
            Text(phase.caption)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .contentTransition(.opacity)
            // Three drifting dots while the backend works — CSM makes this a real wait.
            if phase == .thinking {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 4.5, height: 4.5)
                                .offset(y: CGFloat(sin(t * 3.2 + Double(i) * 0.7) * 3))
                        }
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(.top, 26)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(transcript) { line in
                        HStack {
                            if line.mine { Spacer(minLength: 40) }
                            Text(line.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(line.mine ? 0.72 : 0.95))
                                .multilineTextAlignment(line.mine ? .trailing : .leading)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(.white.opacity(line.mine ? 0.06 : 0.11))
                                )
                            if !line.mine { Spacer(minLength: 40) }
                        }
                        .id(line.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 210)
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(colors: [.clear, .black, .black, .black],
                               startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: transcript) { _, _ in
                if let last = transcript.last {
                    withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    /// No mic button by design — the orb is the control, and the turn ends itself.
    /// Only shows an escape hatch when one is genuinely useful.
    private var controls: some View {
        HStack(spacing: 18) {
            if phase == .speaking {
                secondaryButton("Skip", "forward.end.fill") {
                    audio.stopPlayback(); withAnimation { phase = .idle }
                }
            }
            if phase == .listening {
                secondaryButton("Cancel", "xmark") {
                    _ = audio.stopRecording(); withAnimation { phase = .idle }
                }
            }
            if phase == .idle && !transcript.isEmpty {
                secondaryButton("New call", "arrow.counterclockwise") {
                    Task { await client?.endSession(); transcript = []; error = nil }
                }
            }
        }
        .frame(height: 62)
        .padding(.bottom, 30)
        .padding(.top, 10)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: phase)
    }

    private func secondaryButton(_ label: String, _ icon: String,
                                 _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.08), in: Circle())
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func errorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.red.opacity(0.85)))
                .padding(.bottom, 118)
                .padding(.horizontal, 28)
                .multilineTextAlignment(.center)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    // MARK: actions

    private func connect() async {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else { return }
        let c = VoiceClient(baseURL: url)
        client = c
        // Warm the connection; surface only a hard failure, not "still loading".
        if let h = try? await c.health(), !h.ready {
            show("Mediator is still waking up — give it a moment.")
        }
    }

    private func tapOrb() async {
        error = nil
        switch phase {
        case .thinking:
            return
        case .speaking:
            audio.stopPlayback(); phase = .idle
        case .listening:
            // Tapping while listening just sends immediately; normally the
            // trailing-silence detector does this for you.
            await finishListening()
        case .idle:
            guard await audio.requestPermission() else {
                show("Microphone access is off. Enable it in Settings.")
                return
            }
            do {
                audio.stopPlayback()
                audio.onSpeechEnded = { [self] in
                    Task { await finishListening() }
                }
                try audio.startRecording()
                withAnimation { phase = .listening }
            } catch {
                show("Could not start recording.")
            }
        }
    }

    /// Ends the listening turn and sends. Guarded: the VAD callback and a manual
    /// tap can both land, and sending twice would duplicate the turn.
    private func finishListening() async {
        guard phase == .listening else { return }
        audio.onSpeechEnded = nil
        guard let file = audio.stopRecording() else {
            withAnimation { phase = .idle }
            show("I didn't catch that — try again.")
            return
        }
        await send(file)
    }

    private func send(_ file: URL) async {
        guard let c = client else { show("No connection."); return }
        withAnimation { phase = .thinking }
        let started = Date()
        do {
            let (result, data) = try await c.send(audio: file,
                                                 speaker: Config.speakerName,
                                                 listener: Config.listenerName)
            lastTurnSeconds = Date().timeIntervalSince(started)
            withAnimation {
                transcript.append(Line(mine: true, text: result.heard))
                transcript.append(Line(mine: false, text: result.replyText))
                phase = .speaking
            }
            try audio.play(data) {
                withAnimation { phase = .idle }
            }
        } catch {
            withAnimation { phase = .idle }
            show(error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        withAnimation { error = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if error == message { error = nil } }
        }
    }
}

/// Tucked away so the main screen stays clean. Reachable via the ⋯ button.
private struct SettingsSheet: View {
    @Binding var serverURL: String
    var lastTurnSeconds: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                }
                Section("Voice") {
                    LabeledContent("Engine", value: "Sesame CSM-1B")
                    Text("Warmer, more natural prosody. Runs slower than realtime, so replies take a moment to arrive.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let s = lastTurnSeconds {
                    Section("Last turn") {
                        LabeledContent("Round trip", value: String(format: "%.1f s", s))
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

#Preview { ContentView() }
