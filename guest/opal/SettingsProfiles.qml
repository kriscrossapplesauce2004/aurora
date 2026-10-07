import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Save the whole look and layout of Opal, and switch between saved setups.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    readonly property var keys: ["barStyle","iconStyle","quickTiles","sheetSections","light","palette","dynamicColors","dynamicPalette","colorScheme","glass","wallpaperPath","wallpaperFit","wallpaperDim","mode","taskbarCenter","taskbarLabels","taskbarClockDate","taskbarAutoHide","reduceMotion","desktopWidgets"]
    readonly property var profiles: Hub.prefs.profiles || {}
    readonly property var names: Object.keys(profiles).sort()
    function snapshot() { const out = {}; keys.forEach(k => { if (Hub.prefs[k] !== undefined) out[k] = Hub.prefs[k]; }); return out; }
    function save(name) { name = name.trim(); if (!name) return; const next = Object.assign({}, profiles); next[name] = snapshot(); Hub.set("profiles", next); nameField.text = ""; }
    function apply(name) { const saved = profiles[name]; if (!saved) return; Object.keys(saved).forEach(k => Hub.set(k, saved[k])); Hub.message("Switched to " + name); }
    function remove(name) { const next = Object.assign({}, profiles); delete next[name]; Hub.set("profiles", next); }
    ColumnLayout {
        id: column; width: parent.width; spacing: 8
        MText { text: "A profile keeps your bar, tiles, sections, colours, wallpaper and layout."; role: "bodyS"; color: Theme.subtext; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.leftMargin: 6; Layout.bottomMargin: 6 }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Theme.level(3)
                TextInput {
                    id: nameField; anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; maximumLength: 40
                    onAccepted: page.save(text)
                    MText { anchors.verticalCenter: parent.verticalCenter; visible: nameField.text === ""; text: "Name this setup"; role: "body"; color: Theme.subtext }
                }
            }
            MButton { text: "Save"; icon: "save"; filled: true; enabled: nameField.text.trim() !== "" && page.names.length < 10; onClicked: page.save(nameField.text) }
        }
        Repeater {
            model: page.names
            Rectangle {
                required property string modelData
                Layout.fillWidth: true; Layout.preferredHeight: 64; radius: Theme.shapeLg; color: Theme.level(3)
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 8; spacing: 10
                    Glyph { name: "style"; font.pixelSize: 22; color: Theme.primary; Layout.preferredWidth: 26 }
                    ColumnLayout { Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 0
                        MText { text: modelData; role: "titleS"; Layout.fillWidth: true }
                        MText { text: (page.profiles[modelData].barStyle || "islands") + " bar · " + (page.profiles[modelData].light ? "light" : "dark"); role: "labelS"; color: Theme.subtext; Layout.fillWidth: true } }
                    MButton { text: "Use"; compact: true; tonal: true; onClicked: page.apply(modelData) }
                    MButton { icon: "trash"; compact: true; implicitWidth: 40; ink: Theme.subtext; tooltip: "Delete"; onClicked: page.remove(modelData) }
                }
            }
        }
        MText { visible: page.names.length === 0; text: "No saved profiles yet."; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6; Layout.topMargin: 8 }
    }
}
