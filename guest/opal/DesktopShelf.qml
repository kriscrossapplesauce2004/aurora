import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

Item {
    id:shelf
    property var output:null
    property var panel:null
    property real panelHeight:64
    property alias strip:tasks
    property alias leftIsland:leftGroup
    property alias rightIsland:rightGroup
    signal engaged()
    signal released()
    signal contextRequested(var item, real x, real y)
    readonly property color ink:Theme.light ? Theme.containerInk : Theme.text
    readonly property real rightWidth:rightGroup.width
    readonly property real islandHeight:44
    readonly property bool startOpen:Hub.page==="launcher"&&Hub.targetScreen===output
    function show(page) {Hub.targetScreen=output;Hub.toggle(page);}
    function apps() {Hub.targetScreen=output;Hub.openStart(false);}
    implicitHeight:64

    RowLayout {
        id:leftGroup
        x:Hub.prefs.taskbarCenter ? Math.max(18,(shelf.width-width)/2-rightGroup.width/2) : 18
        anchors.verticalCenter:parent.verticalCenter
        height:shelf.islandHeight;spacing:10
        width:Math.min(implicitWidth,Math.max(44,shelf.width-rightGroup.width-54))
        Behavior on x {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
        // Start: a glass circle with a live dot. The dot grows on hover and morphs to a square while Start is open.
        Island {
            id:appsButton
            Layout.preferredWidth:shelf.islandHeight;Layout.preferredHeight:shelf.islandHeight
            scale:startMouse.pressed ? .92 : 1
            Behavior on scale {NumberAnimation {duration:Theme.motion(160);easing.type:Easing.OutCubic}}
            Rectangle {
                anchors.centerIn:parent
                width:shelf.startOpen ? 18 : startMouse.containsMouse ? 20 : 16;height:width
                radius:shelf.startOpen ? 5 : width/2
                rotation:shelf.startOpen&&!Theme.reduceMotion ? 45 : 0
                color:Theme.light ? Theme.containerInk : Theme.primary
                Behavior on width {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutBack}}
                Behavior on radius {NumberAnimation {duration:Theme.motion(260)}}
                Behavior on rotation {NumberAnimation {duration:Theme.motion(320);easing.type:Easing.OutBack}}
            }
            MouseArea {
                id:startMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                acceptedButtons:Qt.LeftButton|Qt.RightButton
                onClicked:e=>{if(e.button===Qt.RightButton)shelf.contextRequested(appsButton,e.x,e.y);else shelf.apps();}
            }
            Accessible.role:Accessible.Button;Accessible.name:"Start"
        }
        SearchPill {
            visible:shelf.width>=700
            output:shelf.output;wide:shelf.width>=1200
            Layout.preferredWidth:shelf.width>=1200 ? 200 : 150;Layout.preferredHeight:shelf.islandHeight
        }
        Rectangle {visible:tasks.width>0;Layout.preferredWidth:1.5;Layout.preferredHeight:24;radius:1;color:Theme.alpha(Theme.light ? Theme.containerInk : "#ffffff",.28)}
        TaskStrip {
            id:tasks
            Layout.fillWidth:true;Layout.preferredWidth:Math.min(labels ? 720 : 520,groups.length*(labels ? 120 : 44)+Math.max(0,groups.length-1)*6)
            Layout.minimumWidth:0;Layout.fillHeight:true
            labels:!!Hub.prefs.taskbarLabels;islandStyle:true;output:shelf.output;panelHeight:shelf.panelHeight
            onEngaged:shelf.engaged()
            onReleased:shelf.released()
        }
    }
    Row {
        id:rightGroup
        anchors.right:parent.right;anchors.rightMargin:18;anchors.verticalCenter:parent.verticalCenter
        spacing:8;height:shelf.islandHeight
        // Now playing pill: art dot, title and a play/pause key. It only appears while a player has a track.
        Island {
            visible:Hub.status.track!==""&&shelf.width>=1360
            width:Math.min(230,mediaRow.implicitWidth+14);height:parent.height
            Row {
                id:mediaRow;anchors.verticalCenter:parent.verticalCenter;x:5;spacing:8
                Rectangle {
                    width:34;height:34;radius:17;anchors.verticalCenter:parent.verticalCenter;color:Theme.secondary
                    Glyph {anchors.centerIn:parent;name:"music";font.pixelSize:17;color:Theme.light ? Theme.onSecondaryContainer : Theme.base}
                    RotationAnimation on rotation {from:0;to:360;duration:8000;loops:Animation.Infinite;running:Hub.status.playing&&!Theme.reduceMotion}
                }
                Column {
                    anchors.verticalCenter:parent.verticalCenter;width:Math.min(120,Math.max(titleText.implicitWidth,artistText.implicitWidth))
                    MText {id:titleText;width:parent.width;text:Hub.status.track;font.pixelSize:12;font.weight:Font.Medium;color:shelf.ink}
                    MText {id:artistText;width:parent.width;visible:text!=="";text:Hub.status.artist||"";font.pixelSize:10;color:Theme.subtext}
                }
                MButton {anchors.verticalCenter:parent.verticalCenter;icon:Hub.status.playing ? "pause" : "play";compact:true;filled:true;morph:true;checked:Hub.status.playing;accent:Theme.light ? Theme.containerInk : Theme.primary;fillInk:Theme.light ? Theme.primaryContainer : Theme.onPrimary;implicitWidth:40;implicitHeight:34;tooltip:Hub.status.playing ? "Pause" : "Play";onClicked:Hub.media("play-pause")}
            }
            MouseArea {anchors.fill:parent;z:-1;acceptedButtons:Qt.LeftButton;cursorShape:Qt.PointingHandCursor;onClicked:Hub.toggleAudio(shelf.output)}
        }
        // Focus pill: a live countdown ring while the focus timer runs.
        Island {
            visible:Hub.focusRunning
            width:focusRow.implicitWidth+22;height:parent.height;strong:true
            Row {
                id:focusRow;anchors.centerIn:parent;spacing:7
                Canvas {
                    id:ring;width:22;height:22;anchors.verticalCenter:parent.verticalCenter
                    readonly property real progress:Hub.focusSeconds/(25*60)
                    onProgressChanged:requestPaint()
                    onPaint:{const c=getContext("2d");c.reset();c.lineWidth=3;c.lineCap="round";c.strokeStyle=Theme.alpha(shelf.ink,.25);c.beginPath();c.arc(11,11,8,0,Math.PI*2);c.stroke();c.strokeStyle=Theme.light ? Theme.containerInk : Theme.primary;c.beginPath();c.arc(11,11,8,-Math.PI/2,-Math.PI/2+Math.PI*2*Math.max(0,Math.min(1,progress)));c.stroke();}
                }
                MText {anchors.verticalCenter:parent.verticalCenter;text:Math.floor(Hub.focusSeconds/60)+":"+String(Hub.focusSeconds%60).padStart(2,"0");font.pixelSize:13;font.weight:Font.Medium;font.features:{"tnum":1};color:Theme.light ? Theme.containerInk : Theme.text}
            }
            MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:Hub.timerToggle()}
            Accessible.role:Accessible.Button;Accessible.name:"Focus timer, "+Math.ceil(Hub.focusSeconds/60)+" minutes left. Pause"
        }
        // Quick toggles pill: quiet mode, theme and microphone in one reach.
        Island {
            visible:shelf.width>=(Hub.status.track!=="" ? 1680 : 1200)
            width:toggleRow.implicitWidth+12;height:parent.height
            Row {
                id:toggleRow;anchors.centerIn:parent;spacing:2
                Repeater {
                    model:[
                        {icon:"quiet",on:Hub.dnd,tip:"Do not disturb",run:()=>Hub.set("dnd",!Hub.dnd)},
                        {icon:Theme.light ? "sun" : "moon",on:!Theme.light,tip:"Dark theme",run:()=>Hub.set("light",!Theme.light)},
                        {icon:Hub.status.micMuted ? "mic_off" : "mic",on:!Hub.status.micMuted,tip:"Microphone",run:()=>Hub.command({action:"mic"})}
                    ]
                    Rectangle {
                        required property var modelData
                        width:34;height:34;radius:modelData.on ? 12 : 17;anchors.verticalCenter:parent.verticalCenter
                        color:modelData.on ? (Theme.light ? Theme.containerInk : Theme.primary) : "transparent"
                        Behavior on radius {NumberAnimation {duration:Theme.motion(240);easing.type:Easing.OutBack}}
                        Behavior on color {ColorAnimation {duration:Theme.motion(180)}}
                        Rectangle {anchors.fill:parent;radius:parent.radius;color:parent.modelData.on ? Theme.onPrimary : Theme.stateLayer;opacity:toggleMouse.pressed ? .14 : toggleMouse.containsMouse ? .09 : 0}
                        Glyph {anchors.centerIn:parent;name:parent.modelData.icon;font.pixelSize:18;color:parent.modelData.on ? (Theme.light ? Theme.primaryContainer : Theme.onPrimary) : shelf.ink}
                        MouseArea {id:toggleMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:parent.modelData.run()}
                        Accessible.role:Accessible.CheckBox;Accessible.name:modelData.tip;Accessible.checked:modelData.on
                    }
                }
            }
        }
        Island {
            visible:shelf.width>=800
            width:Hub.unread>0 ? bellRow.implicitWidth+26 : height;height:parent.height
            Behavior on width {NumberAnimation {duration:Theme.motion(220);easing.type:Easing.OutCubic}}
            Row {
                id:bellRow;anchors.centerIn:parent;spacing:4
                Glyph {name:Hub.dnd ? "quiet" : Hub.unread>0 ? "notifications_unread" : "bell";font.pixelSize:20;color:shelf.ink;anchors.verticalCenter:parent.verticalCenter}
                Rectangle {
                    visible:Hub.unread>0;anchors.verticalCenter:parent.verticalCenter
                    width:Math.max(18,count.implicitWidth+10);height:18;radius:9;color:Theme.primary
                    MText {id:count;anchors.centerIn:parent;text:String(Math.min(99,Hub.unread));font.pixelSize:10;font.weight:Font.Bold;color:Theme.onPrimary}
                }
            }
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:bellMouse.pressed ? .12 : bellMouse.containsMouse ? .08 : 0}
            MouseArea {id:bellMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:shelf.show("notifications")}
            Accessible.role:Accessible.Button;Accessible.name:"Notifications"
        }
        Island {
            visible:tray.count>0&&shelf.width>=1000
            width:Math.min(184,trayRow.implicitWidth+24);height:parent.height
            Flickable {
                anchors.fill:parent;anchors.leftMargin:12;anchors.rightMargin:12;clip:true
                contentWidth:trayRow.implicitWidth;contentHeight:height
                boundsBehavior:Flickable.StopAtBounds;flickableDirection:Flickable.HorizontalFlick
                Row {
                id:trayRow;anchors.verticalCenter:parent.verticalCenter;spacing:8
                Repeater {
                    id:tray;model:shelf.width>=1000 ? SystemTray.items : null
                    Item {
                        required property var modelData
                        width:24;height:30
                        Image {anchors.centerIn:parent;width:18;height:18;source:modelData.icon;scale:trayMouse.containsMouse ? 1.15 : 1;Behavior on scale {NumberAnimation {duration:Theme.motion(140)}}}
                        MouseArea {
                            id:trayMouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton
                            onClicked:event=>{
                                if(event.button===Qt.RightButton&&modelData.hasMenu&&shelf.panel){
                                    const point=mapToItem(null,width/2,0);
                                    modelData.display(shelf.panel,point.x,point.y);
                                } else modelData.activate();
                            }
                        }
                    }
                }
                }
            }
        }
        // Status island: one pill, three targets, like a phone status cluster.
        Island {
            width:statusRow.implicitWidth+12;height:parent.height
            Row {
                id:statusRow;anchors.centerIn:parent;spacing:2
                MButton {
                    icon:Hub.status.charging ? "charging" : Hub.status.battery>=0&&Hub.status.battery<=20 ? "battery_alert" : "battery";compact:true;implicitWidth:32;implicitHeight:36;ink:Hub.status.battery>=0&&Hub.status.battery<=15&&!Hub.status.charging ? Theme.error : shelf.ink;hoverHalo:true
                    tooltip:Hub.status.battery>=0 ? Hub.status.battery+"% · Power" : "Power options"
                    onClicked:{const point=mapToItem(null,width/2,0);Hub.togglePowerProfile(shelf.output,point.x,shelf.output ? shelf.output.height-shelf.panelHeight : 0);}
                }
                MButton {
                    icon:Hub.status.muted ? "mute" : Hub.status.volume<34 ? "volume_down" : "volume";compact:true;implicitWidth:32;implicitHeight:36;ink:shelf.ink;hoverHalo:true
                    tooltip:"Sound · "+(Hub.status.muted ? "muted" : Hub.status.volume+"%")+" · scroll for volume";scrollable:true
                    onScrolled:steps=>Hub.audioScroll(steps,shelf.output)
                    onClicked:Hub.toggleAudio(shelf.output)
                }
                MButton {
                    icon:Hub.status.wifi ? "wifi" : "wifiOff";compact:true;implicitWidth:32;implicitHeight:36;ink:shelf.ink;hoverHalo:true
                    tooltip:(Hub.status.wifi ? Hub.status.network : "Offline")+" · Control center";onClicked:shelf.show("controls")
                }
            }
        }
        Island {
            id:clock
            strong:true
            // Solid, not glass: the clock is the one fixed anchor of the shelf.
            color:Theme.light ? Theme.primaryContainer : Theme.mix(Theme.base,Theme.primary,.5)
            border.width:0
            readonly property bool withDate:Hub.prefs.taskbarClockDate!==false&&shelf.width>=900
            width:(withDate ? dateRow.implicitWidth : clockText.implicitWidth)+32;height:parent.height
            Behavior on width {NumberAnimation {duration:Theme.motion(220);easing.type:Easing.OutCubic}}
            MText {
                id:clockText;anchors.centerIn:parent
                text:clock.withDate ? Qt.formatDateTime(Hub.now,"ddd d") : Qt.formatDateTime(Hub.now,"HH:mm")
                font.pixelSize:15;font.weight:Font.Medium;color:Theme.light ? Theme.containerInk : Theme.text
                visible:!clock.withDate
            }
            Row {
                id:dateRow;visible:clock.withDate;anchors.centerIn:parent;spacing:8
                MText {anchors.verticalCenter:parent.verticalCenter;text:Qt.formatDateTime(Hub.now,"ddd d");font.pixelSize:12;color:Theme.light ? Theme.alpha(Theme.containerInk,.75) : Theme.subtext}
                MText {anchors.verticalCenter:parent.verticalCenter;text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:15;font.weight:Font.Medium;color:Theme.light ? Theme.containerInk : Theme.text}
            }
            Rectangle {visible:Hub.unread>0;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:7;width:6;height:6;radius:3;color:Theme.primary}
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:clockMouse.pressed ? .12 : clockMouse.containsMouse ? .08 : 0}
            MouseArea {id:clockMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:shelf.show("notifications")}
            Accessible.role:Accessible.Button
            Accessible.name:Qt.formatDateTime(Hub.now,"dddd, d MMMM HH:mm")+" · "+Hub.unread+" notifications"
        }
    }
}
