# Useful next additions

Version 0.4.1 adds recovery after Mac sleep and remembers the on/off choice across app restarts. The remaining proposals are listed below. The next release prioritizes guided setup, complete backup/restore, distribution, and independent testing; see the [public release plan](docs/PUBLIC-RELEASE.md).

1. Launch at login: offer an opt-in to open FX Talk automatically when the user signs in. Version 0.4.1 already restores the on/off choice across app restarts and Mac sleep, reconnecting and requiring released controls before resuming.
2. Clear feedback: a compact ready/listening/disconnected indicator, plus a visible confirmation when FX Talk detects orange and sends Enter. Distinguish our button/shortcut status from transcription status reported by the dictation app.
3. White-button mappings: make the middle button Escape/cancel and the bottom button Undo or another chosen shortcut. Audio-only operation currently encodes only paddle and orange; adding white buttons requires extending both the mic protocol and Mac decoder.
4. Setup assistant: verify the selected audio input and 48 kHz format, test both buttons, explain permissions, configure the matching dictation shortcut, and back up/install a fresh mic. This is the highest-value addition before sharing with others.
5. Optional app mappings: keep universal Enter as the default; allow overrides such as Command + Return only where the user wants them.
6. Later: built-in transcription could remove the separate dictation-app dependency. That introduces microphone/transcription orchestration, model choice, latency, and text-insertion work; it should be a separate development branch.

Keep the accepted 0.4.0 package as a rollback point while developing additions. Do not overwrite a working Monologue configuration with someone else's settings.
