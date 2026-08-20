import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "linuxinthebox.ssh-lan"

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.settings = root.settings
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    function open() {
        if (panelLoader.item) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function toggle() {
        if (panelLoader.item) panelLoader.item.toggle()
    }

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("SshLan.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰣀"
        tooltipText: "SSH LAN"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.RightButton && panelLoader.item) panelLoader.item.scan()
            else root.toggle()
        }
    }
}
