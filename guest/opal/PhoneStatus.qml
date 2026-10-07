import QtQuick
import QtQuick.Layouts

Item {
    id:bar
    property var output:null
    property bool fpsEnabled:false
    property int fps:0
    property alias pill:activityPill
    property var shownStatus:Hub.status
    implicitHeight:48
    readonly property string timeText:Qt.formatDateTime(Hub.now,"HH:mm")
    readonly property string clockTooltip:Qt.formatDateTime(Hub.now,"dddd, d MMMM")+" · tap for notifications"
    readonly property string focusText:Math.ceil(Hub.focusSeconds/60)+"m focus"
    readonly property string audioIcon:shownStatus.playing ? "music" : shownStatus.muted ? "mute" : "volume"
    readonly property string networkIcon:shownStatus.wifi ? "wifi" : "wifiOff"
    readonly property string batteryText:shownStatus.battery>=0 ? (shownStatus.charging ? "+ " : "")+shownStatus.battery+"%" : ""
    readonly property string networkTooltip:"Quick Settings · "+(shownStatus.network||"Offline")+(shownStatus.charging ? " · Charging" : "")
    function show(page) {if(output)Hub.targetScreen=output;Hub.toggle(page);}
    Timer {id:statusFrame;interval:16;repeat:false;onTriggered:bar.shownStatus=Hub.status}
    Connections {target:Hub;function onStatusChanged(){if(!statusFrame.running)statusFrame.start();}}
    DragHandler {target:null;yAxis.enabled:true;xAxis.enabled:false;onActiveChanged:if(!active&&translation.y>24)bar.show("controls")}
    // Pixel status bar: the time and alerts on the left, plain system icons on the right. Each half is a tap target.
    RowLayout {
        anchors.fill:parent;anchors.leftMargin:22;anchors.rightMargin:20;spacing:8
        MText {text:bar.timeText;font.pixelSize:15;font.weight:Font.Medium}
        Glyph {visible:Hub.unread>0;name:"notifications";font.pixelSize:15;color:Theme.subtext}
        MText {visible:Hub.unread>1;text:String(Math.min(99,Hub.unread));font.pixelSize:11;color:Theme.subtext}
        // Space for the activity pill. The pill itself floats above the bar so it can expand in place.
        Item {id:pillSlot;visible:activityPill.visible;Layout.preferredWidth:activityPill.restWidth;Layout.preferredHeight:36}
        MText {visible:bar.fpsEnabled;text:bar.fps+" FPS";font.pixelSize:11;font.weight:Font.DemiBold;color:Theme.primary}
        Item {Layout.fillWidth:true}
        Glyph {visible:Hub.dnd;name:"do_not_disturb_on";font.pixelSize:16;color:Theme.text}
        Glyph {visible:!!bar.shownStatus.bluetooth;name:"bluetooth";font.pixelSize:16;color:Theme.text}
        Glyph {visible:bar.shownStatus.playing;name:"music_note";font.pixelSize:16;color:Theme.text}
        Glyph {name:bar.networkIcon;font.pixelSize:16;color:Theme.text}
        Glyph {visible:bar.shownStatus.battery>=0;name:bar.shownStatus.charging ? "battery_charging_full" : bar.shownStatus.battery<=15 ? "battery_alert" : "battery_full";font.pixelSize:16;color:bar.shownStatus.battery<=15&&!bar.shownStatus.charging ? Theme.error : Theme.text}
        MText {visible:bar.shownStatus.battery>=0;text:bar.shownStatus.battery+"%";font.pixelSize:13;font.weight:Font.Medium}
    }
    MouseArea {
        anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;width:parent.width/2
        onClicked:bar.show("notifications")
        onPressAndHold:Hub.set("dnd",!Hub.dnd)
        Accessible.role:Accessible.Button;Accessible.name:bar.clockTooltip
    }
    MouseArea {
        anchors.right:parent.right;anchors.top:parent.top;anchors.bottom:parent.bottom;width:parent.width/2
        onClicked:bar.show("controls")
        onPressAndHold:bar.show("convergence")
        Accessible.role:Accessible.Button;Accessible.name:bar.networkTooltip
    }
    // Live activities. Tap to expand, tap again to open, and it folds away alone.
    ActivityPill {
        id:activityPill
        property real restWidth:128
        onWidthChanged:if(!expanded)restWidth=Math.min(width,128)
        output:bar.output;pillHeight:36;maxCompact:128;maxExpanded:bar.width-20;expandOnHover:false
        x:Math.max(10,Math.min(pillSlot.mapToItem(bar,0,0).x,bar.width-width-10))
        y:(bar.height-height)/2
    }
}
