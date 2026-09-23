import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id:picker
    screen:Hub.powerProfileScreen||Quickshell.screens[0]
    visible:Hub.powerProfileOpen
    Connections {
        target:Hub
        function onStatusChanged() {
            if(picker.visible&&picker.screen&&(Hub.status.fullscreenMonitors||[]).indexOf(picker.screen.name)>=0)
                Hub.closePowerProfile();
        }
    }
    readonly property string layoutMode:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")
    readonly property int barHeight:layoutMode==="phone" ? 48 : 0
    anchors {top:true;bottom:true;left:true;right:true}
    exclusionMode:ExclusionMode.Ignore
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.namespace:"opal-power-profile"
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
    color:"transparent"
    // Keep the status controls outside the dismiss region.
    mask:Region {
        Region {x:0;y:0;width:picker.width;height:picker.height}
        Region {intersection:Intersection.Subtract;x:0;y:0;width:picker.width;height:picker.barHeight}
        Region {intersection:Intersection.Subtract;x:0;y:picker.height-64;width:picker.width;height:picker.layoutMode==="desktop" ? 64 : 0}
    }

    MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.closePowerProfile()}
    Surface {
        id:card
        property real reveal:0
        Component.onCompleted:if(picker.visible)enter.restart()
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onWheel:wheel=>{wheel.accepted=true;}}
        width:Math.min(366,picker.width-16)
        height:Math.min(500,picker.height-picker.barHeight-(picker.layoutMode==="desktop" ? 88 : 24))
        radius:26
        translucency:Math.max(.42,Hub.prefs.glass*.72)
        elevated:false
        border.color:Theme.alpha(Theme.outline,.72)
        x:Math.round(Math.max(8,Math.min(Hub.powerProfileX-width/2,picker.width-width-8)))
        y:picker.layoutMode==="desktop" ? picker.height-height-72 : Math.round(Math.max(picker.barHeight+8,Math.min(Hub.powerProfileY+14,picker.height-height-8)))
        z:1
        opacity:reveal
        scale:.94+.06*reveal
        transformOrigin:Item.Top
        Behavior on opacity {NumberAnimation {duration:Theme.motion(140);easing.type:Easing.OutCubic}}
        Behavior on scale {NumberAnimation {duration:Theme.motion(170);easing.type:Easing.OutCubic}}
        NumberAnimation {id:enter;target:card;property:"reveal";to:1;duration:Theme.motion(320);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
        onVisibleChanged:if(visible){reveal=0;enter.restart();}

        Rectangle {
            width:14;height:14;radius:3;rotation:45
            x:Math.max(20,Math.min(Hub.powerProfileX-card.x-width/2,card.width-width-34))
            y:-7
            color:card.color
            border.width:1;border.color:card.border.color
            z:-1
        }
        MText {
            anchors {left:parent.left;top:parent.top;leftMargin:16;topMargin:10}
            text:"Power & batteries"
            font.pixelSize:12
            font.weight:Font.DemiBold
            color:Theme.subtext
        }
        Flickable {
            id:scroll
            anchors {left:parent.left;right:parent.right;top:parent.top;bottom:profiles.top;leftMargin:16;rightMargin:16;topMargin:38;bottomMargin:12}
            contentHeight:details.implicitHeight
            clip:true
            boundsBehavior:Flickable.StopAtBounds
            Column {
                id:details
                width:scroll.width
                spacing:12
                MText {text:Hub.status.battery>=0 ? Hub.status.battery+"%" : "Power status";font.pixelSize:30;font.weight:Font.DemiBold;color:Theme.primary}
                MText {width:parent.width;text:Hub.status.battery>=0 ? (Hub.status.charging ? "Charging" : "Battery level") : "No battery reported";color:Theme.subtext;font.pixelSize:12}
                Repeater {
                    model:Hub.status.batteries||[]
                    Surface {
                        required property var modelData
                        width:details.width;height:70;radius:18
                        Column {
                            anchors {fill:parent;margins:12}
                            spacing:6
                            MText {width:parent.width;text:modelData.name+" · "+modelData.percent+"%";font.pixelSize:12;elide:Text.ElideRight}
                            Rectangle {
                                width:parent.width;height:5;radius:3;color:Theme.alpha(Theme.primary,.16)
                                Rectangle {width:parent.width*Math.max(0,Math.min(100,modelData.percent))/100;height:5;radius:3;color:Theme.primary}
                            }
                            MText {text:modelData.charging ? "Charging" : modelData.state||"Connected device";font.pixelSize:10;color:Theme.subtext}
                        }
                    }
                }
                MText {width:parent.width;text:"CPU "+Hub.status.cpu+"%   ·   Memory "+Hub.status.memory+"%";font.pixelSize:12;color:Theme.subtext}
                MText {width:parent.width;text:"Uptime "+(Hub.status.uptime||"unavailable")+"   ·   Governor "+(Hub.status.governor||"unavailable");wrapMode:Text.Wrap;font.pixelSize:11;color:Theme.subtext}
                MButton {width:parent.width;icon:"coffee";text:Hub.gameSession ? "Play session keeps awake" : Hub.keepAwake ? "Keep awake · On" : "Keep awake · Off";highlighted:Hub.keepAwake||Hub.gameSession;enabled:!Hub.gameSession;onClicked:Hub.keepAwake=!Hub.keepAwake}
                MText {text:Hub.status.profile ? "Power mode" : "Power modes unavailable";font.pixelSize:12;color:Theme.subtext}
            }
        }
        Row {
            id:profiles
            anchors {left:parent.left;right:parent.right;bottom:parent.bottom;margins:10}
            height:70
            spacing:6
            Repeater {
                model:[{id:"power-saver",text:"Saver",icon:"battery"},{id:"balanced",text:"Balanced",icon:"heart"},{id:"performance",text:"Boost",icon:"cpu"}]
                delegate:Item {
                    required property var modelData
                    readonly property bool current:Hub.status.profile===modelData.id
                    width:(profiles.width-12)/3
                    height:profiles.height
                    opacity:Hub.status.profile ? 1 : .45
                    scale:profileMouse.pressed ? .97 : 1
                    Behavior on scale {NumberAnimation {duration:100;easing.type:Easing.OutCubic}}
                    Rectangle {
                        anchors.fill:parent
                        radius:18
                        color:parent.current ? Theme.primary : profileMouse.containsMouse ? Theme.alpha(Theme.surfaceHigh,.76) : Theme.alpha(Theme.surfaceHigh,.48)
                        border.width:parent.current ? 0 : 1
                        border.color:Theme.alpha(Theme.outline,.7)
                        Behavior on color {ColorAnimation {duration:140}}
                    }
                    Glyph {
                        anchors {top:parent.top;horizontalCenter:parent.horizontalCenter;topMargin:10}
                        name:modelData.icon
                        font.pixelSize:19
                        color:parent.current ? Theme.onPrimary : Theme.primary
                    }
                    MText {
                        anchors {left:parent.left;right:parent.right;bottom:parent.bottom;bottomMargin:10}
                        text:modelData.text
                        horizontalAlignment:Text.AlignHCenter
                        font.pixelSize:11
                        font.weight:Font.DemiBold
                        color:parent.current ? Theme.onPrimary : Theme.text
                    }
                    MouseArea {
                        id:profileMouse
                        anchors.fill:parent
                        hoverEnabled:true
                        cursorShape:Qt.PointingHandCursor
                        enabled:!!Hub.status.profile
                        onClicked:Hub.command({action:"profile",value:modelData.id})
                    }
                }
            }
        }
    }
}
