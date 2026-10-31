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
    def test_virtual_outputs_are_left_to_their_owner(self):
        laptop = {"name": "eDP-1", "make": "Apple", "model": "Retina", "serial": "",
                  "fingerprint": "Apple|Retina", "mode": "3456x2234@120", "x": 0, "y": 0,
                  "scale": 2, "transform": 0}
        remote = {"name": "gliff-4242", "make": "", "model": "", "serial": "",
                  "fingerprint": "gliff-4242", "mode": "2560x1600@60", "x": 1728, "y": 0,
                  "scale": 2, "transform": 0}
        self.assertFalse(module.is_virtual(laptop))
        self.assertTrue(module.is_virtual(remote))
        # A built-in panel without EDID identity (Apple eDP-1 under Asahi) is
        # still physical: the connector name decides, or display-manager's
        # `virtual` flag derived from the kernel's DRM connectors when present.
        bare_laptop = {"name": "eDP-1", "make": "", "model": "", "serial": ""}
        self.assertFalse(module.is_virtual(bare_laptop))
        self.assertTrue(module.is_virtual({"name": "HEADLESS-1", "make": "", "model": "", "serial": ""}))
        self.assertFalse(module.is_virtual({"name": "HDMI-A-1", "make": "", "model": "", "serial": ""}))
        self.assertFalse(module.is_virtual({"name": "eDP-1"}))
        self.assertTrue(module.is_virtual(dict(bare_laptop, virtual=True)))
        self.assertFalse(module.is_virtual(dict(remote, virtual=False)))
        replies = {"state": [laptop, remote], "monitors": [{"name": "eDP-1"}, {"name": "gliff-4242"}]}
        original = module.run_json
        module.run_json = lambda command: replies["state" if "state" in command else "monitors"]
        try:
            current, active_names, connected = module.physical_state("display-manager")
        finally:
            module.run_json = original
        self.assertEqual([row["name"] for row in current], ["eDP-1"])
        self.assertEqual(active_names, {"eDP-1"})
        self.assertEqual(module.display_topology(connected), "Apple|Retina")
        plan = module.workspace_assignments(connected, 10, 5)
        self.assertEqual({rule["monitor"] for rule in plan}, {"eDP-1"})
        lua = module.rewrite_lua("", connected, plan)
        self.assertNotIn("gliff-4242", lua)

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

    def test_workspace_plan_follows_physical_order(self):
        displays = [
            {"name": "eDP-1", "x": 1920, "y": 0, "disabled": False},
            {"name": "HDMI-A-1", "x": 0, "y": 0, "disabled": False},
            {"name": "DP-1", "x": 0, "y": 0, "disabled": True},
        ]
        plan = module.workspace_assignments(displays, 10, 3)
        self.assertEqual([(r["workspace"], r["monitor"], r["default"]) for r in plan], [
            (1, "HDMI-A-1", True), (2, "HDMI-A-1", False), (3, "HDMI-A-1", False),
            (4, "eDP-1", True), (5, "eDP-1", False), (6, "eDP-1", False)])
        self.assertEqual(len(module.workspace_assignments(displays[:1], 7, 3)), 7)

    def test_rewrite_lua_drops_absent_monitor_and_keeps_other_settings(self):
        lua = "\n".join([
            "-- Generated by Omarchy Control Panel. Safe to delete.",
            "hl.config({ input = { sensitivity = 0.80 } })",
            "-- Display layout",
            'hl.monitor({ output = "eDP-1", mode = "3456x2234@120.00000", position = "0x0", scale = 2, transform = 0 })',
            'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.00000", position = "1728x0", scale = 1, transform = 0 })',
            "-- Workspace distribution by monitor topology",
            'hl.workspace_rule({ workspace = "1", monitor = "eDP-1", default = true, persistent = true })',
            'hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1", default = true, persistent = true })',
            'hl.unbind("SUPER + SHIFT + up")',
        ]) + "\n"
        displays = [{"name": "eDP-1", "mode": "3456x2234@120.00000", "x": 0, "y": 0, "scale": 2,
                     "transform": 0, "mirror": "", "disabled": False}]
        result = module.rewrite_lua(lua, displays, module.workspace_assignments(displays, 2, 5))
        self.assertNotIn("HDMI-A-1", result)
        self.assertIn("sensitivity = 0.80", result)
        self.assertIn('workspace = "2", monitor = "eDP-1", default = false', result)
        self.assertLess(result.index("-- Display layout"), result.index('hl.unbind("SUPER + SHIFT + up")'))
        # Idempotent: an up-to-date file is never rewritten (a rewrite reloads Hyprland).
        self.assertEqual(module.rewrite_lua(result, displays, module.workspace_assignments(displays, 2, 5)), result)

    def test_unsaved_overlapping_monitor_moves_flush_right(self):
        layout = [
            {"name": "eDP-1", "fingerprint": "eDP-1", "mode": "3456x2234@120", "x": 0, "y": 0, "scale": 2, "transform": 0, "disabled": False},
            {"name": "HDMI-A-1", "fingerprint": "LG|X|1", "mode": "1920x1080@60", "x": 500, "y": 0, "scale": 1, "transform": 0, "disabled": False},
        ]
        placed = module.place_unsaved(layout, {"eDP-1": {"x": 0}})
        self.assertEqual((placed[1]["x"], placed[1]["y"]), (1728, 0))
        self.assertEqual(placed[0]["x"], 0)

    def test_visuals_use_saved_or_palette_colors(self):
        displays = [{"name": "eDP-1", "x": 0, "y": 0}, {"name": "HDMI-A-1", "x": 1728, "y": 0}]
        visuals = module.workspace_visuals(displays, {"multiMonitorWorkspaces": 1, "monitorColors": {"HDMI-A-1": "red"}})
        self.assertEqual(visuals, {"1": {"monitor": "eDP-1", "colorRole": "accent"},
                                   "2": {"monitor": "HDMI-A-1", "colorRole": "red"}})


if __name__ == "__main__":
    unittest.main()
