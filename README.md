![FX Talk — Hold. Speak. Enter. Built with GPT-6 Astra in Codex.](docs/assets/fx-talk-banner.png)

# FX Talk

**Hold. Speak. Enter.** An experimental macOS utility that turns the Teenage Engineering EP–2350 FX-MIC into a physical controller for dictation and the Enter key.

Built with **GPT-6 Astra in Codex**, developed and physically tested by [Blake Graham](https://github.com/bjg4). The core audio decoder and chirp generator are adapted from [Tingle](https://github.com/tutorintelligence/tingle); see the [source provenance](NOTICE.md). This is an independent project, not affiliated with or endorsed by Teenage Engineering or OpenAI.

**[Download v0.4.0](https://github.com/bjg4/fx-talk/releases/tag/v0.4.0)** · **[Setup guide](docs/TRANSFER-GUIDE.md)** · **[Compatibility](docs/COMPATIBILITY.md)** · **[Roadmap](ROADMAP.md)**

Normal use needs only the mic’s curly audio cable and a USB audio input adapter. This is a working prototype with one verified hardware combination; installation is still assisted and the app is not yet notarized.

```text
FX-MIC on AAA batteries → curly 3.5 mm cable → USB audio input adapter → Mac
```

| Control | Action |
| --- | --- |
| Hold the large squeeze paddle | Hold the configured dictation shortcut |
| Release the paddle | Finish dictation |
| Tap the small top orange button | Press Enter in the active app |
| White buttons | Unmapped in audio mode |

FX Talk decodes button signals locally. Monologue, Wispr Flow, Aqua Voice, or another separately installed dictation app handles transcription. FX Talk does not save recordings, inspect draft text, or send network requests.

## Tested hardware

This is the hardware used for physical testing of FX Talk 0.4.0:

| Component | Verified setup |
| --- | --- |
| Microphone | [Teenage Engineering EP–2350 FX-MIC](https://teenage.engineering/store/ep-2350), from the EP series, running firmware **1.0.9**. [Official device guide](https://teenage.engineering/guides/ep-2350). |
| Audio adapter | [CableCreation](https://www.cablecreation.com/) **USB-C audio adapter**, purchased from Amazon, shown in macOS as **Cable Creation**, with C-Media audio and a **48 kHz mono input**. Exact retail model is pending confirmation. |
| Mac | **M4 MacBook Air**, running **macOS 15.6.1**. |

The tested mic runs on **two AAA batteries**, with its **curly 3.5 mm audio cable** connected through the adapter to the Mac. The mic’s direct USB-C connection is needed temporarily for initial setup; it stays unplugged during normal use.

The adapter link goes to the manufacturer’s site; a purchase link will be added once the exact model is confirmed. See [adapter identification and compatibility limits](docs/COMPATIBILITY.md#tested-adapter-identification) before choosing another adapter.

## Download

Get the app and the complete transfer kit from **[Releases](https://github.com/bjg4/fx-talk/releases)**.

The **v0.4.0 release** contains the Apple-silicon build physically verified with USB-C unplugged. It is Developer ID-signed and **not notarized**; this is a personal development release. See [compatibility and tested scope](docs/COMPATIBILITY.md).

## Setup on a Mac

1. Move FX Talk.app to Applications and install your chosen dictation app separately.
2. Use an audio input adapter that supports 48 kHz and passes the 16.5–19.5 kHz control signals. See the [tested hardware](#tested-hardware) above. Output-only headphone adapters do not provide the required input.
3. Allow FX Talk Microphone and Accessibility access. Choose **Audio cable only**, select the adapter, and click **Listen on this input**.
4. Select the same adapter in your dictation app. Configure the same hold shortcut in both apps; the verified Monologue setup uses **Left Control + Left Option + D**.
5. Choose **Large squeeze paddle**, enable **Orange button presses Enter in any app**, and enable mic shortcuts.
6. With a prepared mic on batteries, wait for **Button signal locked**. Focus a text field, hold the paddle, speak, release, wait for the text, and tap orange.

The active app decides what Enter does: submit a message, execute a terminal command, or insert a newline. Orange is ignored during dictation; wait until your words appear before pressing it.

The mic retains its setup when moved to another Mac. Choose the new Mac’s actual adapter and grant permissions there. The [portable settings example](examples/preferences.json) intentionally contains no audio-device identifier; the app does not yet have an Import button.

Read the [transfer guide](docs/TRANSFER-GUIDE.md) for the downloadable kit’s full setup, troubleshooting, and removal instructions.

## Preparing another FX-MIC

A second mic needs a one-time USB data connection to install `device/main.py`, `config.json`, and four signal WAVs. The script adds signaling to the existing stock ROM program; **it does not flash firmware**. Only FX-MIC firmware **1.0.9** has been physically tested.

Back up the second mic’s entire disk first, including sample subfolders. From this repository, with Python 3 installed:

```sh
python3 device/install.py '/Volumes/FX MIC DISK' '/absolute/path/to/a/new/FX-MIC-install-backup'
```

This is an assisted fresh-install procedure, not an update wizard. The installer rejects unrelated existing configuration; custom scripts and presets need a reviewed migration. Its additional backup covers top-level files only, so keep the full manual backup. Eject the disk after successful read-back verification, unplug direct USB, and power-cycle on batteries.

Removal for a fresh installation uses the matching installed-file manifest:

```sh
python3 device/restore.py '/Volumes/FX MIC DISK'
```

The tool checks hashes before removing the six managed files. It does not reconstruct an earlier custom configuration. Keep each mic’s original backup separately; device backups are not stored in this repository.

## Build and test

Requires macOS, Swift 5.10 or later, Xcode command-line tools, and Python 3. The declared deployment target is macOS 13; physical acceptance was on an M4 MacBook Air running macOS 15.6.1.

```sh
zsh build.sh
```

This runs **24 Swift tests and nine Python device tests**, builds the app for the host architecture, and writes `dist/FX Talk.app` and `dist/FX Talk.zip`. Tests simulate controls and audio; they do not inject keyboard events into the session. GitHub Actions runs the same tests and compiles the app.

Builds use an ad hoc signature by default. To use a stable local signing identity:

```sh
FX_TALK_SIGN_IDENTITY='your signing identity' zsh build.sh
```

Reusing an identity preserves the app’s identity across development builds. No signing private key, account token, or dictation preferences file is distributed. The supplied release binary is arm64; Intel and other operating systems need separate builds or ports and testing.

## Current behavior

- Mic shortcuts start disabled after app launch or Mac wake. Enable them again before use.
- The mic sleeps after five idle minutes on batteries and turns off after twenty. Squeeze to wake from sleep; power it on after shutdown.
- There is no fixed dictation duration limit. Three seconds without a valid button report releases a held shortcut.
- Orange emits one Enter per accepted press. Startup-held buttons cannot submit; an 800 ms duplicate-press guard remains in place.
- The mic’s sample slots and clean-speech presets are used by the signaling installation.

See [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), and [planned improvements](ROADMAP.md).

## License

FX Talk is [MIT-licensed](LICENSE). Adapted Tingle code retains its original MIT copyright and license notice. See [NOTICE.md](NOTICE.md) for the exact source provenance and scope of our additions.

## Credits

The chirp synthesis and matched-filter detector are adapted from [Tingle](https://github.com/tutorintelligence/tingle), Copyright © 2026 Tutor Intelligence, Inc., at commit `c762c04544dbf32b38c4ad9e688570810b15c5b1`, under the MIT License. The full [Tingle license](ThirdParty/Tingle-LICENSE.txt) is included in the source and app bundle. FX Talk adds the full-state audio protocol, device script, serial integration, shortcut controls, and macOS settings interface.
