# wemend-ios

Voice UI for **WeMendAI** — an AI mediator for couples. SwiftUI, iOS 17+.

Full-screen voice call: tap the orb, speak, and **stop** — it detects that you've
finished and sends automatically. No mic button, no stop button. Modelled on ChatGPT's
voice mode: black gradient backdrop, an animated orb, live waveform.

## Turn-taking

Trailing-silence VAD in `AudioRecorder`, driven off the same 30 Hz metering that
feeds the orb — no extra audio tap:

- Two thresholds, not one: speech is `level ≥ 0.30`, silence is `< 0.12`. The gap in
  between holds the countdown rather than resetting it, so a breath or a wavering
  tail doesn't restart the turn — and doesn't end it early either.
- Armed only *after* speech is detected, otherwise the quiet before you start talking
  would immediately end the turn.
- **1.3 s** of trailing silence sends it. A closing ring draws around the orb as that
  window elapses, so the send is visible rather than abrupt.
- Tapping the orb while listening sends immediately; `Cancel` discards.

Send is guarded against double-fire: the VAD callback and a manual tap can both
land, and sending twice would duplicate the turn.

## Brand

Palette in `Brand.swift` is sampled from the app icon so the two read as one product:
deep navy tile (`#141A3C` → `#0B0F26`) with the icon's teal → cyan → violet sweep
(`#3DE0B0 → #2ED9C3 → #35A8E8 → #4F8FF0 → #8B6FE8`).

Per-state accents stay inside that palette rather than inventing new hues, and each
maps to something in the icon: listening = the waveform teal, thinking = the female
silhouette violet, speaking = the heart mint. The wordmark mirrors the icon too —
"WeMend" solid, "AI" in the gradient, with the `LISTEN · UNDERSTAND · HEAL` tagline.

## The orb

One view, four states, all driven by a single `TimelineView` clock so every layer
stays in phase. The waveform is **driven by real audio amplitude**, not a canned
loop — `AudioRecorder` meters both directions, so the orb reacts to your voice while
listening and to the mediator's voice while speaking.

| State | Colour | Motion |
|---|---|---|
| Idle | slate | slow breathing pulse, faint ripples |
| Listening | blue | ripples emit outward, waveform tracks mic level |
| Thinking | violet | counter-rotating arcs + drifting dots |
| Speaking | teal | waveform tracks playback amplitude |

Levels are smoothed with a fast attack / slow release so the orb responds without
twitching on metering jitter.

## Voice

Fixed to **Sesame CSM-1B** — no engine picker. It has the warmest prosody, which is
what this product needs, but it runs at ~0.43x realtime, so a reply takes roughly
2.4x its spoken length to generate. The "Thinking" state is therefore a genuine
wait; naming it (rather than showing a bare spinner) keeps a 20s pause from reading
as a hang.

## Build

```bash
brew install xcodegen     # once
xcodegen generate         # creates WeMendAI.xcodeproj
open WeMendAI.xcodeproj
```

No XcodeGen? Create a new iOS App in Xcode named `WeMendAI`, delete its generated
`ContentView.swift`, drag in the four files from `WeMendAI/`, and set
`NSMicrophoneUsageDescription` in Info.plist.

## Backend connection

The server URL is **not on the main screen** — it lives in `Config.swift` and the
hidden settings sheet (the ⋯ button), so the app reads as a product rather than a
test harness.

It defaults to RunPod's public HTTPS proxy, which works on a **physical device** with
no tunnel and no ATS exception:

```
https://<pod-id>-<port>.proxy.runpod.net
```

Only ports declared in the pod config are proxied, and the status code tells you
which: **404** = not exposed, **502** = proxied but nothing listening (bind here).
Default pods already expose **8888**, so binding uvicorn there avoids editing the pod
config and restarting.

> ⚠️ The proxy URL is public and the API has no auth — anyone with it can send audio
> and consume your GPU. Fine for solo testing, not once real conversations exist.

## Files

| File | What |
|---|---|
| `ContentView.swift` | Full-screen voice call, phase state machine, hidden settings |
| `VoiceOrb.swift` | The orb + aurora backdrop (Canvas waveform, ripples, arcs) |
| `AudioRecorder.swift` | Record 16 kHz mono m4a; meters mic **and** playback |
| `VoiceClient.swift` | API client, multipart upload, 300 s timeout (CSM is slow) |
| `Config.swift` | Server URL and placeholder names, kept out of the UI |

## Notes

- Records at 16 kHz mono because Whisper resamples to 16 k anyway — sending 44.1 k
  just wastes upload time on a phone network.
- The client timeout is 300 s deliberately. URLSession's 60 s default fails on a CSM
  turn.
- Utterances under 0.4 s are dropped client-side; the server would 422 them.
