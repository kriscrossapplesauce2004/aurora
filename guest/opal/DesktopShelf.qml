import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

// Desktop bar. One set of parts, four containers: islands, dock, split and edge.
Item {
    id:shelf
    property var output:null
    property var panel:null
    property real panelHeight:64
    // In split style the shelf is drawn twice: "bottom" holds apps, "top" holds status.
    property string part:"bottom"
    property alias strip:tasks
    property alias leftIsland:leftFrame
    property alias rightIsland:rightGroup
    signal engaged()
    signal released()
    signal contextRequested(var item, real x, real y)
    readonly property string style:["islands","dock","split","edge"].indexOf(Hub.prefs.barStyle)>=0 ? Hub.prefs.barStyle : "islands"
    readonly property bool showApps:style!=="split"||part==="bottom"
    readonly property bool showStatus:style!=="split"||part==="top"
    readonly property bool framedParts:style==="islands"||style==="split"&&part==="top"
    readonly property color ink:Theme.text
    readonly property real rightWidth:rightGroup.width
    readonly property real islandHeight:style==="edge" ? 40 : 44
    readonly property bool startOpen:Hub.page==="launcher"&&Hub.targetScreen===output
    // In-bar transient feedback replaces the separate volume and workspace popups.
    readonly property bool osdHere:Hub.osd!==""&&(!Hub.osdScreen||Hub.osdScreen===output)
    property int flashWorkspace:0
    property int workspaceBaseline:-1
    function show(page) {Hub.targetScreen=output;Hub.toggle(page);}
    function apps() {Hub.targetScreen=output;Hub.openStart(false);}
    implicitHeight:64

    Connections {
        target:Hub
        function onStatusChanged() {
            const w=Hub.status.workspace||0;
            if(!Hub.status.hypr||w<=0)return;
            if(shelf.workspaceBaseline<0){shelf.workspaceBaseline=w;return;}
            if(w===shelf.workspaceBaseline)return;
            shelf.workspaceBaseline=w;shelf.flashWorkspace=w;flashTimer.restart();
        }
    }
    Timer {id:flashTimer;interval:1400;onTriggered:shelf.flashWorkspace=0}

    // Container backgrounds. Islands frame the app group only; dock and edge frame everything.
    Rectangle {
        id:leftFrame
        visible:shelf.showApps
        readonly property bool whole:shelf.style==="dock"||shelf.style==="edge"
        x:shelf.style==="edge" ? 0 : whole ? leftGroup.x-6 : leftGroup.x-4
        width:shelf.style==="edge" ? shelf.width : whole ? (shelf.showStatus ? rightGroup.x+rightGroup.width-leftGroup.x+12 : leftGroup.width+12) : leftGroup.width+8
        height:shelf.style==="edge" ? shelf.height : shelf.islandHeight+(whole ? 12 : 8)
        y:shelf.style==="edge" ? 0 : (shelf.height-height)/2
        radius:shelf.style==="edge" ? 0 : height/2
        color:shelf.style==="edge" ? Theme.level(2) : Theme.level(3)
        Behavior on x {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
        Behavior on width {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
        Rectangle {visible:shelf.style==="edge";width:parent.width;height:1;color:Theme.outline}
    }

    RowLayout {
        id:leftGroup
        visible:shelf.showApps
        readonly property real dockTotal:implicitWidth+(shelf.showStatus ? rightGroup.width+24 : 0)
        x:shelf.style==="dock"||shelf.style==="split" ? Math.max(18,(shelf.width-dockTotal)/2)
         : Hub.prefs.taskbarCenter ? Math.max(18,(shelf.width-width)/2-rightGroup.width/2) : (shelf.style==="edge" ? 12 : 22)
        anchors.verticalCenter:parent.verticalCenter
        height:shelf.islandHeight;spacing:6
        width:Math.min(implicitWidth,Math.max(44,shelf.width-(shelf.showStatus ? rightGroup.width : 0)-64))
        Behavior on x {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
        // Start: a filled circle whose mark turns into a rounded square while Start is open.
        Rectangle {
            id:appsButton
            Layout.preferredWidth:shelf.islandHeight;Layout.preferredHeight:shelf.islandHeight
            radius:shelf.startOpen ? Theme.shapeMd : height/2
            color:shelf.startOpen ? Theme.primary : Theme.primaryContainer
            Behavior on radius {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
            Behavior on color {ColorAnimation {duration:Theme.motion(Theme.durShort)}}
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.onContainer;opacity:startMouse.pressed ? .14 : startMouse.containsMouse ? .08 : 0}
            Glyph {anchors.centerIn:parent;name:"apps";font.pixelSize:22;color:shelf.startOpen ? Theme.onPrimary : Theme.onContainer}
            MouseArea {
                id:startMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                acceptedButtons:Qt.LeftButton|Qt.RightButton
                onClicked:e=>{if(e.button===Qt.RightButton)shelf.contextRequested(appsButton,e.x,e.y);else shelf.apps();}
            }
            Accessible.role:Accessible.Button;Accessible.name:"Start"
        }
        // Search: a quiet field inside the app group.
        Rectangle {
            id:search
            visible:shelf.width>=760
            Layout.preferredWidth:shelf.width>=1280 ? 180 : 132;Layout.preferredHeight:shelf.islandHeight
            radius:height/2
            color:Theme.level(shelf.style==="edge" ? 3 : 1)
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:searchMouse.pressed ? .12 : searchMouse.containsMouse ? .06 : 0}
            Row {
                anchors.verticalCenter:parent.verticalCenter;x:14;spacing:8
                Glyph {name:"search";font.pixelSize:19;color:Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
                MText {text:"Search";role:"label";color:Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
            }
            MouseArea {id:searchMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{Hub.targetScreen=shelf.output;Hub.openSearch();}}
            Accessible.role:Accessible.Button;Accessible.name:"Search apps, windows and actions"
        }
        TaskStrip {
            id:tasks
            Layout.preferredWidth:Math.min(720,naturalWidth)
            Layout.minimumWidth:0;Layout.fillHeight:true
            // Adaptive: titles collapse to icons when the strip gets crowded.
            labels:!!Hub.prefs.taskbarLabels&&groups.length<=6;islandStyle:true;output:shelf.output;panelHeight:shelf.panelHeight
            onEngaged:shelf.engaged()
            onReleased:shelf.released()
        }
    }

    Row {
        id:rightGroup
        visible:shelf.showStatus
        x:shelf.style==="dock" ? (shelf.showApps ? leftGroup.x+leftGroup.width+18 : shelf.width-width-18)
         : shelf.width-width-(shelf.style==="edge" ? 12 : 22)
        anchors.verticalCenter:parent.verticalCenter
        spacing:shelf.framedParts ? 8 : 4;height:shelf.islandHeight

        // Submap chip: shows the active key mode, such as resize, until it resets.
        Rectangle {
            id:submapChip
            readonly property string name:String(Hub.status.submap||"")
            visible:name!==""&&name!=="reset"
            implicitWidth:submapRow.implicitWidth+20;implicitHeight:parent.height
            width:implicitWidth;height:implicitHeight;radius:height/2;color:Theme.tertiaryContainer
            Row {
                id:submapRow;anchors.centerIn:parent;spacing:6
                Glyph {name:"keyboard";font.pixelSize:16;color:Theme.onTertiaryContainer;anchors.verticalCenter:parent.verticalCenter}
                MText {text:submapChip.name;role:"label";color:Theme.onTertiaryContainer;anchors.verticalCenter:parent.verticalCenter}
            }
            Accessible.role:Accessible.StaticText;Accessible.name:"Key mode "+name
        }
        // Live activities: stacked, compact, and expanded in place on hover or tap.
        ActivityPill {
            id:activity
            output:shelf.output;pillHeight:parent.height;framed:shelf.framedParts
            expandOnHover:true;maxCompact:220;maxExpanded:Math.min(460,shelf.width*.42)
            visible:opacity>0&&shelf.width>=1000
        }

        // Status: tray, battery, sound and network in one pill. Volume changes show here.
        Rectangle {
            id:status
            height:parent.height;radius:height/2
            color:shelf.framedParts ? Theme.level(3) : "transparent"
            width:(shelf.osdHere ? osdRow.implicitWidth : statusRow.implicitWidth)+(shelf.framedParts ? 16 : 6)
            clip:true
            Behavior on width {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:statusMouse.pressed ? .12 : statusMouse.containsMouse ? .06 : 0}
            MouseArea {id:statusMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:shelf.show("controls")
                onWheel:e=>{const d=e.angleDelta.y||e.pixelDelta.y;if(d)Hub.audioScroll(d>0 ? 1 : -1,shelf.output);}
            }
            Row {
                id:statusRow;anchors.verticalCenter:parent.verticalCenter;x:shelf.framedParts ? 10 : 3;spacing:10
                opacity:shelf.osdHere ? 0 : 1;visible:opacity>0
                Behavior on opacity {NumberAnimation {duration:Theme.motion(Theme.durShort)}}
                Repeater {
                    id:tray;model:shelf.width>=1100 ? SystemTray.items : null
                    Item {
                        required property var modelData
                        width:20;height:30;anchors.verticalCenter:parent.verticalCenter
                        Image {anchors.centerIn:parent;width:18;height:18;source:modelData.icon}
                        MouseArea {
                            anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton
                            onClicked:event=>{
                                if(event.button===Qt.RightButton&&modelData.hasMenu&&shelf.panel){
                                    const point=mapToItem(null,width/2,0);
                                    modelData.display(shelf.panel,point.x,point.y);
                                } else modelData.activate();
                            }
                        }
                    }
                }
                Rectangle {visible:tray.count>0;width:1;height:18;color:Theme.outline;anchors.verticalCenter:parent.verticalCenter}
                Glyph {visible:Hub.status.battery>=0;anchors.verticalCenter:parent.verticalCenter;font.pixelSize:19
                    name:Hub.status.charging ? "charging" : Hub.status.battery<=20 ? "battery_alert" : "battery"
                    color:Hub.status.battery<=15&&!Hub.status.charging ? Theme.error : shelf.ink}
                Glyph {anchors.verticalCenter:parent.verticalCenter;font.pixelSize:19;color:shelf.ink;name:Hub.status.muted ? "mute" : Hub.status.volume<34 ? "volume_down" : "volume"}
                Glyph {anchors.verticalCenter:parent.verticalCenter;font.pixelSize:19;color:shelf.ink;name:Hub.status.wifi ? "wifi" : "wifiOff"}
                Glyph {visible:Hub.dnd;anchors.verticalCenter:parent.verticalCenter;font.pixelSize:19;color:shelf.ink;name:"quiet"}
            }
            // Volume feedback: icon, track and value replace the status icons for a moment.
            Row {
                id:osdRow;anchors.verticalCenter:parent.verticalCenter;x:shelf.framedParts ? 10 : 3;spacing:10
                opacity:shelf.osdHere ? 1 : 0;visible:opacity>0
                Behavior on opacity {NumberAnimation {duration:Theme.motion(Theme.durShort)}}
                Glyph {anchors.verticalCenter:parent.verticalCenter;font.pixelSize:20;color:Theme.primary;name:Hub.status.muted ? "mute" : "volume"}
                Rectangle {
                    width:120;height:6;radius:3;anchors.verticalCenter:parent.verticalCenter;color:Theme.alpha(Theme.primary,.22)
                    Rectangle {width:parent.width*(Hub.status.muted ? 0 : Math.max(0,Math.min(100,Hub.status.volume))/100);height:parent.height;radius:3;color:Theme.primary
                        Behavior on width {NumberAnimation {duration:Theme.motion(Theme.durShort)}}}
                }
                MText {anchors.verticalCenter:parent.verticalCenter;width:30;text:Hub.status.muted ? "Off" : Hub.status.volume;role:"label";font.features:{"tnum":1};color:shelf.ink}
            }
            Rectangle {visible:Hub.unread>0&&!shelf.osdHere;anchors.right:parent.right;anchors.top:parent.top;anchors.rightMargin:8;anchors.topMargin:7;width:7;height:7;radius:4;color:Theme.primary}
            Accessible.role:Accessible.Button
            Accessible.name:"Quick settings · "+(Hub.status.wifi ? Hub.status.network : "Offline")+(Hub.unread>0 ? " · "+Hub.unread+" notifications" : "")
        }

        // Clock: the solid anchor of the bar. A workspace switch shows its number here.
        Rectangle {
            id:clock
            readonly property bool withDate:Hub.prefs.taskbarClockDate!==false&&shelf.width>=900
            readonly property bool flashing:shelf.flashWorkspace>0
            height:parent.height;radius:height/2
            color:Theme.primaryContainer
            width:(flashing ? flashRow.implicitWidth : withDate ? dateRow.implicitWidth : timeOnly.implicitWidth)+32
            Behavior on width {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.onContainer;opacity:clockMouse.pressed ? .12 : clockMouse.containsMouse ? .08 : 0}
            MText {id:timeOnly;anchors.centerIn:parent;visible:!clock.withDate&&!clock.flashing;text:Qt.formatDateTime(Hub.now,"HH:mm");role:"titleS";font.features:{"tnum":1};color:Theme.onContainer}
            Row {
                id:dateRow;visible:clock.withDate&&!clock.flashing;anchors.centerIn:parent;spacing:8
                MText {anchors.verticalCenter:parent.verticalCenter;text:Qt.formatDateTime(Hub.now,"ddd d");role:"label";color:Theme.alpha(Theme.onContainer,.75)}
                MText {anchors.verticalCenter:parent.verticalCenter;text:Qt.formatDateTime(Hub.now,"HH:mm");role:"titleS";font.features:{"tnum":1};color:Theme.onContainer}
            }
            Row {
                id:flashRow;visible:clock.flashing;anchors.centerIn:parent;spacing:6
                MText {anchors.verticalCenter:parent.verticalCenter;text:"Workspace";role:"label";color:Theme.alpha(Theme.onContainer,.75)}
                MText {anchors.verticalCenter:parent.verticalCenter;text:String(shelf.flashWorkspace);role:"title";color:Theme.onContainer}
            }
            MouseArea {id:clockMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:shelf.show("notifications")}
            Accessible.role:Accessible.Button
            Accessible.name:Qt.formatDateTime(Hub.now,"dddd, d MMMM HH:mm")
        }
    }
}
