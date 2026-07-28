# wemend-ios

Voice UI for **WeMendAI** — an AI mediator for couples. SwiftUI, iOS 17+.

Full-screen voice call: tap the orb, speak, the mediator replies aloud. Modelled on
ChatGPT's voice mode — black gradient backdrop, an animated orb, and a live waveform.

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
