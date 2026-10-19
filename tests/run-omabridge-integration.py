#!/usr/bin/env python3
"""Run the real OmaBridge page and helper against a fake ot3 client.

Everything happens under a throwaway HOME: no real ot3, OmaBridge, user
service or invitation is touched.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
PLUGIN_BIN = ".config/omarchy/plugins/omarchy-t3-code/bin"


def scenario(expect, install=True, mode="ready"):
    with tempfile.TemporaryDirectory(prefix="cp-omabridge-") as directory:
        root = Path(directory)
        for name in ("desktop", "bin", "home", "runtime", "fake", "qs/Commons"):
            (root / name).mkdir(parents=True, mode=0o700)
        for name in ("OmaBridgePage.qml", "OmaBridgeModel.js", "AppTheme.qml", "ThemePalette.js"):
            shutil.copy2(repo / "desktop" / name, root / "desktop" / name)
        shutil.copy2(repo / "bin/omabridge-client", root / "bin/omabridge-client")
        home = root / "home"
        if install:
            (home / PLUGIN_BIN).mkdir(parents=True)
            shutil.copy2(repo / "tests/fixtures/fake-omarchy-t3-client", home / PLUGIN_BIN / "omarchy-t3-client")
        state, log = root / "fake/state.json", root / "fake/requests.log"
        if mode != "ready":
            state.write_text(json.dumps({"mode": mode}))
        commons = root / "qs/Commons"
        (commons / "qmldir").write_text("module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n")
        (commons / "Color.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color background: "#1a1b26"; property color foreground: "#c0caf5"; property color accent: "#7aa2f7"; property color urgent: "#f7768e" }\n')
        (commons / "Style.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family: "Sans Serif", body: 14, caption: 13}) }\n')
        (root / "desktop/shell.qml").write_text((repo / "tests/omabridge-integration.qml").read_text().replace('import "desktop"', 'import "."'))
        env = {k: v for k, v in os.environ.items() if not k.startswith(("HYPR", "WAYLAND", "DISPLAY", "DBUS", "XDG", "QT_", "QML"))}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), XDG_STATE_HOME=str(root / "state"),
                   XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache"), XDG_RUNTIME_DIR=str(root / "runtime"),
                   QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic", QT_QUICK_CONTROLS_STYLE="Basic",
                   QML2_IMPORT_PATH=str(root), FAKE_OT3_STATE=str(state), FAKE_OT3_LOG=str(log), OMABRIDGE_EXPECT=expect)
        result = subprocess.run(["quickshell", "-p", str(root / "desktop/shell.qml")], env=env, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and f"OMABRIDGE_PASS {expect}" in output and "OMABRIDGE_FAILED" not in output, output
        requests = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        if not install:
            assert requests == [], "no client may run when ot3 is missing"
            return
        for entry in requests:
            assert entry["argv"] == ["omabridge-action"], "requests travel on stdin, never argv"
            json.loads(entry["stdin"])
        bodies = [json.loads(entry["stdin"]) for entry in requests]
        assert bodies[0] == {"action": "read"}, "the page opens with a read"
        if expect != "ready":
            return
        for body in bodies:
            assert ("confirmed" in body) == (body["action"] != "read"), body
            assert body.get("confirmed", True) is True
        actions = [body["action"] for body in bodies if body["action"] != "read"]
        assert actions == ["identity-create", "publish", "invite", "invite-discard", "invite", "invite", "pair", "pair-retry",
                           "approve", "revoke", "pair", "unpublish"], actions
        assert bodies[bodies.index(next(b for b in bodies if b["action"] == "invite")) + 1] == {"action": "read"}, \
            "the client output holding the invitation is replaced immediately"
        publish = next(b for b in bodies if b["action"] == "publish")
        assert publish == {"action": "publish", "ssh": True, "confirmed": True}
        invites = [b for b in bodies if b["action"] == "invite"]
        assert invites[0] == {"action": "invite", "services": ["t3"], "qr": True, "confirmed": True}, invites[0]
        assert invites[1]["qr"] is False
        discard = next(b for b in bodies if b["action"] == "invite-discard")
        assert discard["path"].endswith("omabridge-invite-0.json") and not Path(discard["path"]).exists()
        assert (root / "fake/omabridge-invite-1.json").exists(), "closing the dialog only forgets, it does not delete"
        assert next(b for b in bodies if b["action"] == "pair")["path"] == "/invitations/omabridge invite.json"
        assert next(b for b in bodies if b["action"] == "pair-retry")["id"] == "aaaaaaaa-1111-4111-8111-111111111111"
        assert next(b for b in bodies if b["action"] == "approve")["peer"] == "b2" * 32
        assert "omabridge-invite-" not in output and "data:image" not in output, "secrets never reach the log"


scenario("ready")
scenario("outdated", mode="outdated")
scenario("missing", install=False)
print("OmaBridge integration passed: ready, outdated and missing ot3")
