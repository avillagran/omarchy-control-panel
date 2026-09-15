#!/usr/bin/env python3
import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("hymission_manager", str(ROOT / "bin/hymission-manager"))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
manager = importlib.util.module_from_spec(spec)
loader.exec_module(manager)


class HymissionManagerTests(unittest.TestCase):
    def test_enabled_config_has_live_overview_inputs(self):
        text = manager.render_config(True, True, Path("/tmp/libhymission.so"))
        self.assertIn('SUPER + SHIFT + UP', text)
        self.assertIn('fingers = 3', text)
        self.assertIn('direction = "up"', text)
        self.assertIn('args = "forceall"', text)
        self.assertIn('hover_relayout_duration = 140', text)
        self.assertIn('workspace_change_keeps_overview = 0', text)

    def test_non_animated_config_is_immediate(self):
        text = manager.render_config(True, False, Path("/tmp/libhymission.so"))
        self.assertIn('hover_relayout_duration = 0', text)
        self.assertIn('hide_bar_animation = 0', text)

    def test_disabled_config_removes_keybinding(self):
        text = manager.render_config(False, False, Path("/tmp/libhymission.so"))
        self.assertIn('Hymission is disabled', text)
        self.assertIn('hl.unbind("SUPER + SHIFT + UP")', text)
        self.assertNotIn('fingers = 3', text)

    def test_require_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hyprland.lua"
            path.write_text("require(\"default.hypr.omarchy\")\n", encoding="utf-8")
            self.assertTrue(manager.ensure_require(path))
            self.assertFalse(manager.ensure_require(path))
            self.assertIn('require("hypr.hymission")', path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
