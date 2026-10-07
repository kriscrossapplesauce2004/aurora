import QtQuick

// Controller button hint bar: a rounded pill of button glyphs and labels.
Rectangle {
    id: bar
    // Entries are {b: "A", t: "Select"}. Labels of two letters or more draw as shoulder pills.
    property var items: []
    implicitHeight: 44
    implicitWidth: row.implicitWidth + 32
    radius: height / 2
    color: Theme.alpha(Theme.level(4), .96)
    border.width: 1
    border.color: Theme.outline
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 16
        Repeater {
            model: bar.items
            Row {
                id: hint
                required property var modelData
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool shoulder: hint.modelData.b.length > 1
                    width: shoulder ? Math.max(34, glyph.implicitWidth + 16) : 26
                    height: shoulder ? 24 : 26
                    radius: shoulder ? 8 : 13
                    color: Theme.secondaryContainer
                    MText { id: glyph; anchors.centerIn: parent; text: hint.modelData.b; role: "labelS"; font.weight: Font.Bold; color: Theme.onSecondaryContainer }
                }
                MText { anchors.verticalCenter: parent.verticalCenter; text: hint.modelData.t; role: "label"; color: Theme.text }
            }
        }
    }
}
