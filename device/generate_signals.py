# Chirp synthesis adapted from Tingle, Copyright (c) 2026 Tutor Intelligence, Inc.
# MIT license: ../ThirdParty/Tingle-LICENSE.txt.
"""Generate FX Talk's exact 48 kHz chirp alphabet using only Python's stdlib."""
import json
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).parent
SWEEPS = [(16500, 17900), (17900, 16500), (18100, 19500), (19500, 18100)]
RATE, COUNT, FADE, AMPLITUDE = 48000, 1200, 144, 0.30

def synthesize(symbol):
    low, high = SWEEPS[symbol]
    phase = 0
    pcm = []
    for i in range(COUNT):
        phase += 2 * math.pi * (low + (high - low) * i / COUNT) / RATE
        value = math.sin(phase)
        if i < FADE:
            value *= 0.5 * (1 - math.cos(math.pi * i / FADE))
        end = COUNT - 1 - i
        if end < FADE:
            value *= 0.5 * (1 - math.cos(math.pi * end / FADE))
        pcm.append(round(value * AMPLITUDE * 32767))
    return struct.pack('<' + 'h' * len(pcm), *pcm)

def generate():
    folder = ROOT / 'fx-talk'
    folder.mkdir(exist_ok=True)
    for symbol in range(4):
        with wave.open(str(folder / f'{symbol}.wav'), 'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(RATE)
            wav.writeframes(synthesize(symbol))
    config = {
        'name': 'FX Talk clean speech',
        'samples': [],
        'presets': [{'pos': i, 'list': [{'effect': 'SAMPLE'}], 'trigger': {'row': 0}} for i in range(4)]
    }
    (ROOT / 'config.json').write_text(json.dumps(config, separators=(',', ':')) + '\n')

if __name__ == '__main__':
    generate()
