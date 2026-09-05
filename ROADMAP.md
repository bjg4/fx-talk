# Useful next additions

These are proposals; the accepted 0.4.0 app and mic behavior have not been changed.

1. Automatic startup and recovery: launch at login; optionally resume after Mac sleep once the adapter is present and both controls have been seen released. Preserve one-shot Enter behavior.
2. Clear feedback: a compact ready/listening/disconnected indicator, plus a visible confirmation when FX Talk detects orange and sends Enter. Distinguish our button/shortcut status from transcription status reported by the dictation app.
3. White-button mappings: make the middle button Escape/cancel and the bottom button Undo or another chosen shortcut. Audio-only operation currently encodes only paddle and orange; adding white buttons requires extending both the mic protocol and Mac decoder.
4. Setup assistant: verify the selected audio input and 48 kHz format, test both buttons, explain permissions, configure the matching dictation shortcut, and back up/install a fresh mic. This is the highest-value addition before sharing with others.
5. Optional app mappings: keep universal Enter as the default; allow overrides such as Command + Return only where the user wants them.
6. Later: built-in transcription could remove the separate dictation-app dependency. That introduces microphone/transcription orchestration, model choice, latency, and text-insertion work; it should be a separate development branch.

Keep the accepted 0.4.0 package as a rollback point while developing additions. Do not overwrite a working Monologue configuration with someone else's settings.
