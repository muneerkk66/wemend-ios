import Foundation

/// Build-time defaults. The server URL is deliberately NOT shown on the main
/// screen — it lives here and in the hidden settings sheet, so the app reads as a
/// product rather than a test harness.
enum Config {
    /// RunPod proxies exposed pod ports over public HTTPS, so this works on a
    /// physical device with no tunnel and no ATS exception.
    /// Pattern: https://<pod-id>-<port>.proxy.runpod.net
    ///
    /// NOTE: the pod id changes whenever the pod is RECREATED (not merely restarted),
    /// so this constant is a moving target. That is the argument for putting a stable
    /// hostname in front of it — see the backend's Phase 0b.
    static let defaultServerURL = "https://tg902v9mwkzxd6-8888.proxy.runpod.net"

    /// Placeholder identities until pairing exists. The relay prompt needs real
    /// names to avoid the perspective-flip failure mode — see the backend's
    /// prompts/relay_distill.md.
    static let speakerName = "Adam"
    static let listenerName = "Sara"
}
