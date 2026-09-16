import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/install-workspace-colors-widget"


class WorkspaceWidgetInstallerTests(unittest.TestCase):
    def test_install_is_idempotent_and_uninstall_restores_builtin(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_path = Path(temporary) / "shell.json"
            original = {
                "version": 1,
                "bar": {"layout": {
                    "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}],
                    "center": [],
                    "right": [{"id": "omarchy.audio"}],
                }},
            }
            config_path.write_text(json.dumps(original), encoding="utf-8")
            prefs_path = Path(temporary) / "prefs.json"
            prefs_path.write_text("{}", encoding="utf-8")
            env = dict(os.environ,
                       OMARCHY_SHELL_CONFIG=str(config_path),
                       OMARCHY_CONTROL_PANEL_PREFS=str(prefs_path))
            env["OMARCHY_MODULE_DIR"] = str(Path(temporary) / "modules")

            first = subprocess.run([str(HELPER)], env=env, check=True, text=True, capture_output=True)
            self.assertTrue(json.loads(first.stdout)["changed"])
            installed = json.loads(config_path.read_text(encoding="utf-8"))
            entry = installed["bar"]["layout"]["left"][1]
            self.assertRegex(entry["id"], r"^workspacescolored-[0-9a-f]{12}$")
            self.assertEqual(entry["type"], "qml")
            self.assertEqual(entry["source"], str(Path(env["OMARCHY_MODULE_DIR"]) / entry["id"] / "workspacescolored.qml"))
            self.assertTrue(Path(entry["source"]).is_file())
            self.assertNotIn("omarchy.workspaces", [item["id"] for item in installed["bar"]["layout"]["left"]])

            second = subprocess.run([str(HELPER)], env=env, check=True, text=True, capture_output=True)
            self.assertFalse(json.loads(second.stdout)["changed"])

            removed = subprocess.run([str(HELPER), "--uninstall"], env=env, check=True, text=True, capture_output=True)
            self.assertTrue(json.loads(removed.stdout)["changed"])
            restored = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertEqual(restored["bar"]["layout"]["left"][1], {"id": "omarchy.workspaces"})
            self.assertEqual(restored["bar"]["layout"]["right"], original["bar"]["layout"]["right"])
            self.assertFalse(list(Path(env["OMARCHY_MODULE_DIR"]).glob("workspacescolored*.qml")))

    def test_source_change_gets_a_new_module_id_for_live_reload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "plugin"
            (root / "bin").mkdir(parents=True)
            helper = root / "bin/install-workspace-colors-widget"
            shutil.copy2(HELPER, helper)
            source = root / "workspace-colors.qml"
            source.write_text("import QtQuick\nItem { property string version: 'one' }\n", encoding="utf-8")
            (root / "ThemePalette.js").write_text(".pragma library\n", encoding="utf-8")
            (root / "WorkspaceNumerals.js").write_text(".pragma library\n", encoding="utf-8")
            config_path = Path(temporary) / "shell.json"
            config_path.write_text(json.dumps({"version": 1, "bar": {"layout": {
                "left": [{"id": "omarchy.workspaces"}], "center": [], "right": []
            }}}), encoding="utf-8")
            env = dict(os.environ, OMARCHY_SHELL_CONFIG=str(config_path))
            env["OMARCHY_MODULE_DIR"] = str(Path(temporary) / "modules")

            subprocess.run([str(helper)], env=env, check=True, capture_output=True)
            first_id = json.loads(config_path.read_text(encoding="utf-8"))["bar"]["layout"]["left"][0]["id"]
            source.write_text("import QtQuick\nItem { property string version: 'two' }\n", encoding="utf-8")
            result = subprocess.run([str(helper)], env=env, check=True, text=True, capture_output=True)
            second_id = json.loads(config_path.read_text(encoding="utf-8"))["bar"]["layout"]["left"][0]["id"]

            self.assertTrue(json.loads(result.stdout)["changed"])
            self.assertNotEqual(first_id, second_id)
            self.assertRegex(second_id, r"^workspacescolored-[0-9a-f]{12}$")
            self.assertFalse((Path(env["OMARCHY_MODULE_DIR"]) / first_id).exists())
            self.assertTrue((Path(env["OMARCHY_MODULE_DIR"]) / second_id / "workspacescolored.qml").is_file())
            self.assertTrue((Path(env["OMARCHY_MODULE_DIR"]) / second_id / "ThemePalette.js").is_file())
            self.assertTrue((Path(env["OMARCHY_MODULE_DIR"]) / second_id / "WorkspaceNumerals.js").is_file())

    def test_sync_settings_updates_the_live_module_entry(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_path = Path(temporary) / "shell.json"
            prefs_path = Path(temporary) / "prefs.json"
            config_path.write_text(json.dumps({"version": 1, "bar": {"layout": {
                "left": [{"id": "omarchy.workspaces"}], "center": [], "right": []
            }}}), encoding="utf-8")
            prefs_path.write_text(json.dumps({
                "workspaceIndicatorMode": "rounded",
                "workspaceIndicatorPadding": 2,
                "workspaceNumeralStyle": "roman",
                "workspaceVisuals": {"1": {"colorRole": "orange"}},
            }), encoding="utf-8")
            env = dict(os.environ,
                       OMARCHY_SHELL_CONFIG=str(config_path),
                       OMARCHY_MODULE_DIR=str(Path(temporary) / "modules"),
                       OMARCHY_CONTROL_PANEL_PREFS=str(prefs_path))
            prefs_path.write_text(json.dumps({
                "workspaceIndicatorMode": "square",
                "workspaceIndicatorPadding": 4,
                "workspaceNumeralStyle": "arabic",
                "workspaceVisuals": {},
            }), encoding="utf-8")
            subprocess.run([str(HELPER)], env=env, check=True, capture_output=True)
            prefs_path.write_text(json.dumps({
                "workspaceIndicatorMode": "rounded",
                "workspaceIndicatorPadding": 2,
                "workspaceNumeralStyle": "roman",
                "workspaceVisuals": {"1": {"colorRole": "orange"}},
            }), encoding="utf-8")
            result = subprocess.run([str(HELPER), "--sync-settings"], env=env,
                                    check=True, text=True, capture_output=True)
            entry = json.loads(config_path.read_text(encoding="utf-8"))["bar"]["layout"]["left"][0]
            self.assertTrue(json.loads(result.stdout)["changed"])
            self.assertEqual(entry["workspaceIndicatorMode"], "rounded")
            self.assertEqual(entry["workspaceIndicatorPadding"], 2)
            self.assertEqual(entry["workspaceNumeralStyle"], "roman")
            self.assertEqual(entry["workspaceVisuals"]["1"]["colorRole"], "orange")
            self.assertEqual(entry["settings"], {
                "workspaceIndicatorMode": "rounded",
                "workspaceIndicatorPadding": 2,
                "workspaceNumeralStyle": "roman",
                "workspaceVisuals": {"1": {"colorRole": "orange"}},
            })


if __name__ == "__main__":
    unittest.main()
