import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id:context
    screen:Hub.taskbarContextScreen || Quickshell.screens[0]
    visible:Hub.taskbarContextOpen&&screen!==null
    readonly property string layoutMode:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")
    readonly property int taskbarHeight:layoutMode==="phone" ? (Hub.prefs.phoneButtons ? 64 : 48) : 64
    anchors {top:true;bottom:true;left:true;right:true}
    exclusionMode:ExclusionMode.Ignore
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.namespace:"opal-taskbar-menu"
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
    color:"transparent"
    // Keep taskbar controls live while a context menu is open. A new right
    // click can then replace the menu without a close-and-click dance.
    mask:Region {
        Region {x:0;y:0;width:context.width;height:context.height}
        Region {intersection:Intersection.Subtract;x:0;y:context.height-context.taskbarHeight;width:context.width;height:context.taskbarHeight}
    }

    MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.closeTaskbarContext()}
    Surface {
        id:menu
        readonly property var entries:Hub.taskbarContextEntries
        property real reveal:0
        width:316
        height:menuBody.implicitHeight
        radius:28
        // Match the shelf's base glass instead of using a heavy elevated card.
        translucency:Math.max(.72,Hub.prefs.glass+.2)
        elevated:false
        border.color:Theme.alpha(Theme.outline,.72)
        x:Math.max(8,Math.min(Hub.taskbarContextCentered ? Hub.taskbarContextX-width/2 : Hub.taskbarContextX,context.width-width-8))
        y:Math.max(8,Math.min(Hub.taskbarContextY-height-10,context.height-height-8))
        z:1
        opacity:reveal
        scale:.94+.06*reveal
        transformOrigin:Item.Bottom
        Behavior on scale {NumberAnimation {duration:Theme.motion(180);easing.type:Easing.OutCubic}}
        Behavior on opacity {NumberAnimation {duration:Theme.motion(150);easing.type:Easing.OutCubic}}
        NumberAnimation {id:enter;target:menu;property:"reveal";to:1;duration:Theme.motion(320);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
        Connections {
            target:Hub
            function onTaskbarContextRequestChanged() {
                if(!Hub.taskbarContextOpen)return;
                // Re-anchor an already open menu without the distracting
                // full fade that made rapid taskbar changes look broken.
                menu.reveal=menu.reveal>.8 ? .86 : 0;
                enter.restart();
            }
        }

        // This marker ties an anchored menu to the task or control that owns it.
        Rectangle {
            width:14
            height:14
            radius:3
            rotation:45
            x:Math.max(20,Math.min(Hub.taskbarContextX-menu.x-width/2,menu.width-width-34))
            y:menu.height-height/2
            color:menu.color
            border.width:1
            border.color:Theme.outline
            visible:Hub.taskbarContextCentered
            z:-1
        }
        ContextMenuBody {
            id:menuBody
            anchors.fill:parent
            entries:menu.entries
            title:Hub.taskbarContextTitle
            icon:Hub.taskbarContextIcon
            subtitle:Hub.taskbarContextIcon==="desktop"&&menu.entries.some(e=>e.icon==="desktop"&&!e.quick) ? "Open windows" : ""
            maxHeight:Math.max(160,context.height-120)
            onActivated:entry=>{
                Hub.targetScreen=context.screen;
                Hub.closeTaskbarContext();
                if(entry.run)entry.run();
            }
        }
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.RightButton;onPressed:mouse.accepted=true}
    }
}
