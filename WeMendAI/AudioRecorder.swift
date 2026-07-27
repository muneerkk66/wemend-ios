import AVFoundation
import Foundation

/// Records one utterance to m4a and plays the reply back.
///
/// Recording format is AAC/m4a at 16kHz mono — Whisper resamples to 16k anyway,
/// so sending 44.1k just wastes upload time on a phone network.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var level: Float = 0          // 0...1, drives the mic meter

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var levelTimer: Timer?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("turn.m4a")
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord + .defaultToSpeaker so playback isn't routed to the earpiece.
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                               options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

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

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let r = self?.recorder else { return }
                r.updateMeters()
                // dB is roughly -160...0; map the useful -50...0 band to 0...1.
                let db = r.averagePower(forChannel: 0)
                self?.level = max(0, min(1, (db + 50) / 50))
            }
        }
    }

    /// Stops recording and returns the file, or nil if nothing usable was captured.
    func stopRecording() -> URL? {
        levelTimer?.invalidate(); levelTimer = nil
        level = 0
        guard let r = recorder, r.isRecording else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        isRecording = false
        // Under ~0.4s is almost always a mis-tap, and the server will 422 on it.
        guard duration > 0.4 else { return nil }
        return fileURL
    }

    func play(_ data: Data) throws {
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        isPlaying = true
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.player = nil
        }
    }
}
