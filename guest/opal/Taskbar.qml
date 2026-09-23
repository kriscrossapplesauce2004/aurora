import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id:bar
    readonly property string layoutMode:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")
    readonly property bool phone:layoutMode==="phone"
    readonly property bool autoHide:!phone&&!!Hub.prefs.taskbarAutoHide
    readonly property bool consoleMode:layoutMode==="console"
    readonly property bool fullscreen:screen&&(Hub.status.fullscreenMonitors||[]).indexOf(screen.name)>=0
    readonly property var taskbarMenuEntries:Hub.taskbarMenu()
    property bool revealed:false
    readonly property bool contextOpen:Hub.taskbarContextOpen&&Hub.taskbarContextScreen===bar.screen
    property var activeStrip:null
    function openSection(section) {Hub.targetScreen=bar.screen;Hub.openSection(section);}
    function openContextAt(item, x, y, entries, centered, title, icon) {
        Hub.targetScreen=bar.screen;
        const point=item.mapToItem(null,x,y);
        const origin=centered ? item.mapToItem(null,0,0) : point;
        const anchorX=centered ? origin.x+item.width/2 : point.x;
        Hub.openTaskbarContext(bar.screen,anchorX,bar.screen.height-bar.height+origin.y,entries||bar.taskbarMenuEntries,centered,title,icon);
        hideTimer.stop();
    }
    anchors {bottom:true;left:true;right:true}
    visible:!consoleMode&&!fullscreen
    implicitHeight:phone ? (Hub.prefs.phoneButtons ? 64 : 48) : 64
    exclusiveZone:(autoHide||consoleMode||fullscreen) ? 0 : implicitHeight
    color:"transparent"
    WlrLayershell.namespace:"opal-shelf"
    WlrLayershell.layer:WlrLayer.Overlay
    mask:Region {
        Region {item:hitRegion;intersection:bar.phone||bar.autoHide&&!bar.revealed ? Intersection.Combine : Intersection.Subtract}
        Region {item:desktopLoader.item ? desktopLoader.item.leftIsland : null}
        Region {item:desktopLoader.item ? desktopLoader.item.rightIsland : null}
    }
    Item {id:hitRegion;x:body.x;y:bar.autoHide&&!bar.revealed ? bar.height-3 : 0;width:body.width;height:bar.height-y}
    MouseArea {anchors.fill:hitRegion;hoverEnabled:true;acceptedButtons:Qt.RightButton
        onEntered:{hideTimer.stop();bar.revealed=true;}
        onExited:hideTimer.restart()
        onClicked:e=>bar.openContextAt(hitRegion,e.x,e.y,undefined,false,"Taskbar","desktop")
    }
    Timer {id:hideTimer;interval:650;onTriggered:if(!bodyHover.hovered&&!bar.contextOpen&&(!bar.activeStrip||(!bar.activeStrip.interacting&&!bar.activeStrip.hovered)))bar.revealed=false}
    Rectangle {
        id:body;x:0
        width:bar.width;height:bar.height
        radius:0;border.width:0
        y:bar.autoHide&&!bar.revealed ? height-3 : 0
        color:bar.phone ? Theme.alpha(Theme.dockTint,Hub.prefs.glass) : "transparent"
        Behavior on y {NumberAnimation {duration:Theme.motion(140);easing.type:Easing.OutCubic}}
        HoverHandler {id:bodyHover;onHoveredChanged:{if(hovered){hideTimer.stop();bar.revealed=true;}else hideTimer.restart();}}
        Rectangle {visible:bar.phone;anchors.top:parent.top;width:parent.width;height:1;color:Theme.outline}
        Loader {id:desktopLoader;anchors.fill:parent;active:!bar.phone;sourceComponent:desktopContent}
        Loader {anchors.fill:parent;active:bar.phone;sourceComponent:phoneContent}
    }
    Component {id:desktopContent;DesktopShelf {
        output:bar.screen;panel:bar;panelHeight:bar.height
        Component.onCompleted:bar.activeStrip=strip
        Component.onDestruction:bar.activeStrip=null
        onEngaged:{hideTimer.stop();bar.revealed=true;}
        onReleased:hideTimer.restart()
        onContextRequested:(item,x,y)=>bar.openContextAt(item,x,y,undefined,true,"Applications","apps")
    }}
    Component {id:phoneContent;PhoneNavigation {anchors.fill:parent;output:bar.screen}}
}
