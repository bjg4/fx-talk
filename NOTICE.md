# Attribution and source provenance

FX Talk was built with GPT-6 Astra in Codex, with product direction and physical hardware testing by Blake Graham. It is an independent project, not affiliated with or endorsed by Teenage Engineering or OpenAI.

## Code adapted from Tingle

FX Talk includes substantial source adapted from [Tingle](https://github.com/tutorintelligence/tingle), Copyright (c) 2026 Tutor Intelligence, Inc., under the [MIT License](ThirdParty/Tingle-LICENSE.txt).

The upstream snapshot used was commit [`c762c04544dbf32b38c4ad9e688570810b15c5b1`](https://github.com/tutorintelligence/tingle/tree/c762c04544dbf32b38c4ad9e688570810b15c5b1).

| FX Talk file | Origin and changes |
| --- | --- |
| `Sources/FXTalkCore/AudioSignal/SymbolSet.swift` | Adapted from Tingle's `Sources/TingleCore/SymbolSet.swift`. Retains the chirp synthesis, signal bands, and codeword alphabet; changes amplitude and the message/state interpretation. |
| `Sources/FXTalkCore/AudioSignal/SymbolDetector.swift` | Adapted from Tingle's `Sources/TingleCore/SymbolDetector.swift`. Retains its matched-filter DSP, correlation, and signal-acquisition foundation; changes event output, state decoding, damaged-frame handling, and timing for this integration. |
| `device/generate_signals.py` | Python implementation of the same chirp synthesis used by the adapted SymbolSet, producing the four matching WAV files. |

These are code adaptations, not merely conceptual inspiration. The audio decoder and generator are a substantial part of what makes audio-only button signaling possible.

## FX Talk-specific work

The project adds its macOS settings interface, dictation-app shortcut integration, universal Enter output, full-state paddle/orange protocol, modified device callback behavior, paddle-travel filtering, reconnect/hold handling, installation helpers, packaging, and tests for the observed failures.

The device startup script also follows Tingle's approach of running the stock ROM program and adding sample-slot signaling through the UI callback. Its current state queue, timing, button mapping, and grip filtering were tailored to FX Talk; it is not a wholesale copy of Tingle's device script.

Transcription itself is provided by the separately installed dictation app, such as Monologue. FX Talk does not include its own speech-to-text model.

## Licenses

Original FX Talk contributions are licensed under the root [MIT License](LICENSE), Copyright (c) 2026 Blake Graham. Tingle's existing copyright and MIT notice remain in [ThirdParty/Tingle-LICENSE.txt](ThirdParty/Tingle-LICENSE.txt) and the adapted Swift files. Both license notices must accompany redistribution of the combined project.
