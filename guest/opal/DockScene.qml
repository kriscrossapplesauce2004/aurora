import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Dock menu on a newly connected screen. Four pages you swipe between: what this screen becomes,
// which apps come over, what the phone becomes, and display settings. Start applies all of it.
FocusScope {
    id: dock
    property string output: ""
    property string description: ""
    property bool hasPhone: true
    property var apps: []            // windows that can move here: {address, title, className}
    property var modes: []           // display modes for this output, like "2560x1440@60.00Hz"
    property var remembered: null    // last saved choice for this output, or null
    property string mode: remembered ? remembered.mode : "desktop"
    property string phoneMode: remembered ? remembered.phoneMode : "trackpad"
    property var chosenApps: apps.map(a => a.address)
    property string resolution: ""
    property real scale: 1
    property bool remember: true
    property int page: 0
    property real arrival: 0
    property bool leaving: false
    // Tests and the demo video step the animation themselves.
    property bool autoplay: true
    property alias pagerView: pager
    signal started(var choice)
    signal dismissed()
    readonly property var pages: hasPhone ? ["screen", "apps", "phone", "display"] : ["screen", "apps", "display"]
    function start() {
        leaving = true;
        if (autoplay) leave.restart();
    }
    function toggleApp(address) {
        const next = chosenApps.slice(); const i = next.indexOf(address);
        if (i >= 0) next.splice(i, 1); else next.push(address);
        chosenApps = next;
    }
    focus: true
    Keys.onLeftPressed: pager.decrementCurrentIndex()
    Keys.onRightPressed: pager.incrementCurrentIndex()
    Keys.onReturnPressed: start()
    Keys.onEscapePressed: dismissed()
    Component.onCompleted: if (autoplay) enter.restart()
    NumberAnimation { id: enter; target: dock; property: "arrival"; from: 0; to: 1; duration: Theme.motion(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate }
    SequentialAnimation {
        id: leave
        NumberAnimation { target: dock; property: "arrival"; to: 0; duration: Theme.motion(Theme.durMedium); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedAccelerate }
        ScriptAction { script: dock.started({mode: dock.mode, phoneMode: dock.phoneMode, apps: dock.mode === "mirror" ? [] : dock.chosenApps, resolution: dock.resolution, scale: dock.scale, remember: dock.remember}) }
    }
    // Remembered choices start on their own after a short countdown; any input cancels it.
    property int countdown: remembered ? 8 : 0
    Timer { interval: 1000; repeat: true; running: dock.countdown > 0 && dock.arrival >= 1 && !dock.leaving; onTriggered: { dock.countdown--; if (dock.countdown === 0) dock.start(); } }
    TapHandler { onTapped: dock.countdown = 0 }
    HoverHandler { onPointChanged: if (dock.arrival >= 1 && point.position.x > 0) dock.countdown = 0 }

    // Background: the wallpaper settles in behind a phone-shaped window that opens to the full screen.
    Rectangle { anchors.fill: parent; color: Theme.base }
    Image {
        anchors.fill: parent
        source: Hub.prefs.wallpaperPath || ""
        fillMode: Image.PreserveAspectCrop; asynchronous: true
        sourceSize: Qt.size(dock.width, dock.height)
        scale: 1.08 - .08 * dock.arrival
        opacity: .5 + .5 * dock.arrival
    }
    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.base, .62) }
    // Phone silhouette: phone proportions and corners at the start, the whole screen at the end.
    Rectangle {
        id: frame
        readonly property real p: Math.min(1, dock.arrival * 1.4)
        readonly property real phoneHeight: dock.height * .42
        width: phoneHeight * .46 + (dock.width - phoneHeight * .46) * p
        height: phoneHeight + (dock.height - phoneHeight) * p
        anchors.centerIn: parent
        radius: 36 * (1 - p)
        color: "transparent"
        border.width: 2; border.color: Theme.alpha(Theme.primary, .6 * (1 - p))
        visible: p < 1 && dock.width >= 700
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(16, dock.width * (dock.width < 700 ? .03 : .05))
        spacing: 20
        opacity: Math.max(0, (dock.arrival - .45) / .55)
        transform: Translate { y: (1 - dock.arrival) * 30 }
        // Header.
        RowLayout {
            Layout.fillWidth: true; spacing: dock.width < 700 ? 8 : 16
            Rectangle {
                Layout.preferredWidth: dock.width < 700 ? 44 : 56; Layout.preferredHeight: dock.width < 700 ? 44 : 56; radius: 18; color: Theme.primaryContainer
                Glyph { anchors.centerIn: parent; name: "cast_connected"; font.pixelSize: dock.width < 700 ? 24 : 30; color: Theme.onContainer }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 0
                MText { text: "Docked to " + (dock.description || dock.output); role: dock.width < 700 ? "title" : "headline"; Layout.fillWidth: true; elide: Text.ElideRight }
                MText { text: dock.countdown > 0 ? "Starting with your last setup in " + dock.countdown + " s" : "Set it up, then start"; role: "body"; color: Theme.subtext }
            }
            MButton { text: dock.width < 700 ? "" : "Not now"; icon: dock.width < 700 ? "close" : ""; tooltip: "Not now"; onClicked: dock.dismissed() }
            MButton { text: "Start"; icon: "arrow_forward"; filled: true; onClicked: dock.start() }
        }
        // Page tabs, also the page indicator. Tabs scroll on narrow displays.
        Flickable {
            Layout.fillWidth: true; Layout.preferredHeight: 40
            contentWidth: tabRow.width; contentHeight: 40; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: tabRow
                x: Math.max(0, (parent.width - width) / 2)
                spacing: 6
                Repeater {
                    model: dock.pages
                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: pager.currentIndex === index
                        width: tabText.implicitWidth + 32; height: 40; radius: 20
                        color: current ? Theme.secondaryContainer : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
                        MText {
                            id: tabText; anchors.centerIn: parent; role: "label"; font.weight: parent.current ? Font.Bold : Font.Medium
                            color: parent.current ? Theme.onSecondaryContainer : Theme.subtext
                            text: ({screen: "This screen", apps: "Apps", phone: "Your phone", display: "Display"})[modelData]
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pager.currentIndex = index }
                    }
                }
            }
        }
        // Pages.
        ListView {
            id: pager
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: ListView.Horizontal; snapMode: ListView.SnapOneItem; highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: Theme.motion(Theme.durMedium); boundsBehavior: Flickable.StopAtBounds; clip: true
            model: dock.pages
            currentIndex: dock.page
            onCurrentIndexChanged: dock.page = currentIndex
            delegate: Loader {
                required property string modelData
                width: pager.width; height: pager.height
                sourceComponent: modelData === "screen" ? screenPage : modelData === "apps" ? appsPage : modelData === "phone" ? phonePage : displayPage
            }
        }
    }

    // A choice card for the layout.
    component Choice: Rectangle {
        id: card
        property string title
        property string detail
        property string art: ""
        property string icon: ""
        property bool chosen: false
        property bool last: false
        signal picked()
        radius: Theme.shapeXl
        color: chosen ? Theme.primaryContainer : Theme.level(3)
        border.width: chosen ? (dock.width < 700 ? 2 : 3) : 0; border.color: Theme.primary
        Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.stateLayer; opacity: cardMouse.pressed ? .1 : cardMouse.containsMouse && !card.chosen ? .05 : 0 }
        ModeArt { visible: card.art !== ""; mode: card.art; active: card.chosen; anchors.horizontalCenter: parent.horizontalCenter; y: dock.width < 700 ? 12 : 24; width: Math.max(10, parent.width - (dock.width < 700 ? 24 : 48)); height: Math.max(10, parent.height - (dock.width < 700 ? 80 : 120)) }
        Glyph { visible: card.art === "" && (card.icon === "" || dock.width >= 700); anchors.horizontalCenter: parent.horizontalCenter; y: (parent.height - 96) / 2 - 28; name: card.icon; font.pixelSize: Math.min(dock.width < 700 ? 40 : 72, Math.max(24, parent.height * .3)); color: card.chosen ? Theme.onContainer : Theme.primary }
        Column {
            visible: card.icon === "" || dock.width >= 700
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: dock.width < 700 ? 12 : 20; spacing: 2
            Row { spacing: 8
                MText { text: card.title; role: dock.width < 700 ? "titleS" : "title"; color: card.chosen ? Theme.onContainer : Theme.text }
                Rectangle { visible: card.last; anchors.verticalCenter: parent.verticalCenter; width: lastText.implicitWidth + 14; height: 22; radius: 11; color: card.chosen ? Theme.onContainer : Theme.secondaryContainer
                    MText { id: lastText; anchors.centerIn: parent; text: "Last time"; role: "labelS"; color: card.chosen ? Theme.primaryContainer : Theme.onSecondaryContainer } }
            }
            MText { width: parent.width; text: card.detail; role: "bodyS"; wrapMode: Text.Wrap; color: card.chosen ? Theme.alpha(Theme.onContainer, .8) : Theme.subtext; maximumLineCount: dock.width < 700 ? 2 : 4; elide: Text.ElideRight }
        }
        RowLayout {
            visible: card.icon !== "" && dock.width < 700
            anchors.fill: parent; anchors.margins: 14; spacing: 14
            Glyph { Layout.alignment: Qt.AlignVCenter; name: card.icon; font.pixelSize: 32; color: card.chosen ? Theme.onContainer : Theme.primary }
            ColumnLayout {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 2
                RowLayout {
                    spacing: 8
                    MText { text: card.title; role: "titleS"; color: card.chosen ? Theme.onContainer : Theme.text }
                    Rectangle { visible: card.last; Layout.preferredWidth: lastTextH.implicitWidth + 14; Layout.preferredHeight: 20; radius: 10; color: card.chosen ? Theme.onContainer : Theme.secondaryContainer
                        MText { id: lastTextH; anchors.centerIn: parent; text: "Last time"; role: "labelS"; color: card.chosen ? Theme.primaryContainer : Theme.onSecondaryContainer } }
                }
                MText { Layout.fillWidth: true; text: card.detail; role: "bodyS"; wrapMode: Text.Wrap; color: card.chosen ? Theme.alpha(Theme.onContainer, .8) : Theme.subtext; maximumLineCount: 2; elide: Text.ElideRight }
            }
        }
        MouseArea { id: cardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.picked() }
        Accessible.role: Accessible.RadioButton; Accessible.name: title; Accessible.checked: chosen
    }

    Component {
        id: screenPage
        GridLayout {
            anchors.fill: parent
            columns: dock.width < 700 ? 2 : 4
            columnSpacing: 12; rowSpacing: 12
            Repeater {
                model: [{id: "desktop", title: "Desktop", detail: "Windows, a bar and Start on the big screen.", art: "desktop"},
                        {id: "console", title: "Play", detail: "Your game library, controller first.", art: "console"},
                        {id: "phone", title: "Touch", detail: "A big touch home, for a touch monitor or tablet.", art: "phone"},
                        {id: "mirror", title: "Mirror", detail: "Show the phone screen as it is.", art: "mirror"}]
                Choice {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.maximumHeight: dock.width < 700 ? 260 : 420
                    title: modelData.title; detail: modelData.detail; art: modelData.art
                    chosen: dock.mode === modelData.id; last: !!dock.remembered && dock.remembered.mode === modelData.id
                    onPicked: { dock.mode = modelData.id; dock.countdown = 0; }
                }
            }
        }
    }
    Component {
        id: appsPage
        ColumnLayout {
            anchors.fill: parent
            spacing: 14
            RowLayout { Layout.fillWidth: true
                MText { text: dock.mode === "mirror" ? "Mirror shows the phone as it is, so apps stay put." : dock.apps.length ? "Pick the apps to bring to this screen." : "No apps are open on the phone."; role: "title"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                MButton { visible: dock.apps.length > 0 && dock.mode !== "mirror"; text: dock.chosenApps.length === dock.apps.length ? "None" : "All"; tonal: true; onClicked: dock.chosenApps = dock.chosenApps.length === dock.apps.length ? [] : dock.apps.map(a => a.address) }
            }
            GridView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                enabled: dock.mode !== "mirror"; opacity: enabled ? 1 : .4
                cellWidth: Math.max(220, width / Math.max(1, Math.floor(width / 260))); cellHeight: 120
                model: dock.apps
                delegate: Item {
                    required property var modelData
                    width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    Rectangle {
                        id: appCard
                        readonly property bool chosen: dock.chosenApps.indexOf(parent.modelData.address) >= 0
                        readonly property var app: Hub.appForWindow(parent.modelData)
                        anchors.fill: parent; anchors.margins: 6
                        radius: Theme.shapeLg; color: chosen ? Theme.primaryContainer : Theme.level(3)
                        border.width: chosen ? 2 : 0; border.color: Theme.primary
                        RowLayout { anchors.fill: parent; anchors.margins: 16; spacing: 14
                            AppIcon { Layout.preferredWidth: 48; Layout.preferredHeight: 48; app: appCard.app; name: appCard.app ? appCard.app.icon : (appCard.parent.modelData.className || "").toLowerCase() }
                            ColumnLayout { Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 0
                                MText { text: appCard.app ? appCard.app.name : appCard.parent.modelData.title; role: "titleS"; Layout.fillWidth: true; color: appCard.chosen ? Theme.onContainer : Theme.text }
                                MText { text: appCard.app ? appCard.parent.modelData.title : "Open window"; role: "labelS"; Layout.fillWidth: true; color: appCard.chosen ? Theme.alpha(Theme.onContainer, .8) : Theme.subtext } }
                            Glyph { name: appCard.chosen ? "check_circle" : "add_circle"; font.pixelSize: 26; color: appCard.chosen ? Theme.onContainer : Theme.subtext }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { dock.toggleApp(appCard.parent.modelData.address); dock.countdown = 0; } }
                    }
                }
            }
        }
    }
    Component {
        id: phonePage
        GridLayout {
            anchors.fill: parent
            columns: dock.width < 700 ? 1 : 3
            columnSpacing: 12; rowSpacing: 12
            Repeater {
                model: [{id: "trackpad", title: "Trackpad", detail: "Drag to move, tap to click, two fingers to scroll. Keyboard one tap away.", icon: "touchpad_mouse"},
                        {id: "screen", title: "Second screen", detail: "The phone keeps its own home and apps.", icon: "smartphone"},
                        {id: "panel", title: "Control panel", detail: "Music, notifications and moving apps between screens.", icon: "dashboard"}]
                Choice {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.maximumHeight: dock.width < 700 ? 130 : 420
                    title: modelData.title; detail: modelData.detail; icon: modelData.icon
                    chosen: dock.phoneMode === modelData.id; last: !!dock.remembered && dock.remembered.phoneMode === modelData.id
                    onPicked: { dock.phoneMode = modelData.id; dock.countdown = 0; }
                }
            }
        }
    }
    Component {
        id: displayPage
        ColumnLayout {
            anchors.fill: parent
            spacing: 14
            MText { text: "Resolution"; role: "label"; color: Theme.primary }
            Flow {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: dock.modes.length ? dock.modes.slice(0, 8) : ["preferred"]
                    Rectangle {
                        required property string modelData
                        readonly property bool chosen: (dock.resolution || (dock.modes[0] || "preferred")) === modelData
                        width: resText.implicitWidth + 32; height: 44; radius: 22
                        color: chosen ? Theme.primaryContainer : Theme.level(3)
                        MText { id: resText; anchors.centerIn: parent; text: modelData === "preferred" ? "Best for this screen" : modelData.replace("Hz", " Hz"); role: "label"; color: parent.chosen ? Theme.onContainer : Theme.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { dock.resolution = modelData; dock.countdown = 0; } }
                    }
                }
            }
            MText { text: "Size of things"; role: "label"; color: Theme.primary; Layout.topMargin: 8 }
            SegmentedButtons {
                Layout.fillWidth: true; Layout.maximumWidth: 640; current: dock.scale
                options: [1, 1.25, 1.5, 2].map(v => ({value: v, label: Math.round(v * 100) + "%", icon: ""}))
                onPicked: value => { dock.scale = value; dock.countdown = 0; }
            }
            SettingToggle {
                Layout.fillWidth: true; Layout.maximumWidth: 640; Layout.topMargin: 8
                icon: "bookmark"; title: "Remember this screen"; description: "Next time, start with this setup on its own"
                checked: dock.remember; onToggled: dock.remember = !checked
            }
            Item { Layout.fillHeight: true }
        }
    }
}
