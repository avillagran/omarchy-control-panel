import QtQuick
import Quickshell
import "desktop"

ShellRoot {
    id: test
    property int phase: 0
    function ensure(ok, message) {
        if (!ok) { console.error("WIZARD_FAILED", message); Qt.quit(); throw new Error(message); }
    }
    function find(item, label) {
        if (item.text === label && typeof item.clicked === "function") return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) { var found = find(children[i], label); if (found) return found; }
        return null;
    }
    function click(label) { var control = find(page, label); ensure(control && control.enabled, label); control.clicked(); }
    QtObject { id: mock; property string uiLang: "en"; function t(lang, key) { return key; } }
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 900; visible: true
        BackupPage { id: page; width: 760; height: implicitHeight; core: mock }
    }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (page.busy) return;
            if (test.phase === 0) {
                test.ensure(page.action === "", "No startup operation");
                page.destinationKind = "local";
                test.click("backupContinue");
                page.connectJob("verify", "@ROOT@/repository");
                test.phase = 1;
            } else if (test.phase === 1) {
                test.ensure(page.verified && !page.failed, page.resultText);
                test.click("backupContinue");
                page.files = true;
                test.click("backupReviewBackup");
                page.runJob("backup");
                test.ensure(page.action === "plan", "Duplicate job guard");
                test.phase = 2;
            } else if (test.phase === 2) {
                test.ensure(page.step === 3 && page.planResult.ok, page.resultText);
                page.files = false;
                test.ensure(page.planResult === null, "Stale review invalidated");
                page.runJob("backup");
                test.ensure(!page.busy, "Backup blocked without review");
                page.files = true;
                page.step = 2;
                test.click("backupReviewBackup");
                test.phase = 3;
            } else if (test.phase === 3) {
                test.click("backupNow"); test.phase = 4;
            } else if (test.phase === 4) {
                test.ensure(page.completed && !page.failed, page.resultText);
                page.intent = "restore"; page.step = 2;
                page.runJob("history"); test.phase = 5;
            } else if (test.phase === 5) {
                test.ensure(page.historyLoaded && page.snapshots.length === 1, page.resultText);
                page.selectedSnapshot = page.snapshots[0];
                page.target = "@ROOT@/recovery";
                test.click("backupReviewRestore");
                test.find(page, "backupRestoreConfirm").checked = true;
                test.click("backupRestore"); test.phase = 6;
            } else if (test.phase === 6) {
                test.ensure(page.completed && !page.failed, page.resultText);
                console.log("WIZARD_PASS local verify, review, backup, history, restore, guards");
                Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.error("WIZARD_FAILED timeout", test.phase, page.status); Qt.quit(); } }
}
