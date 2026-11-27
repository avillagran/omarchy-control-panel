"""Regression: the 3-finger swipe must cycle existing workspaces.

A bare "+1" made Hyprland create a new numbered workspace on every swipe,
so windows ended up on workspaces like 261 and 264.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT / 'bin/sync-gestures-file.py'


def generate(*extra):
    with tempfile.TemporaryDirectory(prefix='cp-swipe-') as folder:
        root = Path(folder)
        (root / 'input.lua').write_text('-- input\n')
        output = root / 'control-panel-gestures.lua'
        subprocess.run(['python3', str(SCRIPT), '--enabled', 'true', '--no-reload',
                        '--input', str(root / 'input.lua'), '--output', str(output),
                        '--quickview', '/nonexistent/quickview.sh', *extra],
                       check=True, capture_output=True, text=True, timeout=30)
        return output.read_text()


def swipe_targets(text):
    return re.findall(r'ocp_swipe\("([^"]+)"\)', text)


class SwipeWorkspaceTargetsTest(unittest.TestCase):
    def test_defaults_cycle_existing_workspaces(self):
        self.assertEqual(swipe_targets(generate()), ['e+1', 'e-1'])

    def test_bare_relative_targets_are_rewritten(self):
        self.assertEqual(swipe_targets(generate('--left', '+1', '--right', '-1')), ['e+1', 'e-1'])

    def test_explicit_existing_targets_are_kept(self):
        self.assertEqual(swipe_targets(generate('--left', 'e-1', '--right', 'e+1')), ['e-1', 'e+1'])

    def test_monitor_relative_targets_are_kept(self):
        # "Swipe also goes to empty workspaces": r±1, like Omarchy's gesture.
        self.assertEqual(swipe_targets(generate('--left', 'r+1', '--right', 'r-1')), ['r+1', 'r-1'])

    def test_core_prefixes_every_target_with_e_or_r(self):
        source = (PROJECT / 'desktop/Core.qml').read_text()
        self.assertIn('var kind = saved.swipeEmpty === false ? "e" : "r"', source)
        targets = [l for l in source.splitlines() if re.search(r'var (left|right)Target = ', l)]
        self.assertEqual(len(targets), 2)
        for line in targets:
            self.assertRegex(line, r'= kind \+ ', line.strip())


if __name__ == '__main__':
    unittest.main()
