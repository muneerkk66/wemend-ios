import SwiftUI

/// Test harness for the WeMendAI voice pipeline.
///
/// Deliberately shows the raw timing breakdown: the whole point of this build is
/// to let you hear CSM vs Kokoro on a real device and see what each costs, rather
/// than trusting a benchmark table. Not a product UI.
struct ContentView: View {
    @StateObject private var audio = AudioRecorder()
    @AppStorage("serverURL") private var serverURL = "http://localhost:8000"
    @AppStorage("voice") private var voiceRaw = TTSVoice.csm.rawValue

    @State private var client: VoiceClient?
    @State private var status = "Idle"
    @State private var heard = ""
    @State private var reply = ""
    @State private var timing: TurnResult.Timing?
    @State private var ttsStats: TurnResult.TTSStats?
    @State private var busy = false
    @State private var error: String?
    @State private var serverReady: Bool?

    private var voice: TTSVoice { TTSVoice(rawValue: voiceRaw) ?? .csm }

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                voiceSection
                micSection
                if !heard.isEmpty || !reply.isEmpty { transcriptSection }
                if let timing { timingSection(timing) }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("WeMendAI")
            .task { await refreshHealth() }
        }
    }

    // MARK: sections

    private var serverSection: some View {
        Section("Server") {
            TextField("http://host:8000", text: $serverURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onSubmit { Task { await refreshHealth() } }
            HStack {
                Circle()
                    .fill(serverReady == true ? .green : (serverReady == nil ? .gray : .orange))
                    .frame(width: 9, height: 9)
                Text(serverReady == true ? "Models loaded"
                     : serverReady == nil ? "Not checked"
                     : "Reachable, still loading models")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check") { Task { await refreshHealth() } }.font(.caption)
            }
        }
    }

    private var voiceSection: some View {
        Section("Voice") {
            Picker("Engine", selection: $voiceRaw) {
                ForEach(TTSVoice.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(voice.blurb).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var micSection: some View {
        Section {
            VStack(spacing: 14) {
                // Level meter — confirms the mic is actually picking you up.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(audio.isRecording ? .red : .gray)
                            .frame(width: geo.size.width * CGFloat(audio.level))
                            .animation(.linear(duration: 0.05), value: audio.level)
                    }
                }
                .frame(height: 6)

                Button {
                    Task { await toggleRecording() }
                } label: {
                    HStack {
                        Image(systemName: audio.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 34))
                        Text(audio.isRecording ? "Stop & Send" : "Hold a conversation")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(audio.isRecording ? .red : .accentColor)
                .disabled(busy)

                if busy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }

                if audio.isPlaying {
                    Button("Stop playback") { audio.stopPlayback() }.font(.caption)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Speak as one partner. The mediator replies aloud. Tap Stop to send.")
        }
    }

    private var transcriptSection: some View {
        Section("Transcript") {
            if !heard.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("You said").font(.caption2).foregroundStyle(.secondary)
                    Text(heard)
                }
            }
            if !reply.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mediator").font(.caption2).foregroundStyle(.secondary)
                    Text(reply)
                }
            }
        }
    }

    private func timingSection(_ t: TurnResult.Timing) -> some View {
        Section("Latency") {
            row("Speech → text", t.stt)
            row("Gemma 4", t.llm)
            row("Text → speech", t.tts)
            Divider()
            row("Total", t.total, bold: true)
            if let s = ttsStats {
                HStack {
                    Text("\(s.engine) speed").font(.caption)
                    Spacer()
                    Text(String(format: "%.2fx realtime", s.realtimeFactor))
                        .font(.caption.monospaced())
                        .foregroundStyle(s.realtimeFactor < 1 ? .orange : .green)
                }
            }
        }
    }

    private func row(_ label: String, _ ms: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .body.weight(.semibold) : .body)
            Spacer()
            Text(ms >= 1000 ? String(format: "%.2f s", Double(ms) / 1000) : "\(ms) ms")
                .font(.body.monospaced())
                .fontWeight(bold ? .semibold : .regular)
        }
    }

    // MARK: actions

    private func makeClient() -> VoiceClient? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        return VoiceClient(baseURL: url)
    }

    private func refreshHealth() async {
        error = nil
        guard let c = makeClient() else { error = "Invalid server URL"; return }
        client = c
        do {
            let h = try await c.health()
            serverReady = h.ready
            status = h.ready ? "Ready · \(h.llm)" : "Loading models…"
        } catch {
            serverReady = nil
            self.error = error.localizedDescription
            status = "Unreachable"
        }
    }

    private func toggleRecording() async {
        error = nil
        if audio.isRecording {
            guard let file = audio.stopRecording() else {
                status = "Too short — hold it a little longer"
                return
            }
            await send(file)
        } else {
            guard await audio.requestPermission() else {
                error = "Microphone permission denied. Enable it in Settings."
                return
            }
            do {
                audio.stopPlayback()
                try audio.startRecording()
                status = "Listening…"
            } catch {
                self.error = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    private func send(_ file: URL) async {
        guard let c = client ?? makeClient() else { error = "Invalid server URL"; return }
        client = c
        busy = true
        // Set expectations honestly: CSM will take a while on purpose.
        status = voice == .csm ? "Thinking… (CSM is slow, ~2.4x the reply length)" : "Thinking…"
        defer { busy = false }
        do {
            let (result, audioData) = try await c.send(
                audio: file, voice: voice, speaker: "Adam", listener: "Sara")
            heard = result.heard
            reply = result.replyText
            timing = result.timingMs
            ttsStats = result.tts
            status = String(format: "Replied in %.1f s", Double(result.timingMs.total) / 1000)
            try audio.play(audioData)
        } catch {
            self.error = error.localizedDescription
            status = "Failed"
        }
    }
}

#Preview { ContentView() }
