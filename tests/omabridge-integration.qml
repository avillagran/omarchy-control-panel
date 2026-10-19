import QtQuick
import Quickshell
import "desktop"

// Drives the real OmaBridge page against tests/fixtures/fake-omarchy-t3-client.
// OMABRIDGE_EXPECT selects the scenario: "ready" walks every action,
// "outdated" and "missing" only check the install/update state.
ShellRoot {
    id: test
    property int phase: 0
    property int idle: 0
    readonly property string expect: Quickshell.env("OMABRIDGE_EXPECT")
    readonly property string awaiting: "aaaaaaaa-1111-4111-8111-111111111111"
    readonly property string peerA: "a1".repeat(32)
    readonly property string peerB: "b2".repeat(32)
    function ensure(ok, message) {
        if (!ok) {
            console.error("OMABRIDGE_FAILED", "phase " + phase + ": " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }
    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = find(children[i], name);
            if (found)
                return found;
        }
        return null;
    }
    // Popups live in the window's overlay, a sibling of the page's content.
    function control(name) {
        return find(page.Window.window.contentItem, name);
    }
    function shown(name) {
        var item = control(name);
        return !!item && item.visible;
    }
    function click(name) {
        var item = control(name);
        ensure(item && item.visible && item.enabled, "clickable " + name);
        item.clicked();
    }
    QtObject {
        id: mock
        property string uiLang: "en"
        function t(lang, key) {
            return key;
        }
    }
    FloatingWindow {
        id: window
        implicitWidth: 820
        implicitHeight: 1000
        visible: true
        OmaBridgePage {
            id: page
            width: 780
            core: mock
        }
    }
    Timer {
        interval: 60
        running: true
        repeat: true
        onTriggered: {
            if (page.busy)
                return;
            if (test.expect !== "ready") {
                if (page.pageState === "loading" && ++test.idle < 100)
                    return;
                test.ensure(page.pageState === test.expect, "state " + page.pageState);
                test.ensure(test.control("omabridgeStateTitle").text === "omabridgeInstallOt3", "install/update title");
                test.ensure(test.control("omabridgeStateDetail").text === (test.expect === "missing" ? "omabridgeOt3Missing" : "omabridgeOt3Outdated"), "state detail");
                test.ensure(!test.shown("omabridgeInviteButton"), "management hidden");
                console.log("OMABRIDGE_PASS", test.expect);
                Qt.quit();
                return;
            }
            switch (test.phase) {
            case 0:
                if (page.pageState === "loading")
                    return;
                test.ensure(page.pageState === "ready" && !page.device, "fresh device");
                test.click("omabridgeCreateIdentity");
                test.ensure(test.shown("omabridgeConfirm") && !page.busy, "identity waits for confirmation");
                test.click("omabridgeConfirm");
                break;
            case 1:
                test.ensure(page.device && page.device.name === "test-device", "identity created");
                test.ensure(!test.shown("omabridgeConfirm"), "confirmation closes on success");
                test.ensure(!test.control("omabridgeInviteButton").enabled, "invite needs publishing");
                test.click("omabridgePublishButton");
                test.ensure(test.shown("omabridgePublishConfirm") && !page.busy, "publish waits for confirmation");
                test.control("omabridgePublishSsh").checked = true;
                test.click("omabridgePublishConfirm");
                break;
            case 2:
                test.ensure(page.published.active && page.published.services.indexOf("ssh") >= 0, "published with SSH");
                test.ensure(!test.shown("omabridgePublishConfirm"), "publish dialog closed");
                test.click("omabridgeInviteButton");
                test.ensure(test.shown("omabridgeInviteClose") && test.shown("omabridgeInviteSsh"), "invite dialog offers published services");
                test.control("omabridgeInviteQr").checked = true;
                test.click("omabridgeInviteCreate");
                break;
            case 3:
                test.ensure(page.created && page.created.path.indexOf("omabridge-invite-0.json") > 0, "invitation shown");
                test.ensure(test.shown("omabridgeInviteQrImage") && test.control("omabridgeInvitePath").text === page.created.path, "QR and path shown once");
                test.click("omabridgeInviteDiscard");
                break;
            case 4:
                test.ensure(page.created === null && !test.shown("omabridgeInviteClose"), "discard forgets the invitation");
                test.ensure(page.status === "omabridgeInviteDeleted", "discard status");
                test.click("omabridgeInviteButton");
                test.ensure(!test.shown("omabridgeInvitePath"), "a new dialog starts empty");
                test.click("omabridgeInviteCreate");
                break;
            case 5:
                test.ensure(page.created && !test.shown("omabridgeInviteQrImage"), "second invitation without QR");
                var field = test.control("omabridgeInvitePath");
                test.ensure(field.text === page.created.path, "path shown");
                test.click("omabridgeInviteClose");
                test.ensure(page.created === null && field.text === "", "closing forgets the invitation");
                test.click("omabridgeInviteButton");
                test.click("omabridgeInviteCreate");
                break;
            case 6:
                test.ensure(page.created && test.shown("omabridgeInviteClose"), "third invitation shown");
                page.visible = false;
                test.ensure(page.created === null && !test.shown("omabridgeInviteClose"), "leaving the page forgets the invitation");
                page.visible = true;
                test.ensure(page.busy, "returning to the page refreshes it");
                break;
            case 7:
                page.pairFile("file:///invitations/omabridge%20invite.json");
                test.ensure(test.shown("omabridgeConfirm") && !page.busy, "pair waits for confirmation");
                test.click("omabridgeConfirm");
                break;
            case 8:
                test.ensure(page.status === "omabridgeWaitingFor" && page.snapshot.awaiting.length === 1, "pairing pending");
                test.click("omabridgeRetry_" + test.awaiting);
                break;
            case 9:
                test.ensure(page.status === "omabridgePairedWith" && page.snapshot.peers.length === 1, "check again approved");
                var services = test.control("omabridgePeerServices_" + test.peerA);
                test.ensure(services && services.text === "omabridgeYouReach T3", "peer services " + (services ? services.text : "missing"));
                test.click("omabridgeApprove_" + test.peerB);
                test.ensure(test.shown("omabridgeConfirm") && !page.busy, "approve waits for confirmation");
                test.click("omabridgeConfirm");
                break;
            case 10:
                test.ensure(page.snapshot.pending.length === 0 && page.snapshot.peers.length === 2, "approved");
                test.click("omabridgeRevoke_" + test.peerA);
                test.click("omabridgeConfirm");
                break;
            case 11:
                test.ensure(page.snapshot.peers.length === 1 && page.status === "omabridgeRevoked", "revoked");
                page.pairFile("file:///invitations/omabridge-expired.json");
                test.click("omabridgeConfirm");
                break;
            case 12:
                test.ensure(page.errorCode === "omabridge_invite_expired" && test.shown("omabridgeConfirm"), "error keeps the dialog open");
                test.click("omabridgeConfirmCancel");
                test.ensure(page.errorCode === "" && !test.shown("omabridgeConfirm"), "cancel clears the error");
                test.click("omabridgeUnpublishButton");
                test.click("omabridgeConfirm");
                break;
            case 13:
                test.ensure(!page.published.enabled && page.status === "omabridgeUnpublished", "unpublished");
                console.log("OMABRIDGE_PASS ready");
                Qt.quit();
                return;
            }
            test.phase++;
        }
    }
}
