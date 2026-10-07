import QtQuick
import QtQuick.Controls
import Quickshell

Item {
    id:s
    property bool labels:true
    property bool islandStyle:false
    property var output:null
    property real panelHeight:0
    readonly property bool contextOpen:Hub.taskbarContextOpen&&Hub.taskbarContextScreen===s.output
    property bool hovered:false
    property string draggingKey:""
    property int sourceIndex:-1
    property int dropIndex:-1
    property real dragWidth:0
    property var dragItem:null
    property var groups:[]
    readonly property bool uniformTaskWidth:!labels||width<=500||groups.every(group=>group.windows.length>0)
    readonly property real taskWidth:islandStyle ? (labels ? 160 : 44) : labels&&width>500 ? Math.max(100,Math.min(184,width/Math.max(1,repeater.count))) : 44
    // Natural width of all tasks, so a container can hug its content.
    readonly property real naturalWidth:groups.reduce((sum,g)=>sum+(labels&&g.windows.length>0 ? taskWidth : 44),0)+Math.max(0,groups.length-1)*row.spacing
    readonly property real taskExtent:taskWidth+row.spacing
    Component.onCompleted:groups=Hub.taskGroups
    Connections {target:Hub;function onTaskGroupsChanged(){if(!s.dragging)s.groups=Hub.taskGroups;}}
    readonly property bool dragging:draggingKey!==""
    readonly property bool interacting:dragging||contextOpen
    signal engaged()
    signal released()
    function begin(key,index,visual) {
        if(dragging)return;
        draggingKey=key;sourceIndex=index;dropIndex=index;
        dragWidth=visual.width;dragItem=visual;engaged();
    }
    function updateDrop(x) {
        if(!uniformTaskWidth){
            let next=Math.max(0,repeater.count-1);
            for(let index=0;index<repeater.count;index+=1){const item=repeater.itemAt(index);if(item&&x<item.x+item.width/2){next=index;break;}}
            if(next!==dropIndex)dropIndex=next;
            return;
        }
        const next=Math.max(0,Math.min(repeater.count-1,Math.floor((x+taskWidth/2)/taskExtent)));
        if(next!==dropIndex)dropIndex=next;
    }
    function finish(commit) {
        const key=draggingKey,to=dropIndex;
        if(dragItem)dragItem.x=0;
        dragItem=null;draggingKey="";sourceIndex=-1;dropIndex=-1;
        if(commit&&key!=="")Hub.reorderTask(key,to);
        groups=Hub.taskGroups;released();
    }
    Flickable {
        id:scroller;anchors.fill:parent;contentWidth:row.width;contentHeight:height;clip:true
        interactive:!s.dragging;boundsBehavior:Flickable.StopAtBounds;flickableDirection:Flickable.HorizontalFlick
        Row {
            id:row;height:scroller.height;spacing:s.islandStyle ? 6 : 4
            Repeater {
                id:repeater;model:s.groups
                Item {
                    id:task
                    required property var modelData
                    required property int index
                    readonly property bool dragged:s.draggingKey===modelData.key
                    readonly property bool urgent:modelData.windows.some(w=>Hub.urgent(w))
                    readonly property bool focused:modelData.windows.some(w=>Hub.active(w))
                    readonly property bool labeled:s.labels&&modelData.windows.length>0&&(s.islandStyle||s.width>500)
                    function openMenu(x,y) {
                        const wins=modelData.windows;const entries=modelData.app ? Hub.appMenu(modelData.app) : wins.length===1 ? Hub.windowMenu(wins[0]) : [{text:"Close all",icon:"close",quick:true,danger:true,run:()=>wins.forEach(w=>Hub.closeWindow(w))}].concat(wins.map(w=>({text:w.title,icon:"desktop",run:()=>Hub.focusWindow(w)})));
                        if(!entries.length)return;
                        const origin=visual.mapToItem(null,0,0);
                        const title=modelData.name||(modelData.app ? modelData.app.name : "Windows");
                        const icon=modelData.windows.length ? "desktop" : "apps";
                        Hub.openTaskbarContext(s.output,origin.x+visual.width/2,s.output.height-s.panelHeight+origin.y,entries,true,title,icon);
                    }
                    width:labeled ? s.taskWidth : 44
                    height:row.height;z:dragged ? 10 : 0
                    Rectangle {anchors.fill:parent;anchors.margins:2;radius:14;visible:task.dragged;color:Theme.alpha(Theme.primary,.10);border.width:1;border.color:Theme.outline}
                    Item {
                        id:visual;width:task.width;height:task.height
                        transform:Translate {
                            x:!s.dragging||task.dragged ? 0 : s.sourceIndex<s.dropIndex&&task.index>s.sourceIndex&&task.index<=s.dropIndex ? -(s.dragWidth+row.spacing) : s.sourceIndex>s.dropIndex&&task.index>=s.dropIndex&&task.index<s.sourceIndex ? s.dragWidth+row.spacing : 0
                            Behavior on x {NumberAnimation {duration:Theme.motion(180);easing.type:Easing.OutCubic}}
                        }
                        scale:task.dragged ? 1.04 : mouse.pressed ? .96 : 1
                        rotation:0
                        Behavior on scale {NumberAnimation {duration:Theme.motion(180);easing.type:Easing.OutCubic}}
                        Behavior on rotation {NumberAnimation {duration:Theme.motion(180)}}
                        Behavior on x {enabled:!mouse.drag.active;NumberAnimation {duration:Theme.motion(200);easing.type:Easing.OutCubic}}
                        Rectangle {visible:!s.islandStyle;anchors.fill:parent;anchors.margins:2;radius:14;color:task.dragged ? Theme.surfaceHigh : task.focused ? Theme.primaryContainer : mouse.containsMouse ? Theme.alpha(Theme.surfaceHigh,.48) : "transparent";border.width:task.dragged ? 1 : 0;border.color:Theme.primary
                            Behavior on color {ColorAnimation {duration:Theme.motion(140)}}
                        }
                        // Island style: apps sit inside the group island. Only the focused app gets a tonal squircle.
                        Rectangle {
                            visible:s.islandStyle&&(task.focused||task.dragged)
                            anchors.centerIn:parent
                            width:task.labeled ? parent.width : Math.min(parent.width,parent.height);height:Math.min(parent.width,parent.height)
                            radius:task.labeled ? height/2 : Theme.shapeMd
                            color:task.dragged ? Theme.level(4) : Theme.primaryContainer
                        }
                        // The halo follows the actual icon centre in both the
                        // compact and labelled taskbar layouts.
                        Rectangle {
                            id:taskHoverHalo
                            width:38;height:38;radius:19
                            x:taskIcon.x+taskIcon.width/2-width/2
                            anchors.verticalCenter:parent.verticalCenter
                            color:Theme.alpha(s.islandStyle ? Theme.stateLayer : Theme.primary,s.islandStyle ? .10 : .20)
                            opacity:mouse.containsMouse||visual.activeFocus ? 1 : 0
                            scale:mouse.containsMouse||visual.activeFocus ? 1 : .70
                            Behavior on opacity {NumberAnimation {duration:Theme.motion(130)}}
                            Behavior on scale {NumberAnimation {duration:Theme.motion(170);easing.type:Easing.OutCubic}}
                        }
                        Image {id:taskIcon;x:task.labeled ? 10 : (parent.width-width)/2;anchors.verticalCenter:parent.verticalCenter;width:s.islandStyle&&!task.labeled ? 26 : 24;height:width;sourceSize:Qt.size(48,48);source:Quickshell.iconPath(task.modelData.icon,true)
                            scale:1
                            Behavior on scale {NumberAnimation {duration:Theme.motion(220);easing.type:Easing.OutCubic}}
                        }
                        Glyph {visible:taskIcon.status!==Image.Ready;x:taskIcon.x;anchors.verticalCenter:parent.verticalCenter;name:Hub.glyphForApp(task.modelData.app);font.pixelSize:24;color:s.islandStyle ? (Theme.light ? Theme.containerInk : Theme.primary) : Theme.primary}
                        MText {visible:task.labeled;x:42;width:parent.width-58;anchors.verticalCenter:parent.verticalCenter;text:task.modelData.windows.length===1 ? task.modelData.windows[0].title : task.modelData.name;font.pixelSize:12;color:task.focused ? Theme.onContainer : Theme.text;role:"label"}
                        Rectangle {visible:task.modelData.windows.length>1;anchors.right:parent.right;anchors.top:parent.top;anchors.rightMargin:1;width:16;height:16;radius:8;color:Theme.primaryContainer;border.width:1;border.color:Theme.outline
                            MText {anchors.centerIn:parent;text:Math.min(99,task.modelData.windows.length);font.pixelSize:9;font.weight:Font.Bold;color:Theme.onContainer}
                        }
                        Rectangle {visible:task.modelData.windows.length>0;anchors.bottom:parent.bottom;anchors.bottomMargin:s.islandStyle ? 3 : 2;anchors.horizontalCenter:parent.horizontalCenter;width:task.focused ? 14 : 4;height:s.islandStyle ? 3 : 3;radius:2;color:s.islandStyle ? (Theme.light ? Theme.containerInk : Theme.primary) : Theme.primary
                            Behavior on width {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
                        }
                        // Urgent windows get an error dot that breathes slowly; reduced motion keeps it still.
                        Rectangle {
                            id:urgentDot
                            visible:task.urgent&&!task.focused
                            anchors.right:parent.right;anchors.top:parent.top;anchors.rightMargin:task.labeled ? 8 : 6;anchors.topMargin:6
                            width:10;height:10;radius:5;color:Theme.error;border.width:1;border.color:Theme.surface
                            SequentialAnimation on opacity {
                                running:urgentDot.visible&&!Theme.reduceMotion;loops:Animation.Infinite
                                NumberAnimation {to:.45;duration:900;easing.type:Easing.InOutSine}
                                NumberAnimation {to:1;duration:900;easing.type:Easing.InOutSine}
                            }
                            Accessible.role:Accessible.Indicator;Accessible.name:"Needs attention"
                        }
                        MouseArea {
                            id:mouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton
                            preventStealing:true
                            drag.target:pressedButtons&Qt.LeftButton ? visual : null;drag.axis:Drag.XAxis;drag.threshold:8
                            property bool suppressClick:false
                            onPressed:suppressClick=false
                            onPositionChanged:if(drag.active){suppressClick=true;s.begin(task.modelData.key,task.index,visual);s.updateDrop(visual.mapToItem(row,mouseX,mouseY).x);}
                            onReleased:{if(task.dragged){const y=visual.mapToItem(s,mouseX,mouseY).y;s.finish(y>=-8&&y<=s.height+8);}else visual.x=0;}
                            onCanceled:{if(task.dragged)s.finish(false);else visual.x=0;suppressClick=true;}
                            onClicked:e=>{if(suppressClick)return;if(e.button===Qt.RightButton)task.openMenu(e.x,e.y);else Hub.activateGroup(task.modelData);}
                            onPressAndHold:e=>{if(!drag.active){suppressClick=true;task.openMenu(e.x,e.y);}}
                            onEntered:{s.hovered=true;s.engaged();}
                            onExited:{s.hovered=false;if(!s.interacting)s.released();}
                        }
                        activeFocusOnTab:true
                        Keys.onReturnPressed:Hub.activateGroup(task.modelData)
                        Keys.onLeftPressed:event=>{if(event.modifiers&Qt.ControlModifier){Hub.reorderTask(task.modelData.key,Math.max(0,task.index-1));event.accepted=true;}else event.accepted=false;}
                        Keys.onRightPressed:event=>{if(event.modifiers&Qt.ControlModifier){Hub.reorderTask(task.modelData.key,Math.min(repeater.count-1,task.index+1));event.accepted=true;}else event.accepted=false;}
                        Accessible.role:Accessible.Button;Accessible.name:task.modelData.name
                        Accessible.onPressAction:Hub.activateGroup(task.modelData)
                    }
                }
            }
        }
        ScrollBar.horizontal:ScrollBar {policy:ScrollBar.AsNeeded;height:3}
    }
    Timer {interval:30;repeat:true;running:s.dragging&&s.dragItem!==null
        onTriggered:{
            const x=s.dragItem.mapToItem(scroller,s.dragItem.width/2,0).x;
            const delta=x<32 ? -12 : x>scroller.width-32 ? 12 : 0;
            const previous=scroller.contentX;
            scroller.contentX=Math.max(0,Math.min(Math.max(0,scroller.contentWidth-scroller.width),previous+delta));
            const moved=scroller.contentX-previous;
            if(s.dragItem&&moved!==0){s.dragItem.x+=moved;s.updateDrop(s.dragItem.mapToItem(row,s.dragItem.width/2,0).x);}
        }
    }
}
