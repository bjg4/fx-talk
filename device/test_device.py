import builtins
import types
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('main.py').read_text()

class FakeTime:
    now = 0
    @classmethod
    def ticks_ms(cls): return cls.now
    @staticmethod
    def ticks_add(a, b): return a + b
    @staticmethod
    def ticks_diff(a, b): return a - b

class DeviceTests(unittest.TestCase):
    def boot(self, paddle=False):
        FakeTime.now = 0
        self.switches = {4: int(paddle), 2: 1}
        self.played = []
        self.stock = []
        self.callback = None
        self.position = None
        ui = types.SimpleNamespace(sw=lambda k: self.switches[k], callback=self.set_callback,
            handle=lambda: float(self.switches[4]) if self.position is None else self.position)
        spl = types.SimpleNamespace(trigger=lambda a, slot, on: self.played.append((FakeTime.now, slot)))
        env = {'ui': ui, 'spl': spl, 'python_callback': self.stock.append}
        # Skip only the stock ROM bootstrap; execute our entire callback unchanged.
        source = SCRIPT.replace("exec(open('/rom/main.py').read())", '')
        source = source.replace('\n_fx_load_samples()\n', '\n')
        with patch.dict('sys.modules', {'time': FakeTime}): exec(source, env)
        self.env = env
    def set_callback(self, callback): self.callback = callback
    def tick(self, ms=10):
        FakeTime.now += ms
        self.callback(3 << 16)
    def advance(self, ms):
        for _ in range(ms // 10): self.tick()
    def test_periodic_complete_idle_words(self):
        self.boot(); self.advance(2200)
        self.assertEqual([s for _, s in self.played], [0] * 16)
        self.assertTrue(all(b[0] - a[0] >= 30 for a, b in zip(self.played, self.played[1:])))
    def test_debounce_and_all_state_words(self):
        self.boot(); self.advance(200)
        self.switches[4] = 1; self.advance(20)
        self.switches[4] = 0; self.advance(80)
        self.assertEqual(len(self.played), 4)
        for paddle, orange, code in [(1, 1, [0,1,1,2]), (1, 0, [1,1,0,3]), (0, 0, [1,0,1,1]), (0, 1, [0,0,0,0])]:
            before = len(self.played)
            self.switches[4] = paddle; self.switches[2] = orange
            self.advance(300)
            self.assertEqual([s for _, s in self.played[before:]], code)
    def test_startup_held_and_white_suppression(self):
        self.boot(paddle=True); self.advance(150)
        self.assertEqual([s for _, s in self.played], [0,1,1,2])
        count = len(self.stock)
        self.callback(1 << 16); self.callback(2 << 16)
        self.assertEqual(len(self.stock), count)
    def test_state_change_during_word_does_not_interleave(self):
        self.boot(); self.advance(20)
        self.switches[4] = 1; self.advance(400)
        self.assertEqual([s for _, s in self.played], [0,0,0,0,0,1,1,2])
    def test_words_have_quiet_boundaries(self):
        self.boot(); self.advance(20)
        self.switches[4] = 1; self.advance(400)
        self.assertGreaterEqual(self.played[4][0] - self.played[3][0], 130)
    def test_orange_tap_is_queued_and_does_not_change_stock_preset(self):
        self.boot(); self.advance(20)
        self.switches[2] = 0; self.advance(70)
        self.switches[2] = 1; self.advance(600)
        self.assertEqual([slot for _, slot in self.played], [0,0,0,0,1,0,1,1,0,0,0,0])
        count = len(self.stock)
        self.callback((1 << 16) | 2); self.callback((2 << 16) | 2)
        self.assertEqual(len(self.stock), count)
    def test_exception_restores_stock_callback(self):
        self.boot()
        self.env['spl'].trigger = lambda *args: 1 / 0
        self.tick()
        self.assertEqual(self.callback, self.stock.append)
    def test_orange_grip_nudge_cannot_start_dictation(self):
        self.boot(); self.advance(200)
        self.position = 0.13
        self.switches[4] = 1; self.switches[2] = 0
        self.advance(400)
        self.assertFalse(self.env['_fx_state']['p'])
        self.assertTrue(self.env['_fx_state']['o'])
        self.assertEqual([slot for _, slot in self.played[4:]], [1,0,1,1])
    def test_deliberate_squeeze_holds_through_switch_bounce_and_releases(self):
        self.boot(); self.advance(200)
        self.position = 0.65; self.switches[4] = 1; self.advance(300)
        self.assertTrue(self.env['_fx_state']['p'])
        self.position = 0.55; self.switches[4] = 0; self.advance(200)
        self.assertTrue(self.env['_fx_state']['p'])
        self.position = 0.10; self.advance(300)
        self.assertFalse(self.env['_fx_state']['p'])

if __name__ == '__main__': unittest.main()
