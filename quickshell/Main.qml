import QtQuick
import QtQuick.Layouts

// The QML layer consumes a state projection; it never edits profile TOML.
Rectangle {
    id: dock
    property var projection: ({
        "schema": 1,
        "revision": 0,
        "health": "disconnected",
        "items": []
    })
    color: "transparent"
    implicitWidth: row.implicitWidth + 24
    implicitHeight: 64

    Rectangle {
        anchors.fill: parent
        anchors.margins: 6
        radius: 18
        color: "#e61b2638"
        border.color: "#40576d"
        border.width: 1
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: dock.projection.items || []
            delegate: Rectangle {
                required property var modelData
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 14
                color: modelData.missing ? "#55414b58" : "#334d647d"
                Accessible.name: modelData.label || modelData.desktop_id || "Unknown application"

                Text {
                    anchors.centerIn: parent
                    text: modelData.label ? modelData.label.slice(0, 1).toUpperCase() : "?"
                    color: "#f4f7fb"
                    font.pixelSize: 20
                }
            }
        }
    }
}
