import QtQuick
import Quickshell
// Workspace switcher pill. The active slot widens to show its apps.
Item {
    id: pill
    property int shown: Hub.status.workspace || 1
    property bool out: true
    readonly property var numbers: {
        const known = (Hub.status.workspaces || []).filter(n => n > 0);
        const top = Math.max(3, Math.min(10, Math.max.apply(null, known.concat([pill.shown || 1]))));
        return Array.from({length: top}, (_, i) => i + 1);
    }
    readonly property int activeIndex: Math.max(0, numbers.indexOf(shown))
    function count(n) { return Hub.windows.filter(w => w.workspace === n).length; }
    width: track.width; height: 72
    // Pill: every workspace is a slot. The active slot widens to show its apps.
    function icons(n) { return Hub.windows.filter(w => w.workspace === n).slice(0, 3).map(w => (w.className || "").toLowerCase()); }
    readonly property real slotWidth: 36
    readonly property real activeWidth: Math.max(56, 24 + icons(shown).length * 26)
    Rectangle {
        id: track
        anchors.horizontalCenter: parent.horizontalCenter
        width: slots.width + 12; height: 48; radius: height / 2
        color: Theme.level(3)
        y: pill.out ? 12 : -height - 4
        Behavior on y { NumberAnimation { duration: Theme.motion(pill.out ? Theme.durMedium : Theme.durShort); easing.type: pill.out ? Easing.OutCubic : Easing.InCubic } }
        Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
        // Active indicator slides and stretches to the current slot.
        Rectangle {
            x: 6 + pill.activeIndex * pill.slotWidth; width: pill.activeWidth
            anchors.verticalCenter: parent.verticalCenter
            height: 36; radius: height / 2
            color: Theme.primaryContainer
            Behavior on x { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
        }
        Row {
            id: slots
            x: 6; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                id: slotRepeater
                model: pill.numbers
                Item {
                    id: slot
                    required property int modelData
                    required property int index
                    readonly property bool current: index === pill.activeIndex
                    readonly property int windows: pill.count(modelData)
                    width: current ? pill.activeWidth : pill.slotWidth; height: 36
                    Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
                    // Inactive: number, with a dot if it has windows.
                    MText {
                        visible: !slot.current
                        anchors.centerIn: parent; anchors.verticalCenterOffset: slot.windows > 0 ? -3 : 0
                        text: slot.modelData; role: "label"
                        color: slot.windows > 0 ? Theme.text : Theme.alpha(Theme.text, .4)
                    }
                    Rectangle { visible: !slot.current && slot.windows > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 7; width: 4; height: 4; radius: 2; color: Theme.subtext }
                    // Active: number and app icons.
                    Row {
                        visible: slot.current
                        anchors.centerIn: parent; spacing: 6
                        MText { anchors.verticalCenter: parent.verticalCenter; text: slot.modelData; role: "titleS"; color: Theme.onContainer }
                        Repeater {
                            model: slot.current ? pill.icons(slot.modelData) : []
                            Image { required property string modelData; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: Quickshell.iconPath(modelData, true); asynchronous: true }
                        }
                    }
                }
            }
        }
    }
}
