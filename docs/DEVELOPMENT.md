# Building and contributing to FX Talk

For installation and everyday use, start with the [setup guide](TRANSFER-GUIDE.md). This guide covers building the source and preparing a mic from a checkout.

## Requirements

macOS, Swift 5.10 or later, Xcode command-line tools, and Python 3. The declared deployment target is macOS 13; physical acceptance was on an M4 MacBook Air running macOS 15.6.1.

## Build and test

From the repository root:

```sh
zsh build.sh
```

This runs **31 Swift tests and nine Python device tests**, regenerates the mic signals, builds the app for Apple silicon (arm64), and writes `dist/FX Talk.app` and `dist/FX Talk.zip`. Tests simulate controls and audio; they do not inject keyboard events into the session. GitHub Actions runs the same tests and compiles the app.

The build does not install or launch the app. Generated build products remain outside version control. After building, confirm that signal generation preserved the checked-in mic payload:

```sh
git diff --exit-code -- device/
```

Builds use an ad hoc signature by default. To use a stable local signing identity:

```sh
FX_TALK_SIGN_IDENTITY='your signing identity' zsh build.sh
```

Reusing an identity preserves the app’s identity across development builds. No signing private key, account token, or dictation preferences file is distributed. The supplied release binary is arm64; Intel and other operating systems need separate builds or ports and testing. See [compatibility and distribution requirements](COMPATIBILITY.md).

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/FXTalk/` | Mac app, settings, audio input, and keyboard output |
| `Sources/FXTalkCore/` | Control routing, serial parsing, and audio decoder |
| `Tests/` | Swift tests |
| `device/` | Mic script, configuration, signal WAVs, installer, restore tool, and Python tests |
| `packaging/` | App bundle metadata and icon generator |
| `docs/` | Setup, compatibility, architecture, and release planning |
| `examples/` | Portable settings example without a computer-specific audio identifier |
| `ThirdParty/` | Original third-party license notices |
| `.github/` | Automated build checks and issue template |

`Package.swift` defines the Swift package; `build.sh` runs tests and assembles the Mac app. `.gitignore` excludes generated builds, local settings, logs, backups, and signing keys. The root license and [NOTICE.md](../NOTICE.md) cover licensing and code provenance.

## Preparing a mic from source

A fresh mic needs a one-time USB data connection to install `device/main.py`, `config.json`, and four signal WAVs. The script adds signaling to the existing stock ROM program; **it does not flash firmware**. Only FX-MIC firmware **1.0.9** has been physically tested.

Back up the mic’s **entire disk first**, including sample subfolders. With Python 3 installed, run from the repository root:

```sh
python3 device/install.py '/Volumes/FX MIC DISK' '/absolute/path/to/a/new/FX-MIC-install-backup'
```

This is an assisted fresh-install procedure, not an update wizard. The installer rejects unrelated existing configuration; custom scripts and presets need a reviewed migration. Its additional backup covers top-level files only, so keep the full manual backup. Eject the disk after successful read-back verification, unplug direct USB, and power-cycle on batteries.

Removal for a fresh installation uses the matching installed-file manifest:

```sh
python3 device/restore.py '/Volumes/FX MIC DISK'
```

The tool checks hashes before removing the six managed files. It does not reconstruct an earlier custom configuration. Keep each mic’s original backup separately; device backups are not stored in this repository. Follow the [transfer guide’s physical acceptance checks](TRANSFER-GUIDE.md#same-prepared-mic-another-mac) after setup on each new Mac or mic.

## Changes and bug reports

Read the [architecture](ARCHITECTURE.md) before changing control timing or the audio protocol. The [roadmap](../ROADMAP.md) describes planned work. Include relevant test results in a pull request and preserve the license notices for adapted code.

For hardware issues, use the [issue template](https://github.com/bjg4/fx-talk/issues/new) to record the mic firmware, adapter, Mac, dictation app, and steps to reproduce. Report only relevant diagnostic events; omit private dictated text and recordings.
