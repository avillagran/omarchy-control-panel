import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "desktop"

Window {
    id: window
    width: captureWidth
    height: 920
    visible: true
    color: "#1a1b26"
    QtObject {
        id: mockCore
        property string uiLang: "en"
        function t(lang, key) {
            return translations[lang][key] || key;
        }
    }
    Rectangle {
        id: captureRoot
        color: window.color
        anchors.fill: parent
        ScrollView {
            anchors.fill: parent
            anchors.margins: 24
            contentWidth: availableWidth
            BackupPage {
                id: page
                width: parent.width
                height: implicitHeight
                core: mockCore
                helperPath: "/forbidden/helper"
                connectionPath: "/forbidden/connection"
                destinationKind: "timecapsule"
            }
        }
    }
    Timer {
        interval: 500
        running: true
        onTriggered: captureRoot.grabToImage(function (result) {
            if (!result.saveToFile(outputDir + "/destination-" + captureWidth + ".png"))
                Qt.exit(2);
            page.step = 1;
            second.start();
        })
    }
    Timer {
        id: second
        interval: 500
        onTriggered: captureRoot.grabToImage(function (result) {
            if (!result.saveToFile(outputDir + "/timecapsule-" + captureWidth + ".png"))
                Qt.exit(3);
            Qt.quit();
        })
    }
}
