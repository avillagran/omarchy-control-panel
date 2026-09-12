#!/usr/bin/env python3
"""Capture the real BackupPage with isolated Core/palette and fail-closed IO.
No Core.qml is copied. Any attempted helper invocation fails the test.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ.get('BACKUP_UI_OUTPUT', '/tmp/backup-wizard-captures')).resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='backup-wizard-ui-') as work:
    root = Path(work)
    desktop = root / 'desktop'
    desktop.mkdir()
    for name in ('BackupPage.qml', 'BackupModel.js', 'AppTheme.qml', 'ThemePalette.js'):
        shutil.copy2(REPO / 'desktop' / name, desktop / name)
    commons = root / 'qs' / 'Commons'
    commons.mkdir(parents=True)
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n')
    (commons / 'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property color background: "#1a1b26"; property color foreground: "#c0caf5"; property color accent: "#7aa2f7" }\n')
    (commons / 'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family: "Sans Serif", body: 14, caption: 13}) }\n')
    io = root / 'Quickshell' / 'Io'
    io.mkdir(parents=True)
    (io.parent / 'qmldir').write_text('module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n')
    (io.parent / 'Quickshell.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property string shellDir: "/forbidden" }\n')
    (io / 'qmldir').write_text('module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n')
    (io / 'Process.qml').write_text('''import QtQuick
QtObject {
 property bool running: false
 property bool stdinEnabled: false
 property var command: []
 property QtObject stdout
 property QtObject stderr
 signal started()
 signal exited(int exitCode, int exitStatus)
 function write(value) { throw new Error("Unexpected helper stdin"); }
 onRunningChanged: { if (running) { console.error("FORBIDDEN helper invocation"); Qt.exit(9); } }
}
''')
    (io / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property bool waitForEnd: true; property string text: "" }\n')
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('HYPR', 'WAYLAND', 'DISPLAY', 'DBUS', 'XDG', 'QT_', 'QML')):
            env.pop(key)
    for name in ('home', 'config', 'data', 'cache', 'runtime'):
        (root / name).mkdir(mode=0o700)
    env.update(HOME=str(root/'home'), XDG_CONFIG_HOME=str(root/'config'), XDG_DATA_HOME=str(root/'data'), XDG_CACHE_HOME=str(root/'cache'), XDG_RUNTIME_DIR=str(root/'runtime'), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='basic', QT_QUICK_CONTROLS_STYLE='Basic', QML_IMPORT_PATH=str(root), QT_QUICK_BACKEND='software')
    source = (REPO / 'tests' / 'backup-wizard-ui.qml').read_text()
    catalog = json.loads((REPO / 'desktop' / 'i18n.json').read_text())
    for width in (640, 1000):
        for scene in ('destination', 'timecapsule'):
            (OUTPUT / f'{scene}-{width}.png').unlink(missing_ok=True)
        properties = f'Window {{\n property int captureWidth: {width}\n property string outputDir: {json.dumps(str(OUTPUT))}\n property var translations: ({json.dumps(catalog, ensure_ascii=False)})\n'
        (root/'capture.qml').write_text(source.replace('Window {', properties, 1))
        run = subprocess.run(['/usr/lib/qt6/bin/qml', '-I', str(root), str(root/'capture.qml')], env=env, capture_output=True, text=True, timeout=20)
        print(run.stdout + run.stderr)
        if run.returncode:
            raise SystemExit(run.returncode)
        for scene in ('destination', 'timecapsule'):
            image = OUTPUT / f'{scene}-{width}.png'
            if not image.exists() or image.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                raise RuntimeError(f'Missing PNG: {image}')
            print(image)
