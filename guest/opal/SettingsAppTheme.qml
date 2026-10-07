import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Send Opal's colours to other apps. Each app gets its own small file and one include line.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    readonly property var targets: Hub.prefs.themeExport || []
    function toggle(id) {
        const next = targets.slice(); const i = next.indexOf(id);
        if (i >= 0) { next.splice(i, 1); Hub.command({action: "theme-export-remove", targets: [id]}); } else next.push(id);
        Hub.set("themeExport", next);
    }
    readonly property var sync: Hub.prefs.themeSync || ({})
    readonly property var choices: Hub.themeChoices || ({})
    Component.onCompleted: Hub.command({action: "theme-discover"})
    function pick(key, value) { const next = Object.assign({}, sync); next[key] = value; Hub.set("themeSync", next); }
    ColumnLayout {
        id: column; width: parent.width; spacing: 4
        MText { text: "Apps follow your Opal colours and update when you change them."; role: "bodyS"; color: Theme.subtext; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.leftMargin: 6; Layout.bottomMargin: 10 }
        Repeater {
            model: [
                {id: "gtk", title: "GTK and GNOME apps", icon: "web_asset", detail: "Accent and surface colours"},
                {id: "kitty", title: "Kitty terminal", icon: "terminal", detail: "Terminal colours, reloaded live"},
                {id: "qt", title: "Qt apps", icon: "widgets", detail: "Kvantum style and colours, or the qt6ct scheme"},
                {id: "hyprland", title: "Window borders", icon: "select_window", detail: "Active and inactive borders"},
                {id: "kde", title: "KDE apps", icon: "palette", detail: "Colour scheme for Dolphin and other KDE apps"},
                {id: "sync", title: "Fonts, icons and cursor", icon: "text_fields", detail: "One choice for GTK, Qt, KDE and the cursor"},
                {id: "flatpak", title: "Flatpak apps", icon: "deployed_code", detail: "Read-only access to your themes"}
            ]
            SettingToggle {
                required property var modelData
                required property int index
                Layout.fillWidth: true; first: index === 0; last: index === 6
                icon: modelData.icon; title: modelData.title; description: modelData.detail
                checked: page.targets.indexOf(modelData.id) >= 0
                onToggled: page.toggle(modelData.id)
            }
        }
        Repeater {
            model: [
                {key: "font", title: "Font", items: page.choices.fonts || [], fallback: Theme.font},
                {key: "iconTheme", title: "Icon theme", items: page.choices.icons || [], fallback: ""},
                {key: "cursorTheme", title: "Cursor theme", items: page.choices.cursors || [], fallback: ""}
            ]
            ColumnLayout {
                id: picker
                required property var modelData
                Layout.fillWidth: true; spacing: 4; visible: page.targets.indexOf("sync") >= 0 && modelData.items.length > 0
                MText { text: picker.modelData.title; role: "label"; color: Theme.subtext; Layout.leftMargin: 6; Layout.topMargin: 12 }
                ListView {
                    Layout.fillWidth: true; Layout.preferredHeight: 40; orientation: ListView.Horizontal; spacing: 6; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: picker.modelData.items
                    delegate: Chip {
                        required property string modelData
                        text: modelData; selected: (page.sync[picker.modelData.key] || picker.modelData.fallback) === modelData
                        onClicked: page.pick(picker.modelData.key, modelData)
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4; visible: page.targets.indexOf("sync") >= 0
            MText { text: "Cursor size"; role: "label"; color: Theme.subtext; Layout.leftMargin: 6; Layout.topMargin: 12 }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [24, 32, 48, 64]
                    Chip { required property int modelData; text: String(modelData); selected: (page.sync.cursorSize || 24) === modelData; onClicked: page.pick("cursorSize", modelData) }
                }
            }
        }
        MText { text: "Chrome has no theme file to write, so it isn't listed."; role: "labelS"; color: Theme.subtext; Layout.leftMargin: 6; Layout.topMargin: 10 }
    }
}
