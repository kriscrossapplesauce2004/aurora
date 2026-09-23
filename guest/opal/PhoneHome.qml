import QtQuick
import QtQuick.Layouts
import Quickshell
// Phone home: pager pages of widgets and icons, page dots, dock and search bar; vertical drags drive the drawer.
Item {
    id:home
    property bool wide:width>=720
    readonly property int columns:wide ? 6 : Math.max(4,Math.min(5,Math.floor(width/84)))
    readonly property int rows:Math.max(3,Math.floor((pager.height-8)/112))
    readonly property int dockCount:wide ? 0 : Math.min(5,Hub.favoriteApps.length)
    // Home icons: pinned apps after the dock, then recent apps that are not pinned.
    readonly property var gridApps:Hub.favoriteApps.slice(dockCount).concat(Hub.recentApps.filter(a=>Hub.favoriteApps.indexOf(a)<0))
    readonly property int perPage:columns*rows
    // The first page shares its height with the glance and widgets; the remaining rows take icons.
    property real topHeight:0
    readonly property int firstRows:Math.max(0,Math.floor((pager.height-topHeight-8)/112))
    readonly property int firstCount:Math.min(gridApps.length,columns*firstRows)
    readonly property int appPages:Math.ceil(Math.max(0,gridApps.length-firstCount)/Math.max(1,perPage))
    function pageApps(index) {return index===0 ? gridApps.slice(0,firstCount) : gridApps.slice(firstCount+(index-1)*perPage,firstCount+index*perPage);}
    signal dragProgress(real value)
    signal dragFinished(bool open)
    signal openDrawer(bool search)

    // Vertical gesture: up opens the drawer, down opens the shade.
    DragHandler {
        id:swipe
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
        ListView {
            id:pager
            Layout.fillWidth:true;Layout.fillHeight:true
            orientation:ListView.Horizontal;snapMode:ListView.SnapOneItem;highlightRangeMode:ListView.StrictlyEnforceRange
            boundsBehavior:Flickable.StopAtBounds;clip:true
            model:1+(home.wide ? 0 : home.appPages)
            delegate:Item {
                id:page
                required property int index
                width:pager.width;height:pager.height
                RowLayout {
                    anchors.fill:parent;spacing:28
                    // Top of the first page: glance, Smart Stack and continuity. On wide screens it is the left column.
                    ColumnLayout {
                        id:top
                        visible:page.index===0
                        Layout.fillWidth:home.wide;Layout.preferredWidth:home.wide ? 1 : pager.width;Layout.alignment:Qt.AlignTop
                        Layout.maximumWidth:home.wide ? pager.width/2 : pager.width
                        spacing:14
                        onImplicitHeightChanged:if(page.index===0&&!home.wide)home.topHeight=implicitHeight
                        Component.onCompleted:if(page.index===0&&!home.wide)home.topHeight=implicitHeight
                        Item {
                            Layout.fillWidth:true;Layout.preferredHeight:glanceText.implicitHeight+12
                            ColumnLayout {
                                id:glanceText;x:6;y:8;width:parent.width-12;spacing:3
                                MText {text:Qt.formatDateTime(Hub.now,"ddd, d MMMM");font.pixelSize:home.wide ? 30 : 24;font.weight:Font.Medium}
                                RowLayout {
                                    spacing:6
                                    Glyph {font.pixelSize:15;color:Theme.primary;name:Hub.unread ? "notifications_unread" : Hub.status.charging ? "bolt" : Hub.dnd ? "do_not_disturb_on" : "wb_twilight"}
                                    MText {font.pixelSize:13;color:Theme.subtext;text:Hub.unread ? Hub.unread+(Hub.unread===1 ? " new notification" : " new notifications") : Hub.dnd ? "Do not disturb is on" : Hub.status.battery>=0 ? Hub.status.battery+"%"+(Hub.status.charging ? " · charging" : "") : "All quiet"}
                                }
                            }
                            MouseArea {anchors.fill:parent;onClicked:Hub.page="notifications"}
                        }
                        SmartStack {Layout.fillWidth:true;Layout.preferredHeight:implicitHeight}
                        ContinuityStrip {Layout.fillWidth:true}
                        CalendarWidget {visible:home.wide&&pager.height>=620;Layout.fillWidth:true;Layout.maximumWidth:420;Layout.alignment:Qt.AlignLeft}
                    }
                    // App grid: the rest of the first page, and every later page.
                    Grid {
                        Layout.fillWidth:true;Layout.preferredWidth:1;Layout.alignment:Qt.AlignTop|Qt.AlignLeft
                        Layout.topMargin:page.index===0&&!home.wide ? 0 : 8
                        columns:home.wide ? 4 : home.columns
                        visible:page.index>0||home.wide
                        Repeater {
                            model:home.wide ? Hub.favoriteApps.slice(0,16) : page.index>0 ? home.pageApps(page.index) : []
                            PhoneAppIcon {
                                required property var modelData
                                app:modelData
                                width:(home.wide ? pager.width/2-14 : pager.width)/(home.wide ? 4 : home.columns);height:112
                                onActivated:Hub.launch(app)
                            }
                        }
                    }
                }
                // First-page icons sit under the widgets in the same column.
                Grid {
                    visible:page.index===0&&!home.wide
                    y:home.topHeight+8;width:parent.width
                    columns:home.columns
                    Repeater {
                        model:page.index===0&&!home.wide ? home.pageApps(0) : []
                        PhoneAppIcon {
                            required property var modelData
                            app:modelData;width:pager.width/home.columns;height:112
                            onActivated:Hub.launch(app)
                        }
                    }
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
                    Behavior on width {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutBack}}
                }
            }
        }
        // Dock.
        RowLayout {
            visible:home.dockCount>0;Layout.fillWidth:true;spacing:0
            Repeater {
                model:Hub.favoriteApps.slice(0,home.dockCount)
                Item {
                    required property var modelData
                    Layout.fillWidth:true;Layout.preferredHeight:70
                    PhoneAppIcon {anchors.centerIn:parent;app:parent.modelData;label:false;size:60;onActivated:Hub.launch(app)}
                }
            }
        }
        // Search bar: the colour mark, then quick tools. Tapping it opens the drawer with the keyboard.
        Rectangle {
            Layout.fillWidth:true;Layout.preferredHeight:58;radius:29
            color:Theme.light ? "#ffffff" : Theme.mix(Theme.base,Theme.primaryContainer,.55)
            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:searchMouse.pressed ? .1 : 0}
            MouseArea {id:searchMouse;anchors.fill:parent;onClicked:home.openDrawer(true)}
            RowLayout {
                anchors.fill:parent;anchors.leftMargin:20;anchors.rightMargin:8;spacing:4
                Item {
                    Layout.preferredWidth:22;Layout.preferredHeight:22
                    Repeater {
                        model:[Theme.primary,Theme.tertiary,Theme.secondary,Theme.light ? Theme.containerInk : Theme.primaryContainer]
                        Rectangle {required property color modelData;required property int index;width:9;height:9;radius:4.5;color:modelData;x:index%2 ? 12 : 1;y:index<2 ? 1 : 12}
                    }
                }
                Item {Layout.fillWidth:true}
                MButton {icon:"calculate";compact:true;implicitWidth:42;implicitHeight:42;hoverHalo:true;ink:Theme.subtext;tooltip:"Calculator";onClicked:{Hub.query="= ";home.openDrawer(true);}}
                MButton {icon:"content_paste";compact:true;implicitWidth:42;implicitHeight:42;hoverHalo:true;ink:Theme.subtext;tooltip:"Clipboard";onClicked:Hub.toggleClipboard()}
            }
            Accessible.role:Accessible.Button;Accessible.name:"Search apps"
        }
    }
}
