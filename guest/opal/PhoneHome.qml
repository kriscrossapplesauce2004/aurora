import QtQuick
import QtQuick.Layouts
import Quickshell
// Phone home: pages of widgets and an editable icon grid with folders, then the dock and search pill.
// Long-press to edit: drag to reorder, drop an app on another to make a folder, add or remove widgets.
Item {
    id:home
    property bool wide:width>=720
    property bool editing:false
    property bool batteryOpen:false
    property var openFolder:null
    property int openFolderPage:-1
    property int openFolderIndex:-1
    readonly property int columns:PhoneState.columnsFor(pager.width,wide)
    readonly property real gridWidth:wide ? pager.width*.55 : pager.width
    readonly property real cellWidth:gridWidth/columns
    readonly property real cellHeight:PhoneState.cellHeight(cellWidth)
    readonly property int dockCount:wide ? 0 : Math.min(4,Hub.favoriteApps.length)
    readonly property var layout:Hub.phoneHome
    PenWatcher {anchors.fill:parent}
    signal dragProgress(real value)
    signal dragFinished(bool open)
    signal openDrawer(bool search)

    function copy() {return JSON.parse(JSON.stringify(layout));}
    function appFor(id) {return Hub.apps.find(a=>a.id===id)||null;}
    function save(next) {Hub.setPhoneHome(next);}
    // Drop handling: reorder, or merge into a folder when the drop lands on another item's centre.
    function drop(pageIndex,from,to,merge) {
        const next=copy();
        const items=next.pages[pageIndex].items;
        if(from<0||from>=items.length)return;
        if(merge&&to>=0&&to<items.length&&to!==from) {
            const moving=items[from];
            if(typeof moving!=="string")return;
            const target=items[to];
            if(typeof target==="string")items[to]={folder:"Folder",apps:[target,moving]};
            else if(target.apps.length<24&&target.apps.indexOf(moving)<0)target.apps.push(moving);
            items.splice(from,1);
        } else {
            const moving=items.splice(from,1)[0];
            items.splice(Math.max(0,Math.min(items.length,to)),0,moving);
        }
        save(next);
    }
    function moveToPage(pageIndex,from,targetPage) {
        const next=copy();
        const moving=next.pages[pageIndex].items.splice(from,1)[0];
        if(moving===undefined)return;
        while(next.pages.length<=targetPage&&next.pages.length<8)next.pages.push({widgets:[],items:[]});
        next.pages[Math.min(targetPage,next.pages.length-1)].items.push(moving);
        save(next);
    }
    function removeItem(pageIndex,index) {const next=copy();next.pages[pageIndex].items.splice(index,1);save(next);}
    function removeWidget(pageIndex,kind) {const next=copy();next.pages[pageIndex].widgets=next.pages[pageIndex].widgets.filter(w=>w!==kind);save(next);}
    function addWidget(kind) {const next=copy();const page=next.pages[Math.max(0,pager.currentIndex)];if(page.widgets.indexOf(kind)<0&&page.widgets.length<4)page.widgets.push(kind);save(next);}
    function addPage() {const next=copy();if(next.pages.length<8)next.pages.push({widgets:[],items:[]});save(next);Qt.callLater(()=>pager.positionViewAtEnd());}
    function folderSet(change) {
        const next=copy();
        const items=next.pages[openFolderPage].items;
        const folder=items[openFolderIndex];
        if(!folder||typeof folder==="string")return;
        change(folder,items);
        if(folder.apps.length===1)items[openFolderIndex]=folder.apps[0];
        else if(folder.apps.length===0)items.splice(openFolderIndex,1);
        save(next);
        openFolder=typeof items[openFolderIndex]==="object" ? items[openFolderIndex] : null;
    }

    // Vertical gesture: up opens the drawer, down opens the shade. Off while editing.
    DragHandler {
        id:swipe
        enabled:!home.editing&&home.openFolder===null
        target:null;xAxis.enabled:false;yAxis.enabled:true
        grabPermissions:PointerHandler.CanTakeOverFromItems
        onTranslationChanged:if(active&&translation.y<0)home.dragProgress(Math.min(1,-translation.y/(home.height*.55)))
        onActiveChanged:{
            if(active)return;
            if(translation.y>70){home.dragProgress(0);Hub.page="controls";return;}
            const progress=-translation.y/(home.height*.55);
            home.dragFinished(progress>.28||centroid.velocity.y<-600);
        }
    }

    ColumnLayout {
        anchors.fill:parent;anchors.leftMargin:16;anchors.rightMargin:16;anchors.bottomMargin:14;spacing:10
        // Edit bar.
        RowLayout {
            visible:home.editing;Layout.fillWidth:true;spacing:8
            MButton {text:"Widgets";icon:"widgets";tonal:true;compact:true;onClicked:widgetSheet.visible=!widgetSheet.visible}
            MButton {text:"Page";icon:"add";compact:true;enabled:home.layout.pages.length<8;onClicked:home.addPage()}
            Item {Layout.fillWidth:true}
            MButton {text:"Done";filled:true;compact:true;onClicked:{home.editing=false;widgetSheet.visible=false;}}
        }
        ListView {
            id:pager
            Layout.fillWidth:true;Layout.fillHeight:true
            orientation:ListView.Horizontal;snapMode:ListView.SnapOneItem;highlightRangeMode:ListView.StrictlyEnforceRange;highlightMoveDuration:Theme.motion(300)
            boundsBehavior:Flickable.StopAtBounds;clip:true
            interactive:!pageDelegateDragging
            property bool pageDelegateDragging:false
            model:home.layout.pages
            delegate:Item {
                id:page
                required property var modelData
                required property int index
                width:pager.width;height:pager.height
                // Neighbour pages recede while the finger moves, so a page change feels continuous.
                readonly property real distance:Math.min(1,Math.abs(x-pager.contentX)/Math.max(1,pager.width))
                opacity:1-distance*.55;scale:1-distance*.05
                // Long-press on empty space enters edit mode.
                MouseArea {anchors.fill:parent;onPressAndHold:home.editing=true}
                Flickable {
                    anchors.fill:parent;contentHeight:pageColumn.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
                    interactive:!pager.pageDelegateDragging
                    Column {
                        id:pageColumn;width:home.wide ? parent.width*.42 : parent.width;spacing:14
                        Repeater {
                            model:page.modelData.widgets
                            PhoneWidget {
                                required property string modelData
                                width:pageColumn.width;kind:modelData;editing:home.editing
                                onRemove:home.removeWidget(page.index,modelData)
                                onLongPressed:home.editing=true
                                onTapped:if(modelData==="battery"&&!home.editing)home.batteryOpen=true
                            }
                        }
                        Loader {
                            width:parent.width;active:page.index===0&&!home.editing
                            visible:active&&!!item&&item.cards.length>0
                            height:visible ? item.implicitHeight : 0
                            sourceComponent:TaskAwareSection {}
                        }
                    }
                        // Icon grid with absolute cells, so a dragged item can float.
                        Item {
                            id:grid
                            x:home.wide ? pager.width-home.gridWidth : 0
                            y:home.wide ? 0 : pageColumn.implicitHeight+(page.modelData.widgets.length ? 14 : 0)
                            width:home.gridWidth
                            height:Math.max(1,Math.ceil(page.modelData.items.length/home.columns))*home.cellHeight
                            Repeater {
                                model:page.modelData.items
                                Item {
                                    id:cell
                                    required property var modelData
                                    required property int index
                                    readonly property bool folder:typeof modelData!=="string"
                                    readonly property var app:folder ? null : home.appFor(modelData)
                                    function restX() {return (index%home.columns)*home.cellWidth;}
                                    function restY() {return Math.floor(index/home.columns)*home.cellHeight;}
                                    x:restX();y:restY()
                                    width:home.cellWidth;height:home.cellHeight
                                    visible:folder||app!==null
                                    z:dragArea.drag.active ? 10 : 0
                                    Behavior on x {enabled:!dragArea.drag.active;NumberAnimation {duration:Theme.motion(Theme.durShort);easing.type:Easing.OutCubic}}
                                    Behavior on y {enabled:!dragArea.drag.active;NumberAnimation {duration:Theme.motion(Theme.durShort);easing.type:Easing.OutCubic}}
                                    PhoneAppIcon {
                                        visible:!cell.folder&&cell.app!==null
                                        anchors.horizontalCenter:parent.horizontalCenter;y:6
                                        app:cell.app||({name:"",icon:""});size:PhoneState.iconSize(home.cellWidth)
                                        enabled:!home.editing
                                        onActivated:Hub.launch(cell.app)
                                    }
                                    // Folder: a squircle with up to four mini icons.
                                    Column {
                                        visible:cell.folder
                                        anchors.horizontalCenter:parent.horizontalCenter;y:10;spacing:7
                                        Rectangle {
                                            anchors.horizontalCenter:parent.horizontalCenter
                                            width:PhoneState.iconSize(home.cellWidth);height:width;radius:width*.3
                                            color:Theme.level(3)
                                            Grid {
                                                anchors.centerIn:parent;columns:2;spacing:4
                                                Repeater {
                                                    model:cell.folder ? cell.modelData.apps.slice(0,4) : []
                                                    AppIcon {required property string modelData;width:20;height:20;app:home.appFor(modelData);style:"raw"}
                                                }
                                            }
                                        }
                                        MText {anchors.horizontalCenter:parent.horizontalCenter;width:home.cellWidth-8;horizontalAlignment:Text.AlignHCenter;text:cell.folder ? cell.modelData.folder : "";role:"label"}
                                    }
                                    // Remove badge while editing.
                                    Rectangle {
                                        visible:home.editing&&!dragArea.drag.active
                                        x:parent.width/2+18;y:2;width:22;height:22;radius:11;color:Theme.level(4)
                                        Glyph {anchors.centerIn:parent;name:"remove";font.pixelSize:16;color:Theme.text}
                                        MouseArea {anchors.fill:parent;anchors.margins:-6;onClicked:home.removeItem(page.index,cell.index)}
                                    }
                                    MouseArea {
                                        id:dragArea
                                        anchors.fill:parent;z:-1
                                        enabled:home.editing||cell.folder
                                        drag.target:home.editing ? cell : null
                                        preventStealing:true
                                        property bool moved:false
                                        onPressed:moved=false
                                        onPositionChanged:if(drag.active){moved=true;pager.pageDelegateDragging=true;edgeTimer.cell=cell;edgeTimer.running=cell.x+cell.width>grid.width+10||cell.x<-10;}
                                        onReleased:{
                                            pager.pageDelegateDragging=false;edgeTimer.running=false;
                                            if(!moved){cell.x=Qt.binding(cell.restX);cell.y=Qt.binding(cell.restY);return;}
                                            const cx=cell.x+cell.width/2,cy=cell.y+cell.height/2;
                                            const col=Math.max(0,Math.min(home.columns-1,Math.floor(cx/home.cellWidth)));
                                            const row=Math.max(0,Math.floor(cy/home.cellHeight));
                                            const target=row*home.columns+col;
                                            // The centre third of a cell means "drop onto", the rest means "move here".
                                            const fx=cx/home.cellWidth-col,fy=cy/home.cellHeight-row;
                                            const merge=fx>.3&&fx<.7&&fy>.25&&fy<.75&&target<page.modelData.items.length;
                                            cell.x=Qt.binding(cell.restX);cell.y=Qt.binding(cell.restY);
                                            home.drop(page.index,cell.index,target,merge);
                                        }
                                        onClicked:if(cell.folder&&!moved){home.openFolder=cell.modelData;home.openFolderPage=page.index;home.openFolderIndex=cell.index;}
                                        onPressAndHold:if(!home.editing)home.editing=true
                                    }
                                }
                            }
                            // Long-press on an icon also enters edit mode.
                            TapHandler {enabled:!home.editing;onLongPressed:home.editing=true}
                        }
                }
                // Holding a dragged item at the page edge moves it to the next or previous page.
                Timer {
                    id:edgeTimer
                    property var cell:null
                    interval:700
                    onTriggered:if(cell){const forward=cell.x>0;const target=Math.max(0,page.index+(forward ? 1 : -1));if(target!==page.index){pager.pageDelegateDragging=false;home.moveToPage(page.index,cell.index,target);Qt.callLater(()=>pager.positionViewAtIndex(target,ListView.Beginning));}}
                }
            }
        }
        // Page dots: the current page stretches into a pill.
        Row {
            visible:pager.count>1;Layout.alignment:Qt.AlignHCenter;spacing:6
            Repeater {
                model:pager.count
                Rectangle {
                    required property int index
                    width:index===pager.currentIndex ? 18 : 6;height:6;radius:3
                    color:index===pager.currentIndex ? Theme.primary : Theme.alpha(Theme.text,.3)
                    Behavior on width {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
                }
            }
        }
        // Dock and search share one tonal tray.
        Rectangle {
            Layout.fillWidth:true
            Layout.preferredHeight:(home.dockCount>0 ? 76 : 0)+62
            radius:Theme.shapeXl;color:Theme.level(2)
            ColumnLayout {
                anchors.fill:parent;anchors.margins:6;spacing:4
                RowLayout {
                    visible:home.dockCount>0;Layout.fillWidth:true;Layout.preferredHeight:70;spacing:0
                    Repeater {
                        model:Hub.favoriteApps.slice(0,home.dockCount)
                        Item {
                            required property var modelData
                            Layout.fillWidth:true;Layout.fillHeight:true
                            PhoneAppIcon {anchors.centerIn:parent;app:parent.modelData;label:false;size:54;onActivated:Hub.launch(app)}
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth:true;Layout.preferredHeight:52;radius:26
                    color:Theme.level(4)
                    Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:searchMouse.pressed ? .1 : 0}
                    MouseArea {id:searchMouse;anchors.fill:parent;onClicked:home.openDrawer(true)}
                    RowLayout {
                        anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:6;spacing:8
                        Glyph {name:"search";font.pixelSize:22;color:Theme.primary}
                        MText {text:"Search apps";role:"body";color:Theme.subtext;Layout.fillWidth:true}
                        PhoneTorch {implicitWidth:40;implicitHeight:40;compact:true}
                        MButton {icon:"calculate";compact:true;implicitWidth:40;implicitHeight:40;ink:Theme.subtext;tooltip:"Calculator";onClicked:{Hub.query="= ";home.openDrawer(true);}}
                        MButton {icon:"apps";compact:true;implicitWidth:40;implicitHeight:40;ink:Theme.subtext;tooltip:"All apps";onClicked:home.openDrawer(false)}
                    }
                    Accessible.role:Accessible.Button;Accessible.name:"Search apps"
                }
            }
        }
    }

    // Battery page.
    Rectangle {
        anchors.fill:parent;visible:home.batteryOpen;color:Theme.alpha(Theme.base,.97)
        MouseArea {anchors.fill:parent}
        Loader {anchors.fill:parent;active:home.batteryOpen;sourceComponent:BatteryStats {onCloseRequested:home.batteryOpen=false}}
    }

    // Widget picker.
    Rectangle {
        id:widgetSheet
        visible:false
        anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:12
        height:widgetColumn.implicitHeight+32;radius:Theme.shapeXl;color:Theme.level(3)
        MouseArea {anchors.fill:parent}
        Column {
            id:widgetColumn;x:16;y:16;width:parent.width-32;spacing:6
            MText {text:"Add a widget";role:"title";bottomPadding:6}
            Repeater {
                model:[{kind:"glance",name:"Clock and status",icon:"schedule"},{kind:"stack",name:"Smart stack",icon:"stacks"},{kind:"media",name:"Now playing",icon:"music_note"},{kind:"calendar",name:"Calendar",icon:"calendar_month"},{kind:"battery",name:"Batteries",icon:"battery_full"},{kind:"focus",name:"Focus timer",icon:"timer"}]
                Rectangle {
                    required property var modelData
                    readonly property bool added:(home.layout.pages[Math.max(0,pager.currentIndex)]||{widgets:[]}).widgets.indexOf(modelData.kind)>=0
                    width:widgetColumn.width;height:48;radius:Theme.shapeMd
                    color:added ? Theme.secondaryContainer : Theme.level(4)
                    Row {anchors.verticalCenter:parent.verticalCenter;x:14;spacing:12
                        Glyph {name:modelData.icon;font.pixelSize:20;color:Theme.primary;anchors.verticalCenter:parent.verticalCenter}
                        MText {text:modelData.name;role:"body";anchors.verticalCenter:parent.verticalCenter}}
                    Glyph {anchors.right:parent.right;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;name:parent.added ? "check" : "add";font.pixelSize:20;color:Theme.subtext}
                    MouseArea {anchors.fill:parent;onClicked:if(parent.added)home.removeWidget(Math.max(0,pager.currentIndex),modelData.kind);else home.addWidget(modelData.kind)}
                }
            }
        }
    }

    // Folder overlay.
    Rectangle {
        anchors.fill:parent;color:Theme.alpha("#000000",.4)
        visible:home.openFolder!==null
        MouseArea {anchors.fill:parent;onClicked:home.openFolder=null}
        Rectangle {
            anchors.centerIn:parent
            width:Math.min(parent.width-48,360);height:folderColumn.implicitHeight+40
            radius:Theme.shapeXl;color:Theme.level(2)
            MouseArea {anchors.fill:parent}
            Column {
                id:folderColumn;x:20;y:20;width:parent.width-40;spacing:16
                TextInput {
                    width:parent.width;horizontalAlignment:TextInput.AlignHCenter
                    text:home.openFolder ? home.openFolder.folder : ""
                    color:Theme.text;font.family:Theme.font;font.pixelSize:22;font.weight:Font.Bold
                    maximumLength:40;selectByMouse:true
                    onEditingFinished:if(home.openFolder&&text.trim()!==""&&text!==home.openFolder.folder){const name=text.trim();home.folderSet(f=>f.folder=name);}
                }
                Grid {
                    anchors.horizontalCenter:parent.horizontalCenter;columns:3;spacing:8
                    Repeater {
                        model:home.openFolder ? home.openFolder.apps : []
                        Item {
                            required property string modelData
                            width:(folderColumn.width-16)/3;height:96
                            PhoneAppIcon {anchors.horizontalCenter:parent.horizontalCenter;app:home.appFor(modelData)||({name:modelData,icon:""});size:52;enabled:!home.editing;onActivated:{const a=home.appFor(modelData);home.openFolder=null;if(a)Hub.launch(a);}}
                            Rectangle {
                                visible:home.editing;x:parent.width/2+14;y:0;width:22;height:22;radius:11;color:Theme.level(4)
                                Glyph {anchors.centerIn:parent;name:"remove";font.pixelSize:16;color:Theme.text}
                                MouseArea {anchors.fill:parent;anchors.margins:-6;onClicked:{const id=modelData;home.folderSet((f,items)=>{f.apps=f.apps.filter(a=>a!==id);items.push(id);});}}
                            }
                        }
                    }
                }
            }
        }
    }
}
