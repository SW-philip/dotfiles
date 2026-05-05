import sys
import importlib.util
from unittest.mock import MagicMock
sys.modules['PIL'] = MagicMock()
sys.modules['PIL.Image'] = MagicMock()
sys.modules['PIL.ImageDraw'] = MagicMock()
sys.modules['PIL.ImageChops'] = MagicMock()

import unittest

spec = importlib.util.spec_from_file_location("theme_gen", "tools/theme-gen.py")
theme_gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme_gen)
ThemeGenerator = theme_gen.ThemeGenerator


class TestPalettePromotion(unittest.TestCase):
    def _make_gen(self, rose="#ff69b4", foam="#40e0d0"):
        return ThemeGenerator(
            primary="#1a1a2e", secondary="#e94560", rose=rose,
            pine="#0f3460", foam=foam, accent="#533483", gold="#e2b96f"
        )

    def test_rose_is_direct(self):
        g = self._make_gen(rose="#ff69b4")
        palette = g.calculate_palette("dark")
        self.assertEqual(palette['ROSE'], "#ff69b4")

    def test_foam_is_direct(self):
        g = self._make_gen(foam="#40e0d0")
        palette = g.calculate_palette("dark")
        self.assertEqual(palette['FOAM'], "#40e0d0")


if __name__ == "__main__":
    unittest.main()
