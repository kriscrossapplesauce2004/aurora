import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Night light, dark mode and Do not disturb on a schedule. "Sun" follows sunset and sunrise for your time zone.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    readonly property var all: Hub.prefs.schedules || {}
    function update(key, change) { const next = JSON.parse(JSON.stringify(all)); next[key] = Object.assign({}, next[key] || {}, change); Hub.set("schedules", next); }
    component Schedule: ColumnLayout {
        id: block
        property string key
        property string title
        property string icon
        property string defaultFrom
        property string defaultTo
        readonly property var item: page.all[key] || {}
        Layout.fillWidth: true; spacing: 6
        SettingToggle { Layout.fillWidth: true; first: true; last: !block.item.enabled; icon: block.icon; title: block.title; checked: !!block.item.enabled; onToggled: page.update(block.key, {enabled: !checked}) }
        Rectangle {
            visible: !!block.item.enabled; Layout.fillWidth: true; implicitHeight: inner.implicitHeight + 28
            radius: Theme.shapeLg; color: Theme.level(3)
            ColumnLayout {
                id: inner; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 10
                SegmentedButtons {
                    Layout.fillWidth: true; current: block.item.mode || "custom"
                    options: [{value: "sun", label: "Sunset to sunrise", icon: "wb_twilight"}, {value: "custom", label: "Custom", icon: "schedule"}]
                    onPicked: value => page.update(block.key, {mode: value})
                }
                MText { visible: (block.item.mode || "custom") === "sun"; text: "Today: " + Hub.sun.sunset + " to " + Hub.sun.sunrise + (Hub.sun.estimated ? " (estimated)" : ""); role: "bodyS"; color: Theme.subtext }
                RowLayout {
                    visible: (block.item.mode || "custom") === "custom"; spacing: 10
                    MText { text: "From"; role: "body" }
                    TimeField { value: block.item.from || block.defaultFrom; onPicked: value => page.update(block.key, {from: value}) }
                    MText { text: "to"; role: "body" }
                    TimeField { value: block.item.to || block.defaultTo; onPicked: value => page.update(block.key, {to: value}) }
                }
                ColumnLayout {
                    visible: block.key === "nightLight"; Layout.fillWidth: true; spacing: 4
                    MText { text: "Warmth · " + (block.item.temperature || 4000) + " K"; role: "label"; color: Theme.subtext }
                    ExpressiveSlider { Layout.fillWidth: true; from: 0; to: 100; icon: "sun"; value: (6500 - (block.item.temperature || 4000)) / 40; onMoved: page.update(block.key, {temperature: Math.round((6500 - value * 40) / 100) * 100}) }
                }
            }
        }
    }
    component TimeField: Rectangle {
        id: field
        property string value: "00:00"
        signal picked(string value)
        width: 96; height: 40; radius: 20; color: Theme.level(4)
        TextInput {
            anchors.centerIn: parent; text: field.value; color: Theme.text; font.family: Theme.font; font.pixelSize: 16
            inputMask: "99:99"; validator: RegularExpressionValidator { regularExpression: /([01]\d|2[0-3]):[0-5]\d/ }
            onEditingFinished: if (acceptableInput && text !== field.value) field.picked(text)
        }
    }
    ColumnLayout {
        id: column; width: parent.width; spacing: 14
        MText { text: "Change things automatically at set times."; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6 }
        Schedule { key: "nightLight"; title: "Night light"; icon: "nightlight"; defaultFrom: "21:00"; defaultTo: "07:00" }
        Schedule { key: "darkMode"; title: "Dark theme"; icon: "dark_mode"; defaultFrom: "19:00"; defaultTo: "07:00" }
        Schedule { key: "dnd"; title: "Do not disturb"; icon: "do_not_disturb_on"; defaultFrom: "23:00"; defaultTo: "07:00" }
    }
}
