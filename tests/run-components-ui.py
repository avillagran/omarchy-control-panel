#!/usr/bin/env python3
"""Headless behaviour test for the shared desktop rows (SliderRow, ToggleRow).

The real component files are copied next to small qs.Commons / qs.Ui stand-ins
so the test needs neither Quickshell nor a running compositor.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = shutil.which('qmltestrunner') or '/usr/lib/qt6/bin/qmltestrunner'

STYLE = '''pragma Singleton
import QtQuick 6.11
QtObject {
  property int cornerRadius: 0
  property real hoverFillAlpha: 0.08
  property real selectedFillAlpha: 0.18
  property var font: ({ family: "Sans Serif", body: 14, caption: 12, title: 18 })
  property var spacing: ({ rowPaddingX: 12, controlHeight: 28 })
  function space(px) { return px }
  function hoverFillFor(f, a) { return Qt.alpha(f, 0.08) }
}
'''
COLOR = '''pragma Singleton
import QtQuick 6.11
QtObject { property color foreground: "#c0caf5"; property color background: "#1a1b26"; property color accent: "#7aa2f7"; property color urgent: "#f7768e" }
'''
SWITCH = '''import QtQuick 6.11
Item {
  property bool checked: false
  property bool interactive: true
  property bool hasCursor: false
  property color foreground
  property color accent
  width: 40; height: 22
}
'''

TEST = r'''import QtQuick 6.11
import QtTest
import "desktop"

Item {
  id: host
  width: 480
  height: 420

  property real bound: 0.4
  property int toggles: 0
  property bool flag: false

  Column {
    width: parent.width
    ToggleRow {
      id: toggle
      label: "Natural scrolling"
      checked: host.flag
      onClicked: { host.flag = !host.flag; host.toggles++ }
    }
    SliderRow {
      id: row
      label: "Sensitivity"
      decimals: 2
      from: -1
      to: 1
      stepSize: 0.05
      value: host.bound
      onMoved: host.bound = value
    }
    ToggleRow { id: second; label: "Tap to click" }
  }

  TestCase {
    name: "DesktopRows"
    when: windowShown

    function test_stepper_keeps_caller_binding() {
      host.bound = 0.4
      var plus = findChild(row, "stepUp")
      verify(plus !== null, "the + stepper exists")
      mouseClick(plus)
      fuzzyCompare(host.bound, 0.45, 0.0001)
      // The caller's binding must survive the interaction.
      host.bound = -0.5
      fuzzyCompare(row.value, -0.5, 0.0001)
    }

    function test_typed_value_snaps_and_reports() {
      host.bound = 0
      row.moveTo(0.33)
      fuzzyCompare(host.bound, 0.35, 0.0001)
      host.bound = 0.1
      fuzzyCompare(row.value, 0.1, 0.0001)
      row.moveTo(9)
      fuzzyCompare(host.bound, 1, 0.0001)
    }

    function test_toggle_keyboard() {
      host.toggles = 0
      toggle.forceActiveFocus(Qt.TabFocusReason)
      verify(toggle.visualFocus, "keyboard focus shows the cursor ring")
      keyClick(Qt.Key_Space)
      keyClick(Qt.Key_Return)
      compare(host.toggles, 2)
      compare(toggle.checked, false)
    }

    function test_focus_chain_visits_rows() {
      toggle.forceActiveFocus(Qt.TabFocusReason)
      var next = toggle.nextItemInFocusChain(true)
      var p = next, inRow = false
      for (; p; p = p.parent) if (p === row) inRow = true
      verify(inRow, "the slider row is the next cursor stop")
      var after = next.nextItemInFocusChain(true)
      compare(after, second, "the value field is not a separate stop")
    }
  }
}
'''


def main():
    if not os.path.exists(RUNNER):
        print('qmltestrunner not available; skipping desktop row test')
        return 0
    with tempfile.TemporaryDirectory(prefix='ocp-rows-') as tmp:
        tmp = pathlib.Path(tmp)
        desktop = tmp / 'desktop'
        desktop.mkdir()
        for name in ('SliderRow.qml', 'ToggleRow.qml'):
            shutil.copy(ROOT / 'desktop' / name, desktop / name)
        commons = tmp / 'qs' / 'Commons'
        ui = tmp / 'qs' / 'Ui'
        commons.mkdir(parents=True)
        ui.mkdir(parents=True)
        (commons / 'qmldir').write_text('module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n')
        (commons / 'Color.qml').write_text(COLOR)
        (commons / 'Style.qml').write_text(STYLE)
        (ui / 'qmldir').write_text('module qs.Ui\nToggleSwitch 1.0 ToggleSwitch.qml\n')
        (ui / 'ToggleSwitch.qml').write_text(SWITCH)
        (tmp / 'tst_rows.qml').write_text(TEST)
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QML_IMPORT_PATH=str(tmp), QML2_IMPORT_PATH=str(tmp))
        result = subprocess.run([RUNNER, '-input', str(tmp / 'tst_rows.qml'), '-import', str(tmp)],
                                env=env, capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode


if __name__ == '__main__':
    sys.exit(main())
