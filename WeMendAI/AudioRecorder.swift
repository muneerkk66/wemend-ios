import AVFoundation
import Foundation

/// Records one utterance to m4a and plays the reply back.
///
/// Meters *both* directions: `level` is mic amplitude while recording and
/// playback amplitude while speaking, so the orb animation tracks the real voice
/// in both states instead of running a canned loop.
///
/// Recording is AAC/m4a 16 kHz mono — Whisper resamples to 16 k anyway, so 44.1 k
/// would only cost upload time on a phone network.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var level: CGFloat = 0          // 0...1, drives the orb
    /// 0...1 — how far through the trailing-silence window we are. Lets the UI
    /// show the turn is about to end instead of cutting off without warning.
    @Published var silenceProgress: CGFloat = 0

    /// Fires when the speaker has said something and then gone quiet, so the turn
    /// can be sent without the user tapping anything (ChatGPT-voice behaviour).
    var onSpeechEnded: (() -> Void)?

    // Tuned against real mic metering: speech peaks well above 0.30, room tone
    // sits under 0.10. The gap avoids a breath or a short pause ending the turn.
    private let speechThreshold: CGFloat = 0.30
    private let silenceThreshold: CGFloat = 0.12
    private let trailingSilence: TimeInterval = 1.3
    /// Don't arm the detector until the speaker has actually said something —
    /// otherwise the initial quiet before they start talking ends the turn.
    private var hasHeardSpeech = false
    private var silenceSince: Date?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var onPlaybackFinished: (() -> Void)?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("turn.m4a")
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        // .defaultToSpeaker so the reply doesn't play out of the earpiece.
        try s.setCategory(.playAndRecord, mode: .spokenAudio,
                          options: [.defaultToSpeaker, .allowBluetoothHFP])
        try s.setActive(true)
    }

    // MARK: record

    func startRecording() throws {
        try configureSession()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: fileURL, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        isRecording = true
        hasHeardSpeech = false
        silenceSince = nil
        silenceProgress = 0
        startMetering { [weak self] in
            guard let r = self?.recorder else { return nil }
            r.updateMeters()
            return r.averagePower(forChannel: 0)
        }
    }

    /// Stops recording; nil if nothing usable was captured.
    func stopRecording() -> URL? {
        stopMetering()
        guard let r = recorder, r.isRecording else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        isRecording = false
        // Under ~0.4s is a mis-tap; the server would 422 it anyway.
        guard duration > 0.4 else { return nil }
        return fileURL
    }

    // MARK: play

    func play(_ data: Data, onFinished: (() -> Void)? = nil) throws {
        try configureSession()
        let p = try AVAudioPlayer(data: data)
        p.isMeteringEnabled = true
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        isPlaying = true
        onPlaybackFinished = onFinished
        startMetering { [weak self] in
            guard let p = self?.player, p.isPlaying else { return nil }
            p.updateMeters()
            return p.averagePower(forChannel: 0)
        }
    }

    func stopPlayback() {
        stopMetering()
        player?.stop()
        player = nil
        isPlaying = false
        onPlaybackFinished = nil
    }

    // MARK: metering

    /// `sample` returns dB (or nil to stop). Shared by record and playback.
    private func startMetering(_ sample: @escaping () -> Float?) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard let db = sample() else { self.level = 0; return }
                // dB is ~-160...0; the useful band for speech is about -45...0.
                let lvl = max(0, min(1, CGFloat((db + 45) / 45)))
                self.level = lvl
                self.updateVAD(lvl)
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
        silenceProgress = 0
        silenceSince = nil
        hasHeardSpeech = false
    }

    /// Trailing-silence detection. Only runs while recording.
    private func updateVAD(_ level: CGFloat) {
        guard isRecording else { return }

        if level >= speechThreshold {
            hasHeardSpeech = true
            silenceSince = nil
            silenceProgress = 0
            return
        }
        guard hasHeardSpeech, level < silenceThreshold else {
            // Between the two thresholds: ambiguous, hold the current countdown
            // rather than resetting it, so a wavering tail still ends the turn.
            return
        }
        let now = Date()
        let since = silenceSince ?? now
        silenceSince = since
        let elapsed = now.timeIntervalSince(since)
        silenceProgress = min(1, CGFloat(elapsed / trailingSilence))
        if elapsed >= trailingSilence {
            silenceSince = nil
            silenceProgress = 0
            onSpeechEnded?()
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopMetering()
            self.isPlaying = false
            self.player = nil
            let cb = self.onPlaybackFinished
            self.onPlaybackFinished = nil
            cb?()
        }
    }
}
