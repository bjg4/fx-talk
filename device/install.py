"""Install FX Talk's startup script/config/signal files; never flash firmware.

Usage: python3 device/install.py '/Volumes/FX MIC DISK' /absolute/backup/folder
After successful verification, eject the mic's disk before activating the script.
"""
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path
from generate_signals import generate

def install(volume, backup):
    volume, backup = Path(volume), Path(backup)
    if volume.name != 'FX MIC DISK' or not (volume / 'readme.pdf').is_file():
        raise RuntimeError('Expected the known FX MIC DISK volume with readme.pdf.')
    generate()
    source = Path(__file__).parent
    names = ['fx-talk/0.wav', 'fx-talk/1.wav', 'fx-talk/2.wav', 'fx-talk/3.wav', 'config.json', 'main.py']
    existing = {name: (volume / name).read_bytes() for name in names if (volume / name).is_file()}
    if existing and b'FX Talk audio signaling' not in existing.get('main.py', b''):
        raise RuntimeError('Existing user configuration detected. Back it up and review before replacement.')
    backup.mkdir(parents=True, exist_ok=True)
    for item in volume.iterdir():
        if item.is_file() and not (backup / item.name).exists():
            shutil.copyfile(item, backup / item.name)
    manifest = {}
    for name in names:
        target = volume / name
        target.parent.mkdir(exist_ok=True)
        data = (source / name).read_bytes()
        with target.open('wb') as out:
            out.write(data); out.flush(); os.fsync(out.fileno())
        if target.read_bytes() != data:
            raise RuntimeError(f'Read-back verification failed: {name}')
        manifest[name] = hashlib.sha256(data).hexdigest()
    (source / 'installed-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Installed and verified six files. Original sample files and firmware are unchanged.')

if __name__ == '__main__':
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    install(sys.argv[1], sys.argv[2])
