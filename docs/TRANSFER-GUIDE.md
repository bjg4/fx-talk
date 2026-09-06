# FX Talk 0.4.1 candidate — move to another Mac

Hold the large paddle to dictate. Release it to finish. Once the words appear, tap the small top orange button to press Enter in the active app. White buttons are currently unmapped.

The published v0.4.0 preview remains available on [Releases](https://github.com/bjg4/fx-talk/releases/tag/v0.4.0). This guide describes the v0.4.1 candidate; public replacement packages still need the repository’s signing, notarization, and physical acceptance checks.

## Included

- FX Talk.app: the Apple-silicon candidate build; see Compatibility and Next Features for tested scope.
- Mic Setup: startup script, clean-speech configuration, four audio signals, installation and removal tools.
- Source: Swift app, Python device code, tests, build script, and Tingle license.
- Portable Settings.json: the working shortcut/mapping without any computer-specific audio identifier.
- Compatibility and Next Features: tested scope and suggested improvements.
- SHA256SUMS.json: checksums of every file in this kit except this checksum file.

No dictation-account credentials, recordings, personal device backups, or signing private keys are included. Monologue and other transcription apps are separate installations.

## Upgrading from 0.4.0

Quit FX Talk and replace the app in Applications with version 0.4.1. Keep the existing mic setup. On the first launch after upgrading, enable mic shortcuts once to save your choice. Future app restarts and Mac sleep/wake cycles restore that choice automatically after the mic reconnects and both controls are released.

## Same prepared mic, another Mac

1. Use an Apple-silicon Mac. The app targets macOS 13 or later; physical testing was on macOS 15.6.1. Move FX Talk.app to Applications. This is a Developer ID-signed personal development build, not yet notarized; it is not a finished public installer.
2. Connect the mic’s curly cable to a compatible USB audio input adapter connected to this Mac. See the [tested hardware and manufacturer links](https://github.com/bjg4/fx-talk#tested-hardware): the verified mic is the Teenage Engineering EP–2350 FX-MIC, and the CableCreation USB-C adapter appears as Cable Creation (C-Media) in macOS. The adapter’s exact retail model is pending confirmation. A new adapter must provide an actual audio input at 48 kHz and pass the 16.5–19.5 kHz button signals. An output-only headphone dongle does not suffice.
3. Install and sign into Monologue separately. Configure its secondary shortcut as Left Control + Left Option + D with hold-to-talk behavior. Keep other bindings if desired. The app’s shortcut recorder previously caused keyboard doubling on the original Mac; do not repeatedly drive that recorder with automated keystrokes. If this occurs, quit Monologue and FX Talk and repair the binding before continuing.
4. Open FX Talk and allow Microphone and Accessibility access in macOS. Each Mac grants its own permissions.
5. Choose Audio cable only, select the actual adapter on this Mac, and click Listen on this input. Choose that same input in Monologue. If using Monologue’s automatic input selection, set this adapter as the Mac’s default input.
6. Choose Monologue, Hold to talk, Control + Option + D, and Large squeeze paddle. Enable Orange button presses Enter in any app and Enable mic shortcuts. These are the settings described by Portable Settings.json; applying them in the app is sufficient. There is currently no Import button.
7. Leave the mic’s direct USB-C cable unplugged. Turn it on with two AAA batteries, release both controls, and wait about three seconds for Button signal locked.
8. In TextEdit, dictate a short sentence. After the transcript appears, one orange press should insert one newline. Physically type abc123 to check normal typing. Then try a chat: one orange press should invoke that app’s normal Enter action. Also verify a 30-second dictation and a sleep/wake cycle.

The mic retains its installed script. Do not reinstall it merely because you are changing Macs. Re-select the adapter on the new Mac: audio device identifiers do not transfer reliably.

## Another FX-MIC

The Mac app is only one half of the setup. A second mic needs the six signaling files once. Only FX-MIC firmware 1.0.9 was physically tested; the installer does not check firmware compatibility. Check another firmware version before installing; this kit does not flash firmware.

Use the advanced tools in Mic Setup with Python 3. First connect that mic’s USB data cable, confirm its FX MIC DISK volume, and copy its entire disk to a fresh backup folder. Keep that backup with that specific mic. The installer also saves top-level original files, but that is not a complete backup of sample subfolders.

From Terminal, change to the extracted Mic Setup folder and run:

```sh
python3 install.py '/Volumes/FX MIC DISK' '/absolute/path/to/a/new/FX-MIC-install-backup'
```

Use this procedure for a fresh mic only. The installer refuses an unrelated existing main.py/configuration. A mic with custom scripts or presets needs a reviewed migration. The tools are included for assisted setup; a graphical installer and fresh-device validation remain future work.

After successful read-back verification, eject the disk, unplug direct USB, and power-cycle the mic on batteries. Keep the curly audio cable and audio adapter connected. Complete the same TextEdit and chat checks above.

To remove this fresh installation later, disable FX Talk, reconnect the mic’s direct USB, and run from that same Mic Setup folder:

```sh
python3 restore.py '/Volumes/FX MIC DISK'
```

Removal uses the installed-file checksums, stops if a managed file changed, and removes only the six managed files. It does not recreate a previous custom setup; retain the full original backup. Eject and power-cycle afterward.

## Daily use

FX Talk remains in the menu bar when its window closes. FX Talk remembers whether you enabled mic shortcuts. It releases held shortcuts before Mac sleep, reconnects to the saved audio adapter after wake, and resumes once both controls are released. The saved choice also survives app restarts; choosing Off stays Off. A fresh installation starts with shortcuts off. This does not automatically launch the app when you log in. On batteries the mic sleeps after five idle minutes and powers off after twenty. Squeeze to wake it from sleep; power it on if it has turned off.

Orange sends an unmodified Return wherever the cursor is. The active app decides whether that sends a message, executes a terminal command, or inserts a newline. Press after the transcript is ready; presses during dictation are ignored. One held press does not repeat, and an 800 ms duplicate-press guard remains in place.

## Source and rebuilding

Source/fx-talk contains the complete source and third-party license. Building needs Swift 5.10 or later, Xcode command-line tools, and Python 3. From that source folder, run zsh build.sh. It runs 31 Swift tests and nine Python tests. The default signature is ad hoc; use your own stable FX_TALK_SIGN_IDENTITY to preserve permission identity across builds. A signing private key is not distributed in this kit.
