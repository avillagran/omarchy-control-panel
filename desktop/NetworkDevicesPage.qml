pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "NetworkDevicesModel.js" as NetworkDevicesModel

ColumnLayout {
    id: root
    required property var core
    property string helperPath: Quickshell.shellDir + "/../bin/network-devices"
    property string timeCapsuleHelperPath: Quickshell.shellDir + "/../bin/timecapsule-smb"
    property bool busy: false
    property string action: ""
    property string pendingJson: "{}"
    property string status: ""
    property string networkLabel: ""
    property string resultText: ""
    property bool details: false
    property bool timeCapsuleOpen: false
    property bool timeCapsuleBusy: false
    property string timeCapsuleAction: ""
    property string timeCapsuleJson: "{}"
    property string timeCapsulePassword: ""
    property string timeCapsuleUser: ""
    property string timeCapsuleShare: ""
    property var timeCapsuleShares: []
    property string timeCapsuleStatus: ""
    property bool timeCapsuleSecretService: false
    property bool timeCapsuleSmbclient: false
    property bool timeCapsuleUseSaved: false
    property bool timeCapsuleVerified: false
    spacing: theme.padding

    AppTheme {
        id: theme
    }

    function t(key) {
        return root.core.t(root.core.uiLang, key);
    }
    function selected(device) {
        return root.core.selectedNetworkDevice && root.core.selectedNetworkDevice.id === device.id;
    }
    function run(job, request) {
        if (busy)
            return;
        action = job;
        pendingJson = JSON.stringify(request || {});
        busy = true;
        status = t(job === "scan" ? "networkScanning" : (job === "mounts" ? "networkCheckingMounts" : "networkOpening"));
        backend.stdinEnabled = true;
        backend.command = [helperPath, job];
        backend.running = true;
    }
    function scan() {
        run("scan", {
            deep: true
        });
    }
    function connect(protocol) {
        var device = root.core.selectedNetworkDevice;
        if (!device)
            return;
        if (device.legacySmb === true && protocol === "smb") {
            openTimeCapsule();
            return;
        }
        run("connect", {
            device: device.backendDevice,
            protocol: protocol
        });
    }
    function resetTimeCapsule() {
        timeCapsuleOpen = false;
        timeCapsuleUser = "";
        timeCapsuleShare = "";
        timeCapsuleShares = [];
        timeCapsuleStatus = "";
        timeCapsuleUseSaved = false;
        timeCapsuleVerified = false;
        timeCapsulePassword = "";
    }
    function openTimeCapsule() {
        resetTimeCapsule();
        timeCapsuleOpen = true;
        runTimeCapsule("capabilities");
    }
    function runTimeCapsule(job) {
        if (timeCapsuleBusy || !root.core.selectedNetworkDevice)
            return;
        var request = {};
        if (job !== "capabilities")
            request = NetworkDevicesModel.timeCapsuleRequest(root.core.selectedNetworkDevice, timeCapsuleUser, (job === "verify" || job === "save-credential") ? timeCapsuleShare : "", job !== "save-credential" && timeCapsuleUseSaved);
        timeCapsuleAction = job;
        timeCapsuleJson = JSON.stringify(request);
        timeCapsulePassword = (job === "shares" || job === "verify" || job === "save-credential") && !request.savedCredential ? passwordField.text : "";
        timeCapsuleBusy = true;
        timeCapsuleStatus = t("networkTimeCapsuleWorking");
        timeCapsuleBackend.stdinEnabled = true;
        timeCapsuleBackend.command = NetworkDevicesModel.timeCapsuleCommand(timeCapsuleHelperPath, job);
        timeCapsuleBackend.running = true;
    }
    function updateAuthenticatedDevice(savedCredential) {
        root.core.selectedNetworkDevice = NetworkDevicesModel.withTimeCapsuleDestination(root.core.selectedNetworkDevice, timeCapsuleUser, timeCapsuleShare, savedCredential === true);
        var authenticated = root.core.selectedNetworkDevice;
        root.core.networkDevices = root.core.networkDevices.map(function (device) {
            return device.id === authenticated.id ? authenticated : device;
        });
    }
    function finishTimeCapsule(text, exitCode) {
        var actionDone = timeCapsuleAction;
        if (actionDone === "capabilities") {
            var capabilities = NetworkDevicesModel.parseTimeCapsuleCapabilities(text, exitCode);
            timeCapsuleSmbclient = capabilities.smbclient;
            timeCapsuleSecretService = capabilities.secretService;
            timeCapsuleStatus = capabilities.ok && capabilities.smbclient ? t("networkTimeCapsuleReady") : t("networkTimeCapsuleUnavailable");
        } else if (actionDone === "shares") {
            var shares = NetworkDevicesModel.parseTimeCapsuleShares(text, exitCode);
            timeCapsuleShares = shares.shares;
            timeCapsuleShare = "";
            timeCapsuleVerified = false;
            timeCapsuleStatus = shares.ok ? (shares.shares.length ? t("networkChooseShare") : t("networkNoShares")) : t("networkAuthenticationFailed");
        } else if (actionDone === "verify") {
            var verified = NetworkDevicesModel.parseTimeCapsuleVerify(text, exitCode);
            timeCapsuleVerified = verified.ok;
            if (verified.ok) {
                updateAuthenticatedDevice();
                timeCapsuleStatus = t("networkAuthenticatedAvailable");
            } else {
                timeCapsuleStatus = t("networkAuthenticationFailed");
            }
        } else if (actionDone === "save-credential") {
            var saved = NetworkDevicesModel.parseTimeCapsuleMutation(text, exitCode, "saved");
            if (saved.ok)
                updateAuthenticatedDevice(true);
            timeCapsuleStatus = saved.ok ? t("networkCredentialSaved") : t("networkCredentialSaveFailed");
        } else if (actionDone === "forget-credential") {
            var forgotten = NetworkDevicesModel.parseTimeCapsuleMutation(text, exitCode, "forgotten");
            if (forgotten.ok)
                timeCapsuleUseSaved = false;
            timeCapsuleStatus = forgotten.ok ? t("networkCredentialForgotten") : t("networkCredentialForgetFailed");
        }
        timeCapsulePassword = "";
        passwordField.clear();
        timeCapsuleBusy = false;
    }
    function finish(text, exitCode) {
        var checkMountsAfterScan = false;
        resultText = String(text || "");
        if (action === "scan") {
            var scan = NetworkDevicesModel.parseScan(text, exitCode);
            if (scan.ok) {
                root.core.networkDevices = scan.devices;
                if (root.core.selectedNetworkDevice) {
                    var selectedId = root.core.selectedNetworkDevice.id;
                    root.core.selectedNetworkDevice = null;
                    for (var i = 0; i < scan.devices.length; i++)
                        if (scan.devices[i].id === selectedId)
                            root.core.selectedNetworkDevice = scan.devices[i];
                }
                try {
                    var raw = JSON.parse(text);
                    if (Array.isArray(raw.networks))
                        networkLabel = raw.networks.map(function (network) {
                            return network.subnet + (network.interface ? " · " + network.interface : "");
                        }).join(", ");
                    else
                        networkLabel = raw.network || raw.subnet || raw.interface || "";
                } catch (error) {
                    networkLabel = "";
                }
                status = scan.devices.length ? t("networkFound").replace("%1", scan.devices.length) : t("networkNone");
                checkMountsAfterScan = true;
            } else
                status = scan.error;
        } else if (action === "mounts") {
            var mounts = NetworkDevicesModel.parseMounts(text, exitCode);
            if (mounts.ok) {
                root.core.networkDevices = NetworkDevicesModel.mergeMounts(root.core.networkDevices, mounts.mounts);
                if (root.core.selectedNetworkDevice) {
                    var selectedIp = root.core.selectedNetworkDevice.ip;
                    for (var m = 0; m < root.core.networkDevices.length; m++)
                        if (root.core.networkDevices[m].ip === selectedIp)
                            root.core.selectedNetworkDevice = root.core.networkDevices[m];
                }
                status = t("networkMountsChecked");
            } else
                status = mounts.error;
        } else {
            var response;
            try {
                response = JSON.parse(text);
            } catch (error) {
                response = {
                    ok: false,
                    error: t("networkInvalidResponse")
                };
            }
            if (exitCode === 0 && response.ok !== false && response.supported === false)
                status = t(response.reason === "afp_connector_unavailable" ? "networkAfpUnavailable" : "networkLegacyUnsupported");
            else if (exitCode === 0 && response.ok !== false)
                status = response.opened === true ? t("networkOpenedNotConnected") : t("networkConfigureStarted");
            else
                status = response.error || response.reason || t("networkActionFailed");
        }
        busy = false;
        if (checkMountsAfterScan)
            Qt.callLater(function () {
                root.run("mounts", {});
            });
    }

    Process {
        id: backend
        stdout: StdioCollector {
            id: backendOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: backendError
            waitForEnd: true
        }
        function closeWriteChannel() {
            stdinEnabled = false;
        }
        onStarted: {
            write(root.pendingJson + "\n");
            closeWriteChannel();
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.finish(backendOutput.text, exitCode);
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: if (!running && root.busy && backendOutput.text === "") {
            root.status = backendError.text || root.t("networkFailedStart");
            root.busy = false;
        }
    }

    Process {
        id: timeCapsuleBackend
        stdout: StdioCollector {
            id: timeCapsuleOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            waitForEnd: true
        }
        function closeWriteChannel() {
            stdinEnabled = false;
        }
        onStarted: {
            timeCapsuleBackend.write(root.timeCapsuleJson + "\n");
            if (root.timeCapsulePassword !== "")
                timeCapsuleBackend.write(root.timeCapsulePassword + "\n");
            closeWriteChannel();
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.finishTimeCapsule(timeCapsuleOutput.text, exitCode);
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: if (!running && root.timeCapsuleBusy && timeCapsuleOutput.text === "") {
            root.timeCapsulePassword = "";
            passwordField.clear();
            root.timeCapsuleStatus = root.t("networkTimeCapsuleFailedStart");
            root.timeCapsuleBusy = false;
        }
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: theme.textMuted
        font.family: theme.fontUi
        font.pixelSize: theme.caption
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Action: Controls.Button {
        id: button
        property bool primary: false
        Layout.fillWidth: true
        enabled: !root.busy && !root.timeCapsuleBusy
        padding: theme.padding
        font.family: theme.fontUi
        font.pixelSize: theme.body
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

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: root.t("networkDevicesTitle")
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
            Layout.fillWidth: false
            text: root.t(root.core.networkDevices.length ? "networkRefresh" : "networkScan")
            primary: true
            onClicked: root.scan()
        }
    }
    Copy {
        text: root.t("networkIntro")
    }
    Copy {
        visible: root.networkLabel !== ""
        text: root.t("networkSubnet") + " · " + root.networkLabel
    }
    Copy {
        visible: !root.busy && root.core.networkDevices.length === 0
        text: root.t("networkNotScanned")
    }

    GridLayout {
        Layout.fillWidth: true
        columns: root.width < 760 ? 1 : 2
        columnSpacing: theme.padding
        rowSpacing: theme.padding
        Repeater {
            model: root.core.networkDevices
            delegate: Rectangle {
                id: card
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: cardContent.implicitHeight + theme.padding * 2
                radius: theme.radius
                color: root.selected(modelData) ? theme.accentSoft : theme.panelDeep
                border.width: root.selected(modelData) ? 2 : 1
                border.color: root.selected(modelData) ? theme.accent : theme.border
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + " " + modelData.ip
                ColumnLayout {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: theme.padding
                    spacing: theme.gap
                    Text {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        color: theme.text
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Copy {
                        text: card.modelData.ip + (card.modelData.hostname && card.modelData.hostname !== card.modelData.name ? " · " + card.modelData.hostname : "")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: (card.modelData.timeCapsule ? ["timecapsule"] : []).concat(card.modelData.protocols)
                            delegate: Rectangle {
                                id: chip
                                required property string modelData
                                width: chipText.implicitWidth + 14
                                height: chipText.implicitHeight + 8
                                radius: height / 2
                                color: theme.panelAlt
                                border.color: theme.border
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: NetworkDevicesModel.protocolLabel(chip.modelData)
                                    color: theme.text
                                    font.family: theme.fontUi
                                    font.pixelSize: theme.caption
                                }
                            }
                        }
                        Rectangle {
                            width: stateText.implicitWidth + 14
                            height: stateText.implicitHeight + 8
                            radius: height / 2
                            color: card.modelData.connected || card.modelData.protocolAccessible ? theme.accentSoft : theme.panel
                            border.color: card.modelData.connected || card.modelData.protocolAccessible ? theme.accent : theme.border
                            Text {
                                id: stateText
                                anchors.centerIn: parent
                                text: root.t(card.modelData.connected ? "networkConnected" : (card.modelData.protocolAccessible ? "networkAuthenticatedAvailable" : "networkNotConnected"))
                                color: theme.text
                                font.family: theme.fontUi
                                font.pixelSize: theme.caption
                            }
                        }
                    }
                    Action {
                        text: root.t(root.selected(card.modelData) ? "networkSelected" : "networkSelect")
                        primary: root.selected(card.modelData)
                        onClicked: {
                            root.resetTimeCapsule();
                            root.core.selectedNetworkDevice = card.modelData;
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !!root.core.selectedNetworkDevice
        spacing: theme.gap
        Text {
            Layout.fillWidth: true
            text: root.t("networkSelectedDevice") + " · " + (root.core.selectedNetworkDevice ? root.core.selectedNetworkDevice.name : "")
            color: theme.text
            font.family: theme.fontUi
            font.pixelSize: theme.body
            font.bold: true
            wrapMode: Text.Wrap
        }
        Copy {
            visible: !!root.core.selectedNetworkDevice && root.core.selectedNetworkDevice.legacySmb === true
            text: root.t("networkLegacyWarning")
            color: theme.text
        }
        Flow {
            Layout.fillWidth: true
            spacing: theme.gap
            Repeater {
                model: root.core.selectedNetworkDevice ? root.core.selectedNetworkDevice.protocols : []
                delegate: Action {
                    id: protocolAction
                    required property string modelData
                    width: Math.max(150, implicitWidth)
                    Layout.fillWidth: false
                    visible: !(root.core.selectedNetworkDevice.legacySmb === true && protocolAction.modelData !== "smb")
                    text: root.core.selectedNetworkDevice.legacySmb === true && protocolAction.modelData === "smb" ? root.t("networkConfigureBackup") : root.t("networkOpenProtocol").replace("%1", NetworkDevicesModel.protocolLabel(protocolAction.modelData))
                    onClicked: root.connect(protocolAction.modelData)
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            visible: root.timeCapsuleOpen && !!root.core.selectedNetworkDevice && root.core.selectedNetworkDevice.legacySmb === true
            implicitHeight: timeCapsuleContent.implicitHeight + theme.padding * 2
            color: theme.panelDeep
            radius: theme.radius
            border.color: theme.border
            ColumnLayout {
                id: timeCapsuleContent
                anchors.fill: parent
                anchors.margins: theme.padding
                spacing: theme.gap
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.t("networkTimeCapsuleSetup")
                        color: theme.text
                        font.family: theme.fontUi
                        font.pixelSize: theme.body
                        font.bold: true
                    }
                    Controls.BusyIndicator {
                        visible: root.timeCapsuleBusy
                        running: root.timeCapsuleBusy
                    }
                    Action {
                        Layout.fillWidth: false
                        text: root.t("close")
                        onClicked: root.resetTimeCapsule()
                    }
                }
                Copy {
                    text: root.t("networkTimeCapsuleAuthHint")
                }
                Controls.TextField {
                    id: userField
                    Layout.fillWidth: true
                    enabled: !root.timeCapsuleBusy
                    placeholderText: root.t("networkUsername")
                    text: root.timeCapsuleUser
                    onTextEdited: root.timeCapsuleUser = text
                    color: theme.text
                    font.family: theme.fontUi
                    font.pixelSize: theme.body
                    background: Rectangle {
                        color: theme.panel
                        radius: theme.radius
                        border.color: userField.activeFocus ? theme.accent : theme.border
                    }
                }
                Controls.CheckBox {
                    visible: root.timeCapsuleSecretService
                    enabled: !root.timeCapsuleBusy
                    text: root.t("networkUseSavedCredential")
                    checked: root.timeCapsuleUseSaved
                    onToggled: {
                        root.timeCapsuleUseSaved = checked;
                        if (checked)
                            passwordField.clear();
                    }
                    palette.highlight: theme.accent
                    palette.windowText: theme.text
                }
                Controls.TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    visible: !root.timeCapsuleUseSaved
                    enabled: !root.timeCapsuleBusy
                    placeholderText: root.timeCapsuleVerified ? root.t("networkPasswordAgain") : root.t("networkPassword")
                    echoMode: TextInput.Password
                    color: theme.text
                    font.family: theme.fontUi
                    font.pixelSize: theme.body
                    background: Rectangle {
                        color: theme.panel
                        radius: theme.radius
                        border.color: passwordField.activeFocus ? theme.accent : theme.border
                    }
                }
                Action {
                    visible: root.timeCapsuleShares.length === 0
                    text: root.t("networkListShares")
                    primary: true
                    enabled: root.timeCapsuleSmbclient && root.timeCapsuleUser.trim() !== "" && (root.timeCapsuleUseSaved || passwordField.text !== "") && !root.timeCapsuleBusy
                    onClicked: root.runTimeCapsule("shares")
                }
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.timeCapsuleShares.length > 0
                    columns: root.width < 760 ? 1 : 2
                    columnSpacing: theme.gap
                    rowSpacing: theme.gap
                    Repeater {
                        model: root.timeCapsuleShares
                        delegate: Action {
                            required property var modelData
                            text: modelData.name + (modelData.comment ? "\n" + modelData.comment : "")
                            primary: root.timeCapsuleShare === modelData.name
                            onClicked: {
                                root.timeCapsuleShare = modelData.name;
                                root.timeCapsuleVerified = false;
                            }
                        }
                    }
                }
                Action {
                    visible: root.timeCapsuleShares.length > 0
                    text: root.t("networkVerifyShare")
                    primary: true
                    enabled: root.timeCapsuleShare !== "" && (root.timeCapsuleUseSaved || passwordField.text !== "") && !root.timeCapsuleBusy
                    onClicked: root.runTimeCapsule("verify")
                }
                Copy {
                    visible: root.timeCapsuleVerified
                    text: root.t("networkAuthenticatedAvailableHint")
                    color: theme.text
                }
                Copy {
                    visible: root.timeCapsuleVerified && root.timeCapsuleSecretService
                    text: root.t("networkKeyringExplanation")
                }
                Action {
                    visible: root.timeCapsuleVerified && root.timeCapsuleSecretService
                    text: root.t("networkSaveCredential")
                    enabled: passwordField.text !== "" && !root.timeCapsuleBusy
                    onClicked: root.runTimeCapsule("save-credential")
                }
                Action {
                    visible: root.timeCapsuleSecretService
                    text: root.t("networkForgetCredential")
                    enabled: root.timeCapsuleUser.trim() !== "" && !root.timeCapsuleBusy
                    onClicked: root.runTimeCapsule("forget-credential")
                }
                Copy {
                    visible: root.timeCapsuleStatus !== ""
                    text: root.timeCapsuleStatus
                    color: theme.text
                }
            }
        }
        Action {
            text: root.t("networkCheckMounts")
            onClicked: root.run("mounts", {})
        }
    }

    Copy {
        visible: root.status !== ""
        text: root.status
        color: theme.text
    }
    Controls.CheckBox {
        visible: root.resultText !== ""
        text: root.t("networkDetails")
        checked: root.details
        onToggled: root.details = checked
        palette.highlight: theme.accent
        palette.windowText: theme.text
    }
    Controls.TextArea {
        visible: root.details && root.resultText !== ""
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        text: root.resultText
        color: theme.text
        wrapMode: TextEdit.Wrap
        background: Rectangle {
            color: theme.panelDeep
            radius: theme.radius
        }
    }
}
