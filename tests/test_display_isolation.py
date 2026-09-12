"""Regression: the helper suite must not modify its caller's config."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DisplayIsolationTest(unittest.TestCase):
    def test_helper_suite_leaves_caller_configuration_untouched(self):
        project = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='cp-isolation-') as folder:
            root = Path(folder)
            config = root / 'config'
            lua = config / 'hypr/control-panel.lua'
            lua.parent.mkdir(parents=True)
            original = '-- caller config: must not change\nhl.monitor({ output = "eDP-1", transform = 0 })\n'
            lua.write_text(original)
            home = root / 'home'
            home.mkdir()
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config),
                       XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(root / 'runtime'),
                       HYPRLAND_INSTANCE_SIGNATURE='', WAYLAND_DISPLAY='',
                       DISPLAY='', DBUS_SESSION_BUS_ADDRESS='')
            result = subprocess.run(['bash', str(project / 'tests/helper.test.sh')],
                                    env=env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(lua.read_text(), original,
                             'helper tests leaked monitor persistence into caller config')


if __name__ == '__main__':
    unittest.main()
