import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
// Display arrangement, resolution, scale and rotation. Changes revert after 15 seconds unless you keep them.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    property var draft: []
    property var previous: []
    property int selected: 0
    property int countdown: 0
    readonly property var current: draft[selected] || null
    function load() { draft = Hub.monitors.map(m => ({name: m.name, description: m.description, width: m.width, height: m.height, x: m.x, y: m.y, scale: m.scale, transform: m.transform, disabled: m.disabled, mirror: m.mirror, modes: m.modes, mode: m.width + "x" + m.height + "@" + m.refresh.toFixed(2)})); }
    function specs(list) { return list.map(d => ({name: d.name, mode: d.mode, x: Math.round(d.x), y: Math.round(d.y), scale: d.scale, transform: d.transform, disabled: !!d.disabled, mirror: d.mirror || "none"})); }
    function edit(change) { const next = draft.slice(); next[selected] = Object.assign({}, next[selected], change); draft = next; }
    function apply() { previous = specs(Hub.monitors.map(m => ({name: m.name, mode: m.width + "x" + m.height + "@" + m.refresh.toFixed(2), x: m.x, y: m.y, scale: m.scale, transform: m.transform, disabled: m.disabled, mirror: m.mirror}))); Hub.command({action: "monitors-apply", displays: specs(draft), keep: false}); countdown = 15; }
    function keep() { countdown = 0; Hub.command({action: "monitors-apply", displays: specs(draft), keep: true}); Hub.message("Display settings saved"); }
    function revert() { countdown = 0; if (previous.length) Hub.command({action: "monitors-apply", displays: previous, keep: false}); }
    Component.onCompleted: Hub.command({action: "monitors"})
    Connections { target: Hub; function onMonitorsChanged() { if (page.countdown === 0) page.load(); } }
    Timer { interval: 1000; repeat: true; running: page.countdown > 0; onTriggered: { page.countdown--; if (page.countdown === 0) page.revert(); } }

    // Logical size after scale and rotation.
    function logical(d) { const [w, h] = (d.mode || "").split("@")[0].split("x").map(Number); const turned = d.transform % 2 === 1; return {w: (turned ? h : w) / d.scale, h: (turned ? w : h) / d.scale}; }
    readonly property var bounds: {
        let minX = 0, minY = 0, maxX = 1, maxY = 1;
        draft.forEach(d => { const s = logical(d); minX = Math.min(minX, d.x); minY = Math.min(minY, d.y); maxX = Math.max(maxX, d.x + s.w); maxY = Math.max(maxY, d.y + s.h); });
        return {x: minX, y: minY, w: maxX - minX, h: maxY - minY};
    }

    ColumnLayout {
        id: column; width: parent.width; spacing: 12
        // Keep or revert banner.
        Rectangle {
            visible: page.countdown > 0; Layout.fillWidth: true; implicitHeight: 64; radius: Theme.shapeLg; color: Theme.primaryContainer
            RowLayout { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 10; spacing: 10
                MText { text: "Keep these display settings? Reverting in " + page.countdown + " s"; role: "titleS"; color: Theme.onContainer; Layout.fillWidth: true; wrapMode: Text.Wrap }
                MButton { text: "Revert"; compact: true; onClicked: page.revert() }
                MButton { text: "Keep"; compact: true; filled: true; onClicked: page.keep() } }
        }
        // Layout for the whole shell.
        MText { text: "Layout"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
        SegmentedButtons {
            Layout.fillWidth: true; current: Hub.prefs.mode || "auto"
            options: [{value: "auto", label: "Flow", icon: "auto_awesome"}, {value: "desktop", label: "Desktop", icon: "desktop_windows"}, {value: "phone", label: "Phone", icon: "smartphone"}, {value: "console", label: "Play", icon: "sports_esports"}]
            onPicked: value => Hub.mode(value)
        }
        MText { text: Hub.prefs.mode === "auto" ? "Flow: each screen picks its own layout below." : "Every screen uses this layout. Choose Flow to set screens one by one."; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6; Layout.bottomMargin: 6; wrapMode: Text.Wrap; Layout.fillWidth: true }
        // Automatic switching: per-trigger preferences with undo.
        MText { text: "Automatic"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
        ConvergenceSettings { Layout.fillWidth: true; Layout.bottomMargin: 6 }
        MText { visible: page.draft.length === 0; text: "No displays reported. Display settings need Hyprland."; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6 }
        // Arrangement: drag displays; they snap to each other's edges.
        Rectangle {
            id: canvas
            visible: page.draft.length > 0
            Layout.fillWidth: true; Layout.preferredHeight: 220; radius: Theme.shapeXl; color: Theme.level(2)
            readonly property real ratio: Math.min((width - 48) / page.bounds.w, (height - 48) / page.bounds.h)
            Repeater {
                model: page.draft
                Rectangle {
                    id: screen
                    required property var modelData
                    required property int index
                    readonly property var size: page.logical(modelData)
                    x: 24 + (modelData.x - page.bounds.x) * canvas.ratio; y: 24 + (modelData.y - page.bounds.y) * canvas.ratio
                    width: size.w * canvas.ratio; height: size.h * canvas.ratio
                    radius: Theme.shapeSm
                    color: index === page.selected ? Theme.primaryContainer : Theme.level(4)
                    opacity: modelData.disabled ? .4 : 1
                    border.width: index === page.selected ? 2 : 0; border.color: Theme.primary
                    MText { anchors.centerIn: parent; text: modelData.name; role: "label"; color: index === page.selected ? Theme.onContainer : Theme.text }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                        drag.target: page.draft.length > 1 ? screen : null
                        onPressed: page.selected = screen.index
                        onReleased: {
                            if (!drag.active && screen.x === 24 + (screen.modelData.x - page.bounds.x) * canvas.ratio) return;
                            let nx = (screen.x - 24) / canvas.ratio + page.bounds.x, ny = (screen.y - 24) / canvas.ratio + page.bounds.y;
                            // Snap to the nearest edge of another display.
                            page.draft.forEach((o, i) => { if (i === screen.index) return; const s = page.logical(o);
                                [[o.x + s.w, "x"], [o.x - screen.size.w, "x"], [o.x, "x"]].forEach(([v]) => { if (Math.abs(nx - v) < 120) nx = v; });
                                [[o.y, "y"], [o.y + s.h, "y"], [o.y - screen.size.h, "y"]].forEach(([v]) => { if (Math.abs(ny - v) < 120) ny = v; }); });
                            page.selected = screen.index; page.edit({x: Math.round(nx), y: Math.round(ny)});
                        }
                    }
                }
            }
        }
        // Selected display.
        ColumnLayout {
            visible: page.current !== null; Layout.fillWidth: true; spacing: 8
            RowLayout { Layout.fillWidth: true
                ColumnLayout { Layout.fillWidth: true; spacing: 0
                    MText { text: page.current ? page.current.name : ""; role: "title" }
                    MText { text: page.current ? page.current.description : ""; role: "labelS"; color: Theme.subtext; Layout.fillWidth: true } }
                MSwitch { visible: page.draft.length > 1; checked: page.current ? !page.current.disabled : true; onToggled: value => page.edit({disabled: !value}) }
            }
            MText { text: "This screen becomes"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
            SegmentedButtons {
                Layout.fillWidth: true; enabledAll: Hub.prefs.mode === "auto"
                current: page.current ? ((Hub.prefs.displayModes || {})[page.current.name] || "auto") : "auto"
                options: [{value: "auto", label: "Auto", icon: "auto_awesome"}, {value: "desktop", label: "Desktop", icon: "desktop_windows"}, {value: "phone", label: "Touch", icon: "smartphone"}, {value: "console", label: "Play", icon: "sports_esports"}]
                onPicked: value => { if (page.current && Hub.prefs.mode === "auto") Hub.displayMode(page.current.name, value); }
            }
            MText { text: "When it connects"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 6 }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                readonly property var saved: page.current ? (Hub.prefs.dockChoices || {})[page.current.name] : null
                MText { Layout.fillWidth: true; wrapMode: Text.Wrap; role: "bodyS"; color: Theme.subtext
                    text: parent.saved ? "Starts with your saved setup: " + ({desktop: "Desktop", console: "Play", phone: "Touch", mirror: "Mirror"})[parent.saved.mode] + ", phone as " + ({trackpad: "trackpad", screen: "second screen", panel: "control panel"})[parent.saved.phoneMode] + "." : "Shows the dock menu so you can choose." }
                MButton { visible: !!parent.saved; text: "Forget"; compact: true; onClicked: { const next = Object.assign({}, Hub.prefs.dockChoices || {}); delete next[page.current.name]; Hub.set("dockChoices", next); } }
                MButton { text: "Show dock menu"; icon: "cast_connected"; compact: true; tonal: true
                    onClicked: { const screen = Quickshell.screens.find(s => page.current && s.name === page.current.name); if (screen) { Hub.close(); Hub.dockScreen = screen; Hub.dockMenu = true; } } }
            }
            MText { text: "Resolution"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 6 }
            ComboBox {
                id: modeBox
                Layout.fillWidth: true; implicitHeight: 48
                background: Rectangle { radius: 24; color: Theme.level(3) }
                contentItem: MText { leftPadding: 18; text: modeBox.displayText; role: "body"; verticalAlignment: Text.AlignVCenter }
                indicator: Glyph { x: modeBox.width - width - 16; anchors.verticalCenter: parent.verticalCenter; name: "expand_more"; font.pixelSize: 20; color: Theme.subtext }
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: modeBox.width
                    contentItem: MText { text: modelData; role: "body"; color: index === modeBox.currentIndex ? Theme.primary : Theme.text }
                    background: Rectangle { color: hovered ? Theme.level(4) : Theme.level(3) }
                }
                popup.background: Rectangle { radius: Theme.shapeMd; color: Theme.level(3) }
                model: page.current ? page.current.modes.map(m => m.replace("Hz", " Hz")) : []
                currentIndex: page.current ? Math.max(0, page.current.modes.findIndex(m => m.replace("Hz", "") === page.current.mode)) : 0
                onActivated: index => page.edit({mode: page.current.modes[index].replace("Hz", "")})
            }
            MText { text: "Scale"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
            SegmentedButtons {
                Layout.fillWidth: true; current: page.current ? page.current.scale : 1
                options: [1, 1.25, 1.5, 1.75, 2].map(v => ({value: v, label: Math.round(v * 100) + "%", icon: ""}))
                onPicked: value => page.edit({scale: value})
            }
            MText { text: "Rotation"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
            SegmentedButtons {
                Layout.fillWidth: true; current: page.current ? page.current.transform % 4 : 0
                options: [{value: 0, label: "None", icon: ""}, {value: 1, label: "90°", icon: ""}, {value: 2, label: "180°", icon: ""}, {value: 3, label: "270°", icon: ""}]
                onPicked: value => page.edit({transform: value})
            }
            MText { visible: page.draft.length > 1; text: "Mirror"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
            SegmentedButtons {
                visible: page.draft.length > 1; Layout.fillWidth: true; current: page.current ? page.current.mirror || "none" : "none"
                options: [{value: "none", label: "Off", icon: ""}].concat(page.draft.filter((d, i) => i !== page.selected).map(d => ({value: d.name, label: d.name, icon: ""})))
                onPicked: value => page.edit({mirror: value})
            }
        }
        RowLayout {
            visible: page.draft.length > 0; Layout.fillWidth: true; Layout.topMargin: 6
            MText { text: "Saved settings load whenever Opal is on."; role: "labelS"; color: Theme.subtext; Layout.fillWidth: true; wrapMode: Text.Wrap }
            MButton { text: "Reset"; compact: true; onClicked: page.load() }
            MButton { text: "Apply"; filled: true; compact: true; enabled: page.countdown === 0; onClicked: page.apply() }
        }
    }
}
