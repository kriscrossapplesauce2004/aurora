import QtQuick
import Quickshell
import Quickshell.Wayland

// Layer-shell window for the Claude assistant. It opens only from an explicit user action (page "assistant").
PanelWindow {
    id:win
    screen:Hub.targetScreen||Hub.chooseScreen()
    readonly property string layoutMode:screen ? Hub.layoutFor(screen.width,screen.height,screen.name) : "desktop"
    readonly property bool phone:layoutMode==="phone"
    readonly property bool game:layoutMode==="console"
    visible:Hub.page==="assistant"
    anchors {top:true;bottom:true;left:true;right:true}
    exclusionMode:ExclusionMode.Ignore
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.namespace:"opal-assistant"
    WlrLayershell.keyboardFocus:visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color:Theme.alpha("#000000",phone||game ? .32 : .07)
    MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
    Surface {
        id:card
        property real arrival:1
        opacity:arrival
        transform:Translate {y:(1-card.arrival)*(win.phone ? 40 : 10)}
        Connections {target:win;function onVisibleChanged(){if(win.visible)arrive.restart();}}
        NumberAnimation {id:arrive;target:card;property:"arrival";from:0;to:1;duration:Theme.motion(360);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
        readonly property real sheetHeight:Math.round(win.height*.84)
        width:win.phone ? win.width : win.game ? Math.min(980,win.width-80) : Math.min(470,win.width-24)
        height:win.phone ? sheetHeight+28 : win.game ? Math.min(win.height-80,760) : Math.min(win.height-150,800)
        x:win.phone ? 0 : win.game ? (win.width-width)/2 : win.width-width-12
        y:win.phone ? win.height-sheetHeight : win.game ? (win.height-height)/2 : Math.max(62,win.height-height-76)
        radius:win.phone ? 28 : win.game ? 32 : 32
        translucency:Hub.prefs.glass
        border.width:1
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons}
        Rectangle {visible:win.phone;anchors.horizontalCenter:parent.horizontalCenter;y:8;width:36;height:4;radius:2;color:Theme.alpha(Theme.text,.3)}
        AssistantPanel {
            anchors {fill:parent;topMargin:win.phone ? 12 : 0;bottomMargin:win.phone ? 28+(Hub.prefs.phoneButtons ? 64 : 48) : 0}
            layoutMode:win.layoutMode
        }
        PhoneNavigation {visible:win.phone;anchors.bottom:parent.bottom;anchors.bottomMargin:28;width:parent.width;height:implicitHeight;output:win.screen}
    }
    Shortcut {sequence:"Escape";enabled:win.visible;onActivated:Hub.close()}
}
