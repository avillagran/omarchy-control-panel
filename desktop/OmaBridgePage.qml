pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "OmaBridgeModel.js" as OmaBridgeModel

// OmaBridge private links between devices, managed through `omabridge manage`:
// this device's identity, publishing, one-use invitations, pairing from an
// invitation file, approvals and revocation. Every change of trust is
// confirmed first. Invitation paths and QR codes are secrets: shown once,
// forgotten when their dialog closes, never logged or saved in preferences.
ColumnLayout {
    id: root
    required property var core
    property string helperPath: Quickshell.shellDir + "/../bin/omabridge-client"
    property bool busy: false
    property string action: ""
    property string pendingJson: ""
    property var result: null
    readonly property string pageState: OmaBridgeModel.stateFor(result)
    readonly property var snapshot: result && result.ok ? result.snapshot : null
    readonly property var device: snapshot ? snapshot.device : null
    readonly property var published: snapshot ? snapshot.published : ({})
    readonly property var relay: snapshot && snapshot.relay ? snapshot.relay : ({
            mode: "public",
            url: ""
        })
    property string relayChoice: "public"
    // The device being managed from the remote dialog and its last snapshot.
    property var remotePeer: null
    property var remoteSnapshot: null
    property string remoteAction: ""
    property string remoteRelayChoice: "public"
    // Requests sent one after another (moving devices to a hosted relay).
    property var queue: []
    property int queueTotal: 0
    property int queueDone: 0
    // What runs once the queue is empty; by default, report how many succeeded.
    property var queueFinished: null
    // The last public gateway check, for the gateway section.
    property var gatewayCheck: null
    // The invitation chosen for pairing, while its contents are inspected.
    property string inspectPath: ""
    property string errorCode: ""
    property string errorAction: ""
    property string status: ""
    property var created: null
    property var confirmRequest: null
    spacing: theme.padding

    AppTheme {
        id: theme
    }

    function t(key) {
        return root.core.t(root.core.uiLang, key);
    }
    function tr(key, name) {
        return t(key).replace("%1", name || "?");
    }
    function errorText(code, fromAction) {
        return t(OmaBridgeModel.errorKey(code, fromAction));
    }
    function expiry(seconds) {
        return seconds ? new Date(seconds * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : "";
    }
    function run(request) {
        if (busy || !request)
            return false;
        action = request.action;
        pendingJson = JSON.stringify(request);
        errorCode = "";
        busy = true;
        backend.stdinEnabled = true;
        backend.command = [helperPath];
        backend.running = true;
        return true;
    }
    function refresh() {
        status = "";
        run(OmaBridgeModel.readRequest());
    }
    // The Refresh button also asks paired devices for their current names.
    function sync() {
        status = "";
        run(device ? OmaBridgeModel.syncRequest() : OmaBridgeModel.readRequest());
    }
    function openRename() {
        errorCode = "";
        renameField.text = device ? device.name : "";
        renameDialog.open();
    }
    // Opens the confirmation dialog; nothing is sent until Confirm.
    function askRun(title, detail, task) {
        if (busy)
            return;
        errorCode = "";
        confirmRequest = {
            action: "queue",
            values: {},
            title: title,
            detail: detail,
            consent: "",
            run: task
        };
        confirmDialog.open();
    }
    // `consent`, when set, adds an unchecked box whose answer becomes `allowManage`.
    function ask(job, values, title, detail, consent) {
        if (busy)
            return;
        errorCode = "";
        consentCheck.checked = false;
        confirmRequest = {
            action: job,
            values: values || {},
            title: title,
            detail: detail || "",
            consent: consent || ""
        };
        confirmDialog.open();
    }
    function confirmed(job, values) {
        return run(OmaBridgeModel.confirmedRequest(job, values));
    }
    function confirmAsked() {
        if (confirmRequest.run) {
            var task = confirmRequest.run;
            confirmDialog.close();
            task();
            return;
        }
        var values = {};
        for (var key in confirmRequest.values)
            values[key] = confirmRequest.values[key];
        if (confirmRequest.consent)
            values.allowManage = consentCheck.checked;
        confirmed(confirmRequest.action, values);
    }
    // Reads the invitation first: one that asks to manage this device is
    // confirmed with a warning and an explicit, unchecked consent box.
    function pairFile(url) {
        if (busy)
            return;
        inspectPath = OmaBridgeModel.localPath(url);
        run(OmaBridgeModel.inspectRequest(inspectPath));
    }
    function openRemote(peer) {
        if (busy)
            return;
        errorCode = "";
        remotePeer = peer;
        remoteSnapshot = null;
        remoteRenameField.text = "";
        remoteDialog.open();
        remoteRead();
    }
    function remoteRead() {
        if (!remotePeer || busy)
            return;
        remoteAction = "read";
        run(OmaBridgeModel.remoteReadRequest(remotePeer.id));
    }
    // Changes made from the remote dialog itself were chosen there; trust
    // changes (approve, revoke, unpublish) still ask first.
    function remote(command) {
        var values = OmaBridgeModel.remoteValues(remotePeer ? remotePeer.id : "", command);
        if (!values || busy)
            return;
        remoteAction = command.action;
        confirmed("remote", values);
    }
    // Moves every managed device, then this one, to the relay `url`.
    function runQueue(requests, finished) {
        queue = requests;
        queueTotal = requests.length;
        queueDone = 0;
        queueFinished = finished || null;
        nextQueued();
    }
    function useRelayEverywhere(url) {
        runQueue(OmaBridgeModel.relayEverywhereRequests(url, snapshot ? snapshot.peers : []), null);
    }
    function nextQueued() {
        if (!queue.length) {
            if (queueTotal) {
                var finished = queueFinished;
                var done = queueDone, total = queueTotal;
                queueTotal = 0;
                queueFinished = null;
                if (finished)
                    finished(done, total);
                else
                    status = t("omabridgeHostUsed").replace("%1", done).replace("%2", total);
            }
            return;
        }
        var request = queue[0];
        queue = queue.slice(1);
        run(request);
    }
    // This device's peer entry for the managed device, to keep its other grants.
    function peerEntry(id) {
        return (snapshot ? snapshot.peers : []).filter(function (peer) {
            return peer.id === id;
        })[0] || null;
    }
    // Opens this device's T3 to the internet through the managed device, then
    // checks the address answers with this same T3.
    function exposeT3(host) {
        var entry = peerEntry(remotePeer.id);
        gatewayCheck = null;
        runQueue(OmaBridgeModel.exposeRequests(remotePeer.id, entry ? entry.services : [], device.id, host, entry ? entry.public : []), function (done, total) {
            var gateway = remoteSnapshot ? OmaBridgeModel.gatewayFor(remoteSnapshot.gateways, device.id, "t3") : null;
            if (done < total || !gateway) {
                status = t("omabridgeGatewayFailed");
                return;
            }
            remoteAction = "";
            Qt.callLater(function () {
                root.run(OmaBridgeModel.gatewayCheckRequest(gateway.url));
            });
        });
    }
    function concealT3() {
        var entry = peerEntry(remotePeer.id);
        gatewayCheck = null;
        runQueue(OmaBridgeModel.concealRequests(remotePeer.id, entry ? entry.services : [], device.id, entry ? entry.public : []), function (done, total) {
            status = t(done === total ? "omabridgeGatewayClosed" : "omabridgeGatewayFailed");
            remoteRead();
        });
    }
    function askRemote(command, title, detail) {
        var values = OmaBridgeModel.remoteValues(remotePeer ? remotePeer.id : "", command);
        if (!values || busy)
            return;
        remoteAction = command.action;
        ask("remote", values, title, detail);
    }
    onRemoteSnapshotChanged: {
        if (!remoteSnapshot)
            return;
        var services = remoteSnapshot.published.services || [];
        remoteT3.checked = services.indexOf("t3") >= 0;
        remoteSsh.checked = services.indexOf("ssh") >= 0;
        remoteRelayChoice = remoteSnapshot.relay.mode === "custom" ? "custom" : "public";
        remoteRelayUrl.text = remoteSnapshot.relay.url;
    }
    Timer {
        id: remoteConfirm
        interval: 10000
        onTriggered: root.remoteRead()
    }
    // A remote rename comes back as that device's announcement right after the
    // answer; read again so its row shows the new name.
    Timer {
        id: peersReread
        interval: 2000
        onTriggered: if (!root.busy)
            root.run(OmaBridgeModel.readRequest())
    }
    function openInvite() {
        created = null;
        errorCode = "";
        inviteT3.checked = true;
        inviteSsh.checked = false;
        inviteQr.checked = false;
        inviteManage.checked = false;
        inviteDialog.open();
    }
    function openPublish() {
        errorCode = "";
        var services = root.published.services || [];
        publishT3.checked = !!root.published.t3Available && (!root.published.enabled || services.indexOf("t3") >= 0);
        publishSsh.checked = services.indexOf("ssh") >= 0;
        publishDialog.open();
    }
    function openRelay() {
        errorCode = "";
        relayChoice = relay.mode;
        relayUrl.text = relay.url;
        relayDialog.open();
    }
    function finish(text, exitCode) {
        if (!busy)
            return;
        var done = action;
        var response = OmaBridgeModel.parseResponse(text, exitCode);
        busy = false;
        action = "";
        if (queueTotal)
            Qt.callLater(nextQueued);
        if (!response.ok) {
            if (done === "remote")
                remoteAction = "";
            if (done === "invite-inspect")
                inspectPath = "";
            var lost = ["missing", "outdated"].indexOf(OmaBridgeModel.stateFor(response)) >= 0 && (done === "read" || response.error !== "invalid_command");
            if (done === "read" && (lost || !root.snapshot))
                result = response;
            else if (lost) {
                result = response;
                confirmDialog.close();
                inviteDialog.close();
                publishDialog.close();
                relayDialog.close();
                renameDialog.close();
                remoteDialog.close();
            } else {
                errorCode = response.error;
                errorAction = done;
            }
            return;
        }
        result = {
            ok: true,
            snapshot: response.snapshot
        };
        if (queueTotal) {
            queueDone++;
            if (done === "remote" && response.remote && remotePeer && response.remote.device && response.remote.device.id === remotePeer.id)
                remoteSnapshot = response.remote;
            return;
        }
        if (done === "invite") {
            created = response.created;
            // The client's output still holds the secret; replace it right away.
            Qt.callLater(function () {
                root.run(OmaBridgeModel.readRequest());
            });
        } else if (done === "invite-discard") {
            created = null;
            inviteDialog.close();
            status = t("omabridgeInviteDeleted");
        } else if (done === "publish") {
            publishDialog.close();
            status = t("omabridgePublishedNow");
        } else if (done === "gateway-check") {
            gatewayCheck = response.gatewayCheck;
            status = t(OmaBridgeModel.gatewayCheckKey(gatewayCheck));
            return;
        } else if (done === "invite-inspect") {
            var invitation = response.invitation;
            var path = inspectPath;
            inspectPath = "";
            if (invitation && invitation.manage)
                ask("pair", OmaBridgeModel.pairValues(path, invitation, false), tr("omabridgePairManageConfirm", invitation.name), tr("omabridgeManageWarning", invitation.name), tr("omabridgeManageConsent", invitation.name));
            else
                ask("pair", OmaBridgeModel.pairValues(path, invitation, false), t("omabridgePairConfirm"), t("omabridgePairConfirmDetail"));
            return;
        } else if (done === "remote") {
            var changed = remoteAction;
            remoteAction = "";
            if (response.remote)
                remoteSnapshot = response.remote;
            if (changed !== "read") {
                status = t("omabridgeRemoteDone");
                remoteRenameField.text = "";
            }
            // A relay change is undone on that device unless it is reached again soon.
            if (changed === "relay-set" || changed === "relay-host")
                remoteConfirm.restart();
            if (changed === "rename")
                peersReread.restart();
        } else if (done === "admin-set") {
            status = t("omabridgeAdminChanged");
        } else if (done === "rename") {
            renameDialog.close();
            var renamed = OmaBridgeModel.renamedStatus(response.renamed);
            status = t(renamed.key).replace("%1", renamed.reached).replace("%2", renamed.total);
        } else if (done === "relay-set") {
            relayDialog.close();
            status = t("omabridgeRelaySaved");
        } else if (done === "pair" || done === "pair-retry") {
            var paired = response.paired;
            status = paired && paired.status === "approved" ? tr("omabridgePairedWith", paired.name) : tr("omabridgeWaitingFor", paired ? paired.name : "");
        } else if (done === "approve")
            status = t("omabridgeApproved");
        else if (done === "revoke")
            status = t("omabridgeRevoked");
        else if (done === "unpublish")
            status = t("omabridgeUnpublished");
        else if (done === "identity-create")
            status = t("omabridgeIdentityCreated");
        if (confirmRequest && confirmRequest.action === done)
            confirmDialog.close();
    }

    // Leaving the page or hiding the window also drops any shown invitation.
    function forget() {
        confirmDialog.close();
        publishDialog.close();
        relayDialog.close();
        renameDialog.close();
        remoteDialog.close();
        inviteDialog.close();
        created = null;
    }
    readonly property bool windowShown: Window.window ? Window.window.visible : true
    // Showing the window again re-reads, so changes made elsewhere appear.
    onWindowShownChanged: {
        if (!windowShown)
            forget();
        else if (visible && !busy)
            refresh();
    }
    onVisibleChanged: {
        if (!visible)
            forget();
        else if (!busy)
            refresh();
    }
    Component.onCompleted: if (visible)
        refresh()

    Process {
        id: backend
        stdout: StdioCollector {
            id: backendOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
        function closeWriteChannel() {
            stdinEnabled = false;
        }
        onStarted: {
            write(root.pendingJson + "\n");
            root.pendingJson = "";
            closeWriteChannel();
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.finish(backendOutput.text, exitCode);
        }
        // qmllint enable signal-handler-parameters
        // A helper that never started reports nothing through onExited.
        onRunningChanged: if (!running && root.busy)
            Qt.callLater(function () {
                if (root.busy && !backend.running && backendOutput.text === "") {
                    root.pendingJson = "";
                    root.finish('{"error":"failed_start"}', 1);
                }
            })
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: theme.textMuted
        font.family: theme.fontUi
        font.pixelSize: theme.caption
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Heading: Text {
        Layout.fillWidth: true
        color: theme.text
        font.family: theme.fontUi
        font.pixelSize: theme.body
        font.bold: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Action: Controls.Button {
        id: button
        property bool primary: false
        Layout.fillWidth: false
        enabled: !root.busy
        padding: theme.padding
        font.family: theme.fontUi
        font.pixelSize: theme.body
        Accessible.name: text
        contentItem: Text {
            text: button.text
            color: button.enabled ? theme.text : theme.textMuted
            font: button.font
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        background: Rectangle {
            radius: theme.radius
            color: button.primary ? theme.accentSoft : (button.hovered ? theme.panelAlt : theme.panel)
            border.color: button.activeFocus || button.primary ? theme.accent : theme.border
        }
    }
    component Check: Controls.CheckBox {
        enabled: !root.busy
        palette.highlight: theme.accent
        palette.windowText: theme.text
        font.family: theme.fontUi
        font.pixelSize: theme.body
    }
    component Card: Rectangle {
        default property alias content: cardContent.data
        Layout.fillWidth: true
        implicitHeight: cardContent.implicitHeight + theme.padding * 2
        radius: theme.radius
        color: theme.panelDeep
        border.color: theme.border
        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: theme.padding
            spacing: theme.gap
        }
    }
    component ErrorLine: Copy {
        visible: root.errorCode !== ""
        text: root.errorCode !== "" ? root.errorText(root.errorCode, root.errorAction !== "read") : ""
        color: theme.urgent
    }
    component BridgeDialog: Controls.Popup {
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(520, parent ? parent.width - 32 : 520)
        padding: theme.padding * 2
        modal: true
        closePolicy: root.busy ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
        background: Rectangle {
            color: theme.panel
            radius: theme.radius
            border.color: theme.border
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "󰌘"
            color: theme.text
            font.family: theme.fontUi
            font.pixelSize: theme.body + 4
        }
        Text {
            Layout.fillWidth: true
            text: root.t("omabridgeTitle")
            color: theme.text
            font.family: theme.fontUi
            font.pixelSize: theme.body
            font.bold: true
        }
        Controls.BusyIndicator {
            visible: root.busy
            running: root.busy
        }
        Action {
            objectName: "omabridgeRefresh"
            text: root.t("omabridgeRefresh")
            onClicked: root.sync()
        }
    }
    Copy {
        text: root.t("omabridgeIntro")
    }

    // OmaBridge missing or too old for `omabridge manage`.
    Card {
        visible: root.pageState !== "ready"
        Heading {
            objectName: "omabridgeStateTitle"
            text: root.pageState === "loading" ? root.t("omabridgeChecking") : (root.pageState === "failed" ? root.errorText(root.result.error, false) : root.t("omabridgeInstall"))
        }
        Copy {
            objectName: "omabridgeStateDetail"
            visible: text !== ""
            text: root.pageState === "missing" ? root.t("omabridgeMissingDetail") : (root.pageState === "outdated" || root.pageState === "unavailable" ? root.t("omabridgeOutdatedDetail") : "")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.pageState === "ready"
        spacing: theme.padding

        Card {
            Heading {
                text: root.t("omabridgeThisDevice")
            }
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    Text {
                        objectName: "omabridgeDeviceName"
                        Layout.fillWidth: true
                        text: root.device ? root.device.name : root.t("omabridgeNoIdentity")
                        color: theme.text
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    Copy {
                        visible: !!root.device
                        text: root.t("omabridgeDeviceId") + " · " + (root.device ? root.device.id : "")
                        wrapMode: Text.NoWrap
                        elide: Text.ElideMiddle
                    }
                }
                Action {
                    objectName: "omabridgeRenameButton"
                    visible: !!root.device
                    enabled: !root.busy
                    text: root.t("omabridgeRename")
                    onClicked: root.openRename()
                }
                Action {
                    visible: !!root.device && typeof root.core.copyToClipboard === "function"
                    text: root.t("omabridgeCopyId")
                    onClicked: root.core.copyToClipboard(root.device.id)
                }
                Action {
                    objectName: "omabridgeCreateIdentity"
                    visible: !root.device
                    primary: true
                    text: root.t("omabridgeCreateIdentity")
                    onClicked: root.ask("identity-create", {}, root.t("omabridgeCreateIdentityConfirm"), root.t("omabridgeCreateIdentityDetail"))
                }
            }
        }

        // Publishing runs OmaBridge as a user service; off by default.
        Card {
            Heading {
                text: root.t("omabridgePublish")
            }
            Copy {
                objectName: "omabridgePublishStatus"
                text: root.t(OmaBridgeModel.publishStatusKey(root.published)) + ((root.published.enabled || root.published.external) && root.published.active && !root.published.stale ? " · " + OmaBridgeModel.servicesText(root.published.services) : "")
                color: root.published.stale ? theme.urgent : theme.textMuted
            }
            Flow {
                Layout.fillWidth: true
                spacing: theme.gap
                Action {
                    objectName: "omabridgePublishButton"
                    visible: !root.published.enabled && !root.published.external
                    primary: true
                    enabled: !root.busy && !!root.device
                    text: root.t("omabridgePublishAction")
                    onClicked: root.openPublish()
                }
                Action {
                    visible: !!root.published.enabled && (!!root.published.stale || !root.published.active)
                    text: root.t("omabridgeRepublish")
                    onClicked: root.openPublish()
                }
                Action {
                    objectName: "omabridgeUnpublishButton"
                    visible: !!root.published.enabled
                    text: root.t("omabridgeUnpublishAction")
                    onClicked: root.ask("unpublish", {}, root.t("omabridgeUnpublishConfirm"), root.t("omabridgeUnpublishDetail"))
                }
            }
        }

        // How this device reaches peers it cannot dial directly (NAT, private IPs).
        Card {
            Heading {
                text: root.t("omabridgeRelay")
            }
            Copy {
                objectName: "omabridgeRelayStatus"
                text: root.t(OmaBridgeModel.relayStatusKey(root.relay)) + (root.relay.mode === "custom" ? " · " + root.relay.url : "")
                wrapMode: Text.WrapAnywhere
            }
            Action {
                objectName: "omabridgeRelayButton"
                enabled: !root.busy
                text: root.t("omabridgeRelayChange")
                onClicked: root.openRelay()
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: theme.gap
            Action {
                objectName: "omabridgeInviteButton"
                primary: true
                enabled: !root.busy && !!root.device && !!root.published.active
                text: root.t("omabridgeInvite")
                onClicked: root.openInvite()
            }
            Action {
                objectName: "omabridgePairButton"
                enabled: !root.busy && !!root.device
                text: root.t("omabridgePairFromFile")
                onClicked: inviteFile.open()
            }
        }
        Copy {
            visible: !!root.device && !root.published.active
            text: root.t("omabridgeInviteNeedsPublish")
        }

        // Pairings sent from here that the other device has not approved yet.
        Repeater {
            model: root.snapshot ? root.snapshot.awaiting : []
            delegate: Card {
                id: awaitingCard
                required property var modelData
                Copy {
                    text: root.tr("omabridgeWaitingFor", awaitingCard.modelData.name) + (awaitingCard.modelData.expires ? " · " + root.t("omabridgeExpires") + " " + root.expiry(awaitingCard.modelData.expires) : "")
                    color: theme.text
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: theme.gap
                    Action {
                        objectName: "omabridgeRetry_" + awaitingCard.modelData.id
                        text: root.t("omabridgeCheckAgain")
                        onClicked: root.confirmed("pair-retry", {
                            id: awaitingCard.modelData.id
                        })
                    }
                    Action {
                        objectName: "omabridgeDiscard_" + awaitingCard.modelData.id
                        text: root.t("omabridgeCancelPairing")
                        onClicked: root.ask("pair-discard", {
                            id: awaitingCard.modelData.id
                        }, root.tr("omabridgeCancelPairingConfirm", awaitingCard.modelData.name), "")
                    }
                }
            }
        }

        // Requests to reach this device.
        Heading {
            visible: !!root.snapshot && root.snapshot.pending.length > 0
            text: root.t("omabridgePending")
        }
        Repeater {
            model: root.snapshot ? root.snapshot.pending : []
            delegate: Card {
                id: pendingCard
                required property var modelData
                border.color: theme.accent
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        Heading {
                            text: pendingCard.modelData.name + " · " + OmaBridgeModel.shortId(pendingCard.modelData.id)
                        }
                        Copy {
                            text: root.t("omabridgeAsksToReach") + " " + OmaBridgeModel.servicesText(pendingCard.modelData.services) + (pendingCard.modelData.expires ? " · " + root.t("omabridgeExpires") + " " + root.expiry(pendingCard.modelData.expires) : "")
                        }
                    }
                    Action {
                        objectName: "omabridgeApprove_" + pendingCard.modelData.id
                        primary: true
                        text: root.t("omabridgeApprove")
                        onClicked: root.ask("approve", {
                            peer: pendingCard.modelData.id,
                            expires: pendingCard.modelData.expires
                        }, root.tr("omabridgeApproveConfirm", pendingCard.modelData.name), OmaBridgeModel.servicesText(pendingCard.modelData.services) + " · " + pendingCard.modelData.id)
                    }
                }
            }
        }

        Heading {
            visible: !!root.snapshot && root.snapshot.peers.length > 0
            text: root.t("omabridgePeers")
        }
        Copy {
            visible: !!root.snapshot && root.snapshot.peers.length === 0 && root.snapshot.pending.length === 0 && root.snapshot.awaiting.length === 0
            text: root.t("omabridgeNoPeers")
        }
        Repeater {
            model: root.snapshot ? root.snapshot.peers : []
            delegate: Card {
                id: peerCard
                required property var modelData
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        Heading {
                            text: peerCard.modelData.name + " · " + OmaBridgeModel.shortId(peerCard.modelData.id)
                        }
                        Copy {
                            objectName: "omabridgePeerServices_" + peerCard.modelData.id
                            text: [peerCard.modelData.remoteServices.length ? root.t("omabridgeYouReach") + " " + OmaBridgeModel.servicesText(peerCard.modelData.remoteServices) : "", peerCard.modelData.services.length ? root.t("omabridgeItReaches") + " " + OmaBridgeModel.servicesText(peerCard.modelData.services) : ""].filter(function (s) {
                                return s !== "";
                            }).join(" · ")
                        }
                        Copy {
                            objectName: "omabridgePeerManage_" + peerCard.modelData.id
                            visible: text !== ""
                            text: OmaBridgeModel.manageText(peerCard.modelData, root.t)
                            color: theme.accent
                        }
                    }
                    Action {
                        objectName: "omabridgeCopySsh_" + peerCard.modelData.id
                        readonly property string command: OmaBridgeModel.sshCommand(peerCard.modelData, root.snapshot ? root.snapshot.peers : [], root.snapshot ? root.snapshot.features : [])
                        visible: command !== "" && typeof root.core.copyToClipboard === "function"
                        text: root.t("omabridgeCopySsh")
                        onClicked: root.core.copyToClipboard(command)
                    }
                    Action {
                        objectName: "omabridgeManage_" + peerCard.modelData.id
                        visible: peerCard.modelData.managed
                        primary: true
                        enabled: !root.busy
                        text: root.t("omabridgeManage")
                        onClicked: root.openRemote(peerCard.modelData)
                    }
                    Action {
                        objectName: "omabridgeAdmin_" + peerCard.modelData.id
                        enabled: !root.busy
                        text: root.t(peerCard.modelData.admin ? "omabridgeAdminRemove" : "omabridgeAdminGrant")
                        onClicked: peerCard.modelData.admin ? root.ask("admin-set", {
                            peer: peerCard.modelData.id,
                            allowed: false
                        }, root.tr("omabridgeAdminRemoveConfirm", peerCard.modelData.name), root.t("omabridgeAdminRemoveDetail")) : root.ask("admin-set", {
                            peer: peerCard.modelData.id,
                            allowed: true
                        }, root.tr("omabridgeAdminGrantConfirm", peerCard.modelData.name + " · " + OmaBridgeModel.shortId(peerCard.modelData.id)), root.tr("omabridgeManageWarning", peerCard.modelData.name))
                    }
                    Action {
                        objectName: "omabridgeRevoke_" + peerCard.modelData.id
                        text: root.t("omabridgeRevoke")
                        onClicked: root.ask("revoke", {
                            peer: peerCard.modelData.id
                        }, root.tr("omabridgeRevokeConfirm", peerCard.modelData.name), root.t("omabridgeRevokeDetail"))
                    }
                }
            }
        }

        Copy {
            visible: !!root.snapshot && root.snapshot.error !== ""
            text: root.snapshot ? root.errorText(root.snapshot.error, false) : ""
            color: theme.urgent
        }
    }

    Copy {
        objectName: "omabridgeStatus"
        visible: root.status !== ""
        text: root.status
        color: theme.text
    }
    ErrorLine {
        objectName: "omabridgeError"
        visible: root.errorCode !== "" && !confirmDialog.visible && !inviteDialog.visible && !publishDialog.visible && !relayDialog.visible && !renameDialog.visible && !remoteDialog.visible
    }

    FileDialog {
        id: inviteFile
        title: root.t("omabridgeChooseInvite")
        fileMode: FileDialog.OpenFile
        nameFilters: [root.t("omabridgeInviteFilter") + " (*.json)", "* (*)"]
        onAccepted: root.pairFile(selectedFile)
    }

    BridgeDialog {
        id: confirmDialog
        objectName: "omabridgeConfirmDialog"
        onClosed: {
            root.confirmRequest = null;
            root.errorCode = "";
        }
        contentItem: ColumnLayout {
            spacing: theme.padding
            Heading {
                text: root.confirmRequest ? root.confirmRequest.title : ""
            }
            Copy {
                visible: text !== ""
                text: root.confirmRequest ? root.confirmRequest.detail : ""
                wrapMode: Text.Wrap
            }
            Check {
                id: consentCheck
                objectName: "omabridgeConsent"
                Layout.fillWidth: true
                visible: !!root.confirmRequest && root.confirmRequest.consent !== ""
                text: root.confirmRequest ? root.confirmRequest.consent : ""
            }
            ErrorLine {}
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                Action {
                    objectName: "omabridgeConfirmCancel"
                    text: root.t("cancel")
                    onClicked: confirmDialog.close()
                }
                Action {
                    objectName: "omabridgeConfirm"
                    primary: true
                    text: root.t("omabridgeConfirm")
                    onClicked: root.confirmAsked()
                }
            }
        }
    }

    BridgeDialog {
        id: publishDialog
        objectName: "omabridgePublishDialog"
        onClosed: root.errorCode = ""
        contentItem: ColumnLayout {
            spacing: theme.padding
            Heading {
                text: root.t("omabridgePublishConfirm")
            }
            Copy {
                text: root.t("omabridgePublishDetail")
            }
            Check {
                id: publishT3
                objectName: "omabridgePublishT3"
                text: root.t("omabridgeShareT3")
                enabled: !root.busy && !!root.published.t3Available
            }
            Copy {
                visible: !root.published.t3Available
                text: root.t("omabridgeErrorT3Unavailable")
            }
            Check {
                id: publishSsh
                objectName: "omabridgePublishSsh"
                text: root.t("omabridgeShareSsh")
                enabled: !root.busy && !!root.published.sshAvailable
            }
            Copy {
                visible: !root.published.sshAvailable
                text: root.t("omabridgeErrorSshUnavailable")
            }
            ErrorLine {}
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                Action {
                    text: root.t("cancel")
                    onClicked: publishDialog.close()
                }
                Action {
                    objectName: "omabridgePublishConfirm"
                    primary: true
                    enabled: !root.busy && (OmaBridgeModel.publishValues(root.published, publishT3.checked, publishSsh.checked).t3 || OmaBridgeModel.publishValues(root.published, publishT3.checked, publishSsh.checked).ssh)
                    text: root.t("omabridgePublishAction")
                    onClicked: root.confirmed("publish", OmaBridgeModel.publishValues(root.published, publishT3.checked, publishSsh.checked))
                }
            }
        }
    }

    BridgeDialog {
        id: remoteDialog
        objectName: "omabridgeRemoteDialog"
        width: Math.min(640, parent ? parent.width - 32 : 640)
        onClosed: root.errorCode = ""
        contentItem: Controls.ScrollView {
            id: remoteScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(remoteColumn.implicitHeight, root.Window.window ? root.Window.window.height - 120 : 640)
            ColumnLayout {
                id: remoteColumn
                width: remoteScroll.availableWidth
                spacing: theme.padding
                Heading {
                    text: root.remotePeer ? root.tr("omabridgeManageTitle", root.remotePeer.name + " · " + OmaBridgeModel.shortId(root.remotePeer.id)) : ""
                }
                Copy {
                    visible: !root.remoteSnapshot
                    text: root.t(root.busy ? "omabridgeRemoteLoading" : "omabridgeRemoteUnavailable")
                }
                ErrorLine {}

                // Name
                Heading {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeRemoteName")
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot
                    Controls.TextField {
                        id: remoteRenameField
                        objectName: "omabridgeRemoteRename"
                        Layout.fillWidth: true
                        enabled: !root.busy
                        maximumLength: 80
                        placeholderText: root.remoteSnapshot && root.remoteSnapshot.device ? root.remoteSnapshot.device.name : ""
                        selectByMouse: true
                        color: theme.text
                        placeholderTextColor: theme.textMuted
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        background: Rectangle {
                            color: theme.panelDeep
                            radius: theme.radius
                            border.color: remoteRenameField.activeFocus ? theme.accent : theme.border
                        }
                    }
                    Action {
                        objectName: "omabridgeRemoteRenameSave"
                        enabled: !root.busy && OmaBridgeModel.nameValid(remoteRenameField.text)
                        text: root.t("omabridgeRelaySave")
                        onClicked: root.remote(OmaBridgeModel.renameValues(remoteRenameField.text).name ? {
                            action: "rename",
                            name: OmaBridgeModel.renameValues(remoteRenameField.text).name
                        } : null)
                    }
                }

                // Publishing
                Heading {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgePublish")
                }
                Copy {
                    objectName: "omabridgeRemotePublishStatus"
                    visible: !!root.remoteSnapshot
                    text: root.remoteSnapshot ? root.t(OmaBridgeModel.publishStatusKey(root.remoteSnapshot.published)) + (root.remoteSnapshot.published.active ? " · " + OmaBridgeModel.servicesText(root.remoteSnapshot.published.services) : "") : ""
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot
                    spacing: theme.gap
                    Check {
                        id: remoteT3
                        objectName: "omabridgeRemoteT3"
                        text: root.t("omabridgeShareT3")
                        enabled: !root.busy && !!root.remoteSnapshot && root.remoteSnapshot.published.t3Available
                    }
                    Check {
                        id: remoteSsh
                        objectName: "omabridgeRemoteSsh"
                        text: root.t("omabridgeShareSsh")
                        enabled: !root.busy && !!root.remoteSnapshot && root.remoteSnapshot.published.sshAvailable
                    }
                    Action {
                        objectName: "omabridgeRemotePublish"
                        enabled: !root.busy && !!root.remoteSnapshot && !root.remoteSnapshot.published.external && (OmaBridgeModel.publishValues(root.remoteSnapshot.published, remoteT3.checked, remoteSsh.checked).t3 || OmaBridgeModel.publishValues(root.remoteSnapshot.published, remoteT3.checked, remoteSsh.checked).ssh)
                        text: root.t("omabridgePublishAction")
                        onClicked: {
                            var values = OmaBridgeModel.publishValues(root.remoteSnapshot.published, remoteT3.checked, remoteSsh.checked);
                            root.remote({
                                action: "publish",
                                t3: values.t3,
                                ssh: values.ssh
                            });
                        }
                    }
                    Action {
                        objectName: "omabridgeRemoteUnpublish"
                        visible: !!root.remoteSnapshot && root.remoteSnapshot.published.enabled
                        enabled: !root.busy
                        text: root.t("omabridgeUnpublishAction")
                        onClicked: root.askRemote({
                            action: "unpublish"
                        }, root.tr("omabridgeRemoteUnpublishConfirm", root.remotePeer.name), root.t("omabridgeRemoteUnpublishDetail"))
                    }
                }

                // Relay
                Heading {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeRelay")
                }
                Copy {
                    visible: !!root.remoteSnapshot
                    text: root.remoteSnapshot ? root.t(OmaBridgeModel.relayStatusKey(root.remoteSnapshot.relay)) + (root.remoteSnapshot.relay.mode === "custom" ? " · " + root.remoteSnapshot.relay.url : "") : ""
                    wrapMode: Text.WrapAnywhere
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot
                    spacing: theme.gap
                    Repeater {
                        model: ["public", "custom"]
                        delegate: Controls.RadioButton {
                            required property string modelData
                            objectName: "omabridgeRemoteRelay_" + modelData
                            enabled: !root.busy
                            checked: root.remoteRelayChoice === modelData
                            onClicked: root.remoteRelayChoice = modelData
                            text: root.t(modelData === "public" ? "omabridgeRelayOptionPublic" : "omabridgeRelayOptionCustom")
                            palette.highlight: theme.accent
                            palette.windowText: theme.text
                            font.family: theme.fontUi
                            font.pixelSize: theme.body
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot
                    Controls.TextField {
                        id: remoteRelayUrl
                        objectName: "omabridgeRemoteRelayUrl"
                        Layout.fillWidth: true
                        visible: root.remoteRelayChoice === "custom"
                        enabled: !root.busy
                        placeholderText: "https://relay.example.net"
                        selectByMouse: true
                        color: theme.text
                        placeholderTextColor: theme.textMuted
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        background: Rectangle {
                            color: theme.panelDeep
                            radius: theme.radius
                            border.color: remoteRelayUrl.activeFocus ? theme.accent : theme.border
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        visible: root.remoteRelayChoice !== "custom"
                    }
                    Action {
                        objectName: "omabridgeRemoteRelaySave"
                        enabled: !root.busy && !!root.remoteSnapshot && OmaBridgeModel.relayValid(root.remoteRelayChoice, remoteRelayUrl.text) && (root.remoteRelayChoice !== root.remoteSnapshot.relay.mode || (root.remoteRelayChoice === "custom" && remoteRelayUrl.text.trim() !== root.remoteSnapshot.relay.url))
                        text: root.t("omabridgeRelaySave")
                        onClicked: root.remote({
                            action: "relay-set",
                            relay: OmaBridgeModel.relayValues(root.remoteRelayChoice, remoteRelayUrl.text).relay
                        })
                    }
                }
                Copy {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeRemoteRelayNote")
                }

                // Private relay hosted here
                Heading {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeHostTitle")
                }
                Copy {
                    objectName: "omabridgeRemoteHostStatus"
                    visible: !!root.remoteSnapshot
                    text: root.remoteSnapshot ? root.t(OmaBridgeModel.relayHostStatusKey(root.remoteSnapshot.relayHost)) + (root.remoteSnapshot.relayHost.enabled ? " · " + root.remoteSnapshot.relayHost.url : "") : ""
                    color: root.remoteSnapshot && root.remoteSnapshot.relayHost.error ? theme.urgent : theme.textMuted
                    wrapMode: Text.WrapAnywhere
                }
                Copy {
                    visible: !!root.remoteSnapshot && !root.remoteSnapshot.relayHost.enabled
                    text: root.remoteSnapshot && root.remoteSnapshot.relayHost.suggested ? root.tr("omabridgeHostSuggested", root.remoteSnapshot.relayHost.suggested) : root.t("omabridgeHostNoSuggestion")
                    wrapMode: Text.WrapAnywhere
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot && !root.remoteSnapshot.relayHost.enabled
                    Controls.TextField {
                        id: remoteHostUrl
                        objectName: "omabridgeRemoteHostUrl"
                        Layout.fillWidth: true
                        enabled: !root.busy
                        placeholderText: root.remoteSnapshot && root.remoteSnapshot.relayHost.suggested ? root.remoteSnapshot.relayHost.suggested : "https://relay.example.net:3341"
                        selectByMouse: true
                        color: theme.text
                        placeholderTextColor: theme.textMuted
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        background: Rectangle {
                            color: theme.panelDeep
                            radius: theme.radius
                            border.color: remoteHostUrl.activeFocus ? theme.accent : theme.border
                        }
                    }
                    Action {
                        objectName: "omabridgeRemoteHostEnable"
                        primary: true
                        enabled: !root.busy && (remoteHostUrl.text.trim() !== "" ? OmaBridgeModel.relayValid("custom", remoteHostUrl.text) : !!root.remoteSnapshot && root.remoteSnapshot.relayHost.suggested !== "")
                        text: root.t("omabridgeHostEnable")
                        onClicked: {
                            var command = {
                                action: "relay-host",
                                enabled: true
                            };
                            if (remoteHostUrl.text.trim() !== "")
                                command.url = remoteHostUrl.text.trim();
                            root.remote(command);
                        }
                    }
                }
                Copy {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeHostDetail")
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot && root.remoteSnapshot.relayHost.enabled
                    spacing: theme.gap
                    Action {
                        objectName: "omabridgeRemoteHostUse"
                        primary: true
                        enabled: !root.busy && !!root.remoteSnapshot && root.remoteSnapshot.relayHost.running
                        text: root.t("omabridgeHostUseEverywhere")
                        onClicked: {
                            var url = root.remoteSnapshot.relayHost.url;
                            root.askRun(root.tr("omabridgeHostUseConfirm", url), root.t("omabridgeHostUseDetail"), function () {
                                root.useRelayEverywhere(url);
                            });
                        }
                    }
                    Action {
                        objectName: "omabridgeRemoteHostDisable"
                        enabled: !root.busy
                        text: root.t("omabridgeHostDisable")
                        onClicked: root.askRemote({
                            action: "relay-host",
                            enabled: false
                        }, root.tr("omabridgeHostDisableConfirm", root.remotePeer.name), root.t("omabridgeHostDisableDetail"))
                    }
                }

                // Public access to this device's T3 through that device
                Heading {
                    visible: !!root.remoteSnapshot
                    text: root.t("omabridgeGatewayTitle")
                }
                Repeater {
                    model: root.remoteSnapshot ? root.remoteSnapshot.gateways : []
                    delegate: RowLayout {
                        id: gatewayRow
                        required property var modelData
                        Layout.fillWidth: true
                        Copy {
                            objectName: "omabridgeGateway_" + gatewayRow.modelData.peer
                            Layout.fillWidth: true
                            text: (gatewayRow.modelData.name || OmaBridgeModel.shortId(gatewayRow.modelData.peer)) + " · " + gatewayRow.modelData.url + " · " + root.t(gatewayRow.modelData.running ? "omabridgeHostRunning" : (gatewayRow.modelData.error === "port" ? "omabridgeHostPort" : gatewayRow.modelData.error === "certificate" ? "omabridgeHostCertificate" : "omabridgeHostStarting"))
                            color: gatewayRow.modelData.running ? theme.text : theme.urgent
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
                Copy {
                    objectName: "omabridgeGatewayCheck"
                    visible: !!root.gatewayCheck
                    text: root.gatewayCheck ? root.t(OmaBridgeModel.gatewayCheckKey(root.gatewayCheck)) : ""
                    color: root.gatewayCheck && root.gatewayCheck.reachable && root.gatewayCheck.sameEnvironment !== false ? theme.text : theme.urgent
                }
                Copy {
                    visible: !!root.remoteSnapshot && !OmaBridgeModel.gatewayFor(root.remoteSnapshot.gateways, root.device ? root.device.id : "", "t3")
                    text: root.t(root.published.services && root.published.services.indexOf("t3") >= 0 ? "omabridgeGatewayDetail" : "omabridgeGatewayNeedsT3")
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot && !!root.device && !OmaBridgeModel.gatewayFor(root.remoteSnapshot.gateways, root.device.id, "t3")
                    Controls.TextField {
                        id: gatewayHost
                        objectName: "omabridgeGatewayHost"
                        Layout.fillWidth: true
                        enabled: !root.busy
                        text: root.remoteSnapshot && root.device ? OmaBridgeModel.gatewayHostSuggestion(root.device.name, root.remoteSnapshot.gatewayZones) : ""
                        placeholderText: root.t("omabridgeGatewayHostPlaceholder")
                        selectByMouse: true
                        color: theme.text
                        placeholderTextColor: theme.textMuted
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        background: Rectangle {
                            color: theme.panelDeep
                            radius: theme.radius
                            border.color: gatewayHost.activeFocus ? theme.accent : theme.border
                        }
                    }
                    Action {
                        objectName: "omabridgeGatewayOpen"
                        primary: true
                        enabled: !root.busy && OmaBridgeModel.validHost(gatewayHost.text) && !!root.published.services && root.published.services.indexOf("t3") >= 0
                        text: root.t("omabridgeGatewayOpen")
                        onClicked: {
                            var host = gatewayHost.text.trim();
                            root.askRun(root.tr("omabridgeGatewayConfirm", root.remotePeer.name), root.t("omabridgeGatewayWarning"), function () {
                                root.exposeT3(host);
                            });
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !!root.remoteSnapshot && !!root.device && !!OmaBridgeModel.gatewayFor(root.remoteSnapshot.gateways, root.device.id, "t3")
                    spacing: theme.gap
                    Action {
                        objectName: "omabridgeGatewayRecheck"
                        enabled: !root.busy
                        text: root.t("omabridgeGatewayRecheck")
                        onClicked: root.run(OmaBridgeModel.gatewayCheckRequest(OmaBridgeModel.gatewayFor(root.remoteSnapshot.gateways, root.device.id, "t3").url))
                    }
                    Action {
                        objectName: "omabridgeGatewayClose"
                        enabled: !root.busy
                        text: root.t("omabridgeGatewayCloseAction")
                        onClicked: root.askRun(root.tr("omabridgeGatewayCloseConfirm", root.remotePeer.name), root.t("omabridgeGatewayCloseDetail"), function () {
                            root.concealT3();
                        })
                    }
                }

                // Requests waiting on that device
                Heading {
                    visible: !!root.remoteSnapshot && root.remoteSnapshot.pending.length > 0
                    text: root.t("omabridgePending")
                }
                Repeater {
                    model: root.remoteSnapshot ? root.remoteSnapshot.pending : []
                    delegate: RowLayout {
                        id: remotePending
                        required property var modelData
                        Layout.fillWidth: true
                        Copy {
                            Layout.fillWidth: true
                            text: remotePending.modelData.name + " · " + OmaBridgeModel.shortId(remotePending.modelData.id) + " · " + root.t("omabridgeAsksToReach") + " " + OmaBridgeModel.servicesText(remotePending.modelData.services)
                            color: theme.text
                        }
                        Action {
                            objectName: "omabridgeRemoteApprove_" + remotePending.modelData.id
                            enabled: !root.busy
                            text: root.t("omabridgeApprove")
                            onClicked: root.askRemote({
                                action: "approve",
                                peer: remotePending.modelData.id,
                                expires: remotePending.modelData.expires
                            }, root.tr("omabridgeRemoteApproveConfirm", remotePending.modelData.name), OmaBridgeModel.servicesText(remotePending.modelData.services) + " · " + remotePending.modelData.id)
                        }
                    }
                }

                // Its paired devices
                Heading {
                    visible: !!root.remoteSnapshot && root.remoteSnapshot.peers.length > 0
                    text: root.t("omabridgePeers")
                }
                Repeater {
                    model: root.remoteSnapshot ? root.remoteSnapshot.peers : []
                    delegate: RowLayout {
                        id: remotePeerRow
                        required property var modelData
                        Layout.fillWidth: true
                        Copy {
                            Layout.fillWidth: true
                            text: remotePeerRow.modelData.name + " · " + OmaBridgeModel.shortId(remotePeerRow.modelData.id) + (remotePeerRow.modelData.admin ? " · " + root.t("omabridgeRemoteAdminPeer") : "")
                            color: theme.text
                        }
                        Action {
                            objectName: "omabridgeRemoteRevoke_" + remotePeerRow.modelData.id
                            visible: OmaBridgeModel.remoteRevocable(remotePeerRow.modelData)
                            enabled: !root.busy
                            text: root.t("omabridgeRevoke")
                            onClicked: root.askRemote({
                                action: "revoke",
                                peer: remotePeerRow.modelData.id
                            }, root.tr("omabridgeRemoteRevokeConfirm", remotePeerRow.modelData.name), root.t("omabridgeRemoteRevokeDetail"))
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item {
                        Layout.fillWidth: true
                    }
                    Action {
                        objectName: "omabridgeRemoteRefresh"
                        enabled: !root.busy
                        text: root.t("omabridgeRefresh")
                        onClicked: root.remoteRead()
                    }
                    Action {
                        objectName: "omabridgeRemoteClose"
                        primary: true
                        text: root.t("omabridgeDone")
                        onClicked: remoteDialog.close()
                    }
                }
            }
        }
    }

    BridgeDialog {
        id: renameDialog
        objectName: "omabridgeRenameDialog"
        onClosed: root.errorCode = ""
        contentItem: ColumnLayout {
            spacing: theme.padding
            Heading {
                text: root.t("omabridgeRenameTitle")
            }
            Copy {
                text: root.t("omabridgeRenameDetail")
            }
            Controls.TextField {
                id: renameField
                objectName: "omabridgeRenameField"
                Layout.fillWidth: true
                enabled: !root.busy
                maximumLength: 80
                selectByMouse: true
                color: theme.text
                font.family: theme.fontUi
                font.pixelSize: theme.body
                background: Rectangle {
                    color: theme.panelDeep
                    radius: theme.radius
                    border.color: renameField.activeFocus ? theme.accent : theme.border
                }
                onAccepted: if (renameSave.enabled)
                    renameSave.clicked()
            }
            ErrorLine {}
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                Action {
                    text: root.t("cancel")
                    onClicked: renameDialog.close()
                }
                Action {
                    id: renameSave
                    objectName: "omabridgeRenameSave"
                    primary: true
                    enabled: !root.busy && OmaBridgeModel.nameValid(renameField.text) && !!root.device && renameField.text.trim() !== root.device.name
                    text: root.t("omabridgeRelaySave")
                    onClicked: root.confirmed("rename", OmaBridgeModel.renameValues(renameField.text))
                }
            }
        }
    }

    BridgeDialog {
        id: relayDialog
        objectName: "omabridgeRelayDialog"
        onClosed: root.errorCode = ""
        contentItem: ColumnLayout {
            spacing: theme.padding
            Heading {
                text: root.t("omabridgeRelayConfirm")
            }
            Copy {
                text: root.t("omabridgeRelayDetail")
            }
            Repeater {
                model: ["public", "custom", "none"]
                delegate: Controls.RadioButton {
                    required property string modelData
                    objectName: "omabridgeRelay_" + modelData
                    enabled: !root.busy
                    checked: root.relayChoice === modelData
                    onClicked: root.relayChoice = modelData
                    text: root.t(modelData === "public" ? "omabridgeRelayOptionPublic" : modelData === "custom" ? "omabridgeRelayOptionCustom" : "omabridgeRelayOptionNone")
                    palette.highlight: theme.accent
                    palette.windowText: theme.text
                    font.family: theme.fontUi
                    font.pixelSize: theme.body
                }
            }
            Controls.TextField {
                id: relayUrl
                objectName: "omabridgeRelayUrl"
                Layout.fillWidth: true
                visible: root.relayChoice === "custom"
                enabled: !root.busy
                placeholderText: "https://relay.example.net"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                selectByMouse: true
                color: theme.text
                placeholderTextColor: theme.textMuted
                font.family: theme.fontUi
                font.pixelSize: theme.body
                background: Rectangle {
                    color: theme.panelDeep
                    radius: theme.radius
                    border.color: relayUrl.activeFocus ? theme.accent : theme.border
                }
            }
            Copy {
                visible: root.relayChoice !== "public"
                text: root.t(root.relayChoice === "custom" ? "omabridgeRelayCustomDetail" : "omabridgeRelayNoneDetail")
            }
            Copy {
                objectName: "omabridgeRelayRepairNote"
                visible: !!root.device && (root.relayChoice !== root.relay.mode || (root.relayChoice === "custom" && relayUrl.text.trim() !== root.relay.url))
                text: root.t("omabridgeRelayRepairNote")
                color: theme.text
            }
            ErrorLine {}
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                Action {
                    text: root.t("cancel")
                    onClicked: relayDialog.close()
                }
                Action {
                    objectName: "omabridgeRelaySave"
                    primary: true
                    enabled: !root.busy && OmaBridgeModel.relayValid(root.relayChoice, relayUrl.text) && (root.relayChoice !== root.relay.mode || (root.relayChoice === "custom" && relayUrl.text.trim() !== root.relay.url))
                    text: root.t("omabridgeRelaySave")
                    onClicked: root.confirmed("relay-set", OmaBridgeModel.relayValues(root.relayChoice, relayUrl.text))
                }
            }
        }
    }

    BridgeDialog {
        id: inviteDialog
        objectName: "omabridgeInviteDialog"
        // The invitation path and QR are secrets: forget them on close.
        onClosed: {
            root.created = null;
            root.errorCode = "";
        }
        contentItem: ColumnLayout {
            spacing: theme.padding
            Heading {
                text: root.t("omabridgeInviteTitle")
            }
            Copy {
                text: root.t("omabridgeInviteDetail")
            }
            Check {
                id: inviteT3
                objectName: "omabridgeInviteT3"
                visible: !root.created && (root.published.services || []).indexOf("t3") >= 0
                text: root.t("omabridgeShareT3")
                checked: true
            }
            Check {
                id: inviteSsh
                objectName: "omabridgeInviteSsh"
                visible: !root.created && (root.published.services || []).indexOf("ssh") >= 0
                text: root.t("omabridgeShareSsh")
            }
            Check {
                id: inviteQr
                objectName: "omabridgeInviteQr"
                visible: !root.created
                text: root.t("omabridgeShowQr")
            }
            Check {
                id: inviteManage
                objectName: "omabridgeInviteManage"
                visible: !root.created
                text: root.t("omabridgeInviteManage")
            }
            Copy {
                visible: !root.created && inviteManage.checked
                text: root.t("omabridgeInviteManageDetail")
            }
            Image {
                objectName: "omabridgeInviteQrImage"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 220
                Layout.preferredHeight: visible ? 220 : 0
                visible: !!root.created && root.created.qrImage !== ""
                source: root.created ? root.created.qrImage : ""
                fillMode: Image.PreserveAspectFit
                smooth: false
                cache: false
            }
            Copy {
                visible: !!root.created
                text: root.t("omabridgeInviteShownOnce")
                color: theme.text
            }
            Controls.TextField {
                id: invitePath
                objectName: "omabridgeInvitePath"
                Layout.fillWidth: true
                visible: !!root.created
                text: root.created ? root.created.path : ""
                readOnly: true
                selectByMouse: true
                color: theme.text
                font.family: theme.fontUi
                font.pixelSize: theme.body
                background: Rectangle {
                    color: theme.panelDeep
                    radius: theme.radius
                    border.color: invitePath.activeFocus ? theme.accent : theme.border
                }
            }
            Copy {
                visible: !!root.created
                text: root.created ? root.t("omabridgeExpires") + " " + root.expiry(root.created.expires) + " · " + OmaBridgeModel.servicesText(root.created.services) : ""
            }
            ErrorLine {}
            RowLayout {
                Layout.fillWidth: true
                Action {
                    objectName: "omabridgeInviteDiscard"
                    visible: !!root.created
                    text: root.t("omabridgeInviteDelete")
                    onClicked: root.confirmed("invite-discard", {
                        path: root.created.path
                    })
                }
                Item {
                    Layout.fillWidth: true
                }
                Action {
                    objectName: "omabridgeInviteClose"
                    text: root.t(root.created ? "omabridgeDone" : "cancel")
                    onClicked: inviteDialog.close()
                }
                Action {
                    objectName: "omabridgeInviteCreate"
                    visible: !root.created
                    primary: true
                    enabled: !root.busy && OmaBridgeModel.inviteValues(root.published, inviteT3.checked && inviteT3.visible, inviteSsh.checked && inviteSsh.visible, false).services.length > 0
                    text: root.t("omabridgeInviteCreate")
                    onClicked: root.confirmed("invite", OmaBridgeModel.inviteManageValues(OmaBridgeModel.inviteValues(root.published, inviteT3.checked && inviteT3.visible, inviteSsh.checked && inviteSsh.visible, inviteQr.checked), inviteManage.checked))
                }
            }
        }
    }
}
