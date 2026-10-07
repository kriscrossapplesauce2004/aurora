import QtQuick
import QtQuick.Layouts
Rectangle {
    id:t
    property string icon:""
    property string title:""
    property string subtitle:""
    property bool active:false
    property bool settings:false
    property color accent:Theme.primary
    signal clicked()
    signal openSettings()
    implicitHeight:94
    radius:mouse.pressed ? 20 : active ? 38 : 24
    color:active ? accent : Theme.tile
    scale:mouse.pressed ? .97 : 1
    Behavior on radius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
    Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
    Behavior on scale {NumberAnimation {duration:Theme.motion(150)}}
    Glyph {x:20;y:16;name:t.icon;color:t.active ? Theme.onPrimary : Theme.text;font.pixelSize:25}
    Column {x:20;y:49;width:parent.width-36;spacing:3
        MText {text:t.title;width:parent.width;font.pixelSize:13;font.weight:Font.DemiBold;color:t.active ? Theme.onPrimary : Theme.text}
        MText {text:t.subtitle;width:parent.width;font.pixelSize:10;color:t.active ? Theme.alpha(Theme.onPrimary,.8) : Theme.subtext}
    }
    MouseArea {id:mouse;anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:t.clicked();onPressAndHold:t.openSettings()}
    Loader {active:t.settings;anchors {top:parent.top;right:parent.right;topMargin:10;rightMargin:10}
        sourceComponent:Component {MButton {icon:"next";compact:true;implicitWidth:32;implicitHeight:32;ink:t.active ? Theme.onPrimary : Theme.subtext;tooltip:"Open settings";onClicked:t.openSettings()}}
    }
    Accessible.role:Accessible.Button
    Accessible.name:title+", "+subtitle
    Accessible.onPressAction:clicked()
}
