import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// julia-shell's QML client. Julia owns profiles, pins, revisions, and policy;
// this file owns only presentation and ephemeral interaction state.
Scope {
    id: root

    property var projection: ({
        "schema": 1,
        "statusbar": { "schema": 1, "health": "disconnected", "profile": "personal", "revision": 0,
                        "compositor": "unknown", "outputs": 0, "workspaces": 0, "pinned": 0,
                        "running": 0, "focused": 0, "urgent": 0, "degraded": [] },
        "revision": 0,
        "health": "disconnected",
        "service": "offline",
        "profile": "personal",
        "dock": { "edge": "bottom", "autohide": "never", "exclusive_zone": 0 },
        "items": [],
        "applications": [],
        "workspaces": [],
        "outputs": []
    })
    property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ((Quickshell.env("TMPDIR") || "/tmp") + "/julia-shell-runtime")
    property string socketPath: root.runtimeDir + "/julia-shell/julia-shell.sock"
    property string pendingMessage: ""
    property bool requestInFlight: false
    property var cycleIndex: ({})
    property int requestSerial: 0
    property bool launcherOpen: false
    property bool controlCenterOpen: false
    property bool notificationCenterOpen: false
    property string searchText: ""
    property string lastError: ""
    property string clockText: ""
    property string autohide: "never"
    property bool reducedMotion: Quickshell.env("JULIA_SHELL_REDUCED_MOTION") === "1"
    property color background: "#e9161c2b"
    property color surface: "#f01c2638"
    property color surfaceBright: "#f52b3a50"
    property color surfaceMuted: "#a52b3a50"
    property color textPrimary: "#f3f6fb"
    property color textSecondary: "#b8c5d5"
    property color accent: "#93d7ff"
    property color accentStrong: "#2f9bd4"
    property color danger: "#ffb4ab"
    property bool bottomEdge: !root.projection.dock || root.projection.dock.edge !== "top"
    property bool hasBattery: UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery

    function refreshState() {
        request("state.get", { "profile": root.projection.profile || "personal" })
    }

    function request(method, params) {
        if (root.pendingMessage !== "" || root.requestInFlight)
            return
        root.requestSerial += 1
        root.requestInFlight = true
        root.pendingMessage = JSON.stringify({
            "v": 1,
            "id": "qml-" + root.requestSerial,
            "method": method,
            "params": params || {}
        }) + "\n"
        daemonSocket.path = root.socketPath
        daemonSocket.connected = true
    }

    function receive(raw) {
        var message
        try {
            message = JSON.parse(raw)
        } catch (error) {
            root.lastError = "daemon returned malformed JSON"
            root.requestInFlight = false
            return
        }
        if (message.event === "state.changed") {
            root.refreshState()
            return
        }
        if (!message.ok) {
            root.lastError = message.error && message.error.message ? message.error.message : "daemon request failed"
            root.requestInFlight = false
            return
        }
        if (message.result && message.result.schema === 1) {
            root.projection = message.result
            if (message.result.dock && message.result.dock.autohide)
                root.autohide = message.result.dock.autohide
        }
        root.requestInFlight = false
        root.lastError = ""
    }

    function itemWindow(item) {
        if (!item || !item.instances || !item.instances.length)
            return null
        var index = root.cycleIndex[item.id] || 0
        root.cycleIndex[item.id] = (index + 1) % item.instances.length
        return item.instances[index]
    }

    function activateItem(item) {
        var instance = itemWindow(item)
        if (instance)
            request("apps.focus", { "window_id": instance.id })
        else if (item && item.desktop_id)
            request("apps.launch", { "desktop_id": item.desktop_id })
    }

    function togglePin(item) {
        if (!item || !item.desktop_id)
            return
        if (item.pinned)
            request("pins.unpin", { "profile": root.projection.profile, "desktop_id": item.desktop_id, "if_revision": root.projection.revision })
        else
            request("pins.pin", { "profile": root.projection.profile, "desktop_id": item.desktop_id, "if_revision": root.projection.revision })
    }

    function filteredApplications() {
        var query = root.searchText.toLowerCase().trim()
        var applications = root.projection.applications || []
        if (!query)
            return applications.slice(0, 36)
        return applications.filter(function (application) {
            return (application.label || "").toLowerCase().indexOf(query) !== -1 ||
                   (application.generic_name || "").toLowerCase().indexOf(query) !== -1 ||
                   (application.desktop_id || "").toLowerCase().indexOf(query) !== -1
        }).slice(0, 36)
    }

    function launchApplication(application) {
        root.launcherOpen = false
        root.searchText = ""
        request("apps.launch", { "desktop_id": application.desktop_id })
    }

    function iconSource(icon, fallback) {
        if (icon && icon.indexOf("/") === 0)
            return icon
        return Quickshell.iconPath(icon || fallback, fallback)
    }

    function updateClock() {
        var now = new Date()
        root.clockText = Qt.formatDateTime(now, "ddd, MMM d  •  HH:mm")
    }

    Component.onCompleted: {
        updateClock()
        refreshState()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.updateClock()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refreshState()
    }

    Socket {
        id: daemonSocket
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                root.receive(data)
                daemonSocket.connected = false
            }
        }
        onConnectedChanged: {
            if (connected && root.pendingMessage !== "") {
                var message = root.pendingMessage
                root.pendingMessage = ""
                write(message)
                flush()
            }
        }
        onError: function (error) {
            root.lastError = "julia-shelld is unavailable"
            root.pendingMessage = ""
            root.requestInFlight = false
            daemonSocket.connected = false
        }
    }

    NotificationServer {
        id: notificationServer
        keepOnReload: true
        persistenceSupported: true
        bodyMarkupSupported: false
        onNotification: function (notification) {
            notification.tracked = true
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData
            aboveWindows: true
            focusable: root.launcherOpen || root.controlCenterOpen || root.notificationCenterOpen
            color: "transparent"
            implicitHeight: (root.launcherOpen || root.controlCenterOpen || root.notificationCenterOpen) ? 570 : 84
            exclusiveZone: root.projection.dock && root.projection.dock.exclusive_zone !== undefined ? root.projection.dock.exclusive_zone : 0
            anchors {
                left: true
                right: true
                top: !root.bottomEdge
                bottom: root.bottomEdge
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    root.launcherOpen = false
                    root.controlCenterOpen = false
                    root.notificationCenterOpen = false
                    event.accepted = true
                } else if (root.launcherOpen && event.key === Qt.Key_Return) {
                    var results = root.filteredApplications()
                    if (results.length)
                        root.launchApplication(results[0])
                    event.accepted = true
                }
            }

            Item {
                id: windowContent
                anchors.fill: parent

                Rectangle {
                    id: utilityPane
                    visible: root.launcherOpen || root.controlCenterOpen || root.notificationCenterOpen
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    height: visible ? 470 : 0
                    anchors.bottom: root.bottomEdge ? dockBar.top : undefined
                    anchors.top: root.bottomEdge ? undefined : dockBar.bottom
                    color: root.background
                    radius: 28
                    border.width: 1
                    border.color: "#39516b"

                    Loader {
                        anchors.fill: parent
                        active: root.launcherOpen
                        sourceComponent: launcherComponent
                    }
                    Loader {
                        anchors.fill: parent
                        active: root.controlCenterOpen
                        sourceComponent: controlCenterComponent
                    }
                    Loader {
                        anchors.fill: parent
                        active: root.notificationCenterOpen
                        sourceComponent: notificationComponent
                    }
                }

                Rectangle {
                    id: dockBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    height: 68
                    anchors.bottom: root.bottomEdge ? parent.bottom : undefined
                    anchors.top: root.bottomEdge ? undefined : parent.top
                    color: root.surface
                    radius: 22
                    border.width: 1
                    border.color: "#435a72"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 16
                            color: root.launcherOpen ? root.accentStrong : root.surfaceBright
                            Accessible.name: "Open application launcher"
                            Text { anchors.centerIn: parent; text: "⌕"; color: root.textPrimary; font.pixelSize: 27 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.launcherOpen = !root.launcherOpen
                                    root.controlCenterOpen = false
                                    root.notificationCenterOpen = false
                                }
                            }
                        }

                        RowLayout {
                            spacing: 4
                            Layout.preferredWidth: Math.min(220, implicitWidth)
                            Repeater {
                                model: (root.projection.workspaces || []).slice(0, 6)
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: 10
                                    color: index === 0 ? root.accentStrong : root.surfaceMuted
                                    Text { anchors.centerIn: parent; text: modelData; color: root.textPrimary; font.pixelSize: 12; font.bold: true }
                                    Accessible.name: "Workspace " + modelData
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            id: appRow
                            spacing: 5
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: root.projection.items || []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 48
                                    radius: 15
                                    color: modelData.focused ? root.accentStrong : (modelData.missing ? "#55414b58" : root.surfaceBright)
                                    border.width: modelData.urgent ? 2 : 0
                                    border.color: root.danger
                                    opacity: modelData.missing ? 0.75 : 1
                                    Accessible.name: (modelData.label || modelData.desktop_id || "Unknown application") +
                                                     (modelData.running ? ", running" : ", not running") +
                                                     (modelData.missing ? ", missing" : "")

                                    Image {
                                        id: appIcon
                                        anchors.centerIn: parent
                                        width: 25
                                        height: 25
                                        source: root.iconSource(modelData.icon, "application-x-executable")
                                        sourceSize.width: 48
                                        sourceSize.height: 48
                                        fillMode: Image.PreserveAspectFit
                                        visible: !modelData.missing
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.missing ? "?" : (modelData.label || "?").slice(0, 1).toUpperCase()
                                        color: root.textPrimary
                                        font.pixelSize: 19
                                        visible: modelData.missing || appIcon.status !== Image.Ready
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: modelData.running ? Math.max(7, Math.min(22, 7 + (modelData.instance_count || 1) * 4)) : 0
                                        height: 3
                                        radius: 2
                                        color: modelData.focused ? root.accent : root.textSecondary
                                    }
                                    MouseArea {
                                        id: appMouse
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function (mouse) {
                                            if (mouse.button === Qt.RightButton)
                                                root.togglePin(modelData)
                                            else
                                                root.activateItem(modelData)
                                        }
                                        onPressAndHold: {
                                            var instance = root.itemWindow(modelData)
                                            if (instance)
                                                root.request("apps.close", { "window_id": instance.id })
                                        }
                                    }
                                    ToolTip.visible: appMouse.containsMouse
                                    ToolTip.text: modelData.label || modelData.desktop_id || "Unknown application"
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 7
                            Rectangle {
                                Layout.preferredWidth: 82
                                Layout.preferredHeight: 34
                                radius: 12
                                color: root.projection.statusbar && root.projection.statusbar.health === "ready" ? root.surfaceBright : "#664a3b28"
                                border.width: root.projection.statusbar && root.projection.statusbar.health === "degraded" ? 1 : 0
                                border.color: root.danger
                                Accessible.name: "Julia status: " + (root.projection.statusbar ? root.projection.statusbar.health : "unknown")
                                Text {
                                    anchors.centerIn: parent
                                    text: (root.projection.statusbar ? root.projection.statusbar.health : "unknown") + "  r" +
                                          (root.projection.statusbar ? root.projection.statusbar.revision : 0)
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                text: root.clockText
                                color: root.textSecondary
                                font.pixelSize: 12
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 14
                                color: root.notificationCenterOpen ? root.accentStrong : root.surfaceBright
                                Accessible.name: "Notifications"
                                Text { anchors.centerIn: parent; text: (notificationServer.trackedNotifications.values || []).length ? "●" : "◌"; color: root.textPrimary; font.pixelSize: 18 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.notificationCenterOpen = !root.notificationCenterOpen
                                        root.launcherOpen = false
                                        root.controlCenterOpen = false
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 14
                                color: root.controlCenterOpen ? root.accentStrong : root.surfaceBright
                                Accessible.name: "Open control center"
                                Text { anchors.centerIn: parent; text: "☷"; color: root.textPrimary; font.pixelSize: 20 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.controlCenterOpen = !root.controlCenterOpen
                                        root.launcherOpen = false
                                        root.notificationCenterOpen = false
                                    }
                                }
                            }
                            Item {
                                Layout.preferredWidth: root.hasBattery ? 56 : 0
                                Layout.preferredHeight: 36
                                visible: root.hasBattery
                                Text { anchors.centerIn: parent; text: Math.round(UPower.displayDevice.percentage) + "%"; color: root.textSecondary; font.pixelSize: 12 }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.lastError !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: root.bottomEdge ? dockBar.top : dockBar.bottom
                    anchors.bottomMargin: 8
                    width: Math.min(parent.width - 40, errorText.implicitWidth + 34)
                    height: 30
                    radius: 12
                    color: "#b33b2025"
                    Text { id: errorText; anchors.centerIn: parent; text: root.lastError; color: root.danger; font.pixelSize: 11 }
                }
            }
        }
    }

    Component {
        id: launcherComponent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Launch anything"; color: root.textPrimary; font.pixelSize: 22; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { text: (root.projection.applications || []).length + " apps"; color: root.textSecondary; font.pixelSize: 12 }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 17
                color: root.surfaceBright
                border.width: 1
                border.color: root.accentStrong
                Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: root.accent; font.pixelSize: 25 }
                TextField {
                    id: launcherSearch
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 48
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.textPrimary
                    selectionColor: root.accentStrong
                    selectedTextColor: root.textPrimary
                    font.pixelSize: 16
                    text: root.searchText
                    onTextChanged: root.searchText = text
                    focus: root.launcherOpen
                    activeFocusOnTab: true
                    placeholderText: "Search apps, files, commands…"
                }
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 6
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: root.filteredApplications()
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: 17
                        color: applicationMouse.containsMouse ? root.surfaceBright : "#7d263448"
                        Accessible.name: "Launch " + (modelData.label || modelData.desktop_id)
                        Image {
                            id: applicationIcon
                            anchors.top: parent.top
                            anchors.topMargin: 11
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 29
                            height: 29
                            source: root.iconSource(modelData.icon, "application-x-executable")
                            sourceSize.width: 48
                            sourceSize.height: 48
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            text: modelData.label || modelData.desktop_id
                            color: root.textPrimary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea {
                            id: applicationMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.launchApplication(modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: controlCenterComponent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Control center"; color: root.textPrimary; font.pixelSize: 22; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { text: root.projection.compositor || "unknown compositor"; color: root.textSecondary; font.pixelSize: 12 }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 105
                    radius: 20
                    color: root.surfaceBright
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        Text { text: "Shell health"; color: root.textSecondary; font.pixelSize: 12 }
                        Text { text: (root.projection.health || "unknown").toUpperCase(); color: root.projection.health === "ready" ? root.accent : root.danger; font.pixelSize: 20; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "revision " + (root.projection.revision || 0); color: root.textSecondary; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Text { text: "Wi-Fi " + (Networking.devices.values.some(function (device) { return device.connected }) ? "on" : "off"); color: root.textSecondary; font.pixelSize: 11 }
                            Text { text: "BT " + (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "on" : "off"); color: root.textSecondary; font.pixelSize: 11 }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 105
                    radius: 20
                    color: root.surfaceBright
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        Text { text: "Workspace"; color: root.textSecondary; font.pixelSize: 12 }
                        Text { text: (root.projection.workspaces || []).join("  ·  ") || "—"; color: root.textPrimary; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight }
                        Text { text: (root.projection.outputs || []).length + " output(s) · " + (Pipewire.ready ? "audio ready" : "audio unavailable"); color: root.textSecondary; font.pixelSize: 11 }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 105
                radius: 20
                color: root.surfaceBright
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 15
                    Text { text: "♫"; color: root.accent; font.pixelSize: 28 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text {
                            text: Mpris.players.values.length ? (Mpris.players.values[0].trackTitle || "Playing") : "Nothing playing"
                            color: root.textPrimary
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }
                        Text {
                            text: Mpris.players.values.length ? (Mpris.players.values[0].trackArtist || Mpris.players.values[0].identity || "Unknown artist") : "Open a MPRIS player to see media controls"
                            color: root.textSecondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 14
                        color: root.accentStrong
                        visible: Mpris.players.values.length > 0 && Mpris.players.values[0].canTogglePlaying
                        Text { anchors.centerIn: parent; text: Mpris.players.values.length && Mpris.players.values[0].isPlaying ? "Ⅱ" : "▶"; color: root.textPrimary; font.pixelSize: 17 }
                        MouseArea { anchors.fill: parent; onClicked: if (Mpris.players.values.length) Mpris.players.values[0].togglePlaying() }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: root.surfaceBright
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    Text { text: "System tray"; color: root.textSecondary; font.pixelSize: 12 }
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: SystemTray.items
                            delegate: Image {
                                required property var modelData
                                Layout.preferredWidth: 25
                                Layout.preferredHeight: 25
                                source: modelData.icon
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: SystemTray.items.values.length ? SystemTray.items.values.length + " indicators" : "No indicators"; color: root.textSecondary; font.pixelSize: 11 }
                    }
                    Text { text: "Right-click an app to pin or unpin it. Missing entries stay visible until repaired."; color: root.textSecondary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
            }
        }
    }

    Component {
        id: notificationComponent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Notifications"; color: root.textPrimary; font.pixelSize: 22; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { text: notificationServer.trackedNotifications.values.length + " active"; color: root.textSecondary; font.pixelSize: 12 }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                clip: true
                model: notificationServer.trackedNotifications
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 78
                    radius: 18
                    color: root.surfaceBright
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 4
                        Text { text: modelData.appName || "Notification"; color: root.accent; font.pixelSize: 11 }
                        Text { text: modelData.summary || ""; color: root.textPrimary; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.body || ""; color: root.textSecondary; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    MouseArea { anchors.fill: parent; onClicked: modelData.dismiss() }
                }
            }
            Text { text: "Click a notification to dismiss it"; color: root.textSecondary; font.pixelSize: 11 }
        }
    }
}
