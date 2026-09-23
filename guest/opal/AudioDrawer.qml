import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    // Input-only, unblurred click-away surfaces. They never take keyboard focus.
    Variants {
        model:Quickshell.screens
        delegate:PanelWindow {
            required property var modelData
            screen:modelData;visible:Hub.audioOpen
            readonly property string layoutMode:Hub.layoutFor(modelData.width,modelData.height,modelData.name)
            readonly property int barHeight:layoutMode==="phone" ? 48 : 0
            anchors {top:true;bottom:true;left:true;right:true}
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.layer:WlrLayer.Top
            WlrLayershell.namespace:"opal-audio-dismiss"
            WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
            color:"transparent"
            // Keep the animated card interactive even if this window is
            // stacked above it by the compositor.
            mask:Region {
                Region {x:0;y:0;width:modelData.width;height:modelData.height}
                Region {intersection:Intersection.Subtract;x:0;y:0;width:modelData.width;height:barHeight}
                Region {
                    intersection:Intersection.Subtract
                    x:modelData.width-drawer.width+card.x
                    y:drawer.phone ? drawer.margins.top : modelData.height-drawer.height-drawer.margins.bottom
                    width:drawer.screen===modelData&&drawer.visible ? card.width : 0
                    height:card.height
                }
            }
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.closeAudio()
                // Dismiss the drawer when the wheel moves outside the card.
                onWheel:event=>{Hub.closeAudio();event.accepted=true;}
            }
        }
    }
    PanelWindow {
        id:drawer
        screen:Hub.audioScreen||Quickshell.screens[0]
        property bool presenting:false
        property real progress:0
        visible:presenting
        readonly property bool phone:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")==="phone"
        anchors {top:drawer.phone;bottom:!drawer.phone;right:true}
        margins.top:phone ? 56 : 0
        margins.bottom:phone ? 0 : 72
        implicitWidth:Math.min(444,screen ? screen.width : 444)
        implicitHeight:Math.min(354,screen ? screen.height-70 : 354)
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Top
        WlrLayershell.namespace:"opal-audio"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        mask:Region {item:card}
        Connections {target:Hub;function onAudioOpenChanged(){
            if(Hub.audioOpen)Qt.callLater(()=>{
                if(!Hub.audioOpen)return;
                drawer.presenting=true;slide.to=1;slide.restart();
            });
            else {slide.to=0;slide.restart();}
        }}
        NumberAnimation {id:slide;target:drawer;property:"progress";duration:Theme.motion(280);easing.type:Easing.OutCubic;onFinished:if(!Hub.audioOpen)drawer.presenting=false}
        Surface {id:card;width:drawer.width-12;height:drawer.height;x:12+(1-drawer.progress)*drawer.width;radius:30;translucency:Hub.prefs.glass
            enabled:Hub.audioOpen
            AudioPanel {anchors.fill:parent}
        }
    }
}
