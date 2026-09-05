# From working prototype to public utility

## Positioning

FX Talk is an independent macOS utility for the Teenage Engineering EP–2350 FX-MIC. Its promise is specific: hold the paddle to dictate, release to finish, then tap orange to press Enter in the active app. Normal operation uses the curly audio cable and a USB audio input adapter.

Describe the current release as **experimental, with assisted setup**. It depends on a separate dictation app. One hardware combination has been physically verified. Do not claim universal hardware compatibility or an unattended installer.

Development credit: **Built with GPT-6 Astra in Codex.** Human credit: Blake Graham for product direction and physical testing. Technical credit: Tingle's chirp synthesis and matched-filter detector, with its existing MIT notice retained. Do not imply Teenage Engineering or OpenAI sponsorship or endorsement.

## Visual direction

Use FX Talk as the project name. Warm gray, graphite, orange, compact monospaced annotations, thin rules, and simple control diagrams give the project an instrument-like appearance. Make original graphics. Keep the device manufacturer’s logo and official brand lockups out of the project’s own identity.

The first asset is `assets/fx-talk-banner.svg`, used by the README. A short real-device demonstration should follow: show both cables, unplug direct USB, dictate, and submit with one orange press. A human-recorded demonstration is still needed; do not present a mockup as a real test.

## Before changing repository visibility

- Approve a license for the original FX Talk code. MIT is proposed; Tingle’s MIT license and attribution remain intact. The proposal is not yet applied.
- Review repository history, release archives, signing-certificate identity, and Actions logs as public material. Exclude credentials, private keys, recordings, and device backups. Keep a clean copy of the accepted v0.4.0 package.
- Keep v0.4.0 marked as a prerelease with its exact tested configuration and known limitations.
- Provide reproducible build instructions and a clear way to report device, firmware, adapter, macOS, dictation app, and the observed behavior without uploading private text or recordings.

Making a repository public exposes its contents and Actions history/logs. See [GitHub’s visibility guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility). The proposed [MIT license](https://choosealicense.com/licenses/mit/) allows reuse, modification, and redistribution with its notice retained.

## Next release: someone else can set it up

The release goal is that a new user can install and complete the audio-only acceptance test without a developer operating their Mac.

1. **Complete backup and restore.** Back up the entire mic disk, including subfolders. Record the original and installed files per mic. Check payload integrity and compatibility before changes, stage writes, read them back, and preserve a recovery path if installation stops. The current helper only makes an extra top-level backup and is not a migration wizard.
2. **Guided setup.** Select the input, verify 48 kHz and the button signal, explain microphone/Accessibility access, guide the matching dictation shortcut, and test both controls in a scratch text field. Avoid automating Monologue’s shortcut recorder, which previously triggered keyboard doubling during setup.
3. **Distribution.** Add and test hardened runtime with required audio permissions, secure-timestamped Developer ID signing, Apple notarization, and a stapled ticket. Test a fresh download on another Mac. Follow [Apple’s notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
4. **Recovery and feedback.** Offer launch at login and an explicit opt-in to resume after Mac sleep once controls have been released. Make disconnected, ready, and shortcut-held states visible. Indicate an Enter event without claiming the target app actually submitted it.
5. **Independent beta testing.** Start with a small group. Verify fresh setup and removal on at least two FX-MICs and two Macs; document the exact firmware, adapters, and dictation apps. Include a 30-second hold, rapid/repeated presses, startup-held buttons, battery sleep, Mac sleep, adapter disconnect/reconnect, normal typing, and one Enter per accepted press.

## After setup and recovery are dependable

Add configurable white-button Escape/Undo or hands-free actions, optional per-app shortcut overrides, and an Intel/universal build if there is demand. Built-in transcription is a larger separate project. The current audio protocol contains only paddle and orange, so white-button features require coordinated device and host changes.
