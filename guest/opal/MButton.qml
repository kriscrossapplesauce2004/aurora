import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Rectangle {
    id: a
    property string text: ""
    property string icon: ""
    property string secondaryIcon: ""
    property string tooltip: text
    property bool filled: false
    property bool tonal: false
    property bool compact: false
    property bool morph: false
    property bool checked: false
    property bool highlighted: false
    property bool contained: false
    property bool hoverHalo: false
    property color accent: Theme.primary
    property color fillInk: Theme.onPrimary
    property color ink: filled ? Theme.onPrimary : Theme.text
    property var menuEntries: []
    property bool scrollable: false
    signal scrolled(int steps)
    signal clicked()
    signal contextRequested(real x, real y)
    implicitWidth: Math.max(compact ? 42 : 48, content.implicitWidth + (compact ? 24 : 32))
    implicitHeight: compact ? 38 : 48
    // Original expressive pills: soft at rest, gently compressed on press.
    radius: mouse.pressed ? Math.min(height/2,Theme.shapeMd) : morph&&checked ? Math.min(18,height*.30) : height/2
    color: filled ? accent : highlighted ? Theme.surfaceHigh : contained ? Theme.alpha(Theme.surfaceHigh,.48) : tonal ? Theme.primaryContainer : "transparent"
    readonly property color contentInk: filled ? fillInk : tonal ? Theme.onContainer : ink
    // M3 state layer: the content colour at 8% for hover and 12% for press.
    Rectangle {
        anchors.fill: parent
        radius: a.radius
        visible: !(a.hoverHalo && a.icon !== "" && !a.filled)
        color: a.contentInk
        opacity: !a.enabled ? 0 : mouse.pressed ? .14 : mouse.containsMouse || a.activeFocus ? .08 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion(120) } }
    }
    // Shape-bounded press pulse. It grows from the centre and fades out.
    Rectangle {
        id: pulse
        anchors.centerIn: parent
        width: parent.width; height: parent.height; radius: a.radius
        color: a.contentInk
        opacity: 0; scale: .6
        ParallelAnimation {
            id: pulseAnimation
            NumberAnimation { target: pulse; property: "scale"; from: .55; to: 1; duration: Theme.motion(360); easing.type: Easing.OutCubic }
            NumberAnimation { target: pulse; property: "opacity"; from: .18; to: 0; duration: Theme.motion(420); easing.type: Easing.OutQuad }
        }
    }
    // M3 focus indicator: an outline with an offset, outside the control.
    Rectangle {
        anchors.fill: parent; anchors.margins: -3
        radius: a.radius + 3
        color: "transparent"
        border.width: 2; border.color: Theme.primary
        visible: a.activeFocus
    }
    opacity: enabled ? 1 : 0.35
    scale: 1
    Behavior on radius { NumberAnimation { duration: Theme.motion(220); easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.motion(180); easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Theme.motion(160) } }
    // Opt-in only: taskbar icon targets get a centred halo, rather than a
    // broad rectangular hover state that makes adjacent icons ambiguous.
    Rectangle {
        width:Math.min(38,a.width-4)
        height:width
        radius:width/2
        anchors.centerIn:parent
        visible:a.hoverHalo&&a.icon!==""&&!a.filled
        color:Theme.alpha(Theme.primary,.20)
        opacity:mouse.containsMouse||a.activeFocus ? 1 : 0
        scale:mouse.containsMouse||a.activeFocus ? 1 : .70
        Behavior on opacity {NumberAnimation {duration:Theme.motion(130)}}
        Behavior on scale {NumberAnimation {duration:Theme.motion(170);easing.type:Easing.OutCubic}}
    }
    // Icon-only controls must use their natural glyph width. A fixed compact
    // button can be 30 px wide, so its text padding must not shift the icon.
    RowLayout { id: content; anchors.centerIn: parent; width: a.text==="" ? implicitWidth : Math.min(implicitWidth, Math.max(0,a.width-24)); spacing: a.secondaryIcon!=="" ? 5 : 9
        Glyph { visible: a.icon!==""; name:a.icon; color:a.filled ? a.fillInk : a.tonal ? Theme.onContainer : a.ink; font.pixelSize:a.compact ? 19 : 22 }
        Glyph { visible:a.secondaryIcon!==""; name:a.secondaryIcon; color:a.filled ? a.fillInk : a.tonal ? Theme.onContainer : a.ink; font.pixelSize:a.compact ? 17 : 20 }
        MText { visible:a.text!==""; text:a.text; textFormat:Text.PlainText; Layout.fillWidth:true; elide:Text.ElideRight; color:a.filled ? a.fillInk : a.tonal ? Theme.onContainer : a.ink; font.pixelSize:a.compact ? 12 : 14; font.weight:Font.DemiBold }
    }
    activeFocusOnTab: true
    function controllerActivate() { clicked(); }
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    // Keep the Popup in its original coordinate space while avoiding menu-item
    // construction until it is actually open.
    Component {id:buttonMenuComponent;OpalMenu {entries:a.menuEntries}}
    Loader {id:buttonMenu;active:a.menuEntries.length>0;sourceComponent:buttonMenuComponent}
    MouseArea {
        id:mouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
        acceptedButtons:Qt.LeftButton|Qt.RightButton
        property bool held:false
        onWheel:e=>{
            if(!a.scrollable){e.accepted=false;return;}
            // Support mouse-wheel and touchpad deltas, and ignore zero-delta events.
            const delta=e.angleDelta.y||e.pixelDelta.y;
            if(delta)a.scrolled(delta>0 ? 1 : -1);
            e.accepted=delta!==0;
        }
        onPressed:held=false
        onClicked:e=>{if(held)return;if(e.button===Qt.RightButton){if(a.menuEntries.length)buttonMenu.item.popupFrom(a,e.x,e.y);else a.contextRequested(e.x,e.y);}else a.clicked();}
        onPressAndHold:e=>{if(a.menuEntries.length){held=true;buttonMenu.item.popupFrom(a,e.x,e.y);}}
    }
    Accessible.role: Accessible.Button
    Accessible.name: tooltip
    Accessible.onPressAction: clicked()
}
