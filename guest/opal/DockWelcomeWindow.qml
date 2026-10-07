import QtQuick
import Quickshell
import Quickshell.Wayland

// Shows the docking card on one screen: the phone when there is one, else the new screen. It never takes keyboard focus.
PanelWindow {
    id:window
    screen:Hub.phoneScreen||Hub.dockScreen||Quickshell.screens[0]
    readonly property bool phone:Hub.phoneScreen!==null
    readonly property bool wanted:Hub.dockNotice&&Hub.dockScreen!==null&&!Hub.dockMenu&&(Hub.page===""||Hub.page==="launcher")&&!Hub.audioOpen
    property bool presenting:false
    property real arrival:0
    function sync(){if(wanted&&!presenting){presenting=true;card.replay();}animation.to=wanted ? 1 : 0;animation.restart();}
    onWantedChanged:Qt.callLater(sync)
    Component.onCompleted:Qt.callLater(sync)
    visible:presenting
    anchors {bottom:true;right:!window.phone}
    margins {bottom:window.phone ? 28 : 82;right:12}
    implicitWidth:Math.min(window.phone ? 480 : 440,(screen ? screen.width : 440)-24)
    implicitHeight:card.implicitHeight
    exclusionMode:ExclusionMode.Ignore
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.namespace:"opal-toast"
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
    color:"transparent"
    mask:Region {item:card}
    NumberAnimation {id:animation;target:window;property:"arrival";to:1;duration:Theme.motion(window.wanted ? 480 : 240);easing.type:Easing.BezierSpline;easing.bezierCurve:window.wanted ? Theme.emphasizedDecelerate : Theme.emphasizedAccelerate;onFinished:if(!window.wanted)window.presenting=false}
    DockWelcome {id:card;width:window.width;phone:window.phone
        x:window.phone ? 0 : (1-window.arrival)*40
        y:window.phone ? (1-window.arrival)*window.height : 0
        opacity:window.arrival
    }
}
