# FX Talk audio signaling 0.3.4. Startup script for EP-2350 FX-MIC.
# Inspired by Tingle's host-independent sample signaling (MIT; see credits).
# Signals use the four sample slots; config.json makes all presets clean.
# No USB prints or file operations run in the periodic audio callback.

exec(open('/rom/main.py').read())
import time

_fx_stock = python_callback

def _fx_load_samples():
    # Load explicitly: some stock ROM versions have a broken optional
    # sample/duck config parser. Default ducking is zero (voice stays live).
    for slot in range(4):
        sample = open('/fat/fx-talk/%d.wav' % slot, 'rb')
        try:
            loaded = spl.load_wav(slot, sample, 'oneshot')
        finally:
            sample.close()
        if loaded is False:
            raise RuntimeError('Could not load FX Talk signal sample')

_fx_load_samples()
_fx_code = ((0, 0, 0, 0), (0, 1, 1, 2), (1, 0, 1, 1), (1, 1, 0, 3))
_fx_now = time.ticks_ms()
_fx_state = {
    'p': bool(ui.sw(4)), 'o': not bool(ui.sw(2)),
    'pc': bool(ui.sw(4)), 'oc': not bool(ui.sw(2)),
    'pt': _fx_now, 'ot': _fx_now,
    'pending': [], 'word': (), 'index': 0, 'next': _fx_now,
    'last': time.ticks_add(_fx_now, -700), 'ticks': 0,
}

def fx_talk_status():
    print('FXTAUDIO2', int(_fx_state['p']), int(_fx_state['o']), _fx_state['ticks'])

def _fx_paddle_value():
    # sw(4) closes at the start of travel. Gripping the mic to press orange
    # can close it while handle() stays near zero. Require deliberate travel,
    # then retain the hold until the handle returns and the switch opens.
    held = _fx_state['p']
    position = ui.handle()
    switch = bool(ui.sw(4))
    if not held and switch and position >= 0.50:
        return True
    if held and not switch and position <= 0.20:
        return False
    return held

def _fx_audio_tick():
    s = _fx_state
    now = time.ticks_ms()
    changed = False
    for key, value in (('p', _fx_paddle_value()), ('o', not bool(ui.sw(2)))):
        if value != s[key + 'c']:
            s[key + 'c'] = value
            s[key + 't'] = now
        elif value != s[key] and time.ticks_diff(now, s[key + 't']) >= 45:
            s[key] = value
            changed = True
    if changed:
        if len(s['pending']) >= 8:
            s['pending'] = []
        s['pending'].append(int(s['p']) + 2 * int(s['o']))
    if not s['word'] and time.ticks_diff(now, s['next']) >= 0 and (s['pending'] or time.ticks_diff(now, s['last']) >= 700):
        value = s['pending'].pop(0) if s['pending'] else int(s['p']) + 2 * int(s['o'])
        s['word'] = _fx_code[value]
        s['index'] = 0
        s['last'] = now
    if s['word'] and time.ticks_diff(now, s['next']) >= 0:
        spl.trigger(-1, s['word'][s['index']], True)
        s['index'] += 1
        s['next'] = time.ticks_add(now, 30)
        if s['index'] == 4:
            s['word'] = ()
            # An explicit quiet interval prevents adjacent state reports from
            # being assembled into a false release or orange-button press.
            s['next'] = time.ticks_add(now, 130)
    s['ticks'] += 1

def python_callback(message):
    try:
        kind, value = message >> 16, message & 0xFFFF
        # White would play an unframed sample; orange is now reserved for
        # the host action and must not switch presets during a signal.
        if kind in (1, 2) and value in (0, 2):
            return
        _fx_stock(message)
        if kind == 4 and value == 1:
            _fx_load_samples()
            _fx_state['word'] = ()
        if kind == 3:
            _fx_audio_tick()
    except Exception as error:
        # Restore the stock callback if our script fails. Never print here:
        # USB output can block forever after the data cable is removed.
        ui.callback(_fx_stock)
        try:
            import sys
            log = open('/fat/fx-talk-error.log', 'w')
            sys.print_exception(error, log)
            log.close()
        except:
            pass

ui.callback(python_callback)
