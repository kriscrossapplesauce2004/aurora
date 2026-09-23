import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "StartSearch.js" as Search
// Launcher search: one field, instant answers, a best match and grouped results. Nothing goes online until the web row is chosen.
FocusScope {
    id: panel
    readonly property string query: Hub.query.trim()
    readonly property bool searching: query !== ""
    readonly property bool math: searching && (query.startsWith("=") || Hub.looksLikeMath(query))
    readonly property var actions: [
        {id:"settings",name:"Settings",detail:"Device preferences",icon:"settings",keywords:"configure preferences options"},
        {id:"controls",name:"Quick settings",detail:"Wi-Fi, sound and display",icon:"tune",keywords:"control center volume brightness"},
        {id:"network",name:"Wi-Fi",detail:"Choose a network",icon:"wifi",keywords:"internet wireless network"},
        {id:"bluetooth",name:"Bluetooth",detail:"Pair and connect devices",icon:"bluetooth",keywords:"headphones pairing"},
        {id:"appearance",name:"Personalize",detail:"Colours, glass and theme",icon:"palette",keywords:"theme dark light style colour color"},
        {id:"wallpaper",name:"Wallpaper",detail:"Choose a background image",icon:"wallpaper",keywords:"background photo picture"},
        {id:"windows",name:"App switcher",detail:"Every open window",icon:"desktop",keywords:"tasks windows switch"},
        {id:"clipboard",name:"Clipboard history",detail:"Things you copied this session",icon:"clipboard",keywords:"copy paste"},
        {id:"screenshot",name:"Screenshot",detail:"Capture the screen",icon:"capture",keywords:"screen capture image"},
        {id:"lock",name:"Lock",detail:"Lock this session",icon:"lock",keywords:"secure screen"},
        {id:"focus",name:"Focus timer",detail:"25 minutes, no distractions",icon:"timer",keywords:"pomodoro concentrate"},
        {id:"convergence",name:"Displays and docking",detail:"Layouts for every screen",icon:"convergence",keywords:"monitor phone dock layout"}
    ]
    readonly property var found: searching && !math ? Search.search(query, "all", Hub.appSearchIndex, Hub.windows, actions, Hub.favoriteApps.map(a => a.id), Hub.prefs.recent || []).slice(0, 12) : []
    readonly property var best: found.length ? found[0] : null
    readonly property var rest: found.slice(1)
    readonly property var groups: [
        {title: "Apps", items: rest.filter(r => r.kind === "app")},
        {title: "Windows", items: rest.filter(r => r.kind === "window")},
        {title: "Settings and actions", items: rest.filter(r => r.kind === "action")}
    ].filter(g => g.items.length)
    // Keyboard order: best match, then each group, then the web row.
    readonly property var flat: (best ? [best] : []).concat(groups.reduce((all, g) => all.concat(g.items), [])).concat(searching && !math ? [{kind: "web", title: query, key: "web"}] : [])
    property int selection: 0
    readonly property var selected: flat[selection] || null
    onFlatChanged: selection = 0
    readonly property real fitHeight: layout.implicitHeight + 32
    function highlight(text) {
        const plain = String(text || ""), q = query.replace(/^[>@=?]\s*/, "").toLowerCase();
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const at = q ? plain.toLowerCase().indexOf(q) : -1;
        if (at < 0) return esc(plain);
        return esc(plain.slice(0, at)) + "<b>" + esc(plain.slice(at, at + q.length)) + "</b>" + esc(plain.slice(at + q.length));
    }
    function run(item, fresh) {
        if (!item) return;
        if (item.kind === "app") { if (fresh) Hub.launchNew(item.data); else Hub.launch(item.data); }
        else if (item.kind === "window") Hub.focusWindow(item.data);
        else if (item.kind === "web") { Hub.command({action: "web", text: query.replace(/^\?\s*/, "")}); Hub.close(); }
        else {
            const id = item.data.id;
            if (id === "screenshot") Hub.screenShot();
            else if (id === "lock" || id === "network" || id === "bluetooth") Hub.settings(id);
            else if (id === "focus") { Hub.focusSeconds = 25 * 60; Hub.focusRunning = true; Hub.close(); }
            else if (id === "settings") Hub.openSettings();
            else Hub.page = id;
        }
    }
    function accept(fresh) {
        if (math) { if (Hub.calculation !== "") Hub.command({action: "clipboard", text: Hub.calculation}); return; }
        run(selected, fresh);
    }
    Connections {
        target: Hub
        function onStartSearchRequestChanged() { field.forceActiveFocus(); }
        function onQueryChanged() {
            if (field.text !== Hub.query) field.text = Hub.query;
            Hub.calculation = "";
            calc.stop();
            if (panel.math) calc.restart();
        }
    }
    Timer { id: calc; interval: 120; onTriggered: if (panel.math) Hub.command({action: "calculate", text: Hub.calcExpression(panel.query)}) }
    Component.onCompleted: field.forceActiveFocus()
    Keys.onEscapePressed: event => { if (panel.searching) Hub.query = ""; else Hub.close(); event.accepted = true; }

    ColumnLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12
        // Field: solid, tall and quiet, with the colour mark and a live clear key.
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 28
            color: Theme.light ? "#ffffff" : Theme.mix(Theme.base, Theme.primaryContainer, .55)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 8; spacing: 12
                Item {
                    Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    Repeater {
                        model: [Theme.primary, Theme.tertiary, Theme.secondary, Theme.light ? Theme.containerInk : Theme.primaryContainer]
                        Rectangle { required property color modelData; required property int index; width: 8; height: 8; radius: 4; color: modelData; x: index % 2 ? 11 : 1; y: index < 2 ? 1 : 11 }
                    }
                }
                TextField {
                    id: field
                    Layout.fillWidth: true; Layout.fillHeight: true
                    background: Item {}
                    color: Theme.text; placeholderTextColor: Theme.subtext
                    font.family: Theme.font; font.pixelSize: 17; selectByMouse: true
                    placeholderText: "Search apps, windows, settings and the web"
                    text: Hub.query
                    onTextEdited: Hub.query = text
                    Keys.onReturnPressed: event => panel.accept(!!(event.modifiers & Qt.ControlModifier))
                    Keys.onEnterPressed: event => panel.accept(!!(event.modifiers & Qt.ControlModifier))
                    Keys.onDownPressed: panel.selection = Math.min(panel.flat.length - 1, panel.selection + 1)
                    Keys.onUpPressed: panel.selection = Math.max(0, panel.selection - 1)
                    Keys.onTabPressed: panel.selection = (panel.selection + 1) % Math.max(1, panel.flat.length)
                }
                MButton { visible: panel.searching; icon: "close"; compact: true; implicitWidth: 38; implicitHeight: 38; tooltip: "Clear"; onClicked: { Hub.query = ""; field.forceActiveFocus(); } }
            }
        }

        // Empty state: recent apps as large icons, then shortcuts.
        ColumnLayout {
            visible: !panel.searching; Layout.fillWidth: true; spacing: 10
            MText { visible: Hub.recentApps.length > 0; text: "Recent"; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.subtext; Layout.leftMargin: 6 }
            RowLayout {
                visible: Hub.recentApps.length > 0; Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: Hub.recentApps.slice(0, 6)
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredHeight: 88; radius: 20
                        color: recentMouse.containsMouse ? Theme.alpha(Theme.stateLayer, .08) : "transparent"
                        Column {
                            anchors.centerIn: parent; spacing: 6; width: parent.width - 8
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 48; radius: 24
                                color: Theme.light ? "#ffffff" : Theme.alpha(Theme.glassRaised, .8)
                                Image { id: recentIcon; anchors.centerIn: parent; width: 30; height: 30; sourceSize: Qt.size(60, 60); asynchronous: true; source: Quickshell.iconPath(modelData.icon, true) }
                                Glyph { visible: recentIcon.status !== Image.Ready; anchors.centerIn: parent; name: Hub.glyphForApp(modelData); color: Theme.primary }
                            }
                            MText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.pixelSize: 11 }
                        }
                        MouseArea { id: recentMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Hub.launch(parent.modelData) }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: [{text: "Calculator", icon: "calculate", prefix: "= "}, {text: "Actions", icon: "bolt", prefix: "> "}, {text: "Windows", icon: "desktop", prefix: "@ "}, {text: "Clipboard", icon: "clipboard", page: "clipboard"}, {text: "Screenshot", icon: "capture", shot: true}]
                    Chip {
                        required property var modelData
                        text: modelData.text; icon: modelData.icon; implicitHeight: 36
                        onClicked: { if (modelData.shot) Hub.screenShot(); else if (modelData.page) Hub.toggleClipboard(); else { Hub.query = modelData.prefix; field.forceActiveFocus(); } }
                    }
                }
            }
        }

        // Answer card: arithmetic resolves as you type, with no "=" needed.
        Rectangle {
            visible: panel.math; Layout.fillWidth: true; Layout.preferredHeight: 104; radius: 24
            color: Theme.primaryContainer
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 2
                MText { text: Hub.calcExpression(panel.query) + " ="; font.pixelSize: 13; color: Theme.alpha(Theme.onContainer, .75) }
                RowLayout {
                    Layout.fillWidth: true
                    MText { Layout.fillWidth: true; text: Hub.calculation || "…"; font.pixelSize: 34; font.weight: Font.Medium; color: Theme.onContainer }
                    MButton { text: "Copy"; icon: "copy"; compact: true; filled: true; accent: Theme.onContainer; fillInk: Theme.primaryContainer; enabled: Hub.calculation !== ""; onClicked: panel.accept(false) }
                }
            }
        }

        // Best match: the top result, large, with its primary action spelled out.
        Rectangle {
            id: bestCard
            visible: !!panel.best; Layout.fillWidth: true; Layout.preferredHeight: 76; radius: 24
            color: panel.selection === 0 ? Theme.primaryContainer : Theme.alpha(Theme.glassRaised, Theme.light ? .7 : .55)
            Behavior on color { ColorAnimation { duration: Theme.motion(120) } }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 14
                ResultIcon { item: panel.best; size: 48 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    MText { Layout.fillWidth: true; textFormat: Text.StyledText; text: panel.best ? panel.highlight(panel.best.title) : ""; font.pixelSize: 17; font.weight: Font.Medium; color: panel.selection === 0 ? Theme.onContainer : Theme.text }
                    MText { Layout.fillWidth: true; text: panel.best ? panel.best.detail : ""; font.pixelSize: 12; color: panel.selection === 0 ? Theme.alpha(Theme.onContainer, .75) : Theme.subtext }
                }
                MButton { text: panel.best && panel.best.kind === "window" ? "Switch" : "Open"; compact: true; filled: true; onClicked: panel.run(panel.best, false) }
            }
            MouseArea { anchors.fill: parent; z: -1; hoverEnabled: true; onEntered: panel.selection = 0; onClicked: panel.run(panel.best, false) }
        }

        // Grouped results. Each row maps back to its index in the keyboard order.
        Repeater {
            model: panel.groups
            ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true; spacing: 2
                MText { text: group.modelData.title; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.subtext; Layout.leftMargin: 6; Layout.bottomMargin: 2 }
                Repeater {
                    model: group.modelData.items
                    ResultRow { required property var modelData; item: modelData }
                }
            }
        }

        // Web row: always last, and the only path that leaves the device.
        ResultRow { visible: panel.searching && !panel.math; item: panel.flat.length ? panel.flat[panel.flat.length - 1] : null; web: true }
        MText {
            visible: panel.searching && !panel.math; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
            text: "↑↓ choose   ·   Enter open   ·   Ctrl+Enter new window   ·   Esc clear"
            font.pixelSize: 10; color: Theme.subtext
        }
    }

    component ResultIcon: Rectangle {
        property var item: null
        property real size: 36
        Layout.preferredWidth: size; Layout.preferredHeight: size
        radius: size / 2
        color: item && item.kind === "app" ? (Theme.light ? "#ffffff" : Theme.alpha(Theme.glassRaised, .85)) : Theme.alpha(Theme.primary, .16)
        Image { id: icon; anchors.centerIn: parent; width: parent.size * .66; height: width; visible: !!parent.item && parent.item.kind === "app"; source: visible ? Quickshell.iconPath(parent.item.icon, true) : ""; sourceSize: Qt.size(96, 96); asynchronous: true }
        Glyph {
            anchors.centerIn: parent
            visible: !parent.item || parent.item.kind !== "app" || icon.status !== Image.Ready
            name: !parent.item ? "search" : parent.item.kind === "web" ? "web" : parent.item.kind === "window" ? "desktop" : parent.item.kind === "app" ? Hub.glyphForApp(parent.item.data) : parent.item.icon
            font.pixelSize: parent.size * .5; color: Theme.primary
        }
    }
    component ResultRow: Rectangle {
        id: row
        property var item: null
        property bool web: false
        readonly property int order: panel.flat.indexOf(item)
        readonly property bool current: order >= 0 && order === panel.selection
        Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 16
        color: current ? Theme.secondaryContainer : rowMouse.containsMouse ? Theme.alpha(Theme.stateLayer, .06) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion(100) } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 12
            ResultIcon { item: row.item; size: 34 }
            MText {
                Layout.fillWidth: true; textFormat: Text.StyledText
                text: !row.item ? "" : row.web ? "Search the web for <b>" + panel.highlight(panel.query.replace(/^\?\s*/, "")).replace(/<\/?b>/g, "") + "</b>" : panel.highlight(row.item.title)
                font.pixelSize: 14; color: row.current ? Theme.onSecondaryContainer : Theme.text
            }
            MText { visible: !row.web && !!row.item; text: row.item ? row.item.detail || "" : ""; font.pixelSize: 11; color: Theme.subtext; Layout.maximumWidth: row.width * .4 }
            Glyph { visible: row.current; name: row.web ? "open_in_new" : "keyboard_return"; font.pixelSize: 16; color: row.current ? Theme.onSecondaryContainer : Theme.subtext }
        }
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: if (row.order >= 0) panel.selection = row.order; onClicked: panel.run(row.item, false) }
        Accessible.role: Accessible.Button
        Accessible.name: row.item ? (row.web ? "Search the web for " + panel.query : row.item.title) : ""
    }
}
