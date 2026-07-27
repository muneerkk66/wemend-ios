# wemend-ios

Test harness for the [WeMendAI voice backend](https://github.com/muneerkk66/wemend-backend).
SwiftUI, iOS 17+.

Not a product UI. Its job is to let you **hear CSM vs Kokoro on a real device** and see
exactly what each costs, instead of trusting a benchmark table.

## What it does

Record an utterance → upload → mediator replies aloud → shows the transcript and a
per-stage latency breakdown (STT / LLM / TTS / total) plus the measured realtime factor.

A segmented control switches TTS engine per request. Expect the difference to be
obvious: Kokoro replies in ~3 s, CSM takes ~25 s for the same reply.

## Build

```bash
brew install xcodegen     # once
xcodegen generate         # creates WeMendAI.xcodeproj
open WeMendAI.xcodeproj
```

No XcodeGen? Create a new iOS App in Xcode named `WeMendAI`, delete its generated
`ContentView.swift`, drag in the four files from `WeMendAI/`, and set
`NSMicrophoneUsageDescription` in Info.plist.

## Point it at the backend

The pod has no public HTTPS, so tunnel port 8000 to your Mac:

```bash
ssh -N -L 8000:127.0.0.1:8000 root@<pod-ip> -p <pod-port> -i ~/.ssh/id_ed25519
```

Then use `http://localhost:8000` in the app's Server field. Works on the **simulator**.

For a **physical device**, either expose the port via RunPod's HTTP proxy
(`https://<pod-id>-8000.proxy.runpod.net`) or run the tunnel on a host the phone can
reach and use your Mac's LAN IP. `Info.plist` allows insecure HTTP for localhost/LAN
**for development only** — remove that before shipping.

## Files

| File | What |
|---|---|
| `VoiceClient.swift` | API client, multipart upload, 300 s timeout (CSM is slow) |
| `AudioRecorder.swift` | AVFoundation record (16 kHz mono m4a) + playback + level meter |
| `ContentView.swift` | UI, engine picker, latency readout |

## Notes

- Records at 16 kHz mono because Whisper resamples to 16 k anyway — sending 44.1 k
  just wastes upload time on a phone network.
- The client timeout is 300 s deliberately. URLSession's 60 s default fails on a CSM
  turn.
- Utterances under 0.4 s are dropped client-side; the server would 422 them.
