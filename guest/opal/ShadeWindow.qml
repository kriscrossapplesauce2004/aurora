import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id:shadeScope
    readonly property bool opened:Hub.page==="controls"||Hub.page==="notifications"
    property bool presentCard:false
    property int openedWorkspace:0
    property string openedMonitor:""
    Connections {
        target:Hub
        function onStatusChanged() {
            if(shadeScope.opened&&Hub.status.hypr&&
               (Hub.status.workspace!==shadeScope.openedWorkspace||
                (Hub.status.activeMonitor||"")!==shadeScope.openedMonitor))
                Hub.close();
        }
    }
    function showCard() {
        openedWorkspace=Hub.status.workspace;
        openedMonitor=Hub.status.activeMonitor||"";
        presentCard=true;
        Qt.callLater(()=>{if(opened)shadeCard.open();});
    }
    function hideCard() {
        if(presentCard)shadeCard.close();
    }
    onOpenedChanged:{if(opened)showCard();else hideCard();}
    Component.onCompleted:if(opened)showCard()
    // Each output needs its own input surface. Otherwise a shade opened on one
    // monitor stays up when the user clicks somewhere else on another monitor.
    Variants {
        model:Quickshell.screens
        delegate:PanelWindow {
            required property var modelData
            screen:modelData
            readonly property string layoutMode:Hub.layoutFor(modelData.width,modelData.height,modelData.name)
            readonly property int barHeight:layoutMode==="phone" ? 48 : 0
            visible:shadeScope.presentCard&&modelData!==shade.screen
            anchors {top:true;bottom:true;left:true;right:true}
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.layer:WlrLayer.Top
            WlrLayershell.namespace:"opal-shade-dismiss"
            WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
            color:"transparent"
            // Do not own pointer input over the status bar.
            mask:Region {
                Region {x:0;y:0;width:modelData.width;height:modelData.height}
                Region {intersection:Intersection.Subtract;x:0;y:0;width:modelData.width;height:barHeight}
            }
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
        }
    }
    PanelWindow {
        id:shade
        screen:Hub.targetScreen||Quickshell.screens[0]
        readonly property string layoutMode:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")
        readonly property bool phone:layoutMode==="phone"&&(screen ? screen.width<680 : true)
        readonly property int barHeight:layoutMode==="phone" ? 48 : 0
        visible:shadeScope.presentCard
        anchors {top:true;bottom:true;left:true;right:true}
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Top
        // The shade rule enables blur with ignore_alpha, so only painted
        // card pixels blur; the transparent click-away area stays clear.
        WlrLayershell.namespace:"opal-shade"
        WlrLayershell.keyboardFocus:shadeScope.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color:"transparent"
        // Keep the real status buttons above this click-away surface.
        mask:Region {
            Region {x:0;y:0;width:shade.width;height:shade.height}
            Region {intersection:Intersection.Subtract;x:0;y:0;width:shade.width;height:shade.barHeight}
        }
        // One input surface owns both the card and its outside-click area.
        // Do not mask this window to the card: that sends outside clicks to
        // applications without ever notifying us.
        Item {
            anchors.fill:parent
            focus:true
            Keys.priority:Keys.AfterItem
            // The shade owns keyboard focus, so printable input aimed at the
            // app below would otherwise leave a forgotten shade on screen.
            // Let controls consume their own input first, and only dismiss
            // unhandled typing when the pointer has left the card.
            Keys.onPressed:event=>{
                const plainText=event.text!==""&&!(event.modifiers&(Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier));
                if(plainText&&!cardHover.hovered){Hub.close();event.accepted=true;}
            }
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
            Surface {
            id:shadeCard
            readonly property real fit:shadeContent.item&&shadeContent.item.fitHeight>0 ? shadeContent.item.fitHeight : 460
            width:shade.phone ? shade.width : Math.min(380,shade.width-36)
            height:shade.phone ? shade.height : Math.min(fit,shade.height-92)
            Behavior on height {enabled:shadeCard.reveal>0.99&&!shade.phone;NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
            x:shade.phone ? 0 : shade.width-width-18
            y:shade.phone ? 0 : shade.height-height-72
            radius:shade.phone ? 0 : 32;translucency:shade.phone ? Hub.prefs.glass : Math.min(.55,Hub.prefs.glass)
            HoverHandler {id:cardHover}
            // Blank space inside the card must not reach the dismiss area.
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons}
            property real reveal:0
            function open() {
                exit.stop();
                enter.from=reveal;
                enter.restart();
            }
            function close() {
                enter.stop();
                exit.from=reveal;
                exit.restart();
            }
            opacity:reveal;scale:.95+.05*reveal;transformOrigin:shade.phone ? Item.Top : Item.BottomRight
            transform:Translate {y:(shade.phone ? -28 : 32)*(1-shadeCard.reveal)}
            NumberAnimation {id:enter;target:shadeCard;property:"reveal";to:1;duration:Theme.motion(400);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
            NumberAnimation {id:exit;target:shadeCard;property:"reveal";to:0;duration:Theme.motion(200);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedAccelerate;onFinished:if(!shadeScope.opened)shadeScope.presentCard=false}
            Loader {id:shadeContent;anchors.fill:parent;anchors.topMargin:shade.phone ? 48 : 0;anchors.bottomMargin:shade.phone ? (Hub.prefs.phoneButtons ? 64 : 48) : 0;active:shadeScope.presentCard;sourceComponent:Component {QuickSettings {}}}
            PhoneNavigation {visible:shade.phone;anchors.bottom:parent.bottom;width:parent.width;height:implicitHeight;output:shade.screen}
            Rectangle {visible:Hub.toast!=="";anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:12;height:70;radius:22;color:Theme.surfaceHigh;z:5
                MText {anchors.fill:parent;anchors.margins:12;text:Hub.toast;font.pixelSize:12;wrapMode:Text.Wrap;maximumLineCount:3;verticalAlignment:Text.AlignVCenter}
                MouseArea {anchors.fill:parent;onClicked:Hub.toast=""}
            }
            Shortcut {sequence:"Escape";onActivated:Hub.close()}
            }
        }
    }
}
