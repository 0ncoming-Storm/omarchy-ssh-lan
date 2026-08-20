import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "linuxinthebox.ssh-lan"
    ipcTarget: "linuxinthebox.ssh-lan"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property string statusText: ""
    property string selectedHost: ""
    property int selectedIndex: -1
    property var servers: []
    property bool scanning: false
    property bool cursorActive: false
    property string scanError: ""
    property string savingHost: ""
    property var pendingHostSettings: null
    property bool hostEditorOpen: false
    property string editingHost: ""
    property bool settingsOpen: false
    property bool logsOpen: false
    property string logText: ""
    property string configuredRanges: setting("networks", "")

    function localPath(fileName) {
        var url = String(Qt.resolvedUrl(fileName))
        return url.indexOf("file://") === 0
            ? decodeURIComponent(url.substring(7))
            : url
    }

    readonly property string scanScript: localPath("scan.sh")
    readonly property string connectScript: localPath("connect.sh")
    readonly property string askpassScript: localPath("askpass.sh")
    readonly property string logPath: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "/tmp") + "/.cache")) + "/omarchy-ssh-lan/scan.log"
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property string defaultUser: Quickshell.env("USER") || ""

    function rangeTokens(raw) {
        var tokens = String(raw || "").split(/[\s,]+/)
        var result = []
        for (var i = 0; i < tokens.length; i++) {
            var token = tokens[i].trim()
            if (token !== "" && result.indexOf(token) === -1) result.push(token)
        }
        return result
    }

    function validRangeToken(token) {
        return /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/(?:[0-9]|[12][0-9]|3[0-2])$/.test(token)
    }

    function hostSettings(host) {
        var hosts = root.settings && root.settings.hosts
        var configured = hosts && hosts[host]
        if (!configured || typeof configured !== "object") return {}
        return configured
    }

    function discoveredName(host) {
        for (var i = 0; i < servers.length; i++) {
            if (servers[i].host === host && String(servers[i].name || "").trim() !== "")
                return String(servers[i].name).trim()
        }
        return ""
    }

    function hostName(host) {
        var name = String(hostSettings(host).name || "").trim()
        if (name !== "") return name
        var discovered = discoveredName(host)
        return discovered !== "" ? discovered : host
    }

    function hostUser(host) {
        var user = String(hostSettings(host).user || "").trim()
        return user !== "" ? user : root.defaultUser
    }

    function hostPort(host) {
        var value = parseInt(hostSettings(host).port)
        return isFinite(value) && value >= 1 && value <= 65535 ? value : 22
    }

    function persistHostSettings(host, values) {
        var hosts = {}
        var configuredHosts = root.settings && root.settings.hosts
        if (configuredHosts && typeof configuredHosts === "object") {
            for (var existingHost in configuredHosts) hosts[existingHost] = configuredHosts[existingHost]
        }
        hosts[host] = values
        persistSettings({ hosts: hosts })
    }

    function openHostEditor(host) {
        editingHost = host
        hostEditorOpen = true
        selectedHost = host
        selectedIndex = serverIndex(host)
        Qt.callLater(function() {
            hostNameField.text = hostName(host)
            hostUserField.text = hostUser(host)
            hostPortField.text = String(hostPort(host))
            hostPasswordField.text = ""
            hostNameField.forceActiveFocus()
        })
    }

    function closeHostEditor() {
        hostEditorOpen = false
        editingHost = ""
        hostPasswordField.text = ""
    }

    function saveHostEditor() {
        if (savingHost !== "" || editingHost === "") return
        var user = hostUserField.text.trim() || root.defaultUser
        var name = hostNameField.text.trim() || editingHost
        var port = parseInt(hostPortField.text.trim() || "22")
        if (!user) {
            statusText = "Enter a username for " + editingHost + "."
            return
        }
        if (!isFinite(port) || port < 1 || port > 65535) {
            statusText = "Enter a port from 1 to 65535."
            return
        }
        var values = { name: name, user: user, port: port }
        persistHostSettings(editingHost, values)
        if (hostPasswordField.text !== "") {
            savingHost = editingHost
            pendingHostSettings = values
            statusText = "Saving the password in the desktop keyring…"
            storeProc.command = [
                "secret-tool", "store", "--label=Omarchy SSH LAN password",
                "service", "omarchy-ssh-lan",
                "host", editingHost,
                "user", user,
                "port", String(port)
            ]
            storeProc.running = true
        } else {
            statusText = "Saved settings for " + name + "."
            closeHostEditor()
        }
    }

    function persistSettings(values) {
        var entry = { id: root.moduleName }
        for (var existing in root.settings) {
            if (existing !== "id") entry[existing] = root.settings[existing]
        }
        for (var key in values) entry[key] = values[key]
        root.settings = entry
        if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry)
    }

    function saveRanges() {
        var ranges = rangeTokens(rangesField.text)
        for (var i = 0; i < ranges.length; i++) {
            if (!validRangeToken(ranges[i])) {
                statusText = "Invalid range: " + ranges[i] + " (use IPv4 CIDR, /16 through /32)."
                return
            }
        }
        if (ranges.length === 0) {
            statusText = "Add at least one IPv4 CIDR range."
            return
        }
        configuredRanges = ranges.join("\n")
        persistSettings({ networks: configuredRanges })
        settingsOpen = false
        servers = []
        selectedHost = ""
        selectedIndex = -1
        statusText = ranges.length + " manual network range" + (ranges.length === 1 ? "" : "s") + " saved."
    }

    function loadLog() {
        logProc.running = false
        logProc.command = ["tail", "-n", "200", root.logPath]
        logProc.running = true
    }

    function toggleLog() {
        logsOpen = !logsOpen
        if (logsOpen) loadLog()
    }

    function scan() {
        if (scanProc.running) return
        var ranges = rangeTokens(configuredRanges)
        if (ranges.length === 0) {
            statusText = "No ranges configured. Open the gear and add one or more IPv4 CIDRs."
            settingsOpen = true
            return
        }
        scanning = true
        statusText = "Scanning configured network ranges…"
        scanError = ""
        servers = []
        selectedHost = ""
        selectedIndex = -1
        scanProc.command = ["bash", root.scanScript].concat(ranges)
        scanProc.running = true
    }

    function parseScan(raw) {
        var next = []
        var seen = {}
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var fields = lines[i].trim().split("\t")
            if (fields.length < 2 || !fields[0] || seen[fields[0]]) continue
            seen[fields[0]] = true
            next.push({ host: fields[0], route: fields[1], name: fields.length >= 3 ? fields.slice(2).join("\t").trim() : "" })
        }
        next.sort(function(a, b) { return a.host.localeCompare(b.host, undefined, { numeric: true }) })
        servers = next
        if (next.length === 0) statusText = "No SSH servers found."
        else statusText = next.length + " SSH server" + (next.length === 1 ? "" : "s") + " found."
    }

    function selectServer(server, index) {
        selectedHost = server.host
        selectedIndex = index
    }

    function serverIndex(host) {
        for (var i = 0; i < servers.length; i++) if (servers[i].host === host) return i
        return -1
    }

    function connectTo(server) {
        var user = hostUser(server.host)
        if (!user) {
            openHostEditor(server.host)
            statusText = "Enter a username for " + server.host + "."
            return
        }
        selectServer(server, serverIndex(server.host))
        // All values are separate exec arguments. connect.sh validates them
        // again before it invokes ssh, and the secret is read only in the
        // terminal process through SSH_ASKPASS.
        Quickshell.execDetached([
            "omarchy-launch-terminal", "bash", root.connectScript,
            user, server.host, String(hostPort(server.host)), root.askpassScript
        ])
        root.close()
    }

    function moveSelection(delta) {
        if (servers.length === 0) return
        selectedIndex = Math.max(0, Math.min(servers.length - 1,
            (selectedIndex < 0 ? 0 : selectedIndex) + delta))
        selectedHost = servers[selectedIndex].host
    }

    onOpenedChanged: if (opened) {
        scan()
        Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseScan(text)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.scanError = String(text || "").trim()
        }
        onExited: function(exitCode) {
            root.scanning = false
            if (exitCode !== 0 && root.servers.length === 0)
                root.statusText = root.scanError !== ""
                    ? root.scanError
                    : "Scan failed. Check that bash and nmap are available."
            if (root.logsOpen) Qt.callLater(root.loadLog)
        }
    }

    Process {
        id: logProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.logText = String(text || "No scan log yet.")
        }
    }

    Process {
        id: storeProc
        stdinEnabled: true
        onStarted: storeProc.write(hostPasswordField.text + "\n")
        onExited: function(exitCode) {
            var host = root.savingHost
            root.savingHost = ""
            root.pendingHostSettings = null
            hostPasswordField.text = ""
            if (exitCode === 0) {
                root.statusText = "Saved settings and password for " + root.hostName(host) + "."
                root.closeHostEditor()
            } else {
                root.statusText = "Settings saved, but the password could not be stored in Secret Service."
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(560))
        contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onMoveRequested: function(dx, dy) {
                if (dx !== 0) return
                if (!root.cursorActive) root.cursorActive = true
                root.moveSelection(dy === 0 ? 1 : dy)
            }
            onActivateRequested: {
                if (root.selectedIndex >= 0 && root.selectedIndex < root.servers.length)
                    root.connectTo(root.servers[root.selectedIndex])
            }
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            onTextKey: function(t) {
                if (t === "r" || t === "R") root.scan()
                else if ((t === "p" || t === "P") && root.selectedIndex >= 0)
                    root.openHostEditor(root.servers[root.selectedIndex].host)
            }
        }

        Flickable {
            id: panelFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: contentColumn
                width: panelFlick.width
                spacing: Style.space(12)

                PanelHero {
                    width: parent.width
                    title: "SSH LAN"
                    meta: root.scanning ? "NMAP SCAN IN PROGRESS" : "MANUAL NETWORK RANGES"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    iconComponent: Component {
                        Text {
                            text: "󰣀"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.display
                        }
                    }
                    trailingControl: Component {
                        PanelActionButton {
                            iconText: "󰒓"
                            tooltipText: "Configure network ranges"
                            foreground: root.foreground
                            onClicked: {
                                root.settingsOpen = !root.settingsOpen
                                if (root.settingsOpen) Qt.callLater(function() { rangesField.forceActiveFocus() })
                            }
                        }
                    }
                }

                Column {
                    visible: root.settingsOpen
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                        width: parent.width
                        text: "NETWORK RANGES"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                            width: parent.width
                            text: "One IPv4 CIDR per line. Only these ranges are scanned; /16 through /32 is allowed."
                            color: Qt.darker(root.foreground, 1.45)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                        }

                    TextArea {
                        id: rangesField
                        width: parent.width
                        height: Style.space(88)
                        text: root.configuredRanges
                        placeholderText: "192.168.1.0/24\n100.100.0.0/16"
                        color: root.foreground
                        placeholderTextColor: Qt.darker(root.foreground, 1.6)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        background: BorderSurface {
                            color: "transparent"
                            borderSpec: Border.controlSpec(rangesField.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
                            radius: Style.cornerRadius
                        }
                    }
                    Row {
                        spacing: Style.space(8)
                        Button {
                            text: "Save ranges"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: root.saveRanges()
                        }
                        Button {
                            text: "Cancel"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: root.settingsOpen = false
                        }
                        Button {
                            text: root.logsOpen ? "Hide log" : "View scan log"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: root.toggleLog()
                        }
                    }
                    Text {
                        visible: root.logsOpen
                        width: parent.width
                        text: root.logPath
                        color: Qt.darker(root.foreground, 1.65)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideMiddle
                    }
                    TextArea {
                        visible: root.logsOpen
                        width: parent.width
                        height: Style.space(170)
                        text: root.logText
                        readOnly: true
                        color: root.foreground
                        font.family: "monospace"
                        font.pixelSize: Style.font.caption
                        wrapMode: TextEdit.NoWrap
                        selectByMouse: true
                        background: BorderSurface {
                            color: "transparent"
                            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                            radius: Style.cornerRadius
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Style.space(8)
                    Button {
                        text: root.scanning ? "Scanning…" : "Rescan"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: !root.scanning
                        onClicked: root.scan()
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.defaultUser ? "Default user: " + root.defaultUser + " · port 22" : "Configure a username per host"
                        color: Qt.darker(root.foreground, 1.55)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: root.statusText !== ""
                    width: parent.width
                    text: root.statusText
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                }

                PanelSeparator { foreground: root.foreground }

                PanelSectionHeader {
                    text: "SSH SERVERS"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }

                Text {
                    visible: root.servers.length === 0 && !root.scanning
                    width: parent.width
                    text: root.configuredRanges === ""
                        ? "Configure ranges with the gear before scanning."
                        : "No port 22 hosts found in the configured ranges. Press Rescan or r."
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                }

                Repeater {
                    model: root.servers
                    Item {
                        required property var modelData
                        required property int index
                        width: contentColumn.width
                        implicitHeight: serverSurface.implicitHeight

                        CursorSurface {
                            id: serverSurface
                            anchors.left: parent.left
                            anchors.right: parent.right
                            implicitHeight: Style.space(52)
                            foreground: root.foreground
                            hasCursor: root.selectedIndex === index

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(10)
                                anchors.rightMargin: Style.space(6)
                                spacing: Style.space(8)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: root.hostName(modelData.host)
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.hostUser(modelData.host) + "@" + modelData.host + ":" + root.hostPort(modelData.host)
                                        color: Qt.darker(root.foreground, 1.55)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                PanelActionButton {
                                    Layout.preferredWidth: Style.space(26)
                                    Layout.preferredHeight: Style.space(26)
                                    iconText: "󰒓"
                                    tooltipText: "Edit host settings"
                                    foreground: root.foreground
                                    onClicked: root.openHostEditor(modelData.host)
                                }
                                Button {
                                    text: "Connect"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                    fontSize: Style.font.bodySmall
                                    active: root.selectedIndex === index
                                    onClicked: root.connectTo(modelData)
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.hostEditorOpen
                    width: parent.width
                    spacing: Style.space(8)
                    PanelSeparator { foreground: root.foreground }
                    PanelSectionHeader {
                        text: "HOST SETTINGS · " + root.editingHost
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }
                    TextField {
                        id: hostNameField
                        width: parent.width
                        foreground: root.foreground
                        font.family: root.fontFamily
                        placeholderText: "Name (defaults to address)"
                    }
                    RowLayout {
                        width: parent.width
                        spacing: Style.space(8)
                        TextField {
                            id: hostUserField
                            Layout.fillWidth: true
                            foreground: root.foreground
                            font.family: root.fontFamily
                            placeholderText: root.defaultUser || "Username"
                        }
                        TextField {
                            id: hostPortField
                            Layout.preferredWidth: Style.space(76)
                            foreground: root.foreground
                            font.family: root.fontFamily
                            placeholderText: "22"
                            inputMethodHints: Qt.ImhDigitsOnly
                        }
                    }
                    TextField {
                        id: hostPasswordField
                        width: parent.width
                        foreground: root.foreground
                        font.family: root.fontFamily
                        placeholderText: "Password (leave blank to keep saved password)"
                        password: true
                        enabled: root.savingHost === ""
                    }
                    Row {
                        spacing: Style.space(8)
                        Button {
                            text: root.savingHost !== "" ? "Saving…" : "Save host"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            enabled: root.savingHost === ""
                            onClicked: root.saveHostEditor()
                        }
                        Button {
                            text: "Cancel"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            enabled: root.savingHost === ""
                            onClicked: root.closeHostEditor()
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Only saved manual ranges are scanned. First-time hosts offer ssh-copy-id after the first successful session."
                    color: Qt.darker(root.foreground, 1.65)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
