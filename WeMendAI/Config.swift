import Foundation

/// Build-time defaults. The server URL is deliberately NOT shown on the main
/// screen — it lives here and in the hidden settings sheet, so the app reads as a
/// product rather than a test harness.
enum Config {
    /// RunPod proxies exposed pod ports over public HTTPS, so this works on a
    /// physical device with no tunnel and no ATS exception.
    /// Pattern: https://<pod-id>-<port>.proxy.runpod.net
    static let defaultServerURL = "https://5lrojxsn35t1mv-8888.proxy.runpod.net"

    /// Placeholder identities until pairing exists. The relay prompt needs real
    /// names to avoid the perspective-flip failure mode — see the backend's
    /// prompts/relay_distill.md.
    static let speakerName = "Adam"
    static let listenerName = "Sara"
}
