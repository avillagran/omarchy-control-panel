pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "BackupModel.js" as BackupModel

ColumnLayout {
    id: root
    required property var core
    property int step: 0
    property string intent: "backup"
    property string destinationKind: ""
    property var destination: ""
    property bool verified: false
    property bool manualHost: false
    property string host: ""
    property var devices: []
    property var folders: []
    property var localDevices: []
    property bool checkedFolders: false
    property bool connectionOpened: false
    readonly property string connectionStage: BackupModel.connectionStage(host, connectionOpened, folders.length > 0, verified)
    property bool configurations: true
    property bool files: false
    property bool encrypted: false
    property string recipient: ""
    property string recoveryKey: ""
    property string pathsText: ""
    property string target: ""
    property string identityFile: ""
    property var snapshots: []
    property var selectedSnapshot: null
    property bool historyLoaded: false
    property bool busy: false
    property string action: ""
    property bool connectionJob: false
    property string pendingJson: ""
    property var plannedRequest: null
    property var planResult: null
    property string status: ""
    property string resultText: ""
    property bool failed: false
    property bool completed: false
    property bool details: false
    property string dialogPurpose: "destination"
    // Qt.resolvedUrl cannot escape Quickshell's virtual desktop/ config root.
    // Process arguments need filesystem paths, not intercepted QML URLs.
    property string helperPath: Quickshell.shellDir + "/../bin/control-panel-backup"
    property string connectionPath: Quickshell.shellDir + "/../bin/backup-connection"
    readonly property string backupJson: JSON.stringify(requestFor("plan"))
    readonly property string restoreJson: JSON.stringify(requestFor("restore"))
    readonly property bool canContinue: BackupModel.wizardCanContinue(step, {
        intent: intent,
        destinationKind: destinationKind,
        destination: destination,
        verified: verified,
        configurations: configurations,
        files: files,
        snapshot: selectedSnapshot ? selectedSnapshot.id : "",
        target: target,
        encrypted: !!(selectedSnapshot && selectedSnapshot.encrypted),
        identityFile: identityFile
    })
    spacing: theme.padding
    AppTheme {
        id: theme
    }
    function t(key) {
        return core.t(core.uiLang, key);
    }
    function localPath(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""));
    }
    function selectNetworkDevice(device) {
        if (!device)
            return;
        var protocols = device.protocols || [];
        destinationKind = device.timeCapsule ? "timecapsule" : (protocols.indexOf("smb") >= 0 ? "smb" : (protocols.indexOf("sftp") >= 0 ? "sftp" : "smb"));
        host = device.hostname || device.ip || "";
        if (destinationKind === "timecapsule") {
            var selected = device.selectedDestination;
            if (selected && selected.savedCredential === true) {
                destination = selected;
                verified = true;
                encrypted = true;
            } else {
                destination = "";
                verified = false;
            }
        }
    }
    Connections {
        target: root.core
        ignoreUnknownSignals: true
        function onSelectedNetworkDeviceChanged() {
            root.selectNetworkDevice(root.core.selectedNetworkDevice);
        }
    }
    Component.onCompleted: selectNetworkDevice(core.selectedNetworkDevice)
    function requestFor(job) {
        return BackupModel.request({
            destination: destination,
            transport: destinationKind === "timecapsule" ? "timecapsule" : "local",
            configurations: configurations,
            files: files,
            pathsText: pathsText,
            encrypted: job === "restore" ? !!(selectedSnapshot && selectedSnapshot.encrypted) : encrypted,
            ageRecipient: recipient,
            snapshot: selectedSnapshot ? selectedSnapshot.id : "",
            target: target,
            identityFile: identityFile
        }, job);
    }
    onBackupJsonChanged: {
        planResult = null;
        plannedRequest = null;
        completed = false;
    }
    onRestoreJsonChanged: {
        restoreConfirmation.checked = false;
        completed = false;
    }
    onDestinationChanged: {
        verified = false;
        snapshots = [];
        selectedSnapshot = null;
        historyLoaded = false;
    }
    onDestinationKindChanged: {
        connectionOpened = false;
        destination = "";
        verified = false;
        host = "";
        devices = [];
        folders = [];
        localDevices = [];
        checkedFolders = false;
        manualHost = false;
        if (destinationKind === "local")
            Qt.callLater(function () { root.connectJob("local-devices"); });
    }
    onHostChanged: {
        connectionOpened = false;
        destination = "";
        verified = false;
        folders = [];
        checkedFolders = false;
    }
    function start(job, request, connection) {
        if (busy)
            return;
        action = job;
        connectionJob = connection;
        pendingJson = JSON.stringify(request);
        busy = true;
        failed = false;
        status = t("backupRunning");
        resultText = "";
        helper.stdinEnabled = true;
        helper.command = ["python3", connection ? connectionPath : helperPath, job];
        helper.running = true;
    }
    function connectJob(job, value) {
        var payload = {
            transport: destinationKind,
            host: host
        };
        if (job === "verify") {
            verified = false;
            payload.path = value || destination;
        }
        if (job === "mount")
            payload.device = value;
        start(job, payload, true);
    }
    function runJob(job) {
        if (busy)
            return;
        var request = requestFor(job);
        if ((job === "plan" || job === "backup") && encrypted && recoveryKey && !BackupModel.safeRecoveryKey(recoveryKey, typeof destination === "string" ? destination : "")) {
            failed = true;
            status = t("backupKeyOutside");
            return;
        }
        var error = BackupModel.validate(request, job);
        if (error) {
            failed = true;
            status = t(error);
            return;
        }
        if (job !== "capabilities" && !verified)
            return;
        if (job === "backup" && (step !== 3 || completed || !BackupModel.canConfirm(planResult, plannedRequest, request)))
            return;
        if (job === "restore" && (step !== 3 || completed || !selectedSnapshot || !restoreConfirmation.checked))
            return;
        if (job === "plan") {
            plannedRequest = request;
            planResult = null;
        }
        if (job === "history") {
            snapshots = [];
            selectedSnapshot = null;
            historyLoaded = false;
        }
        start(job, request, false);
    }
    function finish(text, exitCode, diagnostic) {
        var result = BackupModel.parseResponse(text, exitCode);
        if (!result.ok && diagnostic)
            result.diagnostic = diagnostic;
        resultText = JSON.stringify(result, null, 2);
        failed = !result.ok;
        status = result.ok ? t("backupCompleted") : t("backupFailed");
        if (connectionJob && result.ok) {
            if (action === "discover") {
                devices = result.devices || [];
                manualHost = devices.length === 0;
                status = t(devices.length ? "backupDevicesFound" : "backupNoDevices");
            }
            if (action === "connect") {
                connectionOpened = result.opened === true;
                status = t("backupOpenedNotConnected");
            }
            if (action === "folders") {
                folders = result.folders || [];
                checkedFolders = true;
                status = t(folders.length ? "backupMountsFound" : "backupNoMounts");
            }
            if (action === "local-devices") {
                localDevices = result.devices || [];
                status = t(localDevices.length ? "backupLocalDevicesFound" : "backupNoLocalDevices");
            }
            if (action === "mount") {
                status = t("backupDeviceMounted");
                Qt.callLater(function () { root.connectJob("verify", result.destination); });
            }
            if (action === "verify") {
                if (result.transport === "local" && BackupModel.absolutePath(result.destination)) {
                    destination = result.destination;
                    verified = true;
                    status = t("backupFolderVerified");
                } else {
                    failed = true;
                    status = t("backupChooseDestination");
                }
            }
        } else if (!connectionJob) {
            if (action === "plan") {
                planResult = result;
                if (result.ok && JSON.stringify(plannedRequest) === backupJson)
                    step = 3;
            }
            if (action === "history" && result.ok) {
                snapshots = result.snapshots || [];
                historyLoaded = true;
            }
            if (action === "create-key" && result.ok) {
                recipient = result.ageRecipient || "";
                recoveryKey = result.identityFile || "";
                status = t("backupKeepKey");
            }
            if (action === "backup" || action === "restore") {
                planResult = null;
                restoreConfirmation.checked = false;
                completed = result.ok;
                status = t(result.ok ? (action === "backup" ? "backupSaved" : "backupRecovered") : "backupFailed");
            }
        }
        if (result.missing && result.missing.length)
            status += "\n" + t("backupInstallHint") + " " + (result.missingPackages || result.missing).join(", ");
        if (!result.ok && result.error)
            status += "\n" + (connectionJob ? t(BackupModel.connectionErrorKey(result.reason || result.error)) : result.error);
        busy = false;
    }
    Process {
        id: helper
        stdout: StdioCollector {
            id: helperOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: helperError
            waitForEnd: true
        }
        // Scoped compatibility wrapper: false flushes stdin and closes its channel.
        function closeWriteChannel() {
            stdinEnabled = false;
        }
        onStarted: {
            write(root.pendingJson + "\n");
            closeWriteChannel();
        }
        onExited: function (exitCode, exitStatus) {
            root.finish(helperOutput.text, exitStatus === 0 ? exitCode : -1, helperError.text);
        }
        onRunningChanged: {
            if (!running && root.busy) {
                root.failed = true;
                root.status = root.t("backupFailedStart");
                root.busy = false;
            }
        }
    }
    FolderDialog {
        id: folderDialog
        title: root.t(root.dialogPurpose === "target" ? "backupChooseStaging" : "backupChooseFolder")
        onAccepted: {
            if (root.dialogPurpose === "target")
                root.target = root.localPath(selectedFolder);
            else {
                var url = selectedFolder.toString();
                root.connectJob("verify", url.indexOf("file://") === 0 ? root.localPath(url) : url);
            }
        }
    }
    FileDialog {
        id: identityDialog
        title: root.t("backupChooseKeyFile")
        fileMode: FileDialog.OpenFile
        onAccepted: root.identityFile = root.localPath(selectedFile)
    }
    FileDialog {
        id: createKeyDialog
        title: root.t("backupCreateKey")
        fileMode: FileDialog.SaveFile
        nameFilters: [root.t("backupKeyFilter")]
        defaultSuffix: "key"
        onAccepted: {
            var path = root.localPath(selectedFile);
            if (!BackupModel.safeRecoveryKey(path, root.destination)) {
                root.failed = true;
                root.status = root.t("backupKeyOutside");
                return;
            }
            root.start("create-key", {
                identityFile: path
            }, false);
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
    component Heading: Copy {
        color: theme.text
        font.pixelSize: theme.body
        font.bold: true
    }
    component Field: Controls.TextField {
        Layout.fillWidth: true
        enabled: !root.busy
        color: theme.text
        placeholderTextColor: theme.textMuted
        font.family: theme.fontUi
        padding: theme.padding
        Accessible.name: placeholderText
        background: Rectangle {
            color: theme.panelDeep
            radius: theme.radius
            border.color: parent.activeFocus ? theme.accent : theme.border
        }
    }
    component Action: Controls.Button {
        id: button
        property bool primary: false
        Layout.fillWidth: true
        enabled: !root.busy
        padding: theme.padding
        font.family: theme.fontUi
        font.pixelSize: theme.body
        contentItem: Text {
            text: button.text
            textFormat: Text.PlainText
            font: button.font
            color: button.enabled ? theme.text : theme.textMuted
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        background: Rectangle {
            radius: theme.radius
            color: button.primary || button.checked ? theme.accentSoft : (button.hovered ? theme.panelAlt : theme.panel)
            border.color: button.activeFocus || button.primary || button.checked ? theme.accent : theme.border
            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
        }
    }
    component Check: Controls.CheckBox {
        id: check
        indicator: Rectangle {
            implicitWidth: 18
            implicitHeight: 18
            x: check.leftPadding
            y: (check.height - height) / 2
            radius: 4
            color: check.checked ? theme.accentSoft : theme.panelDeep
            border.color: check.activeFocus || check.checked ? theme.accent : theme.border
            Text {
                anchors.centerIn: parent
                text: check.checked ? "✓" : ""
                color: theme.text
            }
        }
        Layout.fillWidth: true
        enabled: !root.busy
        contentItem: Text {
            text: check.text
            textFormat: Text.PlainText
            color: theme.text
            font.family: theme.fontUi
            font.pixelSize: theme.body
            wrapMode: Text.Wrap
            leftPadding: check.indicator.width + check.spacing
        }
        palette.highlight: theme.accent
    }
    Heading {
        text: root.t("backupWizardTitle")
    }
    Copy {
        text: root.t("backupStep") + " " + (root.step + 1) + " / 4 · " + root.t(["backupStart", "backupConnection", root.intent === "backup" ? "backupScope" : "backupSelectSnapshot", "backupReview"][root.step])
    }
    ColumnLayout {
        visible: root.step === 0
        Layout.fillWidth: true
        spacing: theme.padding
        Heading {
            text: root.t("backupIntent")
        }
        RowLayout {
            Layout.fillWidth: true
            Action {
                text: root.t("backupIntentBackup")
                checked: root.intent === "backup"
                onClicked: root.intent = "backup"
            }
            Action {
                text: root.t("backupIntentRestore")
                checked: root.intent === "restore"
                onClicked: root.intent = "restore"
            }
        }
        Heading {
            text: root.t("backupDestination")
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 700 ? 1 : 2
            Action {
                text: root.t("backupLocal")
                checked: root.destinationKind === "local"
                onClicked: root.destinationKind = "local"
            }
            Action {
                text: root.core.selectedNetworkDevice
                    ? root.t("backupSelectedNetworkDevice") + "\n" + root.core.selectedNetworkDevice.name + " · " + root.core.selectedNetworkDevice.ip
                    : root.t("backupNetworkDestination")
                checked: root.destinationKind !== "" && root.destinationKind !== "local"
                onClicked: {
                    if (root.core.selectedNetworkDevice)
                        root.selectNetworkDevice(root.core.selectedNetworkDevice);
                    else
                        root.core.currentTab = 5;
                }
            }
        }
        Action {
            text: root.t("backupChooseFromNetworkDevices")
            onClicked: root.core.currentTab = 5
        }
        Copy {
            text: root.t("backupManualOnly")
        }
    }
    ColumnLayout {
        visible: root.step === 1
        Layout.fillWidth: true
        spacing: theme.padding
        Heading {
            text: root.t("backupConnection")
        }
        Copy {
            text: root.t(root.destinationKind === "local" ? "backupDiskHelp" : (root.destinationKind === "timecapsule" ? "backupTimeCapsuleDirectHelp" : "backupNativeHelp"))
        }
        ColumnLayout {
            visible: root.destinationKind !== "local"
            Layout.fillWidth: true
            Copy {
                text: root.core.selectedNetworkDevice
                    ? root.t("backupSelectedNetworkDevice") + ": " + root.core.selectedNetworkDevice.name + " · " + root.core.selectedNetworkDevice.ip
                    : root.t("backupChooseNetworkDevice")
                color: theme.text
            }
            Copy {
                visible: !!root.core.selectedNetworkDevice && root.core.selectedNetworkDevice.legacySmb === true
                text: root.t("networkLegacyWarning")
                color: theme.text
            }
            Action {
                text: root.t("backupChooseFromNetworkDevices")
                onClicked: root.core.currentTab = 5
            }
            Action {
                visible: !!root.core.selectedNetworkDevice && root.destinationKind !== "timecapsule"
                text: root.t("backupCheckConnection")
                onClicked: root.connectJob("folders")
            }
            Copy {
                visible: root.checkedFolders && root.folders.length === 0
                text: root.t("backupNoMounts")
            }
            Repeater {
                model: root.destinationKind === "timecapsule" ? [] : root.folders
                delegate: Action {
                    required property var modelData
                    text: modelData.name + "\n" + modelData.path
                    onClicked: {
                        root.destination = modelData.path;
                        root.connectJob("verify", modelData.path);
                    }
                }
            }
        }
        Action {
            visible: root.destinationKind === "local" || (!!root.core.selectedNetworkDevice && root.destinationKind !== "timecapsule")
            text: root.t("backupChooseFolder")
            onClicked: {
                root.dialogPurpose = "destination";
                folderDialog.open();
            }
        }
        ColumnLayout {
            visible: root.destinationKind === "local"
            Layout.fillWidth: true
            spacing: theme.gap
            Action {
                text: root.t("backupDetectDevices")
                onClicked: root.connectJob("local-devices")
            }
            Copy {
                visible: root.localDevices.length === 0
                text: root.t("backupNoLocalDevices")
            }
            Repeater {
                model: root.localDevices
                delegate: Action {
                    required property var modelData
                    text: modelData.name + " · " + modelData.size + " · "
                        + (modelData.mounted ? root.t("backupDeviceMounted") : root.t("backupMountDevice"))
                    checked: modelData.mounted && root.destination === modelData.mountpoint
                    onClicked: {
                        if (modelData.mounted)
                            root.connectJob("verify", modelData.mountpoint);
                        else
                            root.connectJob("mount", modelData.device);
                    }
                }
            }
        }
        Copy {
            visible: root.destinationKind === "local" || root.destinationKind === "timecapsule" || root.destination !== ""
            text: root.destinationKind === "timecapsule" ? (root.verified ? root.core.selectedNetworkDevice.name + " · " + root.core.selectedNetworkDevice.selectedShare : root.t("backupTimeCapsuleCredentialRequired")) : (root.destination || root.t("backupNoFolder"))
            color: root.verified ? theme.text : theme.textMuted
        }
        Copy {
            visible: root.verified
            text: root.t("backupFolderVerified")
        }
    }
    ColumnLayout {
        visible: root.step === 2 && root.intent === "backup"
        Layout.fillWidth: true
        spacing: theme.padding
        Heading {
            text: root.t("backupScope")
        }
        Action {
            text: root.t("backupConfigurations")
            checked: root.configurations
            onClicked: root.configurations = !root.configurations
        }
        Action {
            text: root.t("backupFiles")
            checked: root.files
            onClicked: root.files = !root.files
        }
        Copy {
            visible: root.files
            text: root.t("backupFilesDefault")
        }
        Check {
            text: root.t("backupEncrypted")
            checked: root.encrypted
            enabled: root.destinationKind !== "timecapsule"
            onToggled: root.encrypted = root.destinationKind === "timecapsule" ? true : checked
        }
        Copy {
            visible: root.destinationKind === "timecapsule"
            text: root.t("backupTimeCapsuleEncryptionRequired")
        }
        ColumnLayout {
            visible: root.encrypted
            Layout.fillWidth: true
            Copy {
                text: root.t("backupEncryptionSimple")
            }
            Action {
                text: root.t("backupCreateKey")
                onClicked: createKeyDialog.open()
            }
            Copy {
                visible: root.recoveryKey !== ""
                text: root.t("backupKeepKey") + "\n" + root.recoveryKey
                color: theme.text
            }
            Copy {
                visible: root.recipient !== ""
                text: root.t("backupKeyReady")
            }
        }
        Check {
            id: advanced
            text: root.t("backupAdvanced")
        }
        ColumnLayout {
            visible: advanced.checked
            Layout.fillWidth: true
            Copy {
                visible: root.files
                text: root.t("backupPathsHint")
            }
            Controls.TextArea {
                visible: root.files
                Layout.fillWidth: true
                enabled: !root.busy
                text: root.pathsText
                onTextChanged: root.pathsText = text
                placeholderText: root.t("backupRelativePlaceholder")
                Accessible.name: root.t("backupPathsHint")
                color: theme.text
                placeholderTextColor: theme.textMuted
                wrapMode: TextEdit.Wrap
                background: Rectangle {
                    color: theme.panelDeep
                    radius: theme.radius
                }
            }
            Field {
                visible: root.encrypted
                text: root.recipient
                onTextEdited: root.recipient = text
                placeholderText: root.t("backupRecipient")
            }
            Copy {
                visible: root.encrypted
                text: root.t("backupEncryptionHint")
            }
            Action {
                text: root.t("backupCapabilities")
                onClicked: root.runJob("capabilities")
            }
        }
    }
    ColumnLayout {
        visible: root.step === 2 && root.intent === "restore"
        Layout.fillWidth: true
        spacing: theme.padding
        Heading {
            text: root.t("backupSelectSnapshot")
        }
        Action {
            text: root.t("backupHistory")
            onClicked: root.runJob("history")
        }
        Copy {
            visible: root.historyLoaded && root.snapshots.length === 0
            text: root.t("backupNoSnapshots")
        }
        Repeater {
            model: root.snapshots
            delegate: Action {
                required property var modelData
                text: modelData.id + (modelData.encrypted ? " · " + root.t("backupEncryptedLabel") : "")
                checked: root.selectedSnapshot === modelData
                onClicked: root.selectedSnapshot = modelData
            }
        }
        Copy {
            text: root.t("backupRestoreHint")
        }
        Action {
            text: root.t("backupChooseStaging")
            onClicked: {
                root.dialogPurpose = "target";
                folderDialog.open();
            }
        }
        Copy {
            text: root.target || root.t("backupNoFolder")
        }
        Action {
            visible: !!(root.selectedSnapshot && root.selectedSnapshot.encrypted)
            text: root.t("backupChooseKeyFile")
            onClicked: identityDialog.open()
        }
        Copy {
            visible: !!(root.selectedSnapshot && root.selectedSnapshot.encrypted)
            text: root.identityFile
        }
    }
    ColumnLayout {
        visible: root.step === 3
        Layout.fillWidth: true
        spacing: theme.padding
        Heading {
            text: root.t("backupReview")
        }
        Copy {
            text: root.t("backupDestination") + ": " + root.destination
        }
        Copy {
            visible: root.intent === "backup"
            text: root.t("backupScope") + ": " + [root.configurations ? root.t("backupConfigLabel") : "", root.files ? root.t("backupFilesLabel") : ""].filter(function (v) {
                return v !== "";
            }).join(" + ")
        }
        Copy {
            text: root.t((root.intent === "backup" ? root.encrypted : !!(root.selectedSnapshot && root.selectedSnapshot.encrypted)) ? "backupEncryptedLabel" : "backupUnencryptedLabel")
        }
        Copy {
            visible: root.intent === "backup"
            text: root.t("backupReviewCaution")
        }
        Repeater {
            model: root.intent === "backup" && root.planResult ? (root.planResult.warnings || []) : []
            delegate: Copy {
                required property var modelData
                text: root.t("backupWarning") + ": " + modelData
            }
        }
        Copy {
            visible: root.intent === "backup" && !!root.planResult && !!root.planResult.missing && root.planResult.missing.length > 0
            text: root.t("backupInstallHint") + " " + (root.planResult && root.planResult.missing ? root.planResult.missing.join(", ") : "")
        }
        Copy {
            visible: root.intent === "restore"
            text: (root.selectedSnapshot ? root.selectedSnapshot.id : "") + "\n" + root.t("backupStagingLabel") + ": " + root.target
        }
        Check {
            id: restoreConfirmation
            visible: root.intent === "restore" && !root.completed
            text: root.t("backupRestoreConfirm")
        }
        Action {
            visible: root.intent === "backup" && !root.completed
            primary: true
            text: root.t("backupNow")
            enabled: !root.busy && BackupModel.canConfirm(root.planResult, root.plannedRequest, JSON.parse(root.backupJson))
            onClicked: root.runJob("backup")
        }
        Action {
            visible: root.intent === "restore" && !root.completed
            primary: true
            text: root.t("backupRestore")
            enabled: !root.busy && restoreConfirmation.checked
            onClicked: root.runJob("restore")
        }
        Action {
            visible: root.completed
            text: root.t("backupStartAgain")
            onClicked: {
                root.step = 0;
                root.completed = false;
                root.status = "";
                root.planResult = null;
            }
        }
    }
    Heading {
        visible: root.status !== ""
        text: root.status
    }
    Controls.BusyIndicator {
        visible: root.busy
        running: root.busy
        Layout.alignment: Qt.AlignHCenter
    }
    Check {
        visible: root.resultText !== ""
        text: root.t("backupDetails")
        checked: root.details
        onToggled: root.details = checked
    }
    Controls.TextArea {
        visible: root.details && root.resultText !== ""
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        text: root.resultText
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        color: theme.text
        background: Rectangle {
            color: theme.panelDeep
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Action {
            visible: root.step > 0
            text: root.t("backupBack")
            onClicked: {
                root.step--;
                root.status = "";
                root.details = false;
            }
        }
        Action {
            visible: root.step < 3
            primary: true
            text: root.t(root.step === 2 ? (root.intent === "backup" ? "backupReviewBackup" : "backupReviewRestore") : "backupContinue")
            enabled: !root.busy && root.canContinue
            onClicked: {
                root.status = "";
                root.details = false;
                if (root.step === 2 && root.intent === "backup")
                    root.runJob("plan");
                else
                    root.step++;
            }
        }
    }
}
