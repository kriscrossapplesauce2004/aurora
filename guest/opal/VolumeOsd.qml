import QtQuick
import QtQuick.Layouts

Surface {
    id:osd
    implicitWidth:340
    implicitHeight:112
    radius:28
    translucency:Math.max(.72,Hub.prefs.glass+.2)
    property real reveal:0
    Component.onCompleted:reveal=1
    Component.onDestruction:Hub.osdHovered=false
    HoverHandler {onHoveredChanged:Hub.osdHovered=hovered}
    opacity:reveal
    scale:.96+.04*reveal
    Behavior on opacity {NumberAnimation {duration:Theme.motion(160)}}
    Behavior on scale {NumberAnimation {duration:Theme.motion(200);easing.type:Easing.OutCubic}}
    RowLayout {
        anchors {fill:parent;leftMargin:18;rightMargin:18;topMargin:16;bottomMargin:16}
        spacing:12
        MButton {
            icon:Hub.status.muted ? "mute" : "volume"
            filled:true;morph:true;checked:Hub.status.muted
            implicitWidth:52;implicitHeight:52
            tooltip:Hub.status.muted ? "Unmute" : "Mute"
            scrollable:true
            onScrolled:steps=>Hub.audioScroll(steps,Hub.osdScreen)
            onClicked:{Hub.command({action:"mute"});Hub.showVolumeOsd();}
        }
        ColumnLayout {
            Layout.fillWidth:true
            spacing:6
            RowLayout {
                Layout.fillWidth:true
                MText {Layout.fillWidth:true;text:Hub.status.muted ? "Muted" : "Volume";font.pixelSize:13;font.weight:Font.DemiBold}
                MText {text:Hub.status.volume+"%";font.pixelSize:15;font.weight:Font.DemiBold;color:Theme.primary}
            }
            MText {Layout.fillWidth:true;text:Hub.status.audioOutput||"Default output";elide:Text.ElideRight;font.pixelSize:10;color:Theme.subtext}
            ExpressiveSlider {Layout.fillWidth:true;Layout.preferredHeight:30;compact:true;trackHeight:18;showIcon:false;activeColor:Hub.status.muted ? Theme.subtext : Theme.primary;value:Hub.status.volume;opacity:Hub.status.muted ? .5 : 1;Accessible.name:"Output volume";onMoved:Hub.volume(value)}
        }
    }
}
