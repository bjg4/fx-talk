# How FX Talk works

The device startup script executes the mic’s stock ROM program, loads four short WAV signals, and adds a periodic UI callback. Speech and these high-frequency signals share the analog output; the direct USB connection is unnecessary during normal use.

Each four-symbol word encodes the complete paddle/orange state. A quiet interval separates words. Changes are queued, and the current state repeats every 700 ms. The host accepts exact complete words rather than guessing a state from a damaged burst.

The Mac app opens the selected 48 kHz audio input with AVAudioEngine and decodes the first channel locally. DSP work uses a bounded queue. Input loss releases any held dictation shortcut. A released, previously known mic can re-arm after battery sleep; startup-held controls require a release first.

A deliberate paddle press needs at least 50% travel and remains held until travel returns below 20% and the raw switch opens. This filters the slight grip movement that can occur when pressing orange.

The paddle sends the configured hold shortcut through a private CGEvent source. After the paddle is released, orange emits one Return key down/up with no modifiers in the active session. It does not inspect the app’s text fields, retry a submission later, or intercept physical keyboard events. The dictation app owns recording, transcription, and text insertion.

The audio protocol currently contains paddle and orange only. White-button mapping requires coordinated changes to the device script, symbols/protocol, host receiver, and tests. Firmware is not flashed by these tools.

Source areas:

- Sources/FXTalk: app state, UI, Core Audio input, and keyboard output.
- Sources/FXTalkCore: button routing, serial parsing, and audio decoder.
- device: mic startup/configuration, signal generation, install/remove tools, and callback tests.
- Tests/FXTalkCoreTests: host-side routing, serial, and audio tests.
