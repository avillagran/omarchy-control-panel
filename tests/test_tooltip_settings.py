"""Isolated CLI tests for the shared tooltip preferences."""

import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "bin/tooltip-settings"
DEFAULTS = {"shape": "theme", "borderMode": "theme", "borderColor": "#ffffff"}


class TooltipSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.path = self.base / "config/omarchy/tooltips.json"
        integration = self.base / "omarchy/shell/Commons/ToolTipStyle.qml"
        integration.parent.mkdir(parents=True)
        integration.touch()
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.base / "config"),
                    "HOME": str(self.base / "home"), "OMARCHY_PATH": str(self.base / "omarchy")}

    def call(self, *args):
        done = subprocess.run(["python3", str(HELPER), *args], env=self.env,
                              capture_output=True, text=True)
        return done.returncode, json.loads(done.stdout)

    def test_read_defaults_without_creating_file(self):
        code, output = self.call("get")
        self.assertEqual(code, 0)
        self.assertEqual(output["settings"], DEFAULTS)
        self.assertTrue(output["available"])
        self.assertFalse(self.path.exists())

    def test_fields_preserve_unknown_and_restore_theme(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps({"other": {"keep": True}, "shape": "rounded"}))
        for field, value in [("borderColor", "#AbC123"), ("borderMode", "custom"),
                             ("shape", "square"), ("shape", "theme"),
                             ("borderMode", "theme")]:
            code, result = self.call("set", field, value)
            self.assertEqual(code, 0, result)
        actual = json.loads(self.path.read_text())
        self.assertEqual(actual, {**DEFAULTS, "other": {"keep": True}, "borderColor": "#abc123"})
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        before = self.path.stat().st_mtime_ns
        self.assertEqual(self.call("set", "shape", "theme")[0], 0)
        self.assertEqual(self.path.stat().st_mtime_ns, before)

    def test_invalid_changes_never_mutate(self):
        self.assertEqual(self.call("set", "shape", "rounded")[0], 0)
        before = self.path.read_bytes()
        for field, value in [("shape", "oval"), ("borderMode", "opaque"),
                             ("borderColor", "#12345"), ("borderColor", "red"),
                             ("borderColor", "#ffffff\n"), ("unknown", "ok")]:
            code, output = self.call("set", field, value)
            self.assertNotEqual(code, 0, output)
            self.assertFalse(output["ok"])
            self.assertEqual(self.path.read_bytes(), before)

    def test_malformed_file_is_not_replaced(self):
        self.path.parent.mkdir(parents=True)
        for invalid in ["[1,2]", "{", '{"shape":"oval"}']:
            self.path.write_text(invalid)
            code, result = self.call("set", "shape", "theme")
            self.assertEqual((code, result["error"]), (1, "invalid_file"))
            self.assertEqual(self.path.read_text(), invalid)

    def test_unavailable_integration_blocks_writes(self):
        self.env["OMARCHY_PATH"] = str(self.base / "missing")
        code, state = self.call("get")
        self.assertEqual(code, 0)
        # A system-wide integration may exist independently of OMARCHY_PATH.
        if not state["available"]:
            code, result = self.call("set", "shape", "rounded")
            self.assertEqual((code, result["error"]), (1, "unavailable"))
            self.assertFalse(self.path.exists())

    def test_parallel_writers_merge_distinct_fields(self):
        updates = [("shape", "rounded"), ("borderMode", "custom"), ("borderColor", "#123ABC")]
        for _ in range(8):
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                outputs = list(pool.map(lambda pair: self.call("set", *pair), updates))
            self.assertTrue(all(code == 0 for code, _ in outputs), outputs)
            self.assertEqual(json.loads(self.path.read_text()),
                             {"shape": "rounded", "borderMode": "custom", "borderColor": "#123abc"})
            self.path.unlink()


if __name__ == "__main__":
    unittest.main()
