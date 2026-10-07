import QtQuick
import QtQuick.Layouts
// Smart Stack: several widgets in one slot. Swipe vertically to flip; it moves to music or a running timer by itself.
Item {
    id:stack
    readonly property var cards:{
        const list=[];
        if(Hub.status.track!=="")list.push("media");
        if(Hub.focusRunning)list.push("focus");
        list.push("clock");
        list.push("calendar");
        if(Hub.status.battery>=0)list.push("battery");
        return list;
    }
    property int index:0
    readonly property string current:cards[Math.min(index,cards.length-1)]||"clock"
    implicitHeight:current==="calendar" ? calendarCard.implicitHeight : 176
    Behavior on implicitHeight {NumberAnimation {duration:Theme.motion(300);easing.type:Easing.OutCubic}}
    function flip(delta) {index=(index+delta+cards.length)%cards.length;}
    // Context wins: new music or a new timer brings its card to the front.
    Connections {
        target:Hub
        function onFocusRunningChanged() {stack.index=Hub.focusRunning ? Math.max(0,stack.cards.indexOf("focus")) : 0;}
    }
    property string lastTrack:""
    Connections {
        target:Hub
        function onStatusChanged() {
            if(Hub.status.track!==""&&Hub.status.track!==stack.lastTrack){stack.lastTrack=Hub.status.track;stack.index=0;}
        }
    }
    DragHandler {
        target:null;xAxis.enabled:false;yAxis.enabled:true
        onActiveChanged:if(!active&&Math.abs(translation.y)>36)stack.flip(translation.y<0 ? 1 : -1)
    }
    WheelHandler {onWheel:e=>stack.flip(e.angleDelta.y<0 ? 1 : -1)}

    Item {
        id:face
        anchors.fill:parent;anchors.rightMargin:16
        // Each flip slides the new card in from the swipe direction.
        property string shown:stack.current
        onShownChanged:{flipIn.restart();}
        ParallelAnimation {
            id:flipIn
            NumberAnimation {target:face;property:"opacity";from:.2;to:1;duration:Theme.motion(260)}
            NumberAnimation {target:faceShift;property:"y";from:28;to:0;duration:Theme.motion(360);easing.type:Easing.OutCubic;easing.overshoot:1.1}
        }
        transform:Translate {id:faceShift}
        // Clock: analog cookie beside a large time and the date.
        Rectangle {
            visible:face.shown==="clock";anchors.fill:parent;radius:32;color:Theme.primaryContainer
            RowLayout {
                anchors.fill:parent;anchors.margins:16;spacing:16
                AnalogClock {Layout.preferredWidth:parent.height-32;Layout.preferredHeight:Layout.preferredWidth}
                ColumnLayout {
                    Layout.fillWidth:true;spacing:0
                    MText {text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:52;font.weight:Font.Medium;font.letterSpacing:-2;color:Theme.onContainer}
                    MText {text:Qt.formatDateTime(Hub.now,"dddd");font.pixelSize:15;font.weight:Font.Medium;color:Theme.onContainer}
                    MText {text:Qt.formatDateTime(Hub.now,"d MMMM yyyy");font.pixelSize:12;color:Theme.alpha(Theme.onContainer,.75)}
                }
            }
        }
        CalendarWidget {id:calendarCard;visible:face.shown==="calendar";width:parent.width;solid:false}
        MediaCard {visible:face.shown==="media";anchors.fill:parent;compact:true}
        // Focus: a live ring counts down; tap to pause or resume.
        Rectangle {
            visible:face.shown==="focus";anchors.fill:parent;radius:32;color:Theme.tertiaryContainer
            RowLayout {
                anchors.fill:parent;anchors.margins:20;spacing:18
                Canvas {
                    id:ring;Layout.preferredWidth:parent.height-40;Layout.preferredHeight:Layout.preferredWidth
                    readonly property real progress:Hub.focusSeconds/(25*60)
                    onProgressChanged:requestPaint()
                    onVisibleChanged:if(visible)requestPaint()
                    onPaint:{
                        const c=getContext("2d"),r=width/2-7;c.reset();c.lineWidth=10;c.lineCap="round";
                        c.strokeStyle=Theme.alpha(Theme.text,.25);c.beginPath();c.arc(width/2,height/2,r,0,Math.PI*2);c.stroke();
                        c.strokeStyle=Theme.tertiary;c.beginPath();c.arc(width/2,height/2,r,-Math.PI/2,-Math.PI/2+Math.PI*2*Math.max(0,Math.min(1,progress)));c.stroke();
                    }
                    MText {anchors.centerIn:parent;text:Math.floor(Hub.focusSeconds/60)+":"+String(Hub.focusSeconds%60).padStart(2,"0");font.pixelSize:20;font.weight:Font.Medium;color:Theme.text}
                }
                ColumnLayout {
                    Layout.fillWidth:true;spacing:6
                    MText {text:"Focus";font.pixelSize:22;font.weight:Font.Medium;color:Theme.text}
                    MText {text:Hub.focusRunning ? "Stay with it." : "Paused";font.pixelSize:13;color:Theme.alpha(Theme.text,.8)}
                    MButton {text:Hub.focusRunning ? "Pause" : "Resume";icon:Hub.focusRunning ? "pause" : "play_arrow";compact:true;filled:true;accent:Theme.tertiary;fillInk:Theme.base;onClicked:Hub.timerToggle()}
                }
            }
        }
        // Battery: a gauge that fills, with the charging state.
        Rectangle {
            visible:face.shown==="battery";anchors.fill:parent;radius:32;color:Theme.secondaryContainer
            RowLayout {
                anchors.fill:parent;anchors.margins:22;spacing:20
                Rectangle {
                    Layout.preferredWidth:52;Layout.preferredHeight:parent.height-20;radius:16;color:Theme.alpha(Theme.onSecondaryContainer,.14)
                    Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:parent.height*Math.max(0,Math.min(100,Hub.status.battery))/100;radius:16;color:Theme.onSecondaryContainer}
                    Glyph {anchors.centerIn:parent;visible:Hub.status.charging;name:"bolt";font.pixelSize:26;color:Theme.secondaryContainer}
                }
                ColumnLayout {
                    Layout.fillWidth:true;spacing:2
                    MText {text:Hub.status.battery+"%";font.pixelSize:44;font.weight:Font.Medium;color:Theme.onSecondaryContainer}
                    MText {text:Hub.status.charging ? "Charging" : Hub.status.profile==="power-saver" ? "Battery saver on" : "On battery";font.pixelSize:14;color:Theme.alpha(Theme.onSecondaryContainer,.8)}
                }
            }
            MouseArea {anchors.fill:parent;onClicked:Hub.openSettings("power")}
        }
    }
    // Stack dots on the right edge show position and count.
    Column {
        anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;spacing:5
        Repeater {
            model:stack.cards.length
            Rectangle {
                required property int index
                width:6;height:index===stack.index ? 18 : 6;radius:3
                color:index===stack.index ? Theme.primary : Theme.alpha(Theme.text,.3)
                Behavior on height {NumberAnimation {duration:Theme.motion(240);easing.type:Easing.OutCubic}}
                MouseArea {anchors.fill:parent;anchors.margins:-4;onClicked:stack.index=parent.index}
            }
        }
    }
    Accessible.role:Accessible.Pane
    Accessible.name:"Smart Stack, "+current+". Swipe up or down for more"
}
