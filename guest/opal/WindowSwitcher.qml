import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:s
    property string layoutMode:"desktop"
    property bool active:visible
    property string query:""
    property bool currentWorkspace:false
    readonly property string normalizedQuery:query.toLowerCase()
    readonly property bool touch:layoutMode==="phone"
    readonly property bool gaming:layoutMode==="console"
    readonly property bool touchCarousel:touch&&width<680
    readonly property var windowSearchIndex:Hub.windows.map(entry=>({entry:entry,search:(String(entry.title)+" "+String(entry.className)).toLowerCase()}))
    readonly property var windows:{
        const matches=[];
        for(let index=0;index<windowSearchIndex.length;index+=1){
            const candidate=windowSearchIndex[index];
            if((!currentWorkspace||candidate.entry.workspace===Hub.status.workspace)&&(normalizedQuery===""||candidate.search.indexOf(normalizedQuery)>=0))matches.push(candidate.entry);
        }
        return matches;
    }
    property int selection:0
    Component.onCompleted:{selection=Math.max(0,windows.findIndex(w=>Hub.active(w)));if(active&&!touch)forceActiveFocus();}
    onActiveChanged:if(active&&!touch)forceActiveFocus()
    onWindowsChanged:selection=Math.max(0,Math.min(selection,windows.length-1))
    function navigate(key) {
        if(!active)return;
        if(key==="back"){Hub.close();return;}
        if(key==="accept"){if(windows[selection])Hub.focusWindow(windows[selection]);return;}
        let step=key==="left" ? -1 : key==="right" ? 1 : key==="up" ? -grid.columns : key==="down" ? grid.columns : 0;
        selection=Math.max(0,Math.min(windows.length-1,selection+step));
        if(touchCarousel)carousel.positionViewAtIndex(selection,ListView.SnapPosition);else grid.positionViewAtIndex(selection,GridView.Contain);
    }
    Connections {target:Hub;function onNavigate(key){if(s.active&&s.gaming)s.navigate(key);}}
    Keys.onPressed:event=>{
        const key=({[Qt.Key_Left]:"left",[Qt.Key_Right]:"right",[Qt.Key_Up]:"up",[Qt.Key_Down]:"down",[Qt.Key_Return]:"accept",[Qt.Key_Enter]:"accept",[Qt.Key_Escape]:"back"})[event.key];
        if(key){s.navigate(key);event.accepted=true;}
    }
    ColumnLayout {
        anchors.fill:parent;spacing:12
        RowLayout {Layout.fillWidth:true;spacing:8
            TextField {Layout.fillWidth:true;implicitHeight:48;placeholderText:"Find an open app";leftPadding:18;color:Theme.text;placeholderTextColor:Theme.subtext;font.family:Theme.font;selectByMouse:true;background:Rectangle {radius:24;color:Theme.alpha(Theme.surfaceHigh,.55)} onTextEdited:s.query=text;onAccepted:s.navigate("accept")}
            MButton {visible:Hub.status.hypr;icon:"desktop";text:s.width>600 ? "This workspace" : "";tonal:!s.currentWorkspace;filled:s.currentWorkspace;tooltip:"Only this workspace";onClicked:s.currentWorkspace=!s.currentWorkspace}
        }
        RowLayout {Layout.fillWidth:true
            MText {text:s.windows.length+" open app"+(s.windows.length===1 ? "" : "s");font.pixelSize:12;color:Theme.subtext;Layout.fillWidth:true}
            MText {text:s.touchCarousel ? "Swipe · tap a card to return" : s.touch ? "Tap a window to return" : s.gaming ? "D-pad to choose · A to return" : "Click to return · right-click for actions";font.pixelSize:11;color:Theme.subtext}
        }
        Item {Layout.fillWidth:true;Layout.fillHeight:true
            GridView {
                id:grid;anchors.fill:parent;visible:!s.touchCarousel;clip:true;model:s.touchCarousel ? [] : s.windows
                readonly property int columns:Math.max(1,Math.floor(width/(s.touch ? 420 : s.gaming ? 320 : 270)))
                cellWidth:width/columns;cellHeight:s.touch ? 360 : s.gaming ? 340 : 280
                boundsBehavior:Flickable.StopAtBounds;cacheBuffer:0;ScrollBar.vertical:ScrollBar {}
                delegate:Item {id:gridDelegate;required property var modelData;required property int index;width:grid.cellWidth;height:grid.cellHeight
                    Loader {anchors.fill:parent;anchors.margins:6;sourceComponent:card;onLoaded:{item.entry=Qt.binding(()=>modelData);item.index=Qt.binding(()=>index);item.previewActive=Qt.binding(()=>s.active&&grid.visible&&gridDelegate.y+gridDelegate.height>grid.contentY&&gridDelegate.y<grid.contentY+grid.height);}}
                }
            }
            ListView {
                id:carousel;anchors.left:parent.left;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter
                height:Math.min(parent.height,380);visible:s.touchCarousel;clip:true;model:s.touchCarousel ? s.windows : []
                orientation:ListView.Horizontal;spacing:14;snapMode:ListView.SnapOneItem;boundsBehavior:Flickable.StopAtBounds
                preferredHighlightBegin:16;preferredHighlightEnd:16;highlightRangeMode:ListView.StrictlyEnforceRange;cacheBuffer:0
                onCurrentIndexChanged:if(s.touchCarousel)s.selection=Math.max(0,currentIndex)
                delegate:Item {id:carouselDelegate;required property var modelData;required property int index;width:Math.min(360,carousel.width*.84);height:carousel.height
                    Loader {anchors.fill:parent;anchors.margins:6;sourceComponent:card;onLoaded:{item.entry=Qt.binding(()=>modelData);item.index=Qt.binding(()=>index);item.previewActive=Qt.binding(()=>s.active&&carousel.visible&&carouselDelegate.x+carouselDelegate.width>carousel.contentX&&carouselDelegate.x<carousel.contentX+carousel.width);}}
                }
            }
            MText {anchors.centerIn:parent;visible:s.windows.length===0;text:s.query ? "No open apps match your search." : "Nothing open here yet.";color:Theme.subtext}
        }
        RowLayout {visible:s.touchCarousel&&s.windows.length>1;Layout.alignment:Qt.AlignHCenter
            MButton {icon:"back";tooltip:"Previous app";enabled:s.selection>0;onClicked:s.navigate("left")}
            MText {text:(s.selection+1)+" / "+s.windows.length;font.pixelSize:12;color:Theme.subtext}
            MButton {icon:"next";tooltip:"Next app";enabled:s.selection<s.windows.length-1;onClicked:s.navigate("right")}
        }
    }
    Component {id:card
        Rectangle {
            id:c
            property var entry:({title:"",className:"",workspace:0})
            property int index:0
            property bool previewActive:false
            readonly property var app:Hub.appForWindow(entry)
            radius:s.touch ? 28 : 24;color:Theme.alpha(s.selection===index ? Theme.primaryContainer : Theme.surfaceHigh,s.selection===index ? .60 : .38)
            border.width:1;border.color:s.selection===index ? Theme.primary : Theme.outline
            property real entrance:0
            opacity:entrance;transform:Translate {y:18*(1-c.entrance)}
            Component.onCompleted:Qt.callLater(()=>cardEnter.restart())
            SequentialAnimation {id:cardEnter
                PauseAnimation {duration:Theme.motion(Math.min(c.index,5)*35)}
                NumberAnimation {target:c;property:"entrance";from:0;to:1;duration:Theme.motion(320);easing.type:Easing.OutCubic}
            }
            scale:click.pressed ? .98 : 1
            Behavior on color {ColorAnimation {duration:Theme.motion(180)}}
            Behavior on scale {NumberAnimation {duration:Theme.motion(180)}}
            MouseArea {id:click;anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton;onClicked:e=>{s.selection=c.index;if(e.button===Qt.RightButton)menu.popup(e.x,e.y);else Hub.focusWindow(c.entry);}onPressAndHold:e=>menu.popup(e.x,e.y)}
            OpalMenu {id:menu;entries:Hub.windowMenu(c.entry)}
            ColumnLayout {anchors.fill:parent;anchors.margins:s.gaming ? 24 : 18;spacing:12
                RowLayout {Layout.fillWidth:true;spacing:12
                    Item {Layout.preferredWidth:s.touch||s.gaming ? 48 : 36;Layout.preferredHeight:Layout.preferredWidth
                        Image {id:icon;anchors.fill:parent;source:Quickshell.iconPath(c.app ? c.app.icon : "application-x-executable",true)}
                        Glyph {anchors.centerIn:parent;visible:icon.status!==Image.Ready;name:"apps";font.pixelSize:30;color:Theme.primary}
                    }
                    MText {text:c.app ? c.app.name : String(c.entry.className).startsWith("steam_app_") ? "Game" : c.entry.className||"Application";Layout.fillWidth:true;font.pixelSize:13;font.weight:Font.DemiBold}
                    MButton {icon:"close";implicitWidth:44;implicitHeight:44;tooltip:"Close "+c.entry.title;onClicked:Hub.closeWindow(c.entry)}
                }
                Rectangle {Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:64;radius:14;color:Theme.alpha(Theme.base,.5)
                    Loader {anchors.fill:parent;anchors.margins:4;active:c.previewActive;source:Hub.status.hypr ? "HyprWindowPreview.qml" : "WindowPreview.qml";onLoaded:{if(Hub.status.hypr)item.address=Qt.binding(()=>c.entry.address||"");else item.handle=Qt.binding(()=>c.entry.handle||null);}}
                }
                MText {text:c.entry.title;Layout.fillWidth:true;wrapMode:Text.WordWrap;maximumLineCount:2;font.pixelSize:s.gaming ? 20 : 16;font.weight:Font.DemiBold}
                RowLayout {Layout.fillWidth:true
                    MText {text:c.entry.workspace ? "Workspace "+c.entry.workspace : "Running";font.pixelSize:11;color:Theme.subtext;Layout.fillWidth:true}
                    MText {text:Hub.active(c.entry) ? "Active" : "Return ↗";font.pixelSize:11;color:Theme.primary}
                }
            }
            activeFocusOnTab:true
            onActiveFocusChanged:if(activeFocus)s.selection=index
            Keys.onReturnPressed:Hub.focusWindow(entry)
            Accessible.role:Accessible.Button;Accessible.name:entry.title
            Accessible.onPressAction:Hub.focusWindow(entry)
        }
    }
}
