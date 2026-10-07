import QtQuick

// Suggestion chips from local signals. Hidden during Do not disturb.
Flow {
    id: chips
    spacing: 8
    visible: !Hub.dnd && Activities.chips.length > 0
    Repeater {
        model: Hub.dnd ? [] : Activities.chips
        Chip {
            required property var modelData
            icon: modelData.icon; text: modelData.label; tooltip: modelData.detail ? modelData.label + " · " + modelData.detail : modelData.label
            selected: modelData.kind === "code"
            onClicked: Activities.runChip(modelData)
        }
    }
}
