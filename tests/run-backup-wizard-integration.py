#!/usr/bin/env python3
"""Exercise the real wizard and local helpers without the user's session."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cp-wizard-roundtrip-') as directory:
    root = Path(directory)
    for name in ('desktop', 'bin', 'home', 'repository', 'recovery', 'runtime', 'qs/Commons'):
        (root / name).mkdir(parents=True, mode=0o700)
    for name in ('BackupPage.qml', 'BackupModel.js', 'AppTheme.qml', 'ThemePalette.js'):
        shutil.copy2(repo / 'desktop' / name, root / 'desktop' / name)
    for name in ('control-panel-backup', 'backup-connection'):
        shutil.copy2(repo / 'bin' / name, root / 'bin' / name)
    commons = root / 'qs/Commons'
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n')
    (commons / 'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property color background: "#1a1b26"; property color foreground: "#c0caf5"; property color accent: "#7aa2f7" }\n')
    (commons / 'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family: "Sans Serif", body: 14, caption: 13}) }\n')
    # Match the installed launcher: desktop/ is the Quickshell config root;
    # ../bin lives OUTSIDE it and must not pass through Qt.resolvedUrl().
    (root / 'desktop/shell.qml').write_text((repo / 'tests/backup-wizard-integration.qml').read_text().replace('@ROOT@', str(root)).replace('import "desktop"', 'import "."'))
    home = root / 'home'
    (home / 'Documents').mkdir()
    (home / 'Documents/proof.txt').write_text('Real isolated wizard roundtrip\n')
    (home / '.config/hypr').mkdir(parents=True)
    (home / '.config/hypr/hyprland.conf').write_text('Fixture, never loaded by Hyprland\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith(('HYPR', 'WAYLAND', 'DISPLAY', 'DBUS', 'XDG', 'QT_', 'QML'))}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'), XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='basic', QT_QUICK_CONTROLS_STYLE='Basic', QML2_IMPORT_PATH=str(root))
    result = subprocess.run(['quickshell', '-p', str(root / 'desktop/shell.qml')], env=env, capture_output=True, text=True, timeout=25)
    log = result.stdout + result.stderr
    print(log)
    assert result.returncode == 0 and 'WIZARD_PASS' in log and 'WIZARD_FAILED' not in log, 'Wizard integration failed'
    for relative in ('Documents/proof.txt', '.config/hypr/hyprland.conf'):
        assert (home / relative).read_bytes() == (root / 'recovery/home' / relative).read_bytes()
    print('Restored bytes verified; no real Core or network operations loaded')
