import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id:t
    property string icon:""
    property string title:""
    property string subtitle:""
    property bool active:false
    property bool settings:false
    property bool dense:false
    property bool iconOnly:false
    // Pixel style is the dense layout: wide tiles keep a glass body and only the icon square lights up.
    readonly property bool pixel:dense&&!iconOnly
    readonly property color activeFill:dense ? Theme.primary : Theme.tileActive
    readonly property color activeInk:dense ? Theme.onPrimary : Theme.onTileActive
    property string toggleTooltip:(active ? "Turn off " : "Turn on ")+title
    signal openSettings()
    signal toggled()
    signal clicked(real x, real y)
    readonly property real iconSize:Math.max(30,Math.min(48,width*.22))
    // The coloured icon button is deliberately larger than the glyph itself:
    // it is the direct on/off target, not just a state decoration.
    readonly property real toggleSize:pixel ? Math.max(34,height-12) : dense ? 34 : Math.max(42,Math.min(56,width*.26))
    readonly property color toggleColor:pixel ? (active ? Theme.primary : "transparent") : active ? Theme.alpha(activeInk,.14) : Theme.alpha(Theme.primary,.18)
    // Match the reference controls at the existing large touch size: enabled
    // is a compact rounded square; disabled relaxes to a true circle.
    // Pixel on state: the icon square nests inside the tile corner with a matching inset radius.
    readonly property real toggleRadius:active ? (pixel ? Math.max(8,Math.min(20,height/2)-6) : Math.round(toggleSize*.25)) : toggleSize/2
    readonly property real mainHitLeft:8+toggleSize
    readonly property bool pressed:mainMouse.pressed||toggleMouse.pressed
    readonly property bool hovered:mainMouse.containsMouse||toggleMouse.containsMouse
    implicitHeight:76
    // Expressive shape morph: off is a full pill, on is a rounded square, press squeezes it.
    radius:pressed ? Math.min(14,height/2) : pixel ? (active ? Math.min(20,height/2) : height/2) : active ? Math.min(dense ? 22 : 24,height/2) : height/2
    color:active&&!pixel ? activeFill : Theme.alpha(Theme.tile,dense ? .82 : .94)
    Behavior on color {ColorAnimation {duration:Theme.motion(220)}}
    scale:pressed ? .975 : 1
    Behavior on radius {NumberAnimation {duration:Theme.motion(220);easing.type:Easing.OutCubic}}
    Behavior on scale {NumberAnimation {duration:Theme.motion(180)}}
    Rectangle {anchors.fill:parent;radius:t.radius;color:t.active&&!t.pixel ? t.activeInk : Theme.stateLayer;opacity:t.pressed ? .12 : t.hovered ? .08 : 0
        Behavior on opacity {NumberAnimation {duration:Theme.motion(120)}}
    }
    RowLayout {anchors.fill:parent;anchors.margins:t.pixel ? 6 : t.dense ? 6 : 8;spacing:t.pixel ? 12 : t.dense ? 6 : t.width<180 ? 6 : 10
        Item {
            id:toggleButton
            Layout.preferredWidth:t.toggleSize
            Layout.fillWidth:t.iconOnly
            Layout.preferredHeight:t.toggleSize
            Rectangle {
                anchors.fill:parent
                radius:t.toggleRadius
                Behavior on radius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
                Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
                color:t.dense&&t.iconOnly ? "transparent" : t.toggleColor
                scale:toggleMouse.pressed ? .92 : 1
                Behavior on scale {NumberAnimation {duration:Theme.motion(150);easing.type:Easing.OutCubic}}
                Glyph {anchors.centerIn:parent;name:t.icon;font.pixelSize:t.pixel ? 24 : Math.min(28,t.toggleSize*.54);color:t.active ? t.activeInk : Theme.text}
            }
            MouseArea {
                id:toggleMouse
                anchors.fill:parent
                hoverEnabled:true
                cursorShape:Qt.PointingHandCursor
                onClicked:t.toggled()
                activeFocusOnTab:true
                Keys.onReturnPressed:t.toggled()
                Keys.onSpacePressed:t.toggled()
                Accessible.role:Accessible.Button
                Accessible.name:t.toggleTooltip
                Accessible.onPressAction:t.toggled()
            }
        }
        ColumnLayout {visible:!t.iconOnly;Layout.fillWidth:true;spacing:3
            MText {Layout.fillWidth:true;text:t.title;wrapMode:Text.WordWrap;maximumLineCount:t.pixel ? 1 : 2;font.pixelSize:t.pixel ? 13 : t.dense ? 10 : 12;font.weight:t.pixel ? Font.Medium : Font.DemiBold;color:t.active&&!t.pixel ? t.activeInk : Theme.text}
            MText {visible:t.subtitle!=="";Layout.fillWidth:true;text:t.subtitle;font.pixelSize:t.pixel ? 11 : t.dense ? 9 : 10;color:t.active&&!t.pixel ? Theme.alpha(t.activeInk,.82) : Theme.subtext}
        }
    }
    // Everything except the icon button opens the tile's full page.
    MouseArea {
        id:mainMouse
        anchors {left:parent.left;right:parent.right;top:parent.top;bottom:parent.bottom}
        anchors.leftMargin:t.iconOnly ? t.width : t.mainHitLeft
        hoverEnabled:true
        cursorShape:Qt.PointingHandCursor
        onClicked:mouse=>t.clicked(mouse ? mouse.x : width/2,mouse ? mouse.y : height/2)
        onPressAndHold:if(t.settings)t.openSettings()
        activeFocusOnTab:true
        Keys.onReturnPressed:t.clicked(width/2,height/2)
        Keys.onSpacePressed:t.clicked(width/2,height/2)
        Accessible.role:Accessible.Button
        Accessible.name:t.title+", "+t.subtitle+". Open details"
        Accessible.onPressAction:t.clicked(width/2,height/2)
    }
    Rectangle {anchors.fill:parent;anchors.margins:-3;radius:t.radius+3;color:"transparent";border.width:2;border.color:Theme.primary;visible:mainMouse.activeFocus||toggleMouse.activeFocus}
    ToolTip.visible:iconOnly&&hovered
    ToolTip.text:title+" · "+subtitle
    ToolTip.delay:500
}
