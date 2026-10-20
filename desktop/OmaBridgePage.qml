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
    // Opens the confirmation dialog; nothing is sent until Confirm.
    function ask(job, values, title, detail) {
        if (busy)
            return;
        errorCode = "";
        confirmRequest = {
            action: job,
            values: values || {},
            title: title,
            detail: detail || ""
        };
        confirmDialog.open();
    }
    function confirmed(job, values) {
        return run(OmaBridgeModel.confirmedRequest(job, values));
    }
    function pairFile(url) {
        ask("pair", {
            path: OmaBridgeModel.localPath(url)
        }, t("omabridgePairConfirm"), t("omabridgePairConfirmDetail"));
    }
    function openInvite() {
        created = null;
        errorCode = "";
        inviteT3.checked = true;
        inviteSsh.checked = false;
        inviteQr.checked = false;
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
        if (!response.ok) {
            var lost = ["missing", "outdated"].indexOf(OmaBridgeModel.stateFor(response)) >= 0 && (done === "read" || response.error !== "invalid_command");
            if (done === "read" && (lost || !root.snapshot))
                result = response;
            else if (lost) {
                result = response;
                confirmDialog.close();
                inviteDialog.close();
                publishDialog.close();
                relayDialog.close();
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
        inviteDialog.close();
        created = null;
    }
    readonly property bool windowShown: Window.window ? Window.window.visible : true
    onWindowShownChanged: if (!windowShown)
        forget()
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
            onClicked: root.refresh()
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
        visible: root.errorCode !== "" && !confirmDialog.visible && !inviteDialog.visible && !publishDialog.visible && !relayDialog.visible
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
                wrapMode: Text.WrapAnywhere
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
                    onClicked: root.confirmed(root.confirmRequest.action, root.confirmRequest.values)
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
                    enabled: !root.busy && OmaBridgeModel.relayValid(root.relayChoice, relayUrl.text)
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
                    onClicked: root.confirmed("invite", OmaBridgeModel.inviteValues(root.published, inviteT3.checked && inviteT3.visible, inviteSsh.checked && inviteSsh.visible, inviteQr.checked))
                }
            }
        }
    }
}
