import QtQuick
import Quickshell
import "desktop"

// Drives the real OmaBridge page against tests/fixtures/fake-omabridge.
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
    // The page's timer that re-reads a managed device after a relay change.
    function remoteConfirmRunning() {
        for (var i = 0; i < page.data.length; i++)
            if (page.data[i] instanceof Timer && page.data[i].interval === 10000)
                return page.data[i].running;
        return false;
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
                test.ensure(test.control("omabridgeStateTitle").text === "omabridgeInstall", "install/update title");
                test.ensure(test.control("omabridgeStateDetail").text === (test.expect === "missing" ? "omabridgeMissingDetail" : "omabridgeOutdatedDetail"), "state detail");
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
                test.ensure(test.control("omabridgePublishT3").checked, "T3 Code is offered when it runs");
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
                test.ensure(page.busy, "the invitation is read before asking");
                break;
            case 8:
                test.ensure(test.shown("omabridgeConfirm") && !test.shown("omabridgeConsent"), "plain invitations ask no consent");
                test.click("omabridgeConfirm");
                break;
            case 9:
                test.ensure(page.status === "omabridgeWaitingFor" && page.snapshot.awaiting.length === 1, "pairing pending");
                test.click("omabridgeRetry_" + test.awaiting);
                break;
            case 10:
                test.ensure(page.status === "omabridgePairedWith" && page.snapshot.peers.length === 1, "check again approved");
                var services = test.control("omabridgePeerServices_" + test.peerA);
                test.ensure(services && services.text === "omabridgeYouReach T3", "peer services " + (services ? services.text : "missing"));
                test.ensure(test.control("omabridgePeerManage_" + test.peerA).text === "omabridgeYouManage", "management shown on the row");
                test.click("omabridgeManage_" + test.peerA);
                test.ensure(test.shown("omabridgeRemoteClose") && page.busy, "the managed device is read when the dialog opens");
                break;
            case 11:
                test.ensure(page.remoteSnapshot && page.remoteSnapshot.device.name === "remote-a", "remote state shown");
                test.ensure(!test.shown("omabridgeRemoteRevoke_" + "e5".repeat(32)) && test.shown("omabridgeRemoteRevoke_" + "d4".repeat(32)), "managing devices cannot be revoked remotely");
                test.ensure(!test.control("omabridgeRemoteRelay_none"), "no direct-only option remotely");
                test.control("omabridgeRemoteRename").text = "Remote desk";
                test.click("omabridgeRemoteRenameSave");
                break;
            case 12:
                test.ensure(page.remoteSnapshot.device.name === "Remote desk" && page.status === "omabridgeRemoteDone", "renamed remotely");
                test.control("omabridgeRemoteRelay_custom").clicked();
                test.control("omabridgeRemoteRelayUrl").text = "https://relay.example.net";
                test.click("omabridgeRemoteRelaySave");
                break;
            case 13:
                test.ensure(page.remoteSnapshot.relay.mode === "custom", "remote relay changed");
                test.ensure(test.remoteConfirmRunning(), "the change is confirmed by reaching it again");
                test.click("omabridgeRemoteRevoke_" + "d4".repeat(32));
                test.ensure(test.shown("omabridgeConfirm") && !page.busy, "remote revocation asks first");
                test.click("omabridgeConfirm");
                break;
            case 14:
                test.ensure(page.remoteSnapshot.peers.length === 1, "revoked remotely");
                test.click("omabridgeRemoteClose");
                test.click("omabridgeAdmin_" + test.peerA);
                test.ensure(test.shown("omabridgeConfirm") && !page.busy && page.confirmRequest.detail === "omabridgeManageWarning", "granting management warns first");
                test.click("omabridgeConfirm");
                break;
            case 15:
                test.ensure(page.snapshot.peers[0].admin && page.status === "omabridgeAdminChanged", "management granted");
                test.ensure(test.control("omabridgePeerManage_" + test.peerA).text === "omabridgeManagesThis · omabridgeYouManage", "both directions shown");
                test.click("omabridgeApprove_" + test.peerB);
                test.ensure(test.shown("omabridgeConfirm") && !page.busy, "approve waits for confirmation");
                test.click("omabridgeConfirm");
                break;
            case 16:
                test.ensure(page.snapshot.pending.length === 0 && page.snapshot.peers.length === 2, "approved");
                test.click("omabridgeRevoke_" + test.peerA);
                test.click("omabridgeConfirm");
                break;
            case 17:
                test.ensure(page.snapshot.peers.length === 1 && page.status === "omabridgeRevoked", "revoked");
                page.pairFile("file:///invitations/omabridge-expired.json");
                break;
            case 18:
                test.click("omabridgeConfirm");
                break;
            case 19:
                test.ensure(page.errorCode === "omabridge_invite_expired" && test.shown("omabridgeConfirm"), "error keeps the dialog open");
                test.click("omabridgeConfirmCancel");
                test.ensure(page.errorCode === "" && !test.shown("omabridgeConfirm"), "cancel clears the error");
                page.pairFile("file:///invitations/omabridge-manage.json");
                break;
            case 20:
                var consent = test.control("omabridgeConsent");
                test.ensure(test.shown("omabridgeConfirm") && consent.visible && !consent.checked, "an invitation that asks to manage warns, with consent unchecked");
                test.ensure(consent.text === "omabridgeManageConsent", "consent names the request");
                test.click("omabridgeConfirm");
                break;
            case 21:
                test.ensure(page.status === "omabridgeWaitingFor", "pairing without management goes ahead");
                test.ensure(test.control("omabridgeRelayStatus").text === "omabridgeRelayPublic", "public relays by default");
                test.click("omabridgeRelayButton");
                test.ensure(test.shown("omabridgeRelaySave") && !test.shown("omabridgeRelayUrl") && !page.busy, "relay dialog waits for a choice");
                test.control("omabridgeRelay_custom").clicked();
                var url = test.control("omabridgeRelayUrl");
                test.ensure(url.visible && !test.control("omabridgeRelaySave").enabled, "an own relay needs its address");
                test.ensure(test.shown("omabridgeRelayRepairNote"), "changing the relay warns about existing pairings");
                url.text = "http://relay.example.net";
                test.ensure(!test.control("omabridgeRelaySave").enabled, "only HTTPS relays");
                url.text = "https://relay.example.net";
                test.click("omabridgeRelaySave");
                break;
            case 22:
                test.ensure(page.relay.mode === "custom" && page.status === "omabridgeRelaySaved" && !test.shown("omabridgeRelaySave"), "relay saved");
                test.ensure(test.control("omabridgeRelayStatus").text === "omabridgeRelayCustom · https://relay.example.net", "own relay shown");
                test.click("omabridgeRenameButton");
                var name = test.control("omabridgeRenameField");
                test.ensure(name.visible && name.text === "test-device" && !test.control("omabridgeRenameSave").enabled, "rename starts from the current name");
                name.text = "   ";
                test.ensure(!test.control("omabridgeRenameSave").enabled, "a blank name is refused");
                name.text = " Desk at home ";
                test.click("omabridgeRenameSave");
                break;
            case 23:
                test.ensure(page.device.name === "Desk at home" && page.status === "omabridgeRenamedService" && !test.shown("omabridgeRenameSave"), "renamed");
                test.ensure(test.control("omabridgeDeviceName").text === "Desk at home", "new name shown");
                test.click("omabridgeRefresh");
                break;
            case 24:
                test.click("omabridgeUnpublishButton");
                test.click("omabridgeConfirm");
                break;
            case 25:
                test.ensure(!page.published.enabled && page.status === "omabridgeUnpublished", "unpublished");
                console.log("OMABRIDGE_PASS ready");
                Qt.quit();
                return;
            }
            test.phase++;
        }
    }
}
