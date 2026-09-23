import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:l
    property bool phone:width<650
    property bool consoleMode:Hub.prefs.mode==="console"
    property bool keyboardOpen:false
    property string section:Hub.launcherSection
    property bool special:Hub.query.startsWith("=") || Hub.query.startsWith("?") || Hub.query.startsWith(">")
    property var results:special ? [] : Hub.searchApps(Hub.query,Hub.query!=="" ? "All apps" : Hub.category)
    property int columns:Math.max(2,Math.floor(grid.width/(consoleMode ? 190 : 136)))
    property var commands:[{name:"Take a screenshot",icon:"capture",action:"screenshot"},{name:"Lock device",icon:"lock",action:"lock"},{name:"Quick settings",icon:"settings",action:"controls"},{name:"Start a focus session",icon:"timer",action:"focus"},{name:"Phone mode",icon:"phone",action:"phone"},{name:"Console mode",icon:"game",action:"console"},{name:"Desktop mode",icon:"desktop",action:"desktop"}]
    readonly property var categories:["All apps","Pinned","Games","Create","Work","Internet","System"]
    readonly property var railSections:[{id:"apps",icon:"apps",label:"Apps"},{id:"widgets",icon:"grid",label:"At a glance"},{id:"windows",icon:"desktop",label:"Open"},{id:"style",icon:"palette",label:"Style"}]
    readonly property var phoneSections:[{id:"apps",icon:"apps"},{id:"widgets",icon:"grid"},{id:"windows",icon:"desktop"},{id:"style",icon:"palette"}]
    readonly property string commandQuery:Hub.query.slice(1).trim().toLowerCase()
    property var filteredCommands:commands.filter(c=>c.name.toLowerCase().indexOf(commandQuery)>=0)
    onSectionChanged:if(section!=="apps")keyboardOpen=false
    function invokeCommand(c) {
        if(c.action==="screenshot")Hub.screenShot();
        else if(c.action==="lock")Hub.settings("lock");
        else if(c.action==="controls")Hub.page="controls";
        else if(c.action==="focus") {Hub.focusSeconds=25*60;Hub.focusRunning=true;Hub.message("25 minutes. One thing at a time.");Hub.close();}
        else Hub.mode(c.action);
    }
    function accept() {
        if(Hub.query.startsWith("=")) { if(Hub.calculation!=="") {Hub.command({action:"clipboard",text:Hub.calculation});Hub.message("Result copied");} }
        else if(Hub.query.startsWith("?")) {Hub.command({action:"web",text:Hub.query.slice(1)});Hub.close();}
        else if(Hub.query.startsWith(">")) {if(filteredCommands.length)invokeCommand(filteredCommands[0]);}
        else if(results.length)Hub.launch(results[Math.max(0,grid.currentIndex)]);
    }
    function navigation(key) {
        if(key==="back") {if(Hub.query!=="")Hub.query="";else Hub.close();return;}
        if(key==="accept") {accept();return;}
        if(key==="nextTab" || key==="previousTab") {
            Hub.category=categories[(categories.indexOf(Hub.category)+(key==="nextTab" ? 1 : categories.length-1))%categories.length];return;
        }
        const diff=key==="left" ? -1 : key==="right" ? 1 : key==="up" ? -columns : key==="down" ? columns : undefined;
        if(diff!==undefined) {
            const next=Math.max(0,Math.min(results.length-1,grid.currentIndex+diff));
            if(next!==grid.currentIndex) {grid.currentIndex=next;grid.positionViewAtIndex(next,GridView.Contain);grid.forceActiveFocus();}
        }
    }
    Connections {
        target:Hub
        function onNavigate(key) {if(Hub.page==="launcher")l.navigation(key);}
        function onQueryChanged() {if(search.text!==Hub.query)search.text=Hub.query;}
    }
    onResultsChanged:grid.currentIndex=0
    Component.onCompleted:if(section==="apps"){if(!consoleMode)search.forceActiveFocus();else grid.forceActiveFocus();}
    RowLayout {
        anchors.fill:parent; spacing:0
        Rectangle {
            visible:!l.phone
            Layout.fillHeight:true; Layout.preferredWidth:96
            color:Theme.alpha(Theme.surface,0.35); radius:30
            Column { anchors {top:parent.top; left:parent.left; right:parent.right; margins:10}
spacing:18
                Flower {width:36;height:36;anchors.horizontalCenter:parent.horizontalCenter;fill:Theme.primary;lobes:8
                    Glyph {anchors.centerIn:parent;name:"spark";color:Theme.onPrimary}
                }
                Repeater {model:l.railSections
                    Column {required property var modelData;width:76;spacing:6
                        MButton {anchors.horizontalCenter:parent.horizontalCenter;implicitWidth:64;implicitHeight:48;icon:modelData.icon;tonal:l.section===modelData.id;tooltip:modelData.label;onClicked:Hub.launcherSection=modelData.id}
                        MText {width:parent.width;text:modelData.label;font.pixelSize:10;horizontalAlignment:Text.AlignHCenter;color:l.section===modelData.id ? Theme.primary : Theme.subtext}
                    }
                }
            }
            MButton {anchors {bottom:parent.bottom; horizontalCenter:parent.horizontalCenter; bottomMargin:16}
icon:"settings";tooltip:"Quick settings";onClicked:Hub.page="controls"}
        }
        ColumnLayout {
            Layout.fillWidth:true;Layout.fillHeight:true;Layout.margins:l.phone ? 16 : 24;spacing:14
            RowLayout {Layout.fillWidth:true
                ColumnLayout {spacing:3;Layout.fillWidth:true
                    MText {text:l.consoleMode ? "Game library" : l.section==="apps" ? "Applications" : l.section==="windows" ? "Running windows" : l.section==="widgets" ? "At a glance" : "Personalize";font.pixelSize:l.consoleMode ? 28 : 24;font.weight:Font.DemiBold;Layout.fillWidth:true}
                }
                MButton {icon:"palette";compact:true;tooltip:"Layout & appearance";onClicked:Hub.launcherSection="style";visible:!l.phone}
                MButton {icon:"close";tooltip:"Close · Escape";onClicked:Hub.close()}
            }
            RowLayout {visible:l.phone;Layout.fillWidth:true;spacing:4
                Repeater {model:l.phoneSections
                    MButton {required property var modelData;Layout.fillWidth:true;icon:modelData.icon;tonal:l.section===modelData.id;onClicked:Hub.launcherSection=modelData.id}
                }
            }
            // Pixel-like search field: commands, safe arithmetic, apps and explicit web search.
            Rectangle {
                visible:l.section==="apps";Layout.fillWidth:true;Layout.preferredHeight:l.consoleMode ? 58 : 50;radius:30;color:Theme.alpha(Theme.surfaceHigh,.86)
                Glyph {x:20;anchors.verticalCenter:parent.verticalCenter;name:"search";color:Theme.subtext}
                TextField {
                    id:search;anchors {fill:parent;leftMargin:54;rightMargin:52}
                    background:Item {}
color:Theme.text;placeholderTextColor:Theme.muted
                    placeholderText:l.consoleMode ? "Find your next game" : l.phone ? "Search apps & more" : "Search apps   ·   = calculate   ·   > actions   ·   ? web"
                    font.family:Theme.font;font.pixelSize:15;selectByMouse:true
                    text:Hub.query
                    onTextEdited: {Hub.query=text;if(text.startsWith("="))Hub.command({action:"calculate",text:text.slice(1).trim()});}
                    onAccepted:l.accept()
                    Keys.onDownPressed:l.navigation("down")
                    Keys.onEscapePressed:Hub.close()
                    TapHandler {onTapped:if(l.phone)l.keyboardOpen=true}
                }
                MButton {anchors {right:parent.right;verticalCenter:parent.verticalCenter;rightMargin:8}
icon:Hub.query!=="" ? "close" : "spark";compact:true;tooltip:Hub.query!=="" ? "Clear search" : "Search actions";onClicked:{Hub.query=Hub.query!=="" ? "" : ">";search.forceActiveFocus();}}
            }
            MButton {visible:l.consoleMode&&l.section==="apps"&&Hub.query==="";text:"Open Steam Big Picture";icon:"game";tonal:true;Layout.fillWidth:true;onClicked:Hub.settings("steam")}
            Flickable {
                visible:l.section==="apps"&&!l.special;Layout.fillWidth:true;Layout.preferredHeight:42;contentWidth:filters.width;clip:true;flickableDirection:Flickable.HorizontalFlick
                Row {id:filters;spacing:6
                    Repeater {model:l.categories
                        Chip {required property string modelData;text:modelData;selected:Hub.category===modelData;glass:!selected;implicitHeight:34;icon:({"All apps":"apps","Pinned":"keep","Games":"game","Create":"brush","Work":"work","Internet":"web","System":"settings"})[modelData]||"";onClicked:Hub.category=modelData}
                    }
                }
            }
            // Recent apps are persisted, and can be pinned with right click / long press.
            ColumnLayout {
                visible:l.section==="apps" && Hub.query==="" && !l.consoleMode && !l.phone && Hub.recentApps.length>0 && l.height>720
                Layout.fillWidth:true;spacing:10
                MText {text:"Pick up where you left off";font.weight:Font.DemiBold;font.pixelSize:13;color:Theme.subtext}
                RowLayout {Layout.fillWidth:true;spacing:8
                    Repeater {model:Hub.recentApps
                        AppTile {required property var modelData;required property int index;app:modelData;tintIndex:index;Layout.fillWidth:true;Layout.preferredHeight:112;showPin:false;onActivated:Hub.launch(app)}
                    }
                }
            }
            Item {
                visible:l.section==="apps";Layout.fillWidth:true;Layout.fillHeight:true
                GridView {
                    id:grid;anchors.fill:parent;visible:!l.special;clip:true;model:l.results
                    cellWidth:width/l.columns;cellHeight:l.consoleMode ? 190 : l.phone ? height/Math.max(1,Math.floor(height/132)) : 120
                    currentIndex:0;keyNavigationEnabled:false;boundsBehavior:Flickable.StopAtBounds
                    ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
                    Keys.onPressed:e => {
                        const names={}
names[Qt.Key_Left]="left";names[Qt.Key_Right]="right";names[Qt.Key_Up]="up";names[Qt.Key_Down]="down";names[Qt.Key_Return]="accept";names[Qt.Key_Enter]="accept";names[Qt.Key_Escape]="back";
                        if(names[e.key]) {l.navigation(names[e.key]);e.accepted=true;}
                        else if(e.key===Qt.Key_Tab) {l.navigation("nextTab");e.accepted=true;}
                        else if(e.text && !l.consoleMode) {search.forceActiveFocus();Hub.query+=e.text;e.accepted=true;}
                    }
                    delegate:Item {
                        required property var modelData;required property int index
                        width:grid.cellWidth;height:grid.cellHeight
                        AppTile {anchors {fill:parent;margins:5}
bare:true;app:modelData;tintIndex:index;large:l.consoleMode;selected:grid.activeFocus&&grid.currentIndex===index;onActivated:Hub.launch(app)}
                    }
                    MText {anchors.centerIn:parent;visible:l.results.length===0;text:Hub.category==="Games" ? "No desktop game entries yet.\nOpen Steam above, or choose All apps." : "Nothing here yet.\nTry another search, or pin an app with right-click.";horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;width:parent.width-30;color:Theme.subtext;font.pixelSize:16}
                }
                ColumnLayout {anchors {fill:parent;margins:8}
visible:l.special;spacing:14
                    Rectangle {visible:!Hub.query.startsWith(">");Layout.fillWidth:true;Layout.preferredHeight:170;radius:28;color:Theme.primaryContainer
                        Column {anchors {fill:parent;margins:24}
spacing:12
                            MText {text:Hub.query.startsWith("=") ? "CALCULATOR" : "GOOGLE SEARCH";color:Theme.onContainer;font.pixelSize:11;font.letterSpacing:2}
                            MText {width:parent.width;text:Hub.query.startsWith("=") ? (Hub.calculation||"Type an expression…") : Hub.query.slice(1).trim();font.pixelSize:34;color:Theme.onContainer}
                            MText {text:Hub.query.startsWith("=") ? "Enter to copy result · + − * / % ** ( )" : "Enter to search in your browser";color:Theme.onContainer;font.pixelSize:12}
                        }
                        MouseArea {anchors.fill:parent;onClicked:l.accept()}
                    }
                    Repeater {model:l.special && Hub.query.startsWith(">") ? l.filteredCommands : []
                        MButton {required property var modelData;Layout.fillWidth:true;text:modelData.name;icon:modelData.icon;tonal:true;onClicked:l.invokeCommand(modelData)}
                    }
                    Item {Layout.fillHeight:true}
                }
            }
            Dashboard {visible:l.section==="widgets";Layout.fillWidth:true;Layout.fillHeight:true;compact:l.phone}
            Appearance {visible:l.section==="style";Layout.fillWidth:true;Layout.fillHeight:true;compact:l.phone}
            WindowSwitcher {visible:l.section==="windows";Layout.fillWidth:true;Layout.fillHeight:true;layoutMode:"desktop";active:visible}
            SearchKeyboard {
                visible:l.phone&&l.section==="apps"&&l.keyboardOpen&&!Hub.systemOskReady
                Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,l.height*.38)
                inputTarget:search;contextLabel:"Search apps & more";returnLabel:"Search"
                onInsert:{Hub.query=search.text;if(Hub.query.startsWith("="))Hub.command({action:"calculate",text:Hub.query.slice(1).trim()});}
                onErase:{Hub.query=search.text;if(Hub.query.startsWith("="))Hub.command({action:"calculate",text:Hub.query.slice(1).trim()});}
                onAccept:l.accept()
                onDismiss:{l.keyboardOpen=false;grid.forceActiveFocus();}
            }
            RowLayout {Layout.fillWidth:true;visible:l.section==="apps"
                MText {text:l.consoleMode ? (Hub.controller ? "Controller connected  ·  " : "Keyboard ready  ·  ")+"← ↑ ↓ → Navigate    A / Enter Play    B / Esc Back" : l.phone ? "Long-press for actions" : l.results.length+" apps  ·  Right-click for actions  ·  ↑↓←→ navigate  ·  Enter opens";color:Theme.muted;font.pixelSize:l.consoleMode ? 13 : 10;Layout.fillWidth:true}
                MButton {visible:!l.phone;icon:"expand";compact:true;text:"Convergence";tooltip:"Adapt your workspace";onClicked:Hub.page="convergence"}
            }
            Rectangle {visible:l.phone;Layout.alignment:Qt.AlignHCenter;width:100;height:5;radius:3;color:Theme.subtext
                MouseArea {anchors {fill:parent;margins:-12}
onClicked:Hub.close()}
            }
        }
    }
}
