import QtQuick
import QtQuick.Controls
import Quickshell
Rectangle {
    id:t
    required property var app
    property bool selected:false
    property bool large:false
    property bool showPin:true
    property bool bare:false
    property bool touch:false
    property int tintIndex:0
    signal activated()
    radius: mouse.pressed ? 20 : (large ? 32 : 26)
    color: selected ? Theme.primaryContainer : mouse.containsMouse ? Theme.alpha(Theme.surfaceHigh,.65) : bare ? "transparent" : Theme.alpha(Theme.surface,0.60)
    border.width:selected ? (large ? 3 : 2) : 0
    border.color:Theme.primary
    scale:mouse.pressed ? .96 : 1
    Behavior on scale { NumberAnimation { duration:Theme.motion(180); easing.type:Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration:Theme.motion(180) } }
    Behavior on radius { NumberAnimation { duration:Theme.motion(180); easing.type:Easing.OutBack } }
    Rectangle {
        id:iconBg
        anchors {horizontalCenter:parent.horizontalCenter; top:parent.top; topMargin:t.large ? 24 : t.bare ? 12 : 17}
        width:t.large ? 88 : t.bare&&!t.touch ? 48 : 56; height:width
        radius:t.touch ? (t.tintIndex%3===0 ? width/2 : t.tintIndex%3===1 ? 18 : 12) : t.large ? 28 : 18
        rotation:t.touch&&t.tintIndex%3===2 ? -5 : 0
        color:Theme.alpha([Theme.primary,Theme.secondary,Theme.tertiary][t.tintIndex%3], Theme.light ? .4 : .15)
        Image { id:image; anchors.centerIn:parent; width:parent.width*.68; height:width; source:Quickshell.iconPath(t.app.icon,true); sourceSize:Qt.size(width,height); asynchronous:true; cache:true; rotation:-parent.rotation; smooth:true }
    Glyph { visible:image.status!==Image.Ready; anchors.centerIn:parent; name:Hub.glyphForApp(t.app); color:Theme.primary; font.pixelSize:30 }
    }
    MText { anchors {left:parent.left; right:parent.right; top:!t.large ? iconBg.bottom : undefined; topMargin:8; bottom:!t.large ? undefined : parent.bottom; bottomMargin:t.large ? 24 : 14; leftMargin:10; rightMargin:10}
 text:t.app.name; font.pixelSize:t.large ? 17 : 12; font.weight:Font.Medium; horizontalAlignment:Text.AlignHCenter; maximumLineCount:2; wrapMode:t.touch ? Text.WordWrap : Text.Wrap; elide:Text.ElideRight }
    // Keep the Popup parented to this tile for correct coordinates, but defer
    // the expensive window/action scan until it is actually opened.
    OpalMenu {id:appContext;entries:visible ? Hub.appMenu(t.app) : []}
    MouseArea {
        id:mouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton;cursorShape:Qt.PointingHandCursor
        property bool held:false
        onPressed:held=false
        onClicked:e=>{if(held)return;if(e.button===Qt.RightButton)appContext.popupFrom(t,e.x,e.y);else t.activated();}
        onPressAndHold:e=>{held=true;appContext.popupFrom(t,e.x,e.y);}
    }
    MButton { visible:t.showPin && (mouse.containsMouse || Hub.pinned(t.app)); anchors {right:parent.right; top:parent.top; margins:3}
 implicitWidth:30; implicitHeight:30; compact:true; icon:Hub.pinned(t.app) ? "check" : "pin"; tooltip:Hub.pinned(t.app) ? "Unpin application" : "Pin application"; onClicked:Hub.pin(t.app) }
    Accessible.role:Accessible.Button
    Accessible.name:app.name
    Accessible.onPressAction:activated()
}
