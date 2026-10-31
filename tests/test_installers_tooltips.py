"""Failure-path installer tests; all homes and Git remotes are disposable."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = "io.github.avillagran.omarchy-control-panel"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.plugin = self.home / ".config/omarchy/plugins" / PLUGIN
        self.plugin.parent.mkdir(parents=True)
        self.remote = self.root / "remote"
        self.remote.mkdir()
        self.git("init", "-q", str(self.remote))
        (self.remote / "bin").mkdir()
        (self.remote / "bin/install-tooltip-patch.sh").write_text(
            '#!/bin/bash\nOMARCHY_TOOLTIP_COMMIT="' + 'a' * 40 + '"\nexit 7\n'
        )
        (self.remote / "patches/hyprland").mkdir(parents=True)
        self.git("-C", str(self.remote), "add", ".")
        self.git("-C", str(self.remote), "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "fixture")
        self.git("-C", str(self.remote), "tag", "0.5")
        self.sha = self.git("-C", str(self.remote), "rev-parse", "HEAD").stdout.strip()
        (self.root / "bin").mkdir()
        (self.root / "bin/omarchy").write_text("#!/bin/bash\nexit 0\n")
        (self.root / "bin/omarchy").chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CACHE_HOME=str(self.root / "cache"),
                        XDG_STATE_HOME=str(self.root / "state"), PATH=str(self.root / "bin") + ":" + os.environ["PATH"],
                        OMARCHY_PANEL_REF="0.5", GIT_CONFIG_COUNT="1",
                        GIT_CONFIG_KEY_0="url.file://" + str(self.remote) + ".insteadOf",
                        GIT_CONFIG_VALUE_0="https://github.com/avillagran/omarchy-control-panel.git")

    def git(self, *args):
        return subprocess.run(["git", *args], check=True, capture_output=True, text=True)

    def run_script(self, script, *args):
        return subprocess.run(["bash", str(ROOT / "bin" / script), *args], env=self.env, capture_output=True, text=True)

    def test_bootstrap_placeholder_refuses_without_mutation(self):
        script = self.root / "unpublished-bootstrap"
        script.write_text(re.sub(r'^OMARCHY_TOOLTIP_COMMIT="[^"]+"', 'OMARCHY_TOOLTIP_COMMIT="OMARCHY_TOOLTIP_COMMIT"', (ROOT / "bin/install-tooltip-patch.sh").read_text(), flags=re.M))
        result = subprocess.run(["bash", str(script)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OMARCHY_TOOLTIP_COMMIT", result.stderr)
        self.assertFalse((self.root / "state/omarchy/tooltip-trial.json").exists())

    def test_bootstrap_fetches_exact_sha_and_passes_original_base(self):
        upstream = self.root / "omarchy-upstream"
        upstream.mkdir()
        self.git("init", "-q", str(upstream))
        core = upstream / "bin/omarchy-install-tooltips"
        core.parent.mkdir()
        core.write_text('#!/bin/bash\nprintf "%s\\n" "$OMARCHY_PATH" "$@" > "$HOME/core-args"\n')
        self.git("-C", str(upstream), "add", ".")
        self.git("-C", str(upstream), "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "omarchy fixture")
        sha = self.git("-C", str(upstream), "rev-parse", "HEAD").stdout.strip()
        script = self.root / "bootstrap"
        script.write_text(re.sub(r'^OMARCHY_TOOLTIP_COMMIT="[^"]+"', 'OMARCHY_TOOLTIP_COMMIT="' + sha + '"', (ROOT / "bin/install-tooltip-patch.sh").read_text(), flags=re.M))
        base = self.root / "base"
        (base / "shell").mkdir(parents=True)
        (base / "default").mkdir()
        self.env.update(OMARCHY_PATH=str(base), GIT_CONFIG_COUNT="2",
                        GIT_CONFIG_KEY_1="url.file://" + str(upstream) + ".insteadOf",
                        GIT_CONFIG_VALUE_1="https://github.com/omacom/omarchy.git")
        result = subprocess.run(["bash", str(script)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "core-args").read_text(),
                         str(self.root / "cache/omarchy/tooltip-source" / sha) + "\n--base\n" + str(base) + "\n")

    def test_uninstall_uses_existing_trial_script_without_base(self):
        trial = self.root / "trial/omarchy"
        core = trial / "bin/omarchy-install-tooltips"
        core.parent.mkdir(parents=True)
        core.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$HOME/rollback-args"\n')
        state = self.root / "state/omarchy/tooltip-trial.json"
        state.parent.mkdir(parents=True)
        state.write_text(json.dumps({"trialOmarchy": str(trial)}))
        result = self.run_script("install-tooltip-patch.sh", "--uninstall")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "rollback-args").read_text(), "--uninstall\n")

    def test_non_git_plugin_is_backed_up_on_bootstrap_failure(self):
        self.plugin.mkdir()
        (self.plugin / "user-file").write_text("never lose me")
        result = self.run_script("install-hyprland-scroll-patch.sh")
        self.assertEqual(result.returncode, 7, result.stderr)
        state = json.loads((self.root / "state/omarchy-control-panel-scroll-patch.json").read_text())
        self.assertEqual(state["panelSha"], self.sha)
        self.assertEqual(Path(state["pluginBackup"]).joinpath("user-file").read_text(), "never lose me")
        self.assertEqual(self.git("-C", str(self.plugin), "rev-parse", "HEAD").stdout.strip(), self.sha)
        self.assertFalse((self.home / ".local/bin/Hyprland").exists())
        # Even a failed bootstrap leaves an explicit, reversible state.
        existing_shadow = self.home / ".local/bin/Hyprland"
        existing_shadow.parent.mkdir(parents=True)
        existing_shadow.write_text("prior user binary")
        undone = self.run_script("install-hyprland-scroll-patch.sh", "--uninstall")
        self.assertEqual(undone.returncode, 0, undone.stderr)
        self.assertEqual((self.plugin / "user-file").read_text(), "never lose me")
        self.assertEqual(existing_shadow.read_text(), "prior user binary")
        self.assertFalse((self.root / "state/omarchy-control-panel-scroll-patch.json").exists())

    def test_rerun_preserves_original_backup_without_nested_checkout(self):
        self.plugin.mkdir()
        (self.plugin / "user-file").write_text("original")
        first = self.run_script("install-hyprland-scroll-patch.sh")
        self.assertEqual(first.returncode, 7)
        state_path = self.root / "state/omarchy-control-panel-scroll-patch.json"
        original = json.loads(state_path.read_text())["pluginBackup"]
        second = self.run_script("install-hyprland-scroll-patch.sh")
        self.assertEqual(second.returncode, 7, second.stdout + second.stderr)
        self.assertEqual(json.loads(state_path.read_text())["pluginBackup"], original)
        self.assertEqual(Path(original).joinpath("user-file").read_text(), "original")
        self.assertFalse(list(self.plugin.glob(".control-panel.*")))

    def test_uninstall_without_state_preserves_existing_shadow(self):
        shadow = self.home / ".local/bin/Hyprland"
        shadow.parent.mkdir(parents=True)
        shadow.write_text("not owned")
        result = self.run_script("install-hyprland-scroll-patch.sh", "--uninstall")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(shadow.read_text(), "not owned")

    def test_dirty_tracked_plugin_refused_without_stash_or_move(self):
        shutil.copytree(self.remote, self.plugin)
        (self.plugin / "bin/install-tooltip-patch.sh").write_text("dirty\n")
        result = self.run_script("install-hyprland-scroll-patch.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty tracked edits", result.stdout)
        self.assertEqual((self.plugin / "bin/install-tooltip-patch.sh").read_text(), "dirty\n")
        self.assertFalse((self.root / "state/omarchy-control-panel-scroll-patch.json").exists())

    def test_sha_ref_and_unpublished_bootstrap_refuse_before_plugin_move(self):
        self.env["OMARCHY_PANEL_REF"] = self.sha
        (self.remote / "bin/install-tooltip-patch.sh").write_text(
            '#!/bin/bash\nOMARCHY_TOOLTIP_COMMIT="OMARCHY_TOOLTIP_COMMIT"\n'
        )
        self.git("-C", str(self.remote), "add", ".")
        self.git("-C", str(self.remote), "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "unpublished")
        new_sha = self.git("-C", str(self.remote), "rev-parse", "HEAD").stdout.strip()
        self.env["OMARCHY_PANEL_REF"] = new_sha
        self.plugin.mkdir()
        (self.plugin / "user-file").write_text("safe")
        result = self.run_script("install-hyprland-scroll-patch.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unpublished", result.stdout)
        self.assertEqual((self.plugin / "user-file").read_text(), "safe")
        self.assertFalse((self.root / "state/omarchy-control-panel-scroll-patch.json").exists())


if __name__ == "__main__":
    unittest.main()
