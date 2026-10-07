import QtQuick
import QtQuick.Layouts
import Quickshell
// Desktop widget column: recent apps, analog clock, date, quick actions and media.
Column {
    id: widgets
    property Item backdrop: null
    property bool tall: true
    property real available: 10000
    readonly property var recent: (Hub.recentApps.length ? Hub.recentApps : Hub.apps.filter(a => Hub.pinned(a))).slice(0, tall ? 4 : 3)
    readonly property real half: (width - 14) / 2
    spacing: 14

    // Recent: the apps you used last, as a glass list card.
    Item {
        id: recentCard
        visible: widgets.recent.length > 0 && widgets.available >= 560
        width: parent.width
        height: visible ? recentColumn.implicitHeight + 24 : 0
        Frost { anchors.fill: parent; radius: 28; backdrop: widgets.backdrop }
        Column {
            id: recentColumn
            x: 12; y: 12; width: parent.width - 24; spacing: 6
            RowLayout {
                width: parent.width; height: 40; spacing: 6
                Item {
                    Layout.preferredWidth: 28; Layout.preferredHeight: 28; Layout.leftMargin: 4
                    Glyph { anchors.centerIn: parent; name: "history"; font.pixelSize: 20; color: Theme.primary }
                }
                MText { Layout.fillWidth: true; text: Hub.recentApps.length ? "Recent" : "Pinned"; font.pixelSize: 15; font.weight: Font.Medium }
                MButton { icon: "apps"; compact: true; filled: true; accent: Theme.light ? Theme.containerInk : Theme.primary; fillInk: Theme.light ? Theme.primaryContainer : Theme.onPrimary; implicitWidth: 46; implicitHeight: 34; tooltip: "All applications"; onClicked: Hub.openStart(false) }
                MButton { icon: "search"; compact: true; filled: true; accent: Theme.light ? Theme.containerInk : Theme.primary; fillInk: Theme.light ? Theme.primaryContainer : Theme.onPrimary; implicitWidth: 46; implicitHeight: 34; tooltip: "Search"; onClicked: Hub.openStart(true) }
            }
            Repeater {
                model: widgets.recent
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: recentColumn.width; height: 48
                    // Grouped list shape: outer corners are round, inner corners are tight.
                    topLeftRadius: index === 0 ? 16 : 6; topRightRadius: topLeftRadius
                    bottomLeftRadius: index === widgets.recent.length - 1 ? 16 : 6; bottomRightRadius: bottomLeftRadius
                    color: Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised, Theme.light ? .72 : .5)
                    Rectangle { anchors.fill: parent; topLeftRadius: parent.topLeftRadius; topRightRadius: parent.topRightRadius; bottomLeftRadius: parent.bottomLeftRadius; bottomRightRadius: parent.bottomRightRadius; color: Theme.stateLayer; opacity: rowMouse.pressed ? .12 : rowMouse.containsMouse ? .07 : 0; Behavior on opacity { NumberAnimation { duration: Theme.motion(120) } } }
                    Image { id: rowIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 26; height: 26; sourceSize: Qt.size(52, 52); asynchronous: true; source: Quickshell.iconPath(row.modelData.icon, true) }
                    Glyph { visible: rowIcon.status !== Image.Ready; anchors.centerIn: rowIcon; name: Hub.glyphForApp(row.modelData); font.pixelSize: 22; color: Theme.primary }
                    Column {
                        x: 48; width: parent.width - 58; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        MText { width: parent.width; text: row.modelData.name; font.pixelSize: 13; font.weight: Font.Medium }
                        MText { width: parent.width; text: row.modelData.genericName || (Hub.recentApps.length ? "Opened recently" : "Pinned"); font.pixelSize: 10; color: Theme.subtext }
                    }
                    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Hub.launch(row.modelData) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Open " + row.modelData.name
                    Accessible.onPressAction: Hub.launch(row.modelData)
                }
            }
        }
    }

    Row {
        spacing: 14
        AnalogClock { width: widgets.half; height: width; backdrop: widgets.backdrop }
        // Date blob: a soft wobbly disc with the day, and a scalloped month badge.
        Item {
            width: widgets.half; height: width
            Flower {
                anchors.fill: parent; lobes: 3; depth: .07; phase: -20
                fill: Theme.alpha(Theme.light ? Theme.primaryContainer : Theme.glassRaised, Theme.light ? .86 : .78)
                NumberAnimation on phase { from: -20; to: 340; duration: 90000; loops: Animation.Infinite; running: !Theme.reduceMotion }
            }
            MText {
                anchors.centerIn: parent; anchors.horizontalCenterOffset: parent.width * .06; anchors.verticalCenterOffset: -parent.height * .04
                text: Qt.formatDateTime(Hub.now, "d"); font.pixelSize: parent.width * .42; font.weight: Font.DemiBold; font.letterSpacing: -2
                color: Theme.light ? Theme.containerInk : Theme.text
            }
            MText {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: parent.width * .12
                y: parent.height * .68
                text: Qt.formatDateTime(Hub.now, "dddd"); font.pixelSize: 11; font.weight: Font.Medium; color: Theme.subtext
            }
            Flower {
                x: parent.width * .04; y: parent.height * .56; width: parent.width * .34; height: width
                lobes: 9; depth: .16; fill: Theme.light ? Theme.mix(Theme.tertiary, "#ffffff", .35) : Theme.tertiary
                MText { anchors.centerIn: parent; text: Qt.formatDateTime(Hub.now, "MMM").toUpperCase(); font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: .5; color: Theme.light ? Theme.onTertiaryContainer : Theme.base }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Hub.openSection("widgets") }
            Accessible.role: Accessible.Button
            Accessible.name: Qt.formatDateTime(Hub.now, "dddd, d MMMM") + ". Open calendar"
        }
    }

    // Quick actions: a glass toolbar, lead action filled and taller in shape.
    Item {
        width: parent.width; height: 72
        Frost { anchors.fill: parent; radius: 26; backdrop: widgets.backdrop }
        RowLayout {
            anchors.fill: parent; anchors.margins: 8; spacing: 6
            ActionKey { lead: true; icon: "spark"; label: "Start"; onActivated: Hub.openStart(false) }
            ActionKey { icon: "capture"; label: "Screenshot"; onActivated: Hub.screenShot() }
            ActionKey { icon: "clipboard"; label: "Clipboard"; onActivated: Hub.toggleClipboard() }
            ActionKey { icon: "timer"; label: Hub.focusRunning ? Math.ceil(Hub.focusSeconds / 60) + " min focus" : "Focus timer"; active: Hub.focusRunning; onActivated: Hub.timerToggle() }
            ActionKey { icon: "palette"; label: "Personalize"; onActivated: Hub.page = "appearance" }
        }
    }

    Item {
        visible: Hub.status.track !== "" && widgets.tall
        width: parent.width; height: visible ? 150 : 0
        MediaCard { anchors.fill: parent; compact: true }
    }

    component ActionKey: Rectangle {
        id: key
        property string icon: ""
        property string label: ""
        property bool lead: false
        property bool active: false
        signal activated()
        Layout.fillWidth: true; Layout.fillHeight: true
        radius: lead || active ? height / 2 : keyMouse.pressed ? 10 : 16
        color: lead || active ? (Theme.light ? Theme.containerInk : Theme.primary) : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised, Theme.light ? .7 : .5)
        scale: keyMouse.pressed ? .94 : 1
        Behavior on radius { NumberAnimation { duration: Theme.motion(220); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.motion(150) } }
        Behavior on color { ColorAnimation { duration: Theme.motion(180) } }
        readonly property color ink: lead || active ? (Theme.light ? Theme.primaryContainer : Theme.onPrimary) : Theme.text
        Rectangle { anchors.fill: parent; radius: parent.radius; color: key.ink; opacity: keyMouse.pressed ? .12 : keyMouse.containsMouse ? .08 : 0 }
        Glyph { anchors.centerIn: parent; name: key.icon; font.pixelSize: 22; color: key.ink }
        MouseArea { id: keyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: key.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
    }
}
