import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

// Shared lock and greeter scene: a clock hero on the wallpaper; any input reveals the password pill.
FocusScope {
    id: scene
    property string mode: "lock"
    readonly property bool greeter: mode === "greeter"
    // Account shown in the auth column.
    property string userName: ""
    property string avatar: ""
    // Authentication state from PAM or greetd.
    property string prompt: "Password"
    property string error: ""
    property bool busy: false
    property bool echo: false
    property bool needsResponse: true
    // Lock extras.
    property var notificationGroups: []
    // Greeter extras.
    property var users: []
    property int userIndex: 0
    property var sessions: []
    property int sessionIndex: 0
    property string keyboardLayout: ""
    property var whatsNew: []
    property bool whatsNewOpen: false
    signal submitted(string response)
    signal powerRequested(string verb)
    signal userPicked(int index)
    signal sessionPicked(int index)

    property bool revealed: greeter
    property string confirmPower: ""
    function reveal() { revealed = true; field.forceActiveFocus(); idle.restart(); }
    function clear() { field.text = ""; }
    onErrorChanged: if (error !== "") { field.text = ""; reveal(); }
    // An unlocked-looking idle screen returns to the clock hero after a while.
    Timer { id: idle; interval: 20000; onTriggered: if (!scene.greeter && field.text === "" && !scene.busy) scene.revealed = false }
    focus: true
    Keys.onPressed: event => {
        if (scene.confirmPower !== "") { if (event.key === Qt.Key_Escape) { scene.confirmPower = ""; event.accepted = true; } return; }
        if (!scene.revealed) {
            scene.reveal();
            if (event.text && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) field.insert(field.cursorPosition, event.text);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) { field.text = ""; if (!scene.greeter) scene.revealed = false; event.accepted = true; }
    }

    // Wallpaper. Revealing softens it so the auth column reads clearly.
    Rectangle { anchors.fill: parent; color: Theme.base }
    Image {
        id: wallpaper
        anchors.fill: parent
        source: Hub.prefs.wallpaperPath || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: false
        sourceSize: Qt.size(scene.width, scene.height)
    }
    // Blur sits on top of the sharp image, so software rendering still shows the wallpaper.
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready && blur > 0
        blurEnabled: true; blurMax: 48
        blur: scene.revealed ? 1 : 0
        Behavior on blur { NumberAnimation { duration: Theme.motion(Theme.durLong); easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent; color: "#000000"
        opacity: (scene.revealed ? .42 : .22) + (Hub.prefs.wallpaperDim || 0) * .5
        Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durLong) } }
    }
    MouseArea { anchors.fill: parent; onClicked: { if (scene.confirmPower !== "") scene.confirmPower = ""; else scene.reveal(); } }
    // Touch: swipe up to reveal the password pill.
    DragHandler {
        target: null; xAxis.enabled: false
        onActiveChanged: if (!active && translation.y < -60) scene.reveal()
    }
    MText {
        visible: !scene.revealed && !scene.greeter
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 96
        text: "Swipe up or press any key"; role: "label"; color: Theme.alpha("#ffffff", .7)
    }

    // Clock hero. It moves up and shrinks when the auth column appears.
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: scene.revealed ? scene.height * .1 : scene.height * .2
        scale: scene.revealed ? .55 : 1
        transformOrigin: Item.Top
        spacing: 4
        Behavior on y { NumberAnimation { duration: Theme.motion(Theme.durLong); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
        Behavior on scale { NumberAnimation { duration: Theme.motion(Theme.durLong); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
        MText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(Hub.now, "HH:mm")
            font.pixelSize: Math.min(200, scene.width * .16)
            font.weight: Font.Black
            font.variableAxes: ({"wdth": 125, "ROND": 100})
            font.features: {"tnum": 1}
            color: "#ffffff"
        }
        MText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(Hub.now, "dddd d MMMM")
            role: "title"; font.pixelSize: 22
            color: Theme.alpha("#ffffff", .85)
        }
    }

    // Auth column.
    Column {
        id: auth
        anchors.horizontalCenter: parent.horizontalCenter
        y: scene.height * .42
        width: Math.min(360, scene.width - 48)
        spacing: 14
        opacity: scene.revealed ? 1 : 0
        visible: opacity > 0
        transform: Translate { y: scene.revealed ? 0 : 24; Behavior on y { NumberAnimation { duration: Theme.motion(Theme.durLong); easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durMedium) } }
        // Greeter user picker.
        Row {
            visible: scene.greeter && scene.users.length > 1
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Repeater {
                model: scene.users
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: index === scene.userIndex
                    width: current ? 0 : 44; height: 44; radius: 22
                    visible: !current
                    color: Theme.alpha("#ffffff", userMouse.containsMouse ? .28 : .16)
                    MText { anchors.centerIn: parent; text: (modelData.name || modelData.login || "?").charAt(0).toUpperCase(); role: "titleS"; color: "#ffffff" }
                    MouseArea { id: userMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: scene.userPicked(index) }
                    Accessible.role: Accessible.Button; Accessible.name: "Switch to " + (modelData.name || modelData.login)
                }
            }
        }
        // Avatar.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88; height: 88; radius: 44
            color: Theme.primaryContainer
            clip: true
            Image { id: face; anchors.fill: parent; source: scene.avatar; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready; asynchronous: true }
            MText { anchors.centerIn: parent; visible: !face.visible; text: (scene.userName || "?").charAt(0).toUpperCase(); role: "displayS"; color: Theme.onContainer }
        }
        MText { anchors.horizontalCenter: parent.horizontalCenter; text: scene.userName; role: "headline"; color: "#ffffff" }
        // Password pill.
        Rectangle {
            width: parent.width; height: 56; radius: 28
            color: Theme.level(3)
            border.width: field.activeFocus ? 2 : 0; border.color: scene.error !== "" ? Theme.error : Theme.primary
            opacity: scene.needsResponse ? 1 : .6
            TextInput {
                id: field
                anchors.left: parent.left; anchors.right: go.left; anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 22; anchors.rightMargin: 10
                enabled: !scene.busy && scene.needsResponse
                echoMode: scene.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "●"
                color: Theme.text; selectionColor: Theme.primary; selectedTextColor: Theme.onPrimary
                font.family: Theme.font; font.pixelSize: 18; font.letterSpacing: scene.echo ? 0 : 2
                clip: true
                onTextEdited: idle.restart()
                onAccepted: if (text !== "" || scene.echo) scene.submitted(text)
                Keys.onEscapePressed: event => { event.accepted = false; }
                MText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text === ""
                    text: scene.busy ? "Checking…" : scene.prompt.replace(/:\s*$/, "")
                    role: "body"; color: Theme.subtext
                }
                Accessible.role: Accessible.EditableText; Accessible.name: scene.prompt
            }
            Rectangle {
                id: go
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44; radius: 22
                color: field.text !== "" ? Theme.primary : Theme.level(4)
                Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
                Glyph { anchors.centerIn: parent; name: scene.busy ? "progress_activity" : "arrow_forward"; font.pixelSize: 22; color: field.text !== "" ? Theme.onPrimary : Theme.subtext
                    RotationAnimation on rotation { running: scene.busy && !Theme.reduceMotion; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !scene.busy; onClicked: field.accepted() }
                Accessible.role: Accessible.Button; Accessible.name: scene.greeter ? "Log in" : "Unlock"
            }
        }
        MText {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            visible: text !== "" && field.text === ""; text: scene.error
            role: "bodyS"; color: "#ffb4ab"
        }
    }

    // Bottom row.
    RowLayout {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: 12
        // Lock: now playing.
        Rectangle {
            visible: !scene.greeter && Hub.status.track !== ""
            Layout.preferredHeight: 56; Layout.preferredWidth: Math.min(360, mediaRow.implicitWidth + 24)
            radius: 28; color: Theme.level(3)
            Row {
                id: mediaRow; anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 10
                Rectangle { width: 40; height: 40; radius: 20; color: Theme.secondary; clip: true; anchors.verticalCenter: parent.verticalCenter
                    Image { anchors.fill: parent; source: Hub.status.art || ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready; asynchronous: true; sourceSize: Qt.size(80, 80) }
                    Glyph { anchors.centerIn: parent; visible: !Hub.status.art; name: "music"; font.pixelSize: 20; color: Theme.base } }
                Column { anchors.verticalCenter: parent.verticalCenter; width: Math.min(170, Math.max(trackText.implicitWidth, 60))
                    MText { id: trackText; width: parent.width; text: Hub.status.track; role: "label"; font.weight: Font.DemiBold }
                    MText { width: parent.width; text: Hub.status.artist || ""; role: "labelS"; color: Theme.subtext } }
                MButton { anchors.verticalCenter: parent.verticalCenter; icon: "previous"; compact: true; implicitWidth: 36; implicitHeight: 36; tooltip: "Previous"; onClicked: Hub.media("previous") }
                MButton { anchors.verticalCenter: parent.verticalCenter; icon: Hub.status.playing ? "pause" : "play"; compact: true; filled: true; implicitWidth: 40; implicitHeight: 36; tooltip: Hub.status.playing ? "Pause" : "Play"; onClicked: Hub.media("play-pause") }
                MButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip"; compact: true; implicitWidth: 36; implicitHeight: 36; tooltip: "Next"; onClicked: Hub.media("next") }
            }
        }
        // Greeter: session and keyboard layout.
        Rectangle {
            id: sessionChip
            visible: scene.greeter && scene.sessions.length > 0
            Layout.preferredHeight: 48; Layout.preferredWidth: sessionRow.implicitWidth + 32
            radius: 24; color: Theme.level(3)
            Row { id: sessionRow; anchors.centerIn: parent; spacing: 8
                Glyph { name: "desktop_windows"; font.pixelSize: 19; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                MText { text: scene.sessions.length ? scene.sessions[scene.sessionIndex].name : ""; role: "label"; anchors.verticalCenter: parent.verticalCenter }
                Glyph { name: sessionList.visible ? "expand_less" : "expand_more"; font.pixelSize: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sessionList.visible = !sessionList.visible }
            Accessible.role: Accessible.ComboBox; Accessible.name: "Session"
        }
        Rectangle {
            visible: scene.greeter && scene.keyboardLayout !== ""
            Layout.preferredHeight: 48; Layout.preferredWidth: layoutRow.implicitWidth + 28
            radius: 24; color: Theme.level(3)
            Row { id: layoutRow; anchors.centerIn: parent; spacing: 8
                Glyph { name: "keyboard"; font.pixelSize: 19; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                MText { text: scene.keyboardLayout; role: "label"; anchors.verticalCenter: parent.verticalCenter } }
        }
        Item { Layout.fillWidth: true }
        // Lock: notification counts per app, no content.
        Repeater {
            model: scene.greeter || (Hub.prefs.lockNotifications || "title") !== "count" ? [] : scene.notificationGroups.slice(0, 4)
            Rectangle {
                required property var modelData
                Layout.preferredHeight: 40; Layout.preferredWidth: countRow.implicitWidth + 22
                radius: 20; color: Theme.level(3)
                Row { id: countRow; anchors.centerIn: parent; spacing: 6
                    Image { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter; sourceSize: Qt.size(36, 36); source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""; visible: status === Image.Ready }
                    MText { text: modelData.count; role: "label"; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
                Accessible.name: modelData.count + " notifications from " + modelData.app
            }
        }
        // Status and power.
        Rectangle {
            Layout.preferredHeight: 48; Layout.preferredWidth: statusRow.implicitWidth + 24
            radius: 24; color: Theme.level(3)
            Row { id: statusRow; anchors.centerIn: parent; spacing: 10
                Glyph { visible: !scene.greeter && Hub.status.battery >= 0; name: Hub.status.charging ? "charging" : "battery"; font.pixelSize: 19; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                MText { visible: !scene.greeter && Hub.status.battery >= 0; text: Hub.status.battery + "%"; role: "label"; anchors.verticalCenter: parent.verticalCenter }
                Glyph { visible: !scene.greeter; name: Hub.status.wifi ? "wifi" : "wifiOff"; font.pixelSize: 19; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                MButton { icon: "power"; compact: true; implicitWidth: 36; implicitHeight: 36; tooltip: "Power"; onClicked: scene.confirmPower = scene.confirmPower === "" ? "menu" : "" }
            }
        }
    }

    // Session list for the greeter.
    Rectangle {
        id: sessionList
        visible: false
        x: sessionChip.mapToItem(scene, 0, 0).x; y: scene.height - 28 - 48 - 8 - height
        width: 260; height: sessionColumn.implicitHeight + 16
        radius: Theme.shapeLg; color: Theme.level(3)
        Column { id: sessionColumn; x: 8; y: 8; width: parent.width - 16
            Repeater {
                model: scene.sessions
                Rectangle {
                    required property var modelData
                    required property int index
                    width: sessionColumn.width; height: 44; radius: Theme.shapeMd
                    color: index === scene.sessionIndex ? Theme.secondaryContainer : sessionMouse.containsMouse ? Theme.level(4) : "transparent"
                    MText { anchors.verticalCenter: parent.verticalCenter; x: 14; text: modelData.name; role: "body"; color: index === scene.sessionIndex ? Theme.onSecondaryContainer : Theme.text }
                    MouseArea { id: sessionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { scene.sessionPicked(index); sessionList.visible = false; } }
                }
            }
        }
    }

    // Power menu.
    Rectangle {
        visible: scene.confirmPower !== ""
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 28; anchors.bottomMargin: 28 + 48 + 8
        width: 240; height: powerColumn.implicitHeight + 16
        radius: Theme.shapeLg; color: Theme.level(3)
        Column {
            id: powerColumn; x: 8; y: 8; width: parent.width - 16; spacing: 2
            Repeater {
                model: scene.confirmPower === "menu" ? [{id: "suspend", name: "Sleep", icon: "sleep"}, {id: "reboot", name: "Restart", icon: "restart"}, {id: "poweroff", name: "Power off", icon: "power"}] : [{id: scene.confirmPower, name: scene.confirmPower === "reboot" ? "Restart now" : scene.confirmPower === "suspend" ? "Sleep now" : "Power off now", icon: "check"}, {id: "", name: "Cancel", icon: "close"}]
                Rectangle {
                    required property var modelData
                    width: powerColumn.width; height: 44; radius: Theme.shapeMd
                    color: powerMouse.containsMouse ? Theme.level(4) : "transparent"
                    Row { anchors.verticalCenter: parent.verticalCenter; x: 14; spacing: 12
                        Glyph { name: modelData.icon; font.pixelSize: 19; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        MText { text: modelData.name; role: "body"; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (scene.confirmPower === "menu") scene.confirmPower = modelData.id; else if (modelData.id === "") scene.confirmPower = ""; else { scene.powerRequested(modelData.id); scene.confirmPower = ""; } } }
                }
            }
        }
    }

    // Greeter: what's new in Opal.
    Rectangle {
        visible: scene.greeter && scene.whatsNew.length > 0
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 28
        height: 44; width: newRow.implicitWidth + 28; radius: 22
        color: scene.whatsNewOpen ? Theme.primary : Theme.level(3)
        Row { id: newRow; anchors.centerIn: parent; spacing: 8
            Glyph { name: "auto_awesome"; font.pixelSize: 19; color: scene.whatsNewOpen ? Theme.onPrimary : Theme.primary; anchors.verticalCenter: parent.verticalCenter }
            MText { text: "New in Opal"; role: "label"; font.weight: Font.DemiBold; color: scene.whatsNewOpen ? Theme.onPrimary : Theme.text; anchors.verticalCenter: parent.verticalCenter } }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: scene.whatsNewOpen = !scene.whatsNewOpen }
    }
    Rectangle {
        id: whatsNewSheet
        visible: opacity > 0
        opacity: scene.greeter && scene.whatsNewOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durMedium) } }
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.leftMargin: 28; anchors.topMargin: 84; anchors.bottomMargin: 96
        width: Math.min(420, scene.width * .32)
        radius: Theme.shapeXl; color: Theme.level(2)
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent; anchors.margins: 24; clip: true
            contentHeight: newColumn.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: newColumn; width: parent.width; spacing: 14
                MText { text: "New in Opal"; role: "displayS"; color: Theme.primary }
                Repeater {
                    model: scene.whatsNew
                    Rectangle {
                        required property var modelData
                        width: newColumn.width; height: itemColumn.implicitHeight + 28
                        radius: Theme.shapeLg; color: Theme.level(3)
                        Glyph { x: 16; y: 16; name: modelData.icon; font.pixelSize: 24; color: Theme.primary }
                        Column { id: itemColumn; x: 56; y: 14; width: parent.width - 72; spacing: 2
                            MText { width: parent.width; text: modelData.title; role: "titleS"; wrapMode: Text.Wrap }
                            MText { width: parent.width; text: modelData.text; role: "bodyS"; color: Theme.subtext; wrapMode: Text.Wrap } }
                    }
                }
            }
        }
    }
    // Phone extras: notification titles, torch and the ambient clock.
    Loader { anchors.fill: parent; z: 5; active: !scene.greeter; sourceComponent: LockExtras {}
        onLoaded: item.scene = scene
    }
    // Controller: the first press wakes the scene, then the D-pad moves between controls and the keyboard types.
    Connections { target: ControllerNav; function onKey() { if (!scene.revealed && scene.confirmPower === "") scene.reveal(); } }
    ControllerFocus {
        anchors.fill: parent; root: scene; priority: 20; closeOnBack: false; preferText: true
        active: scene.greeter || Hub.locked
        onBack: { if (scene.confirmPower !== "") scene.confirmPower = ""; else { field.text = ""; if (!scene.greeter) scene.revealed = false; } }
    }
}
