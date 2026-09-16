#!/usr/bin/env python3
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("display_hotplug_sync", str(ROOT / "bin/display-hotplug-sync"))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class DisplayHotplugSyncTests(unittest.TestCase):
    def test_active_profile_display_map(self):
        profiles = {
            "activeProfileId": "desk",
            "profiles": [
                {"id": "other", "settings": {"displays": {"DP-1": {"x": 0}}}},
                {"id": "desk", "settings": {"displays": {"eDP-1": {"x": 1920, "scale": 2}}}},
            ],
        }
        self.assertEqual(module.active_display_map(profiles), {"eDP-1": {"x": 1920, "scale": 2}})

    def test_prefers_exact_physical_monitor_combination(self):
        current = [
            {"name": "eDP-1", "fingerprint": "BOE|Panel|ABC", "disabled": False},
            {"name": "HDMI-A-1", "fingerprint": "Dell|U2723QE|XYZ", "disabled": False},
        ]
        profiles = {"activeProfileId": "desk", "profiles": [{"id": "desk", "settings": {
            "displays": {"HDMI-A-1": {"x": 0}},
            "displayLayouts": {"BOE|Panel|ABC::Dell|U2723QE|XYZ": {
                "BOE|Panel|ABC": {"x": 0}, "Dell|U2723QE|XYZ": {"x": 1728}
            }}
        }}]}
        selected = module.active_display_map(profiles, current)
        self.assertEqual(selected["Dell|U2723QE|XYZ"]["x"], 1728)

    def test_merge_uses_saved_geometry_only_for_connected_monitors(self):
        current = [
            {"name": "eDP-1", "fingerprint": "BOE|Panel|ABC", "x": 0, "y": 0, "scale": 1, "mode": "preferred", "transform": 0, "mirror": "", "disabled": False},
            {"name": "HDMI-A-1", "x": 100, "y": 0, "scale": 1, "mode": "preferred", "transform": 0, "mirror": "", "disabled": True},
        ]
        saved = {
            "BOE|Panel|ABC": {"x": 1920, "y": 50, "scale": 2, "mode": "3456x2234@120", "transform": 0, "mirror": ""},
            "HDMI-A-1": {"x": 0, "y": 0, "scale": 1, "mode": "1920x1080@60", "transform": 0, "mirror": ""},
        }
        result = module.merge_layout(current, {"eDP-1"}, saved)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["name"], "eDP-1")
        self.assertEqual(result[0]["x"], 1920)
        self.assertEqual(result[0]["y"], 50)
        self.assertEqual(result[0]["scale"], 2)
        self.assertFalse(result[0]["disabled"])


if __name__ == "__main__":
    unittest.main()
