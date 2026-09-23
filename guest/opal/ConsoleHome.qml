import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:c
    property bool embedded:false
    property string category:"Games"
    property string query:""
    property bool searching:false
    property bool menuOpen:false
    property int menuIndex:0
    property int selection:0
    onQueryChanged:if(search.text!==query)search.text=query
    readonly property int columns:Math.max(2,Math.min(6,Math.floor((width-64)/260)))
    readonly property var tabs:["Continue","Games","Pinned","All apps"]
    readonly property var continueApps: {
        const running=Hub.windows.map(w=>Hub.appForWindow(w)).filter(a=>a&&(a.categories||[]).indexOf("Game")>=0);
        return running.concat(Hub.recentApps.filter(a=>(a.categories||[]).indexOf("Game")>=0)).filter((a,i,all)=>all.findIndex(other=>other.id===a.id)===i);
    }
    readonly property var library:query!=="" ? Hub.searchApps(query,"All apps") : category==="Continue" ? continueApps : Hub.searchApps("",category)
    readonly property var selected:library.length ? library[Math.min(selection,library.length-1)] : null
    readonly property var selectedWindows:selected ? Hub.windows.filter(w=>Hub.appForWindow(w)===selected) : []
    property int menuTab:0
    readonly property var menuTabs:["Library","Session","Sound","Setup"]
    readonly property bool nintendo:Hub.prefs.controllerLayout==="nintendo"
    readonly property string acceptButton:nintendo ? "B" : "A"
    readonly property string backButton:nintendo ? "A" : "B"
    readonly property string pinButton:nintendo ? "Y" : "X"
    readonly property string searchButton:nintendo ? "X" : "Y"
    readonly property var actions:menuTab===0 ? (selected ? Hub.appMenu(selected) : []).concat([
        {text:"Search installed games & apps",icon:"search",run:()=>c.searchToggle()},
        {text:"App switcher · "+Hub.windows.length+" windows",icon:"desktop",run:()=>Hub.page="windows"},
        {text:"Steam Big Picture",icon:"game",run:()=>Hub.settings("steam")}
    ]) : menuTab===1 ? [
        {text:Hub.gameSession ? "End play session · "+Hub.gameMinutes+" min" : "Start a quiet play session",icon:"game",run:()=>Hub.toggleGameSession(),stay:true},
        {text:"Screenshot",icon:"capture",run:()=>Hub.screenShot()},
        {text:(Hub.keepAwake ? "Allow idle" : "Keep awake")+(Hub.gameSession ? " · after session" : ""),icon:"coffee",run:()=>Hub.keepAwake=!Hub.keepAwake,stay:true},
        {text:(Hub.dnd ? "Allow notification popups" : "Quiet notification popups")+(Hub.gameSession ? " · after session" : ""),icon:"quiet",run:()=>Hub.set("dnd",!Hub.dnd),stay:true},
        {text:"Return to game / close library",icon:"back",run:()=>Hub.close()}
    ] : menuTab===2 ? [
        {text:"Volume down · "+Hub.status.volume+"%",icon:"volume",run:()=>Hub.volume(Math.max(0,Hub.status.volume-5)),stay:true},
        {text:"Volume up · "+Hub.status.volume+"%",icon:"volume",run:()=>Hub.volume(Math.min(100,Hub.status.volume+5)),stay:true},
        {text:Hub.status.muted ? "Unmute" : "Mute",icon:"mute",run:()=>Hub.command({action:"mute"}),stay:true},
        {text:Hub.status.playing ? "Pause music" : "Play music",icon:"music",run:()=>Hub.media("play-pause"),stay:true},
        {text:"Next track",icon:"skip",run:()=>Hub.media("next"),stay:true}
    ] : [
        {text:"Button layout · "+(nintendo ? "Nintendo" : "Xbox / standard"),icon:"game",run:()=>Hub.set("controllerLayout",nintendo ? "standard" : "nintendo"),stay:true},
        {text:Theme.light ? "Use dark appearance" : "Use light appearance",icon:"moon",run:()=>Hub.set("light",!Theme.light),stay:true},
        {text:"Quick Settings · touch / mouse",icon:"settings",run:()=>Hub.page="controls"},
        {text:"Switch to desktop layout",icon:"desktop",run:()=>Hub.mode("desktop")}
    ]
    function menuCategory(delta) {menuTab=(menuTab+delta+menuTabs.length)%menuTabs.length;menuIndex=0;actionList.positionViewAtBeginning();}
    function runAction(index) {const action=actions[index];if(!action)return;if(!action.stay)menuOpen=false;action.run();}
    function openMenu() {menuIndex=0;menuOpen=true;c.forceActiveFocus();}
    onLibraryChanged:selection=0
    function launch() {if(selectedWindows.length)Hub.focusWindow(selectedWindows[0]);else if(selected)Hub.launch(selected);}
    function changeTab(delta) {category=tabs[(tabs.indexOf(category)+delta+tabs.length)%tabs.length];query="";selection=0;}
    function searchToggle() {if(embedded){Hub.page="launcher";return;}searching=!searching;if(searching)c.forceActiveFocus();}
    function navigate(key) {
        if(menuOpen) {
            if(key==="back"||key==="menu")menuOpen=false;
            else if(key==="up") {menuIndex=Math.max(0,menuIndex-1);actionList.positionViewAtIndex(menuIndex,ListView.Contain);}
            else if(key==="down") {menuIndex=Math.min(actions.length-1,menuIndex+1);actionList.positionViewAtIndex(menuIndex,ListView.Contain);}
            else if(key==="left"||key==="previousTab")menuCategory(-1);
            else if(key==="right"||key==="nextTab")menuCategory(1);
            else if(key==="accept")runAction(menuIndex);
            return;
        }
        if(searching&&key!=="search") {keyboard.navigation(key);return;}
        if(key==="search") {searchToggle();return;}
        if(key==="menu") {openMenu();return;}
        if(key==="pin") {if(selected){Hub.pin(selected);Hub.message("Updated favorites");}return;}
        if(key==="back") {if(query){query="";return;}Hub.close();return;}
        if(key==="accept") {launch();return;}
        if(key==="previousTab") {changeTab(-1);return;}
        if(key==="nextTab") {changeTab(1);return;}
        const delta={left:-1,right:1,up:-columns,down:columns}[key];
        if(delta!==undefined) {selection=Math.max(0,Math.min(library.length-1,selection+delta));grid.positionViewAtIndex(selection,GridView.Contain);}
    }
    Connections {target:Hub;function onNavigate(key){if(!c.embedded&&Hub.page==="launcher"&&Hub.prefs.mode==="console")c.navigate(key);}}
    focus:!embedded
    Keys.onPressed:e=>{
        const map={}
map[Qt.Key_Left]="left";map[Qt.Key_Right]="right";map[Qt.Key_Up]="up";map[Qt.Key_Down]="down";map[Qt.Key_Return]="accept";map[Qt.Key_Enter]="accept";map[Qt.Key_Escape]="back";map[Qt.Key_Menu]="menu";
        if(map[e.key]){c.navigate(map[e.key]);e.accepted=true;}
        else if(e.key===Qt.Key_Tab){c.navigate(e.modifiers&Qt.ShiftModifier ? "previousTab" : "nextTab");e.accepted=true;}
        else if(e.key===Qt.Key_F2){c.navigate("pin");e.accepted=true;}
        else if(e.key===Qt.Key_F3){c.searchToggle();e.accepted=true;}
        else if(c.searching&&e.key===Qt.Key_Backspace){keyboard.eraseFromTarget();c.query=search.text;e.accepted=true;}
        else if(c.searching&&e.text&&!(e.modifiers&(Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier))){keyboard.insertIntoTarget(e.text);c.query=search.text;e.accepted=true;}
    }
    Component.onCompleted:if(!embedded)forceActiveFocus()
    ColumnLayout {
        anchors {fill:parent;margins:Math.min(width*.035,48)}
spacing:20
        RowLayout {
            visible:!c.searching
            Layout.fillWidth:true;spacing:14
            Flower {width:46;height:46;fill:Theme.primary;lobes:8;Glyph {anchors.centerIn:parent;name:"game";color:Theme.onPrimary;font.pixelSize:24}}
            MText {visible:c.width>1000;text:"PLAY";font.pixelSize:20;font.weight:Font.Bold;font.letterSpacing:4;Layout.rightMargin:20}
            MButton {text:"LB";compact:true;tonal:true;tooltip:"Previous category";onClicked:c.changeTab(-1)}
            HorizontalScroller {Layout.fillWidth:true;Layout.preferredHeight:48;contentWidth:categoryRow.width
                Row {id:categoryRow;spacing:8
                    Repeater {model:c.tabs
                        MButton {required property string modelData;text:modelData;filled:c.category===modelData;onClicked:{c.category=modelData;c.query="";}}
                    }
                }
            }
            MButton {text:"RB";compact:true;tonal:true;tooltip:"Next category";onClicked:c.changeTab(1)}
            MText {visible:c.width>900;text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:18;color:Theme.subtext}
            MButton {icon:"volume";tooltip:"Sound & music · scroll for volume";scrollable:true;onScrolled:steps=>Hub.audioScroll(steps,Hub.chooseScreen());onClicked:Hub.toggleAudio(Hub.chooseScreen())}
            MButton {icon:"desktop";tooltip:"App switcher";onClicked:Hub.page="windows"}
            MButton {icon:"settings";tooltip:"Play hub · Menu / Select";onClicked:c.openMenu()}
        }
        Rectangle {
            visible:!c.searching
            Layout.fillWidth:true;Layout.preferredHeight:Math.max(132,Math.min(168,c.height*.21));radius:30
            color:Theme.primaryContainer;clip:true
            Image {anchors {fill:parent;margins:12}
source:Hub.artFor(c.selected).hero||"";fillMode:Image.PreserveAspectCrop;opacity:.48;asynchronous:true}
            Rectangle {anchors {fill:parent;margins:12}
gradient:Gradient {orientation:Gradient.Horizontal;GradientStop {position:0;color:Theme.primaryContainer}GradientStop {position:1;color:Theme.alpha(Theme.primaryContainer,.15)}}}
            RowLayout {
                anchors {fill:parent;margins:c.height<700 ? 14 : 18}
spacing:16
                Rectangle {
                    Layout.preferredWidth:Math.min(96,parent.height-36);Layout.preferredHeight:width;radius:24;color:Theme.alpha(Theme.primary,.12)
                    Flower {anchors {fill:parent;margins:8}
fill:Theme.alpha(Theme.primary,.22);lobes:8;rotation:12}
                    Image {anchors.centerIn:parent;width:parent.width*.62;height:width;source:c.selected ? Quickshell.iconPath(c.selected.icon,true) : ""}
                    Glyph {visible:!c.selected;anchors.centerIn:parent;name:"game";font.pixelSize:60;color:Theme.primary}
                }
                ColumnLayout {
                    Layout.fillWidth:true;spacing:6
                    MText {text:c.selectedWindows.length ? "READY TO RESUME" : c.selected ? "READY TO LAUNCH" : "YOUR LOCAL LIBRARY";color:Theme.onContainer;font.pixelSize:11;font.letterSpacing:2}
                    MText {text:c.selected ? c.selected.name : c.category==="Continue" ? "Your next session starts here." : "Choose something to play.";Layout.fillWidth:true;font.pixelSize:Math.min(30,c.width/38);font.weight:Font.DemiBold;maximumLineCount:1;wrapMode:Text.Wrap;elide:Text.ElideRight;color:Theme.onContainer}
                    MText {visible:c.height>700;text:c.selected ? c.selected.comment||c.selected.genericName||"Installed on this device" : "Open Steam or choose All apps. No fake recommendations.";Layout.fillWidth:true;font.pixelSize:13;color:Theme.subtext}
                    RowLayout {spacing:10
                        MButton {visible:!!c.selected;text:c.acceptButton+(c.selectedWindows.length ? "  Resume" : "  Launch");icon:"play";filled:true;onClicked:c.launch()}
                        MButton {visible:!!c.selected;text:c.pinButton+(Hub.pinned(c.selected||{}) ? "  Unpin" : "  Pin");icon:"pin";tonal:true;onClicked:Hub.pin(c.selected)}
                        MButton {text:"Steam Big Picture";icon:"game";tonal:true;onClicked:Hub.settings("steam")}
                    }
                }
            }
        }
        HorizontalScroller {visible:!c.searching;Layout.fillWidth:true;Layout.preferredHeight:56;contentWidth:sessionRow.implicitWidth
            RowLayout {id:sessionRow;height:52;spacing:10
                MButton {text:Hub.gameSession ? "End session · "+Hub.gameMinutes+"m" : "Start play session";icon:"game";filled:Hub.gameSession;tonal:true;tooltip:"Quiet popups, prevent idle and hide shelf; saved preferences stay untouched";onClicked:Hub.toggleGameSession()}
                MButton {text:"CPU "+Hub.status.cpu+"% · RAM "+Hub.status.memory+"%";icon:"cpu";tonal:true;onClicked:Hub.page="controls"}
                MButton {visible:Hub.status.profile!=="";text:Hub.status.profile;icon:"battery";tonal:true;tooltip:"Switch power profile";onClicked:Hub.command({action:"profile",value:Hub.status.profile==="performance" ? "balanced" : "performance"})}
                ExpressiveSlider {Layout.preferredWidth:190;value:Hub.status.volume;icon:"volume";onMoved:Hub.volume(value)}
                MButton {icon:"capture";text:"Screenshot";tonal:true;onClicked:Hub.screenShot()}
            }
        }
        RowLayout {visible:c.searching;Layout.fillWidth:true
            MText {text:"Find your next session";font.pixelSize:30;font.weight:Font.DemiBold;Layout.fillWidth:true}
            MButton {icon:"close";tooltip:"Return to library";onClicked:{c.searching=false;c.forceActiveFocus();}}
        }
        TextField {
            id:search;visible:c.searching||c.query!==""
            Layout.fillWidth:true;Layout.preferredHeight:56;leftPadding:22;rightPadding:22
            onTextEdited:c.query=text
            color:Theme.text;placeholderTextColor:Theme.muted;font.family:Theme.font;font.pixelSize:19
            placeholderText:"Search your installed apps and games"
            background:Rectangle {radius:28;color:Theme.surfaceHigh}
            onAccepted:{c.searching=false;c.forceActiveFocus();}
            Keys.onEscapePressed:{c.searching=false;c.forceActiveFocus();}
        }
        GridView {
            id:grid
            visible:!c.searching
            Layout.fillWidth:true;Layout.fillHeight:true
            clip:true;model:c.library
            cellWidth:width/c.columns;cellHeight:Math.max(120,Math.min(220,height/Math.max(1,Math.round(height/200))))
            ScrollBar.vertical:ScrollBar {}
            boundsBehavior:Flickable.StopAtBounds;currentIndex:c.selection
            delegate:Item {
                required property var modelData;required property int index
                width:grid.cellWidth;height:grid.cellHeight
                GameTile {anchors {fill:parent;margins:7}
                    app:modelData;selected:c.selection===index
                    onActivated:{if(c.selection===index)c.launch();else c.selection=index;}
                }
            }
            MText {anchors.centerIn:parent;visible:c.library.length===0;text:c.query ? "Nothing matched. Try another search." : c.category==="Pinned" ? "Press "+c.pinButton+" / F2 on a title to add it here." : "No entries yet. Choose another category or open Steam.";color:Theme.subtext;font.pixelSize:20}
        }
        MText {visible:c.searching;text:c.library.length+" matches · Done to browse results";color:Theme.subtext;font.pixelSize:14}
        ColumnLayout {visible:c.searching;Layout.fillWidth:true;Layout.fillHeight:true;spacing:6
            Repeater {model:c.height>720 ? c.library.slice(0,3) : []
                MButton {required property var modelData;Layout.fillWidth:true;text:modelData.name;icon:"game";tonal:true;onClicked:{c.query=modelData.name;c.searching=false;c.forceActiveFocus();}}
            }
            Item {Layout.fillHeight:true}
        }
        SearchKeyboard {id:keyboard;visible:c.searching;Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,c.height*.40);controllerMode:true
            inputTarget:search;contextLabel:"Search library";returnLabel:"Done"
            onInsert:c.query=search.text
            onErase:c.query=search.text
            onAccept:{c.searching=false;c.forceActiveFocus();}
            onDismiss:{c.searching=false;c.forceActiveFocus();}
        }
        RowLayout {
            visible:!c.searching
            Layout.fillWidth:true;spacing:14
            Glyph {name:"game";color:Hub.controller ? Theme.secondary : Theme.muted}
            MText {text:Hub.controller ? (Hub.controllerName||"Controller connected") : "Keyboard ready";color:Theme.subtext;font.pixelSize:12;Layout.maximumWidth:280}
            Item {Layout.fillWidth:true}
            MButton {text:c.searchButton+"  Search";icon:"search";tonal:true;onClicked:c.searchToggle()}
            MButton {text:"Menu  Play hub";tonal:true;onClicked:c.openMenu()}
            MButton {visible:!c.embedded;text:c.backButton+"  Back";icon:"back";onClicked:c.navigate("back")}
        }
    }
    Rectangle {
        visible:c.menuOpen;anchors.fill:parent;color:Theme.alpha(Theme.base,.97)
        MouseArea {anchors.fill:parent;onClicked:c.menuOpen=false}
        ColumnLayout {
            anchors.centerIn:parent;width:Math.min(parent.width-64,600);height:Math.min(parent.height-48,c.actions.length*60+230);spacing:12
            RowLayout {Layout.fillWidth:true
                MText {text:"Play hub";font.pixelSize:30;font.weight:Font.DemiBold;Layout.fillWidth:true}
                MButton {icon:"close";tooltip:"Return to library";onClicked:c.menuOpen=false}
            }
            MText {text:Hub.gameSession ? "SESSION ACTIVE · "+Hub.gameMinutes+" min · quiet & awake until session ends" : "Your library, your session, your controls";color:Theme.subtext;font.pixelSize:13}
            RowLayout {Layout.fillWidth:true;spacing:6
                Repeater {model:c.menuTabs
                    MButton {required property string modelData;required property int index;Layout.fillWidth:true;text:modelData;compact:true;filled:c.menuTab===index;tonal:true;onClicked:{c.menuTab=index;c.menuIndex=0;}}
                }
            }
            ListView {id:actionList;model:c.actions;Layout.fillWidth:true;Layout.fillHeight:true;clip:true;spacing:8
                delegate:MButton {required property var modelData;required property int index;implicitWidth:ListView.view.width;implicitHeight:52;text:modelData.text;icon:modelData.icon;filled:index===c.menuIndex;tonal:index!==c.menuIndex;onClicked:c.runAction(index)}
            }
            MText {text:"LB / RB Sections · ↑ ↓ Choose · "+c.acceptButton+" Confirm · "+c.backButton+" Back";color:Theme.subtext;font.pixelSize:13;Layout.topMargin:14}
        }
    }
}
