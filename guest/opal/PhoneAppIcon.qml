import QtQuick
import Quickshell
// Phone launcher icon: a round bubble with the app icon and an optional label. Long press opens the app menu.
Item {
    id:icon
    required property var app
    property bool label:true
    property real size:58
    property bool selected:false
    signal activated()
    implicitWidth:size+16
    implicitHeight:size+(label ? 30 : 8)
    Rectangle {
        id:bubble
        anchors.horizontalCenter:parent.horizontalCenter;y:4
        width:icon.size;height:width;radius:width*.3
        color:"transparent"
        border.width:icon.selected ? 3 : 0;border.color:Theme.primary
        opacity:mouse.pressed ? .8 : 1
        scale:mouse.pressed ? .9 : 1
        Behavior on scale {NumberAnimation {duration:Theme.motion(120);easing.type:Easing.OutCubic}}
        AppIcon {anchors.fill:parent;anchors.margins:icon.selected ? 4 : 0;app:icon.app}
        // Running apps get a small dot under the bubble.
        Rectangle {
            visible:Hub.windows.some(w=>Hub.appForWindow(w)===icon.app)
            anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.bottom;anchors.topMargin:2
            width:5;height:5;radius:2.5;color:Theme.primary
        }
    }
    MText {
        visible:icon.label
        anchors.top:bubble.bottom;anchors.topMargin:7;anchors.horizontalCenter:parent.horizontalCenter
        width:icon.width-4;horizontalAlignment:Text.AlignHCenter
        text:icon.app.name;role:"label";color:Theme.text
    }
    OpalMenu {id:menu;title:icon.app.name;icon:"apps";entries:visible ? Hub.appMenu(icon.app) : []}
    MouseArea {
        id:mouse;anchors.fill:parent
        acceptedButtons:Qt.LeftButton|Qt.RightButton
        onClicked:e=>{if(e.button===Qt.RightButton)menu.popup(e.x,e.y);else icon.activated();}
        onPressAndHold:e=>menu.popup(e.x,e.y)
    }
    Accessible.role:Accessible.Button
    Accessible.name:app.name
    Accessible.onPressAction:activated()
}
