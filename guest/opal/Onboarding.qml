import QtQuick
import QtQuick.Layouts
// First-run tour: theme, bar, icons and layout, one step at a time. Every choice applies right away.
Item {
    id: tour
    property int step: 0
    readonly property int steps: 6
    readonly property real fitHeight: 640
    function finish() { Hub.set("onboarded", true); Hub.close(); }
    focus: true
    Keys.onEscapePressed: finish()
    Keys.onRightPressed: if (step < steps - 1) step++
    Keys.onLeftPressed: if (step > 0) step--
    component Choice: Rectangle {
        id: choice
        property string title
        property string detail
        property string icon
        property bool chosen: false
        signal picked()
        Layout.fillWidth: true; Layout.preferredHeight: 76
        radius: Theme.shapeLg
        color: chosen ? Theme.primaryContainer : Theme.level(3)
        border.width: chosen ? 2 : 0; border.color: Theme.primary
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 14
            Glyph { name: choice.icon; font.pixelSize: 26; color: choice.chosen ? Theme.onContainer : Theme.primary }
            ColumnLayout { Layout.fillWidth: true; spacing: 0
                MText { text: choice.title; role: "titleS"; color: choice.chosen ? Theme.onContainer : Theme.text }
                MText { text: choice.detail; role: "labelS"; color: choice.chosen ? Theme.alpha(Theme.onContainer, .8) : Theme.subtext; Layout.fillWidth: true } }
            Glyph { visible: choice.chosen; name: "check_circle"; font.pixelSize: 22; color: Theme.onContainer }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: choice.picked() }
    }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 28; spacing: 16
        // Progress.
        RowLayout { Layout.fillWidth: true; spacing: 6
            Repeater { model: tour.steps
                Rectangle { required property int index; Layout.fillWidth: true; height: 6; radius: 3; color: index <= tour.step ? Theme.primary : Theme.level(4)
                    Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } } } }
            MButton { text: "Skip"; compact: true; ink: Theme.subtext; onClicked: tour.finish() }
        }
        Loader {
            Layout.fillWidth: true; Layout.fillHeight: true
            sourceComponent: [welcome, theme, bar, icons, layout, done][tour.step]
        }
        RowLayout { Layout.fillWidth: true
            MButton { visible: tour.step > 0; text: "Back"; icon: "back"; onClicked: tour.step-- }
            Item { Layout.fillWidth: true }
            MButton { text: tour.step === tour.steps - 1 ? "Start using Opal" : tour.step === 0 ? "Let's go" : "Next"; filled: true; onClicked: tour.step === tour.steps - 1 ? tour.finish() : tour.step++ }
        }
    }
    Component { id: welcome; ColumnLayout { spacing: 12
        Item { Layout.fillHeight: true }
        Rectangle { Layout.preferredWidth: 88; Layout.preferredHeight: 88; radius: 28; color: Theme.primaryContainer
            Glyph { anchors.centerIn: parent; name: "auto_awesome"; font.pixelSize: 44; color: Theme.onContainer } }
        MText { text: "The new Opal"; role: "displayM"; Layout.fillWidth: true; wrapMode: Text.Wrap }
        MText { text: "A calmer bar, a lock screen and login screen, a new gaming library and phone home, and Claude in Start. Pick a few things and you're set."; role: "body"; color: Theme.subtext; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Item { Layout.fillHeight: true } } }
    Component { id: theme; ColumnLayout { spacing: 10
        MText { text: "Light or dark?"; role: "headline" }
        Choice { title: "Dark"; detail: "Easy on the eyes at night"; icon: "dark_mode"; chosen: !Theme.light; onPicked: Hub.set("light", false) }
        Choice { title: "Light"; detail: "Bright and clear"; icon: "light_mode"; chosen: Theme.light; onPicked: Hub.set("light", true) }
        Choice { title: "Night light at sunset"; detail: "Warm the screen from sunset to sunrise"; icon: "nightlight"; chosen: !!((Hub.prefs.schedules || {}).nightLight || {}).enabled
            onPicked: { const s = JSON.parse(JSON.stringify(Hub.prefs.schedules || {})); s.nightLight = Object.assign({mode: "sun", temperature: 4000}, s.nightLight || {}, {enabled: !(s.nightLight && s.nightLight.enabled)}); Hub.set("schedules", s); } }
        Item { Layout.fillHeight: true } } }
    Component { id: bar; ColumnLayout { spacing: 10
        MText { text: "Choose your bar"; role: "headline" }
        Repeater { model: [{v: "islands", t: "Islands", d: "Apps, status and clock as separate pills", i: "view_column"}, {v: "dock", t: "Dock", d: "Everything in one floating pill", i: "call_to_action"}, {v: "split", t: "Split", d: "Status on top, apps at the bottom", i: "splitscreen"}, {v: "edge", t: "Edge", d: "A classic bar along the bottom edge", i: "bottom_navigation"}]
            Choice { required property var modelData; title: modelData.t; detail: modelData.d; icon: modelData.i; chosen: (Hub.prefs.barStyle || "islands") === modelData.v; onPicked: Hub.set("barStyle", modelData.v) } }
        Item { Layout.fillHeight: true } } }
    Component { id: icons; ColumnLayout { spacing: 10
        MText { text: "App icons"; role: "headline" }
        Repeater { model: [{v: "raw", t: "Original", d: "Icons as the apps ship them", i: "apps"}, {v: "squircle", t: "Backplate", d: "Every icon on the same rounded tile", i: "rounded_corner"}, {v: "themed", t: "Themed", d: "One colour, matched to your palette", i: "palette"}]
            Choice { required property var modelData; title: modelData.t; detail: modelData.d; icon: modelData.i; chosen: (Hub.prefs.iconStyle || "raw") === modelData.v; onPicked: Hub.set("iconStyle", modelData.v) } }
        Item { Layout.fillHeight: true } } }
    Component { id: layout; ColumnLayout { spacing: 10
        MText { text: "How do you use this screen?"; role: "headline" }
        Repeater { model: [{v: "auto", t: "Let Opal decide", d: "Touch or desktop by screen size", i: "auto_awesome"}, {v: "desktop", t: "Desktop", d: "Windows, a bar and search", i: "desktop_windows"}, {v: "phone", t: "Phone or tablet", d: "A touch home with big targets", i: "smartphone"}, {v: "console", t: "Couch gaming", d: "Your games, controller first", i: "sports_esports"}]
            Choice { required property var modelData; title: modelData.t; detail: modelData.d; icon: modelData.i; chosen: Hub.prefs.mode === modelData.v; onPicked: Hub.mode(modelData.v) } }
        Item { Layout.fillHeight: true } } }
    Component { id: done; ColumnLayout { spacing: 10
        MText { text: "A few shortcuts"; role: "headline" }
        Repeater { model: [{k: "Super + Space", t: "Start and search"}, {k: "! in Start", t: "Ask Claude, or have it change Opal for you"}, {k: "Super + Comma", t: "Controls and notifications"}, {k: "Super + L", t: "Lock"}, {k: "Super + Ctrl + G", t: "Gaming mode"}]
            RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 14
                Rectangle { Layout.preferredWidth: keyText.implicitWidth + 24; Layout.preferredHeight: 34; radius: 10; color: Theme.level(4)
                    MText { id: keyText; anchors.centerIn: parent; text: modelData.k; role: "label"; font.weight: Font.Bold } }
                MText { text: modelData.t; role: "body"; Layout.fillWidth: true } } }
        Item { Layout.fillHeight: true } } }
}
