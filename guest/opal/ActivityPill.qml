import QtQuick

// Dynamic-island style pill. Compact by default, expands in place on tap or hover.
Rectangle {
    id: pill
    property var output: null
    // Fill colour. A transparent pill draws only its content.
    property bool framed: true
    // The lock screen lists every activity as a column of rows.
    property bool stack: false
    property bool expandOnHover: false
    // Notification-based activities stay hidden when the lock privacy mode hides them.
    property bool hideNotes: false
    property real pillHeight: 40
    property real maxCompact: 190
    property real maxExpanded: 420
    property color ink: Theme.onSecondaryContainer
    property bool pinned: false
    property string selectedId: ""
    property var shownIds: []
    readonly property bool hovered: hover.hovered
    readonly property bool expanded: pinned || (expandOnHover && hover.hovered)
    readonly property var primary: shownIds.length ? Activities.byId[shownIds[0]] : null
    readonly property var current: Activities.byId[selectedId] || primary
    readonly property int extra: Math.max(0, shownIds.length - 1)
    readonly property real stackRowHeight: 48

    function syncIds() {
        const next = Activities.ids.filter(id => !(hideNotes && Activities.byId[id] && Activities.byId[id].nid !== undefined));
        if (JSON.stringify(next) !== JSON.stringify(shownIds)) shownIds = next;
        if (!shownIds.length) pinned = false;
        if (shownIds.indexOf(selectedId) < 0) selectedId = shownIds.length ? shownIds[0] : "";
    }
    Component.onCompleted: syncIds()
    onHideNotesChanged: syncIds()
    Connections { target: Activities; function onIdsChanged() { pill.syncIds(); } }

    opacity: shownIds.length ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durShort) } }
    height: stack && expanded ? Math.max(pillHeight, shownIds.length * stackRowHeight + 12) : pillHeight
    radius: stack && expanded ? 24 : height / 2
    width: expanded ? (stack ? maxExpanded : Math.min(maxExpanded, expandedContent.implicitWidth + 20)) : Math.min(maxCompact, compactRow.implicitWidth + 20)
    color: framed ? Theme.secondaryContainer : "transparent"
    clip: true
    Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }
    Behavior on radius { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.OutCubic } }

    HoverHandler { id: hover }
    // Touch has no hover, so an open pill folds away on its own.
    Timer { interval: 8000; running: pill.pinned && !pill.hovered; onTriggered: pill.pinned = false }
    MouseArea {
        id: body
        anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor
        onClicked: pill.pinned ? Activities.open(pill.current, pill.output) : pill.pinned = true
    }

    // Compact: the top activity, and a count when more wait behind it.
    Row {
        id: compactRow
        visible: !pill.expanded; anchors.verticalCenter: parent.verticalCenter; x: 10; spacing: 8
        ActivitySegment { a: pill.primary || ({}); ink: pill.ink; maxWidth: pill.maxCompact - 20 - (pill.extra > 0 ? 34 : 0); anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            visible: pill.extra > 0; width: 26; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter
            color: Theme.alpha(pill.ink, .16)
            MText { anchors.centerIn: parent; text: "+" + pill.extra; role: "labelS"; font.weight: Font.DemiBold; color: pill.ink }
        }
    }

    // Expanded: one activity with controls and a switcher, or every activity in a column on the lock screen.
    Item {
        id: expandedContent
        visible: pill.expanded
        x: 10; y: pill.stack ? 6 : 0; height: pill.stack ? pill.height - 12 : pill.height
        implicitWidth: pill.stack ? pill.maxExpanded : pagedRow.implicitWidth
        width: pill.width - 20
        Row {
            id: pagedRow
            visible: !pill.stack; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            ActivitySegment {
                a: pill.current || ({}); ink: pill.ink; detailed: true; output: pill.output
                reserve: pill.extra * 30 + 36; maxWidth: pill.maxExpanded - 20
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Repeater {
                    model: pill.extra > 0 ? pill.shownIds : []
                    Rectangle {
                        required property string modelData
                        readonly property var item: Activities.byId[modelData] || ({})
                        width: 28; height: 28; radius: 14; anchors.verticalCenter: parent.verticalCenter
                        color: modelData === pill.selectedId ? Theme.alpha(pill.ink, .22) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
                        Glyph { anchors.centerIn: parent; name: item.icon || "spark"; font.pixelSize: 15; color: pill.ink; opacity: modelData === pill.selectedId ? 1 : .6 }
                        MouseArea { anchors.fill: parent; onClicked: pill.selectedId = modelData; Accessible.role: Accessible.Button; Accessible.name: item.title || "Activity" }
                    }
                }
                MButton { icon: "expand"; compact: true; implicitWidth: 28; implicitHeight: 28; ink: pill.ink; tooltip: "Collapse"; rotation: 180; visible: pill.pinned; onClicked: pill.pinned = false }
            }
        }
        Column {
            id: stackColumn
            visible: pill.stack; width: parent.width; spacing: 0
            Repeater {
                model: pill.stack ? pill.shownIds : []
                Item {
                    required property string modelData
                    width: stackColumn.width; height: pill.stackRowHeight
                    ActivitySegment {
                        a: Activities.byId[modelData] || ({}); ink: pill.ink; detailed: true; output: pill.output
                        width: parent.width; maxWidth: parent.width; anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: shownIds.length ? (primary ? primary.title : "Activity") + (extra > 0 ? ", plus " + extra + " more" : "") : "Activities"
    Accessible.description: expanded ? "Open" : "Expand"
}
