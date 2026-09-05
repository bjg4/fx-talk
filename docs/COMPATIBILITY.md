# Compatibility and release status

## Verified

- App: FX Talk 0.4.0, Apple silicon (arm64), exact installed executable.
- Physical test Mac: M4 MacBook Air, macOS 15.6.1. Declared app minimum: macOS 13.
- Mic: Teenage Engineering EP–2350 FX-MIC, existing firmware 1.0.9.
- Adapter: Cable Creation, C-Media USB mono audio input, 48 kHz.
- Dictation: Monologue 1.5.0 (99), hold shortcut Left Control + Left Option + D.
- Battery-powered operation through curly audio cable only, paddle dictation, and orange Enter confirmed by the user.
- Enter events logged in the current chat app and Grok Bot. Other apps have not each been physically tested; output uses the same unmodified Return event in every app.
- Thirty-seven-second continuous dictation and battery sleep/wake observed; current app has no fixed recording time limit.
- 24 Swift tests and nine device callback tests passed. Packaged mic payload matches all six verified installation hashes.

## Needs separate validation or work

- Another Mac: select its adapter, configure the dictation shortcut, and grant permissions locally.
- Another FX-MIC: one-time installation plus physical acceptance; other firmware versions unverified.
- Intel Macs: source is included, but this binary is arm64 only. Build and test an Intel or universal version.
- Windows/Linux: would need a port of the audio receiver, shortcut output, and app. This Mac binary will not run there.
- iPhone/iPad: no supported version exists in this kit.
- Alternative adapters and dictation apps: require their own compatibility/shortcut test.
- Public distribution: add hardened runtime, an appropriate microphone entitlement, Apple notarization/stapling, and a first-run setup flow, then retest permission and audio behavior. The current stable app has not been changed to add these release settings.

Apple's distribution guidance:
https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

Teenage Engineering device guide:
https://teenage.engineering/guides/ep-2350
