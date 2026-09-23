import QtQuick
import QtQuick.Controls

Slider {
    id:s
    property string icon:"volume"
    property bool compact:false
    property bool showIcon:true
    property bool stopIndicator:true
    property bool iconAtHandle:false
    property real trackHeight:compact ? 12 : 40
    property color activeColor:Theme.primary
    property color inactiveColor:Theme.alpha(Theme.tile,.9)
    readonly property real trackRadius:trackHeight>=30 ? Math.round(trackHeight*.3) : Math.min(trackHeight/2,compact ? 6 : 16)
    readonly property bool iconInside:showIcon&&icon!==""&&trackHeight>=22
    from:0;to:100;stepSize:1
    implicitHeight:compact ? 32 : 56
    hoverEnabled:true;wheelEnabled:true
    background:Item {
        x:s.leftPadding;y:(s.height-height)/2;width:s.availableWidth;height:s.trackHeight
        readonly property real split:2+(width-4)*s.visualPosition
        readonly property real gap:s.pressed ? 7 : 6
        Rectangle {
            width:Math.max(0,parent.split-parent.gap);height:parent.height
            topLeftRadius:s.trackRadius;bottomLeftRadius:s.trackRadius;topRightRadius:Math.min(4,s.trackRadius);bottomRightRadius:Math.min(4,s.trackRadius)
            color:s.activeColor
            Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
        }
        Rectangle {
            x:parent.split+parent.gap;width:Math.max(0,parent.width-x);height:parent.height
            topLeftRadius:Math.min(4,s.trackRadius);bottomLeftRadius:Math.min(4,s.trackRadius);topRightRadius:s.trackRadius;bottomRightRadius:s.trackRadius
            color:s.inactiveColor
        }
        // M3 stop indicator: a dot marks the end of the inactive track.
        Rectangle {
            visible:s.stopIndicator&&parent.width-parent.split>parent.gap+14
            width:Math.max(4,Math.min(6,s.trackHeight*.22));height:width;radius:width/2
            x:parent.width-width-Math.max(4,(s.trackHeight-width)/2);anchors.verticalCenter:parent.verticalCenter
            color:s.activeColor
        }
        // The icon either stays at the start or rides inside the active track next to the handle.
        Glyph {
            visible:s.iconInside
            readonly property real startX:Math.max(10,(s.trackHeight-font.pixelSize)/2+2)
            x:s.iconAtHandle ? Math.max(startX,parent.split-parent.gap-font.pixelSize-Math.max(10,(s.trackHeight-font.pixelSize)/2)) : startX
            anchors.verticalCenter:parent.verticalCenter;name:s.icon
            color:parent.split>x+font.pixelSize+4 ? Theme.onPrimary : Theme.subtext
            font.pixelSize:Math.min(22,s.trackHeight*.5)
        }
    }
    handle:Rectangle {
        x:s.leftPadding+s.visualPosition*(s.availableWidth-width)
        y:(s.height-height)/2;width:s.pressed ? 3 : 4;height:Math.min(s.height,s.trackHeight+(s.compact ? 10 : 8)+(s.pressed ? 4 : 0));radius:2;color:s.activeColor
        Behavior on height {NumberAnimation {duration:Theme.motion(160);easing.type:Easing.OutCubic}}
        Behavior on width {NumberAnimation {duration:Theme.motion(120)}}
    }
    Accessible.name:icon
}
