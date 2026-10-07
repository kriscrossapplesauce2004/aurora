import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:settings
    property real arrival:0
    opacity:Math.min(1,arrival)
    transform:[
        Scale {origin.x:settings.width/2;origin.y:settings.height/2;xScale:.97+.03*settings.arrival;yScale:.97+.03*settings.arrival},
        Translate {y:(1-settings.arrival)*14}
    ]
    Component.onCompleted:enter.restart()
    NumberAnimation {id:enter;target:settings;property:"arrival";from:0;to:1;duration:Theme.motion(420);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
    readonly property bool narrow:width<720
    readonly property var groups:[
        {title:"Connections",items:[
            {id:"network",title:"Network & internet",icon:"wifi",detail:"Wi-Fi and saved networks"},
            {id:"bluetooth",title:"Connected devices",icon:"bluetooth",detail:"Bluetooth and pairing"},
            {id:"link",title:"Opal Link",icon:"devices",detail:"Your phone and other Opal devices"}]},
        {title:"Device",items:[
            {id:"sound",title:"Sound",icon:"volume",detail:"Volume, outputs and microphone"},
            {id:"displays",title:"Displays",icon:"monitor",detail:"Arrangement, docking and what each screen becomes"},
            {id:"power",title:"Battery & power",icon:"battery",detail:"Profiles and staying awake"}]},
        {title:"Personal",items:[
            {id:"appearance",title:"Wallpaper & style",icon:"palette",detail:"Colours, wallpaper and glass"},
            {id:"taskbar",title:"Shelf",icon:"desktop",detail:"Alignment, labels and hiding"},
            {id:"phone",title:"Phone & navigation",icon:"phone",detail:"Gestures, buttons and keyboard"},
            {id:"notifications",title:"Notifications",icon:"bell",detail:"Do not disturb and inbox"},
            {id:"schedules",title:"Night light & schedules",icon:"nightlight",detail:"Warm screen, dark theme and quiet hours"},
            {id:"apptheme",title:"Theme for apps",icon:"format_paint",detail:"GTK, Kitty, Qt and window borders"},
            {id:"profiles",title:"Profiles",icon:"style",detail:"Save and switch whole setups"}]},
        {title:"System",items:[
            {id:"accessibility",title:"Accessibility",icon:"accessibility_new",detail:"Motion and readable surfaces"},
            {id:"system",title:"Updates & health",icon:"system_update",detail:"Updates, storage and temperatures"},
            {id:"about",title:"About this device",icon:"info",detail:"System, shell and live usage"}]}
    ]
    readonly property var sections:groups.reduce((all,g)=>all.concat(g.items),[])
    property string query:""
    property string armedPower:""
    Timer {id:disarm;interval:3000;onTriggered:settings.armedPower=""}
    readonly property var filteredGroups:groups.map(g=>({title:g.title,items:g.items.filter(s=>(s.title+" "+s.detail).toLowerCase().indexOf(query.toLowerCase())>=0)})).filter(g=>g.items.length)
    readonly property var selected:sections.find(s=>s.id===Hub.settingsSection)||null
    // Badge colours follow the group, so related settings share a hue.
    function badge(index) {return [Theme.primaryContainer,Theme.secondaryContainer,Theme.tertiaryContainer,Theme.surfaceHighest][index%4];}
    function badgeInk(index) {return [Theme.onContainer,Theme.onSecondaryContainer,Theme.onTertiaryContainer,Theme.text][index%4];}
    function groupIndex(id) {return groups.findIndex(g=>g.items.some(i=>i.id===id));}
    // Controller: LB and RB step through sections. B returns to the overview first.
    function controllerTab(delta) {const ids=sections.map(s=>s.id);const i=ids.indexOf(Hub.settingsSection);Hub.settingsSection=ids[i<0 ? (delta>0 ? 0 : ids.length-1) : (i+delta+ids.length)%ids.length];}
    function controllerBack() {if(Hub.settingsSection==="")return false;Hub.settingsSection="";return true;}

    RowLayout {
        anchors.fill:parent;anchors.margins:settings.narrow ? 14 : 20;spacing:20
        // Navigation pane.
        ColumnLayout {
            visible:!settings.narrow||Hub.settingsSection===""
            Layout.fillWidth:settings.narrow;Layout.preferredWidth:settings.narrow ? -1 : 320;Layout.fillHeight:true;spacing:14
            RowLayout {
                Layout.fillWidth:true;Layout.leftMargin:6
                MText {text:"Settings";font.pixelSize:30;font.weight:Font.Medium;Layout.fillWidth:true}
                MButton {visible:settings.narrow;icon:"close";contained:true;compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Close settings";onClicked:Hub.close()}
            }
            Rectangle {
                Layout.fillWidth:true;Layout.preferredHeight:52;radius:26
                color:Theme.light ? "#ffffff" : Theme.mix(Theme.base,Theme.primaryContainer,.5)
                RowLayout {anchors.fill:parent;anchors.leftMargin:16;anchors.rightMargin:8;spacing:10
                    Glyph {name:"search";color:Theme.subtext;font.pixelSize:20}
                    TextField {id:searchField;Layout.fillWidth:true;Layout.fillHeight:true;placeholderText:"Search settings";color:Theme.text;placeholderTextColor:Theme.subtext;font.family:Theme.font;font.pixelSize:15;onTextChanged:settings.query=text
                        background:Item {}}
                    MButton {visible:searchField.text!=="";icon:"close";compact:true;implicitWidth:34;implicitHeight:34;onClicked:searchField.text=""}
                }
            }
            Flickable {
                Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentHeight:nav.implicitHeight;boundsBehavior:Flickable.StopAtBounds
                ScrollBar.vertical:ScrollBar {}
                ColumnLayout {
                    id:nav;width:parent.width;spacing:6
                    DeviceCard {visible:settings.query==="";Layout.fillWidth:true;Layout.bottomMargin:8;compact:true}
                    Repeater {
                        model:settings.filteredGroups
                        ColumnLayout {
                            id:navGroup
                            required property var modelData
                            required property int index
                            Layout.fillWidth:true;Layout.bottomMargin:10;spacing:3
                            MText {text:navGroup.modelData.title;font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:14;Layout.bottomMargin:4}
                            Repeater {
                                model:navGroup.modelData.items
                                NavRow {
                                    required property var modelData
                                    required property int index
                                    item:modelData;first:index===0;last:index===navGroup.modelData.items.length-1
                                    tint:settings.badge(settings.groupIndex(modelData.id));tintInk:settings.badgeInk(settings.groupIndex(modelData.id))
                                }
                            }
                        }
                    }
                    MText {visible:settings.filteredGroups.length===0;Layout.fillWidth:true;Layout.topMargin:20;horizontalAlignment:Text.AlignHCenter;text:"No settings match “"+settings.query+"”";color:Theme.subtext}
                }
            }
        }
        // Detail pane: a solid sheet, so dense controls stay readable over any wallpaper.
        Rectangle {
            visible:!settings.narrow||Hub.settingsSection!==""
            Layout.fillWidth:true;Layout.fillHeight:true;radius:28
            color:Theme.alpha(Theme.light ? Theme.surfaceLow : Theme.surfaceLow,Theme.light ? .9 : .82)
            ColumnLayout {
                anchors.fill:parent;anchors.margins:settings.narrow ? 14 : 22;spacing:14
                RowLayout {
                    Layout.fillWidth:true;spacing:10
                    MButton {visible:settings.narrow;icon:"back";contained:true;compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Back";onClicked:Hub.settingsSection=""}
                    Rectangle {
                        visible:!!settings.selected;Layout.preferredWidth:44;Layout.preferredHeight:44;radius:22
                        color:settings.selected ? settings.badge(settings.groupIndex(settings.selected.id)) : "transparent"
                        Glyph {anchors.centerIn:parent;name:settings.selected ? settings.selected.icon : "";font.pixelSize:22;color:settings.selected ? settings.badgeInk(settings.groupIndex(settings.selected.id)) : Theme.text}
                    }
                    ColumnLayout {
                        Layout.fillWidth:true;spacing:1
                        MText {Layout.fillWidth:true;text:settings.selected ? settings.selected.title : "Overview";font.pixelSize:24;font.weight:Font.Medium}
                        MText {Layout.fillWidth:true;text:settings.selected ? settings.selected.detail : "Your device at a glance";font.pixelSize:12;color:Theme.subtext}
                    }
                    MButton {visible:!settings.narrow;icon:"close";contained:true;compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Close settings";onClicked:Hub.close()}
                }
                Loader {
                    id:page
                    Layout.fillWidth:true;Layout.fillHeight:true
                    sourceComponent:Hub.settingsSection==="" ? overviewPage : Hub.settingsSection==="network"||Hub.settingsSection==="bluetooth" ? connectionPage : Hub.settingsSection==="appearance" ? stylePage : Hub.settingsSection==="displays"||Hub.settingsSection==="display"||Hub.settingsSection==="screens" ? screensPage : Hub.settingsSection==="schedules" ? schedulesPage : Hub.settingsSection==="apptheme" ? appThemePage : Hub.settingsSection==="profiles" ? profilesPage : Hub.settingsSection==="system" ? systemPage : Hub.settingsSection==="link" ? linkPage : Hub.settingsSection==="sound" ? soundPage : optionsPage
                    // Pages slide in from the side on every section change.
                    onLoaded:{pageIn.restart();}
                    ParallelAnimation {
                        id:pageIn
                        NumberAnimation {target:page;property:"opacity";from:0;to:1;duration:Theme.motion(220)}
                        NumberAnimation {target:pageShift;property:"x";from:24;to:0;duration:Theme.motion(320);easing.type:Easing.OutCubic}
                    }
                    transform:Translate {id:pageShift}
                }
            }
        }
    }

    component NavRow: Rectangle {
        id:navRow
        property var item:({})
        property bool first:true
        property bool last:true
        property color tint:Theme.primaryContainer
        property color tintInk:Theme.onContainer
        readonly property bool current:Hub.settingsSection===item.id
        Layout.fillWidth:true;Layout.preferredHeight:68
        topLeftRadius:current ? 34 : first ? 24 : 6;topRightRadius:topLeftRadius
        bottomLeftRadius:current ? 34 : last ? 24 : 6;bottomRightRadius:bottomLeftRadius
        color:current ? Theme.secondaryContainer : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .72 : .5)
        Behavior on color {ColorAnimation {duration:Theme.motion(160)}}
        Behavior on topLeftRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
        Behavior on bottomLeftRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
        Rectangle {anchors.fill:parent;topLeftRadius:parent.topLeftRadius;topRightRadius:parent.topRightRadius;bottomLeftRadius:parent.bottomLeftRadius;bottomRightRadius:parent.bottomRightRadius;color:Theme.stateLayer;opacity:navMouse.pressed ? .12 : navMouse.containsMouse ? .06 : 0}
        RowLayout {
            anchors.fill:parent;anchors.leftMargin:14;anchors.rightMargin:14;spacing:14
            Rectangle {
                Layout.preferredWidth:40;Layout.preferredHeight:40;radius:navRow.current ? 12 : 20;color:navRow.current ? Theme.primary : navRow.tint
                Behavior on radius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
                Glyph {anchors.centerIn:parent;name:navRow.item.icon;font.pixelSize:20;color:navRow.current ? Theme.onPrimary : navRow.tintInk}
            }
            ColumnLayout {
                Layout.fillWidth:true;spacing:2
                MText {Layout.fillWidth:true;text:navRow.item.title;font.pixelSize:15;font.weight:Font.Medium;color:navRow.current ? Theme.onSecondaryContainer : Theme.text}
                MText {Layout.fillWidth:true;text:navRow.item.detail;font.pixelSize:12;color:navRow.current ? Theme.alpha(Theme.onSecondaryContainer,.75) : Theme.subtext}
            }
        }
        MouseArea {id:navMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:Hub.settingsSection=navRow.item.id}
        activeFocusOnTab:true
        Keys.onReturnPressed:Hub.settingsSection=item.id
        Accessible.role:Accessible.Button;Accessible.name:item.title;Accessible.onPressAction:Hub.settingsSection=item.id
    }

    // Device card: live state in one glance. Every value comes from the status adapter.
    component DeviceCard: Rectangle {
        id:card
        property bool compact:false
        implicitHeight:compact ? 128 : 200
        radius:28
        color:Theme.primaryContainer
        clip:true
        Flower {x:card.width-width*.7;y:-height*.25;width:card.height*1.3;height:width;lobes:9;depth:.1;fill:Theme.alpha(Theme.onContainer,.07)
            NumberAnimation on rotation {from:0;to:360;duration:120000;loops:Animation.Infinite;running:!Theme.reduceMotion}
        }
        ColumnLayout {
            anchors.fill:parent;anchors.margins:18;spacing:4
            MText {text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:card.compact ? 30 : 48;font.weight:Font.Medium;color:Theme.onContainer}
            MText {text:Qt.formatDateTime(Hub.now,"dddd, d MMMM")+(Hub.status.uptime ? "  ·  up "+Hub.status.uptime : "");font.pixelSize:12;color:Theme.alpha(Theme.onContainer,.8)}
            Item {Layout.fillHeight:true}
            Flow {
                Layout.fillWidth:true;spacing:6
                Repeater {
                    model:[
                        {icon:Hub.status.wifi ? "wifi" : "wifiOff",text:Hub.status.wifi ? Hub.status.network : "Offline",show:true},
                        {icon:Hub.status.charging ? "charging" : "battery",text:Hub.status.battery+"%",show:Hub.status.battery>=0},
                        {icon:"bluetooth",text:"On",show:!!Hub.status.bluetooth},
                        {icon:Hub.status.muted ? "mute" : "volume",text:Hub.status.muted ? "Muted" : Hub.status.volume+"%",show:true}
                    ].filter(x=>x.show).slice(0,card.compact ? 3 : 4)
                    Rectangle {
                        required property var modelData
                        width:chipRow.implicitWidth+18;height:28;radius:14;color:Theme.alpha(Theme.onContainer,.1)
                        Row {id:chipRow;anchors.centerIn:parent;spacing:5
                            Glyph {name:modelData.icon;font.pixelSize:15;color:Theme.onContainer;anchors.verticalCenter:parent.verticalCenter}
                            MText {text:modelData.text;font.pixelSize:11;font.weight:Font.Medium;color:Theme.onContainer;anchors.verticalCenter:parent.verticalCenter}
                        }
                    }
                }
            }
        }
    }

    Component {id:overviewPage;Flickable {contentHeight:overview.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
        ColumnLayout {id:overview;width:parent.width;spacing:14
            DeviceCard {Layout.fillWidth:true}
            MText {text:"Shortcuts";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6;Layout.topMargin:6}
            GridLayout {
                Layout.fillWidth:true;columns:width>=520 ? 3 : 2;columnSpacing:8;rowSpacing:8
                Repeater {
                    model:settings.sections
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth:true;Layout.preferredHeight:92;radius:24
                        color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                        Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:tileMouse.pressed ? .12 : tileMouse.containsMouse ? .06 : 0}
                        ColumnLayout {anchors.fill:parent;anchors.margins:14;spacing:6
                            Rectangle {Layout.preferredWidth:34;Layout.preferredHeight:34;radius:17;color:settings.badge(settings.groupIndex(modelData.id))
                                Glyph {anchors.centerIn:parent;name:modelData.icon;font.pixelSize:18;color:settings.badgeInk(settings.groupIndex(modelData.id))}
                            }
                            MText {Layout.fillWidth:true;text:modelData.title;font.pixelSize:13;font.weight:Font.Medium}
                        }
                        MouseArea {id:tileMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:Hub.settingsSection=modelData.id}
                    }
                }
            }
        }
    }}
    Component {id:stylePage;Appearance {compact:settings.narrow;embedded:true}}
    Component {id:displayPage;Convergence {embedded:true}}
    Component {id:screensPage;SettingsScreens {}}
    Component {id:schedulesPage;SettingsSchedules {}}
    Component {id:appThemePage;SettingsAppTheme {}}
    Component {id:profilesPage;SettingsProfiles {}}
    Component {id:systemPage;SettingsSystem {}}
    Component {id:linkPage;SettingsLink {}}
    Component {id:connectionPage;ConnectionPanel {kind:Hub.settingsSection==="network" ? "wifi" : "bluetooth";embedded:true;backAction:()=>{Hub.settingsSection="";}}}
    Component {id:soundPage;Flickable {contentHeight:sound.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:ScrollBar {}
        ColumnLayout {id:sound;width:parent.width;spacing:3
            SectionLabel {text:"Output · "+(Hub.status.audioOutput||"Default device")}
            RowLayout {Layout.fillWidth:true;Layout.bottomMargin:12;spacing:8
                ExpressiveSlider {Layout.fillWidth:true;implicitHeight:58;compact:true;trackHeight:46;icon:Hub.status.muted ? "mute" : "volume";iconAtHandle:true;value:Hub.status.volume;activeColor:Hub.status.muted ? Theme.subtext : Theme.primary;onMoved:Hub.volume(value);Accessible.name:"Output volume"}
                MText {Layout.preferredWidth:44;horizontalAlignment:Text.AlignRight;text:Hub.status.volume+"%";font.pixelSize:15;font.weight:Font.Medium}
            }
            SettingToggle {Layout.fillWidth:true;first:true;last:false;icon:"volume_off";title:"Mute output";checked:!!Hub.status.muted;onToggled:Hub.command({action:"mute"})}
            SettingToggle {Layout.fillWidth:true;first:false;last:true;icon:"mic_off";title:"Mute microphone";description:"Applies to the default input device.";checked:!!Hub.status.micMuted;onToggled:Hub.command({action:"mic"})}
            SectionLabel {visible:Hub.status.track!=="";text:"Now playing";Layout.topMargin:12}
            MediaCard {visible:Hub.status.track!=="";Layout.fillWidth:true;Layout.preferredHeight:150;compact:true}
            SectionLabel {text:"More";Layout.topMargin:12}
            LinkRow {Layout.fillWidth:true;first:true;last:false;icon:"graphic_eq";title:"Sound drawer";detail:"Outputs, apps and players";onActivated:Hub.openAudio(Hub.targetScreen)}
            LinkRow {Layout.fillWidth:true;first:false;last:true;icon:"tune";title:"Advanced mixer";detail:"Opens the system volume control";onActivated:Hub.settings("audio")}
        }
    }}
    Component {id:optionsPage;Flickable {contentHeight:options.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:ScrollBar {}
        ColumnLayout {id:options;width:parent.width;spacing:3
            // Power.
            Rectangle {
                visible:Hub.settingsSection==="power";Layout.fillWidth:true;Layout.preferredHeight:112;Layout.bottomMargin:12;radius:28;color:Theme.primaryContainer
                RowLayout {anchors.fill:parent;anchors.margins:20;spacing:18
                    // Battery gauge: a pill that fills with the charge level.
                    Rectangle {Layout.preferredWidth:34;Layout.preferredHeight:66;radius:12;color:Theme.alpha(Theme.onContainer,.14)
                        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:parent.height*Math.max(0,Math.min(100,Hub.status.battery))/100;radius:12;color:Theme.onContainer;Behavior on height {NumberAnimation {duration:Theme.motion(500);easing.type:Easing.OutCubic}}}
                        Glyph {anchors.centerIn:parent;visible:Hub.status.charging;name:"bolt";font.pixelSize:20;color:Theme.primaryContainer}
                    }
                    ColumnLayout {Layout.fillWidth:true;spacing:2
                        MText {text:Hub.status.battery>=0 ? Hub.status.battery+"%" : "No battery";font.pixelSize:34;font.weight:Font.Medium;color:Theme.onContainer}
                        MText {text:Hub.status.battery>=0 ? (Hub.status.charging ? "Charging" : "On battery") : "Battery information is not available";font.pixelSize:13;color:Theme.alpha(Theme.onContainer,.8)}
                    }
                }
            }
            SectionLabel {visible:Hub.settingsSection==="power";text:"Power profile"}
            SegmentedButtons {visible:Hub.settingsSection==="power";Layout.fillWidth:true;Layout.bottomMargin:12;enabledAll:!!Hub.status.profile;current:Hub.status.profile
                options:[{value:"power-saver",label:"Saver",icon:"eco"},{value:"balanced",label:"Balanced",icon:"balance"},{value:"performance",label:"Performance",icon:"speed"}]
                onPicked:value=>Hub.command({action:"profile",value:value})
            }
            SettingToggle {visible:Hub.settingsSection==="power";Layout.fillWidth:true;icon:"coffee";title:"Keep awake";description:"Stop the screen from sleeping while this is on.";checked:Hub.keepAwake;onToggled:Hub.keepAwake=!Hub.keepAwake}
            SectionLabel {visible:Hub.settingsSection==="power";text:"Session";Layout.topMargin:12}
            RowLayout {
                visible:Hub.settingsSection==="power";Layout.fillWidth:true;spacing:6
                Repeater {
                    model:[{id:"lock",label:"Lock",icon:"lock"},{id:"suspend",label:"Sleep",icon:"bedtime"},{id:"reboot",label:"Restart",icon:"restart_alt"},{id:"poweroff",label:"Shut down",icon:"power_settings_new"}]
                    Rectangle {
                        required property var modelData
                        readonly property bool armed:settings.armedPower===modelData.id
                        Layout.fillWidth:true;Layout.preferredHeight:76;radius:armed ? 18 : 24
                        color:armed ? Theme.error : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                        Behavior on color {ColorAnimation {duration:Theme.motion(160)}}
                        Column {anchors.centerIn:parent;spacing:4
                            Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:parent.parent.modelData.icon;font.pixelSize:22;color:parent.parent.armed ? Theme.base : Theme.primary}
                            MText {anchors.horizontalCenter:parent.horizontalCenter;text:parent.parent.armed ? "Tap again" : parent.parent.modelData.label;font.pixelSize:11;font.weight:Font.Medium;color:parent.parent.armed ? Theme.base : Theme.text}
                        }
                        MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{
                            const id=parent.modelData.id;
                            if(id==="lock"){Hub.settings("lock");return;}
                            if(parent.armed){Hub.command({action:"power",verb:id});Hub.close();}
                            else {settings.armedPower=id;disarm.restart();}
                        }}
                        Accessible.role:Accessible.Button;Accessible.name:modelData.label
                    }
                }
            }
            MText {visible:Hub.settingsSection==="power";Layout.fillWidth:true;Layout.leftMargin:6;text:"Sleep, restart and shut down ask for a second tap.";font.pixelSize:11;color:Theme.subtext}
            // Shelf.
            SectionLabel {visible:Hub.settingsSection==="taskbar";text:"Bar style"}
            SegmentedButtons {visible:Hub.settingsSection==="taskbar";Layout.fillWidth:true;Layout.bottomMargin:12;current:Hub.prefs.barStyle||"islands"
                options:[{value:"islands",label:"Islands",icon:"view_column"},{value:"dock",label:"Dock",icon:"call_to_action"},{value:"split",label:"Split",icon:"splitscreen"},{value:"edge",label:"Edge",icon:"bottom_navigation"}]
                onPicked:value=>Hub.set("barStyle",value)}
            SettingToggle {visible:Hub.settingsSection==="taskbar";Layout.fillWidth:true;first:true;last:false;icon:"vertical_align_bottom";title:"Hide the shelf automatically";description:"Move to the bottom edge to reveal it.";checked:!!Hub.prefs.taskbarAutoHide;onToggled:Hub.set("taskbarAutoHide",!checked)}
            SettingToggle {visible:Hub.settingsSection==="taskbar";Layout.fillWidth:true;first:false;last:false;icon:"format_align_center";title:"Center apps";description:"System controls stay on the right.";checked:!!Hub.prefs.taskbarCenter;onToggled:Hub.set("taskbarCenter",!checked)}
            SettingToggle {visible:Hub.settingsSection==="taskbar";Layout.fillWidth:true;first:false;last:false;icon:"label";title:"Window labels";description:"Titles appear when there is room.";checked:!!Hub.prefs.taskbarLabels;onToggled:Hub.set("taskbarLabels",!checked)}
            SettingToggle {visible:Hub.settingsSection==="taskbar";Layout.fillWidth:true;first:false;last:true;icon:"calendar";title:"Date beside the clock";checked:Hub.prefs.taskbarClockDate!==false;onToggled:Hub.set("taskbarClockDate",!checked)}
            SectionLabel {visible:Hub.settingsSection==="taskbar";text:"Pinned apps · "+Hub.favoriteApps.length;Layout.topMargin:12}
            Repeater {
                model:Hub.settingsSection==="taskbar" ? Hub.favoriteApps : []
                Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth:true;Layout.preferredHeight:56
                    topLeftRadius:index===0 ? 24 : 6;topRightRadius:topLeftRadius
                    bottomLeftRadius:index===Hub.favoriteApps.length-1 ? 24 : 6;bottomRightRadius:bottomLeftRadius
                    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                    RowLayout {anchors.fill:parent;anchors.leftMargin:16;anchors.rightMargin:8;spacing:14
                        Image {id:pinIcon;Layout.preferredWidth:28;Layout.preferredHeight:28;sourceSize:Qt.size(56,56);asynchronous:true;source:Quickshell.iconPath(modelData.icon,true)}
                        MText {Layout.fillWidth:true;text:modelData.name;font.pixelSize:14;font.weight:Font.Medium}
                        MButton {icon:"keep_off";compact:true;implicitWidth:36;implicitHeight:36;tooltip:"Unpin "+modelData.name;onClicked:Hub.pin(modelData)}
                    }
                }
            }
            MText {visible:Hub.settingsSection==="taskbar"&&Hub.favoriteApps.length===0;Layout.fillWidth:true;Layout.leftMargin:6;text:"Right-click any app and choose Pin.";font.pixelSize:12;color:Theme.subtext}
            // Phone.
            SectionLabel {visible:Hub.settingsSection==="phone";text:"Navigation"}
            SegmentedButtons {visible:Hub.settingsSection==="phone";Layout.fillWidth:true;Layout.bottomMargin:12;current:!!Hub.prefs.phoneButtons
                options:[{value:false,label:"Gestures",icon:"swipe"},{value:true,label:"Three buttons",icon:"more_horiz"}]
                onPicked:value=>Hub.set("phoneButtons",value)
            }
            SectionLabel {visible:Hub.settingsSection==="phone";text:"App drawer columns"}
            SegmentedButtons {visible:Hub.settingsSection==="phone";Layout.fillWidth:true;Layout.bottomMargin:12;current:Hub.prefs.phoneRows||5
                options:[{value:4,label:"4"},{value:5,label:"5"},{value:6,label:"6"},{value:7,label:"7"}]
                onPicked:value=>Hub.set("phoneRows",value)
            }
            SectionLabel {visible:Hub.settingsSection==="phone"&&Quickshell.screens.length>1;text:"Phone layout display"}
            SegmentedButtons {visible:Hub.settingsSection==="phone"&&Quickshell.screens.length>1;Layout.fillWidth:true;Layout.bottomMargin:12;current:Hub.prefs.phoneDisplay||""
                options:Quickshell.screens.map(sc=>({value:sc.name,label:sc.name}))
                onPicked:value=>Hub.set("phoneDisplay",value)
            }
            SettingToggle {visible:Hub.settingsSection==="phone";Layout.fillWidth:true;icon:"keyboard";title:"On-screen keyboard";description:Hub.systemOskAvailable ? "Show the system keyboard now." : "Run the installer to build the Borealis keyboard.";checked:Hub.systemOskVisible;enabled:Hub.systemOskAvailable;opacity:enabled ? 1 : .5;onToggled:Hub.systemOsk("toggle")}
            // Notifications.
            SettingToggle {visible:Hub.settingsSection==="notifications";Layout.fillWidth:true;first:true;last:false;icon:"quiet";title:"Do not disturb";description:"Silence popups. Notifications stay in your inbox.";checked:Hub.dnd;onToggled:Hub.set("dnd",!checked)}
            Rectangle {
                visible:Hub.settingsSection==="notifications";Layout.fillWidth:true;Layout.preferredHeight:60
                topLeftRadius:6;topRightRadius:6;bottomLeftRadius:24;bottomRightRadius:24
                color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:16;spacing:16
                    Glyph {name:"inbox";font.pixelSize:22;color:Theme.subtext}
                    MText {Layout.fillWidth:true;text:"Notification inbox · "+Hub.inbox.length;font.pixelSize:15;font.weight:Font.Medium}
                    Glyph {name:"next";color:Theme.subtext}
                }
                MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:Hub.page="notifications"}
            }
            MButton {visible:Hub.settingsSection==="notifications"&&Hub.inbox.length>0;Layout.alignment:Qt.AlignRight;Layout.topMargin:10;text:"Clear all";icon:"clear_all";tonal:true;onClicked:Notifier.clear()}
            // Accessibility.
            SettingToggle {visible:Hub.settingsSection==="accessibility";Layout.fillWidth:true;first:true;last:false;icon:"animation";title:"Reduce motion";description:"Remove transitions and decorative animation.";checked:Theme.reduceMotion;onToggled:Hub.set("reduceMotion",!checked)}
            SettingToggle {visible:Hub.settingsSection==="accessibility";Layout.fillWidth:true;first:false;last:true;icon:"dark_mode";title:"Dark theme";checked:!Theme.light;onToggled:Hub.set("light",!Theme.light)}
            SectionLabel {visible:Hub.settingsSection==="accessibility";text:"Surface opacity · "+Math.round(Hub.prefs.glass*100)+"%";Layout.topMargin:12}
            ExpressiveSlider {visible:Hub.settingsSection==="accessibility";Layout.fillWidth:true;implicitHeight:58;compact:true;trackHeight:46;icon:"opacity";iconAtHandle:true;from:45;to:100;value:Hub.prefs.glass*100;onMoved:Hub.set("glass",Math.round(value)/100)}
            // About: live system figures from the status adapter.
            Rectangle {
                visible:Hub.settingsSection==="about";Layout.fillWidth:true;Layout.preferredHeight:120;Layout.bottomMargin:12;radius:28;color:Theme.primaryContainer
                RowLayout {anchors.fill:parent;anchors.margins:20;spacing:16
                    Flower {Layout.preferredWidth:72;Layout.preferredHeight:72;lobes:8;depth:.12;fill:Theme.onContainer
                        Glyph {anchors.centerIn:parent;name:"auto_awesome";font.pixelSize:30;color:Theme.primaryContainer}
                    }
                    ColumnLayout {Layout.fillWidth:true;spacing:2
                        MText {text:"Opal";font.pixelSize:28;font.weight:Font.Medium;color:Theme.onContainer}
                        MText {text:"Material 3 Expressive shell for Quickshell"+(Hub.status.uptime ? " · up "+Hub.status.uptime : "");font.pixelSize:12;color:Theme.alpha(Theme.onContainer,.8)}
                    }
                }
            }
            Repeater {
                model:Hub.settingsSection==="about" ? [{label:"Processor",value:Hub.status.cpu,icon:"speed"},{label:"Memory",value:Hub.status.memory,icon:"memory"}] : []
                Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth:true;Layout.preferredHeight:72
                    topLeftRadius:index===0 ? 24 : 6;topRightRadius:topLeftRadius;bottomLeftRadius:index===1 ? 24 : 6;bottomRightRadius:bottomLeftRadius
                    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                    RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:18;spacing:14
                        Glyph {name:modelData.icon;font.pixelSize:22;color:Theme.subtext}
                        ColumnLayout {Layout.fillWidth:true;spacing:6
                            RowLayout {Layout.fillWidth:true
                                MText {Layout.fillWidth:true;text:modelData.label;font.pixelSize:14;font.weight:Font.Medium}
                                MText {text:Math.round(modelData.value)+"%";font.pixelSize:14;font.weight:Font.Medium;color:Theme.primary}
                            }
                            Rectangle {Layout.fillWidth:true;Layout.preferredHeight:8;radius:4;color:Theme.alpha(Theme.primary,.18)
                                Rectangle {width:parent.width*Math.max(0,Math.min(100,modelData.value))/100;height:parent.height;radius:4;color:Theme.primary;Behavior on width {NumberAnimation {duration:Theme.motion(500);easing.type:Easing.OutCubic}}}
                            }
                        }
                    }
                }
            }
            SectionLabel {visible:Hub.settingsSection==="about";text:"Shell";Layout.topMargin:12}
            Repeater {
                model:Hub.settingsSection==="about" ? [
                    {label:"Layout",value:Hub.prefs.mode==="auto" ? "Flow (adaptive)" : Hub.prefs.mode},
                    {label:"Displays",value:Quickshell.screens.map(sc=>sc.name+" "+sc.width+"×"+sc.height).join(", ")||"None"},
                    {label:"Compositor",value:Hub.status.hypr ? "Hyprland" : "Wayland (generic)"},
                    {label:"Power profile",value:Hub.status.profile||"Unavailable"},
                    {label:"Colour",value:Hub.prefs.dynamicColors ? "Wallpaper colours · "+String(Hub.prefs.colorScheme||"").replace("scheme-","") : Theme.palette.name}
                ] : []
                Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth:true;Layout.preferredHeight:58
                    topLeftRadius:index===0 ? 24 : 6;topRightRadius:topLeftRadius;bottomLeftRadius:index===4 ? 24 : 6;bottomRightRadius:bottomLeftRadius
                    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                    RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:18
                        MText {text:modelData.label;font.pixelSize:14;font.weight:Font.Medium;Layout.preferredWidth:130}
                        MText {Layout.fillWidth:true;horizontalAlignment:Text.AlignRight;text:modelData.value;font.pixelSize:13;color:Theme.subtext}
                    }
                }
            }
            MText {Layout.fillWidth:true;Layout.topMargin:14;text:"Changes save automatically.";color:Theme.muted;font.pixelSize:12;horizontalAlignment:Text.AlignHCenter}
        }
    }}
    component LinkRow: Rectangle {
        id:link
        property string icon:""
        property string title:""
        property string detail:""
        property bool first:true
        property bool last:true
        signal activated()
        Layout.preferredHeight:detail ? 68 : 56
        topLeftRadius:first ? 24 : 6;topRightRadius:topLeftRadius;bottomLeftRadius:last ? 24 : 6;bottomRightRadius:bottomLeftRadius
        color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
        Rectangle {anchors.fill:parent;topLeftRadius:parent.topLeftRadius;topRightRadius:parent.topRightRadius;bottomLeftRadius:parent.bottomLeftRadius;bottomRightRadius:parent.bottomRightRadius;color:Theme.stateLayer;opacity:linkMouse.pressed ? .12 : linkMouse.containsMouse ? .06 : 0}
        RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:16;spacing:16
            Glyph {name:link.icon;font.pixelSize:22;color:Theme.subtext}
            ColumnLayout {Layout.fillWidth:true;spacing:2
                MText {Layout.fillWidth:true;text:link.title;font.pixelSize:15;font.weight:Font.Medium}
                MText {visible:link.detail!=="";Layout.fillWidth:true;text:link.detail;font.pixelSize:12;color:Theme.subtext}
            }
            Glyph {name:"next";color:Theme.subtext}
        }
        MouseArea {id:linkMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:link.activated()}
        Accessible.role:Accessible.Button;Accessible.name:title;Accessible.onPressAction:activated()
    }
    component SectionLabel: MText {font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6;Layout.bottomMargin:4}
}
