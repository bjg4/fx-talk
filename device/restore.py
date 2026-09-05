"""Remove only the FX Talk files installed on this mic to restore stock behavior.

Usage: python3 device/restore.py '/Volumes/FX MIC DISK'
Then eject the disk and power-cycle the mic. Original files were never overwritten.
"""
import hashlib
import json
import sys
from pathlib import Path

def restore(volume):
    volume = Path(volume)
    manifest = json.loads(Path(__file__).with_name('installed-manifest.json').read_text())
    for name, expected in manifest.items():
        file = volume / name
        if file.exists() and hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'{name} has changed since installation; preserve it and review manually.')
    for name in manifest:
        file = volume / name
        if file.exists(): file.unlink()
    folder = volume / 'fx-talk'
    if folder.exists() and not any(folder.iterdir()): folder.rmdir()
    print('FX Talk startup/config/signals removed. Eject the disk and power-cycle the mic.')

if __name__ == '__main__':
    if len(sys.argv) != 2: raise SystemExit(__doc__)
    restore(sys.argv[1])
