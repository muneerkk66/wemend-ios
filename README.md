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

No SSH tunnel needed. RunPod proxies any **exposed** port over public HTTPS:

```
https://<pod-id>-<port>.proxy.runpod.net
```

That is the app's default. It works on a **physical device** as-is — public HTTPS, so
no App Transport Security exception required.

### Finding a port RunPod is actually proxying

Only ports declared in the pod's config are proxied, and the status code tells you
which is which:

| Response | Meaning |
|---|---|
| `404` | Port is **not** exposed in the pod config |
| `502` | Port **is** proxied, nothing listening yet — bind here |

```bash
for p in 8888 8080 8000 3000; do
  echo "$p -> $(curl -s -o /dev/null -w '%{http_code}' https://<pod-id>-$p.proxy.runpod.net/health)"
done
```

On a default RunPod pod, **8888** (the Jupyter port) is already exposed, so binding
uvicorn there avoids editing the pod config and restarting.

> ⚠️ **The proxy URL is public and the API has no auth.** Anyone with the URL can
> send audio and consume your GPU. Fine for a solo test, not acceptable once real
> conversations are involved — add a bearer token before then.

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
