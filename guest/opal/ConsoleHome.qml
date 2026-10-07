import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

// Console mode: a cover grid of every local game, plus the Play hub overlay. Controller first.
Item {
    id:c
    property bool embedded:false
    property string category:"Recent"
    property string query:""
    property bool searching:false
    property bool menuOpen:false
    property int menuIndex:0
    property int menuTab:0
    property int selection:0
    // Sort order for lists other than Recent: az, recent or source.
    property string sortMode:"az"
    property bool detailOpen:false
    readonly property var sortModes:[{id:"az",name:"A to Z"},{id:"recent",name:"Recently played"},{id:"source",name:"By source"}]
    onQueryChanged:if(search.text!==query)search.text=query
    readonly property bool nintendo:Hub.prefs.controllerLayout==="nintendo"
    readonly property string acceptButton:nintendo ? "B" : "A"
    readonly property string backButton:nintendo ? "A" : "B"
    readonly property string pinButton:nintendo ? "Y" : "X"
    readonly property string searchButton:nintendo ? "X" : "Y"

    // Library entries: games from the index, plus desktop games the index does not cover.
    function gameEntry(g) {return {kind:"game",id:g.id,title:g.title,cover:g.cover||"",hero:g.hero||"",icon:g.icon||"",source:g.source,lastPlayed:g.lastPlayed||0,data:g};}
    function appEntry(a,source) {const art=Hub.artFor(a);return {kind:"app",id:a.id,title:a.name,cover:art.cover||"",hero:art.hero||"",icon:a.icon||"",source:source||"App",lastPlayed:0,data:a};}
    readonly property var gameEntries:Hub.games.map(gameEntry)
    readonly property var desktopGames:{
        const titles=Hub.games.map(g=>g.title.toLowerCase());
        return Hub.searchApps("","Games").filter(a=>!/steam:\/\/|rungameid|steam_app_/.test((a.execString||"")+" "+a.id)&&titles.indexOf((a.name||"").toLowerCase())<0).map(a=>appEntry(a,"Desktop"));
    }
    readonly property var allGames:gameEntries.concat(desktopGames)
    readonly property var sources:allGames.map(e=>e.source).filter((s,i,all)=>all.indexOf(s)===i&&all.filter(x=>x===s).length>1).slice(0,4)
    readonly property var tabs:["Recent","All"].concat(allGames.some(e=>running(e)) ? ["Running"] : []).concat(["Pinned","Unplayed"]).concat(sources).concat(["Apps"])
    function running(entry) {return entry.kind==="game" ? Hub.gameRunning(entry.data) : Hub.windows.some(w=>Hub.appForWindow(w)===entry.data);}
    function windowsFor(entry) {return !entry ? [] : entry.kind==="game" ? Hub.gameWindows(entry.data) : Hub.windows.filter(w=>Hub.appForWindow(w)===entry.data);}
    function sorted(list) {
        const copy=list.slice();
        if(sortMode==="recent")copy.sort((a,b)=>(b.lastPlayed-a.lastPlayed)||a.title.localeCompare(b.title));
        else if(sortMode==="source")copy.sort((a,b)=>a.source.localeCompare(b.source)||a.title.localeCompare(b.title));
        else copy.sort((a,b)=>a.title.localeCompare(b.title));
        return copy;
    }
    readonly property bool sortApplies:query.trim()===""&&category!=="Recent"&&category!=="Apps"
    readonly property string sortName:sortModes.find(m=>m.id===sortMode).name
    function cycleSort(delta) {const i=sortModes.findIndex(m=>m.id===sortMode);sortMode=sortModes[(i+delta+sortModes.length)%sortModes.length].id;selection=0;grid.positionViewAtBeginning();}
    // Local playtime for the selected Steam game. The backend reads localconfig.vdf.
    readonly property var facts:selected&&GameState.detail.id===selected.id ? GameState.detail : ({})
    onSelectedChanged:{if(selected&&selected.kind==="game")detailLoad.restart();}
    Timer {id:detailLoad;interval:240;onTriggered:if(c.selected&&c.selected.kind==="game")GameState.loadDetail(c.selected.id)}
    function minutesText(m) {return m<60 ? m+" min" : Math.floor(m/60)+" h "+(m%60)+" min";}
    function ago(stamp) {
        if(!stamp)return "Never played";
        const days=Math.floor((Date.now()/1000-stamp)/86400);
        return days<1 ? "Played today" : days===1 ? "Played yesterday" : days<30 ? "Played "+days+" days ago" : "Played "+Qt.formatDate(new Date(stamp*1000),"d MMM yyyy");
    }
    readonly property string heroKicker:!selected ? "" : running(selected) ? "Running now" : category==="Recent"&&selection===0&&selected.lastPlayed>0&&query==="" ? "Continue playing" : selected.source
    readonly property var library:{
        const q=query.trim().toLowerCase();
        if(q!=="")return allGames.concat(Hub.searchApps(q,"All apps").map(a=>appEntry(a))).filter((e,i,all)=>e.title.toLowerCase().includes(q)&&all.findIndex(o=>o.title===e.title)===i);
        if(category==="Recent"){const live=allGames.filter(e=>running(e));return live.concat(allGames.filter(e=>e.lastPlayed>0&&live.indexOf(e)<0)).slice(0,24);}
        if(category==="All")return sorted(allGames);
        if(category==="Running")return sorted(allGames.filter(e=>running(e)));
        if(category==="Unplayed")return sorted(allGames.filter(e=>e.lastPlayed===0));
        if(category==="Pinned"){const pins=Hub.prefs.gamePins||[];return sorted(allGames.filter(e=>pins.indexOf(e.id)>=0));}
        if(category==="Apps")return Hub.searchApps("","All apps").map(a=>appEntry(a));
        return sorted(allGames.filter(e=>e.source===category));
    }
    readonly property var selected:library.length ? library[Math.min(selection,library.length-1)] : null
    readonly property int columns:Math.max(3,Math.min(8,Math.floor((width-96)/190)))
    onLibraryChanged:selection=Math.min(selection,Math.max(0,library.length-1))
    function launch() {
        if(!selected)return;
        const open=windowsFor(selected);
        if(open.length)Hub.focusWindow(open[0]);
        else if(selected.kind==="game")Hub.launchGame(selected.data);
        else Hub.launch(selected.data);
    }
    function pin() {if(!selected)return;if(selected.kind==="game")Hub.pinGame(selected.data);else Hub.pin(selected.data);}
    function pinned(entry) {return !!entry&&(entry.kind==="game" ? (Hub.prefs.gamePins||[]).indexOf(entry.id)>=0 : Hub.pinned(entry.data));}
    function changeTab(delta) {category=tabs[(tabs.indexOf(category)+delta+tabs.length)%tabs.length];query="";selection=0;grid.positionViewAtBeginning();}
    // Smooth scroll: the grid glides to keep the selected row in view.
    function revealSelection() {
        const row=Math.floor(selection/columns);
        const top=row*grid.cellHeight;
        let target=grid.contentY;
        if(top<grid.contentY)target=top-8;
        else if(top+grid.cellHeight>grid.contentY+grid.height)target=top+grid.cellHeight-grid.height+8;
        target=Math.max(0,Math.min(Math.max(0,grid.contentHeight-grid.height),target));
        if(Math.abs(target-grid.contentY)<1)return;
        gridScroll.stop();gridScroll.from=grid.contentY;gridScroll.to=target;
        if(Theme.reduceMotion)grid.contentY=target;else gridScroll.restart();
    }
    NumberAnimation {id:gridScroll;target:grid;property:"contentY";duration:Theme.motion(Theme.durMedium);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasized}
    function searchToggle() {if(embedded){Hub.page="launcher";return;}searching=!searching;if(searching)c.forceActiveFocus();}
    Component.onCompleted:{if(!embedded)forceActiveFocus();if(!Hub.games.length)Hub.command({action:"game-library"});if(!library.length&&category==="Recent")category="All";}

    // Play hub: sections of controller-friendly rows. Slider rows change with left and right.
    readonly property var menuTabs:[{name:"Now",icon:"sports_esports"},{name:"Sound",icon:"volume_up"},{name:"Performance",icon:"speed"},{name:"Quick",icon:"bolt"},{name:"Library",icon:"grid_view"},{name:"System",icon:"settings"}]
    readonly property var liveEntries:allGames.filter(e=>running(e))
    readonly property var actions:{
        if(menuTab===0){
            const rows=[];
            liveEntries.forEach(e=>{rows.push({text:"Return to "+e.title,icon:"play_arrow",run:()=>{const w=windowsFor(e)[0];if(w)Hub.focusWindow(w);Hub.close();}});rows.push({text:"Close "+e.title,icon:"close",run:()=>windowsFor(e).forEach(w=>Hub.closeWindow(w)),stay:true});});
            rows.push({text:Hub.gameSession ? "End play session" : "Start play session",detail:Hub.gameSession ? Hub.gameMinutes+" min · no popups, no sleep" : "No popups, no sleep",icon:"timer",on:Hub.gameSession,run:()=>Hub.toggleGameSession(),stay:true});
            rows.push({text:"Back to library",icon:"grid_view",run:()=>{}});
            return rows;
        }
        if(menuTab===1)return [
            {text:"Volume",detail:Hub.status.muted ? "Muted" : Hub.status.volume+"%",icon:Hub.status.muted ? "volume_off" : "volume_up",slider:Hub.status.muted ? 0 : Hub.status.volume,adjust:d=>Hub.volume(Math.max(0,Math.min(100,Hub.status.volume+d*5))),run:()=>Hub.command({action:"mute"}),stay:true},
            {text:Hub.status.muted ? "Unmute" : "Mute",icon:"volume_off",on:Hub.status.muted,run:()=>Hub.command({action:"mute"}),stay:true},
            {text:Hub.status.playing ? "Pause music" : "Play music",detail:Hub.status.track||"Nothing playing",icon:Hub.status.playing ? "pause" : "play_arrow",run:()=>Hub.media("play-pause"),stay:true},
            {text:"Next track",icon:"skip_next",run:()=>Hub.media("next"),stay:true}
        ];
        if(menuTab===2)return (GameState.perfReady ? [
            {text:"Frame limit",detail:GameState.perf.fpsLimit ? GameState.perf.fpsLimit+" FPS" : "Off",icon:"speed",adjust:d=>cycleFps(d),run:()=>cycleFps(1),stay:true},
            {text:"Performance overlay",detail:GameState.perf.overlay==="fps" ? "FPS only" : GameState.perf.overlay.charAt(0).toUpperCase()+GameState.perf.overlay.slice(1),icon:"monitoring",adjust:d=>cycleOverlay(d),run:()=>cycleOverlay(1),stay:true}
        ] : []).concat([
            {text:"Processor",detail:Hub.status.cpu+"%",icon:"speed",slider:Hub.status.cpu,info:true},
            {text:"Memory",detail:Hub.status.memory+"%",icon:"memory",slider:Hub.status.memory,info:true}
        ]).concat(Hub.status.profile ? [{id:"power-saver",name:"Power saver",icon:"eco"},{id:"balanced",name:"Balanced",icon:"balance"},{id:"performance",name:"Performance",icon:"rocket_launch"}].map(p=>({text:p.name,icon:p.icon,on:Hub.status.profile===p.id,run:()=>Hub.command({action:"profile",value:p.id}),stay:true})) : []);
        if(menuTab===4)return [
            {text:"Sort",detail:sortApplies ? sortName : "Applies to All, Pinned and source lists",icon:"sort",adjust:d=>{if(sortApplies)cycleSort(d);},run:()=>{if(sortApplies)cycleSort(1);},stay:true},
            {text:"Rescan library",detail:allGames.length+" games",icon:"refresh",run:()=>Hub.command({action:"game-library"}),stay:true},
            {text:"Game details",detail:"Playtime and uninstall",icon:"info",run:()=>{if(selected&&selected.kind==="game"){detailOpen=true;GameState.loadDetail(selected.id);}}}
        ];
        if(menuTab===3)return [
            {text:"Screenshot",icon:"screenshot_monitor",run:()=>Hub.screenShot()},
            {text:"Do not disturb",icon:"do_not_disturb_on",on:Hub.dnd,run:()=>Hub.set("dnd",!Hub.dnd),stay:true},
            {text:"Keep awake",icon:"coffee",on:Hub.keepAwake,run:()=>Hub.keepAwake=!Hub.keepAwake,stay:true},
            {text:"App switcher",detail:Hub.windows.length+" windows",icon:"select_window",run:()=>Hub.page="windows"}
        ];
        return [
            {text:"Button layout",detail:nintendo ? "Nintendo" : "Xbox",icon:"gamepad",run:()=>Hub.set("controllerLayout",nintendo ? "standard" : "nintendo"),stay:true},
            {text:"Dark theme",icon:"dark_mode",on:!Theme.light,run:()=>Hub.set("light",!Theme.light),stay:true},
            {text:"Steam Big Picture",icon:"sports_esports",run:()=>Hub.settings("steam")},
            {text:"Switch to desktop",icon:"desktop_windows",run:()=>Hub.mode("desktop")}
        ];
    }
    function cycleFps(delta) {const list=[0,30,40,45,60,72,90,120,144];const i=Math.max(0,list.indexOf(GameState.perf.fpsLimit||0));GameState.set("fpsLimit",list[(i+delta+list.length)%list.length]);}
    function cycleOverlay(delta) {const list=["off","fps","compact","full"];const i=Math.max(0,list.indexOf(GameState.perf.overlay||"compact"));GameState.set("overlay",list[(i+delta+list.length)%list.length]);}
    onTabsChanged:if(tabs.indexOf(category)<0)category="Recent"
    function menuCategory(delta) {menuTab=(menuTab+delta+menuTabs.length)%menuTabs.length;menuIndex=0;}
    function runAction(index) {const a=actions[index];if(!a||a.info)return;if(!a.stay)menuOpen=false;a.run();}
    function openMenu() {menuIndex=0;menuTab=0;menuOpen=true;GameState.refresh();c.forceActiveFocus();}
    function navigate(key) {
        if(detailOpen) {if(key==="back")detailOpen=false;return;}
        if(menuOpen) {
            const a=actions[menuIndex];
            if(key==="back"||key==="menu")menuOpen=false;
            else if(key==="up")menuIndex=Math.max(0,menuIndex-1);
            else if(key==="down")menuIndex=Math.min(actions.length-1,menuIndex+1);
            else if((key==="left"||key==="right")&&a&&a.adjust)a.adjust(key==="right" ? 1 : -1);
            else if(key==="left"||key==="previousTab")menuCategory(-1);
            else if(key==="right"||key==="nextTab")menuCategory(1);
            else if(key==="accept")runAction(menuIndex);
            return;
        }
        if(searching&&key!=="search") {keyboard.navigation(key);return;}
        if(key==="search") {searchToggle();return;}
        if(key==="menu") {openMenu();return;}
        if(key==="pin") {pin();return;}
        if(key==="pageUp") {if(selected&&selected.kind==="game"){detailOpen=true;GameState.loadDetail(selected.id);}return;}
        if(key==="pageDown") {if(sortApplies)cycleSort(1);return;}
        if(key==="back") {if(query){query="";return;}Hub.close();return;}
        if(key==="accept") {launch();return;}
        if(key==="previousTab") {changeTab(-1);return;}
        if(key==="nextTab") {changeTab(1);return;}
        const delta={left:-1,right:1,up:-columns,down:columns}[key];
        if(delta!==undefined) {selection=Math.max(0,Math.min(library.length-1,selection+delta));revealSelection();}
    }
    Connections {target:Hub;function onNavigate(key){if(!c.embedded&&Hub.page==="launcher"&&Hub.prefs.mode==="console")c.navigate(key);}}
    focus:!embedded
    Keys.onPressed:e=>{
        const map={};
        map[Qt.Key_Left]="left";map[Qt.Key_Right]="right";map[Qt.Key_Up]="up";map[Qt.Key_Down]="down";map[Qt.Key_Return]="accept";map[Qt.Key_Enter]="accept";map[Qt.Key_Escape]="back";map[Qt.Key_Menu]="menu";
        if(map[e.key]){c.navigate(map[e.key]);e.accepted=true;}
        else if(e.key===Qt.Key_Tab){c.navigate(e.modifiers&Qt.ShiftModifier ? "previousTab" : "nextTab");e.accepted=true;}
        else if(e.key===Qt.Key_F2){c.navigate("pin");e.accepted=true;}
        else if(e.key===Qt.Key_F3){c.searchToggle();e.accepted=true;}
        else if(c.searching&&e.key===Qt.Key_Backspace){keyboard.eraseFromTarget();c.query=search.text;e.accepted=true;}
        else if(c.searching&&e.text&&!(e.modifiers&(Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier))){keyboard.insertIntoTarget(e.text);c.query=search.text;e.accepted=true;}
    }

    // Backdrop: the selected game's hero art, dimmed.
    Rectangle {anchors.fill:parent;color:Theme.base}
    Image {
        id:hero
        anchors.fill:parent
        source:c.selected ? c.selected.hero||c.selected.cover||"" : ""
        fillMode:Image.PreserveAspectCrop;asynchronous:true;sourceSize:Qt.size(1280,720)
        opacity:status===Image.Ready ? .35 : 0
        Behavior on opacity {NumberAnimation {duration:Theme.motion(Theme.durLong)}}
    }
    Rectangle {
        anchors.fill:parent
        gradient:Gradient {
            GradientStop {position:0;color:Theme.alpha(Theme.base,.55)}
            GradientStop {position:.45;color:Theme.alpha(Theme.base,.85)}
            GradientStop {position:1;color:Theme.base}
        }
    }

    ColumnLayout {
        anchors {fill:parent;margins:Math.min(width*.035,48)}
        spacing:18
        // Top bar: title, tabs, status.
        RowLayout {
            visible:!c.searching
            Layout.fillWidth:true;spacing:10
            MText {text:"Play";role:"displayS";color:Theme.primary;Layout.rightMargin:12}
            MButton {text:"LB";compact:true;implicitWidth:44;ink:Theme.subtext;tooltip:"Previous tab";onClicked:c.changeTab(-1)}
            HorizontalScroller {Layout.fillWidth:true;Layout.preferredHeight:44;contentWidth:tabRow.width
                Row {id:tabRow;spacing:4
                    Repeater {model:c.tabs
                        Rectangle {
                            required property string modelData
                            readonly property bool current:c.category===modelData
                            width:tabText.implicitWidth+32;height:40;radius:20
                            color:current ? Theme.secondaryContainer : "transparent"
                            MText {id:tabText;anchors.centerIn:parent;text:modelData;role:"label";font.weight:parent.current ? Font.Bold : Font.Medium;color:parent.current ? Theme.onSecondaryContainer : Theme.subtext}
                            MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{c.category=modelData;c.query="";c.selection=0;}}
                        }
                    }
                }
            }
            MButton {text:"RB";compact:true;implicitWidth:44;ink:Theme.subtext;tooltip:"Next tab";onClicked:c.changeTab(1)}
            Rectangle {
                visible:c.sortApplies;Layout.leftMargin:4;Layout.preferredHeight:36;Layout.preferredWidth:sortRow.implicitWidth+26;radius:18;color:Theme.level(3)
                Row {id:sortRow;anchors.centerIn:parent;spacing:6
                    Glyph {name:"sort";font.pixelSize:18;color:Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
                    MText {text:c.sortName;role:"label";anchors.verticalCenter:parent.verticalCenter}
                    MText {text:"RT";role:"labelS";font.weight:Font.Bold;color:Theme.muted;anchors.verticalCenter:parent.verticalCenter}}
                MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:c.cycleSort(1)}
            }
            MButton {icon:"search";compact:true;ink:Theme.subtext;tooltip:"Search";onClicked:c.searchToggle()}
            MButton {icon:"menu";compact:true;ink:Theme.subtext;tooltip:"Play hub";onClicked:c.openMenu()}
            Row {spacing:12;Layout.leftMargin:12
                Glyph {visible:Hub.controller;name:"sports_esports";font.pixelSize:20;color:Theme.primary;anchors.verticalCenter:parent.verticalCenter}
                Glyph {visible:Hub.status.battery>=0;name:Hub.status.charging ? "charging" : "battery";font.pixelSize:20;color:Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
                MText {text:Qt.formatDateTime(Hub.now,"HH:mm");role:"title";font.features:{"tnum":1};anchors.verticalCenter:parent.verticalCenter}
            }
        }
        // Hero: the selected game. On Recent this starts as the last played game.
        Rectangle {
            id:banner
            visible:!c.searching&&!!c.selected
            Layout.fillWidth:true;Layout.preferredHeight:Math.max(150,Math.min(250,c.height*.27))
            readonly property int tint:c.selected ? Math.abs(c.selected.title.split("").reduce((h,ch)=>(h*31+ch.charCodeAt(0))|0,7))%3 : 0
            radius:Theme.shapeXl;color:bannerArt.ready ? Theme.level(3) : [Theme.primaryContainer,Theme.secondaryContainer,Theme.tertiaryContainer][tint]
            Behavior on color {ColorAnimation {duration:Theme.motion(Theme.durMedium)}}
            Flower {visible:!bannerArt.ready;x:parent.width-width*.72;y:-height*.2;width:parent.height*1.7;height:width;lobes:8;depth:.12;fill:Theme.alpha(Theme.text,.07)}
            RoundedImage {id:bannerArt;anchors.fill:parent;radius:banner.radius;source:c.selected ? c.selected.hero||"" : "";decodeSize:Qt.size(1280,420)}
            Rectangle {
                visible:bannerArt.ready
                anchors.fill:parent;radius:banner.radius
                gradient:Gradient {orientation:Gradient.Horizontal
                    GradientStop {position:0;color:Theme.alpha(Theme.base,.94)}
                    GradientStop {position:.55;color:Theme.alpha(Theme.base,.62)}
                    GradientStop {position:1;color:Theme.alpha(Theme.base,.12)}}
            }
            RowLayout {
                anchors {fill:parent;margins:22} spacing:20
                Rectangle {
                    visible:!!c.selected&&!c.selected.hero&&!!c.selected.cover
                    Layout.preferredHeight:parent.height;Layout.preferredWidth:height*.667;radius:Theme.shapeMd;color:Theme.primaryContainer
                    RoundedImage {anchors.fill:parent;radius:Theme.shapeMd;source:c.selected ? c.selected.cover||"" : "";decodeSize:Qt.size(300,450)}
                }
                ColumnLayout {Layout.fillWidth:true;Layout.fillHeight:true;spacing:4
                    MText {text:c.heroKicker.toUpperCase();role:"labelS";font.letterSpacing:1.5;font.weight:Font.Bold;color:Theme.primary}
                    MText {Layout.fillWidth:true;text:c.selected ? c.selected.title : "";role:"displayS";maximumLineCount:2;wrapMode:Text.Wrap}
                    Flow {Layout.fillWidth:true;spacing:8
                        Rectangle {height:26;width:sourceText.implicitWidth+20;radius:13;color:Theme.level(4)
                            MText {id:sourceText;anchors.centerIn:parent;text:c.selected ? c.selected.source : "";role:"labelS"}}
                        Rectangle {height:26;width:playedText.implicitWidth+20;radius:13;color:Theme.level(4);visible:!!c.selected
                            MText {id:playedText;anchors.centerIn:parent;text:c.selected ? c.ago(c.facts.lastPlayed||c.selected.lastPlayed) : "";role:"labelS"}}
                        Rectangle {height:26;width:timeText.implicitWidth+20;radius:13;color:Theme.secondaryContainer;visible:c.facts.playtimeMinutes!==undefined&&c.facts.playtimeMinutes!==null
                            MText {id:timeText;anchors.centerIn:parent;text:c.facts.playtimeMinutes!==undefined&&c.facts.playtimeMinutes!==null ? c.minutesText(c.facts.playtimeMinutes)+" played" : "";role:"labelS";color:Theme.onSecondaryContainer}}
                    }
                    Item {Layout.fillHeight:true}
                    RowLayout {spacing:10
                        MButton {text:c.acceptButton+"  "+(c.selected&&c.running(c.selected) ? "Resume" : "Play");icon:"play";filled:true;onClicked:c.launch()}
                        MButton {text:c.pinButton+"  "+(c.pinned(c.selected) ? "Unpin" : "Pin");icon:"pin";tonal:true;onClicked:c.pin()}
                        MButton {visible:!!c.selected&&c.selected.kind==="game";text:"LT  Details";icon:"info";tonal:true;onClicked:{c.detailOpen=true;GameState.loadDetail(c.selected.id);}}
                    }
                }
            }
        }
        RowLayout {visible:c.searching;Layout.fillWidth:true
            MText {text:"Search";role:"displayS";Layout.fillWidth:true}
            MButton {icon:"close";tooltip:"Back to library";onClicked:{c.searching=false;c.forceActiveFocus();}}
        }
        TextField {
            id:search;visible:c.searching||c.query!==""
            Layout.fillWidth:true;Layout.preferredHeight:56;leftPadding:22;rightPadding:22
            onTextEdited:c.query=text
            color:Theme.text;placeholderTextColor:Theme.muted;font.family:Theme.font;font.pixelSize:19
            placeholderText:"Search games and apps"
            background:Rectangle {radius:28;color:Theme.level(3)}
            onAccepted:{c.searching=false;c.forceActiveFocus();}
            Keys.onEscapePressed:{c.searching=false;c.forceActiveFocus();}
        }
        // Cover grid.
        GridView {
            id:grid
            visible:!c.searching
            Layout.fillWidth:true;Layout.fillHeight:true
            clip:true;model:c.library
            cellWidth:width/c.columns;cellHeight:cellWidth*1.5
            boundsBehavior:Flickable.StopAtBounds;currentIndex:c.selection;flickDeceleration:3000;maximumFlickVelocity:5000
            highlightFollowsCurrentItem:false
            // The grid can shrink or refill after the hero appears. Keep the selected row in view.
            onHeightChanged:Qt.callLater(()=>{if(c.selection<c.columns)grid.positionViewAtBeginning();else c.revealSelection();})
            onCountChanged:Qt.callLater(()=>{if(c.selection<c.columns)grid.positionViewAtBeginning();})
            ScrollBar.vertical:ScrollBar {}
            delegate:Item {
                required property var modelData;required property int index
                width:grid.cellWidth;height:grid.cellHeight
                GameCover {
                    anchors.fill:parent;anchors.margins:8
                    entry:modelData;selected:c.selection===index;running:c.running(modelData)
                    onActivated:{if(c.selection===index)c.launch();else c.selection=index;}
                }
            }
            Column {
                anchors.centerIn:parent;visible:c.library.length===0;spacing:10
                Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:c.category==="Pinned" ? "keep" : "sports_esports";font.pixelSize:44;color:Theme.muted}
                MText {anchors.horizontalCenter:parent.horizontalCenter;role:"title"
                    text:c.query ? "Nothing matches" : c.category==="Pinned" ? "Press "+c.pinButton+" on a game to pin it" : c.category==="Recent" ? "Nothing played yet" : "No games found"}
            }
        }
        SearchKeyboard {id:keyboard;visible:c.searching;Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,c.height*.40);controllerMode:true
            inputTarget:search;contextLabel:"Search library";returnLabel:"Done"
            onInsert:c.query=search.text
            onErase:c.query=search.text
            onAccept:{c.searching=false;c.forceActiveFocus();}
            onDismiss:{c.searching=false;c.forceActiveFocus();}
        }
        // Button hints.
        RowLayout {
            visible:!c.searching&&!c.detailOpen
            Layout.fillWidth:true;spacing:18
            MText {text:c.library.length+" "+(c.category==="Apps" ? "apps" : "titles");role:"label";color:Theme.subtext}
            Item {Layout.fillWidth:true}
            ControllerHints {
                items:{
                    const list=[{b:c.acceptButton,t:"Play"},{b:c.pinButton,t:"Pin"},{b:c.searchButton,t:"Search"},{b:"LB RB",t:"Tabs"}];
                    if(c.selected&&c.selected.kind==="game")list.push({b:"LT",t:"Details"});
                    if(c.sortApplies)list.push({b:"RT",t:"Sort"});
                    list.push({b:"☰",t:"Play hub"});
                    if(!c.embedded)list.push({b:c.backButton,t:"Back"});
                    return list;
                }
            }
        }
    }

    GameDetail {
        anchors.fill:parent
        entry:c.selected&&c.selected.kind==="game" ? c.selected : null
        open:c.detailOpen&&!!c.selected&&c.selected.kind==="game"
        running:!!c.selected&&c.running(c.selected)
        pinned:c.pinned(c.selected)
        onDismissed:c.detailOpen=false
        onPlay:{c.detailOpen=false;c.launch();}
        onPin:c.pin()
        onQuit:{c.windowsFor(c.selected).forEach(w=>Hub.closeWindow(w));c.detailOpen=false;}
        onUninstall:{Hub.command({action:"game-uninstall",id:c.selected.id});c.detailOpen=false;}
    }

    // Play hub: a side sheet with a section rail.
    Rectangle {
        anchors.fill:parent;color:Theme.alpha("#000000",.45)
        opacity:c.menuOpen ? 1 : 0;visible:opacity>0
        Behavior on opacity {NumberAnimation {duration:Theme.motion(Theme.durShort)}}
        MouseArea {anchors.fill:parent;onClicked:c.menuOpen=false}
    }
    Rectangle {
        id:hub
        width:Math.min(560,c.width*.9);height:c.height
        x:c.menuOpen ? c.width-width : c.width
        visible:x<c.width
        color:Theme.level(2)
        topLeftRadius:Theme.shapeXl;bottomLeftRadius:Theme.shapeXl
        Behavior on x {NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}}
        MouseArea {anchors.fill:parent}
        RowLayout {
            anchors.fill:parent;anchors.margins:24;spacing:16
            // Section rail.
            ColumnLayout {
                Layout.fillHeight:true;Layout.preferredWidth:76;spacing:8
                Repeater {model:c.menuTabs
                    Item {
                        required property var modelData;required property int index
                        readonly property bool current:c.menuTab===index
                        Layout.fillWidth:true;Layout.preferredHeight:60
                        Rectangle {anchors.horizontalCenter:parent.horizontalCenter;y:2;width:56;height:32;radius:16;color:parent.current ? Theme.secondaryContainer : "transparent"
                            Glyph {anchors.centerIn:parent;name:parent.parent.modelData.icon;font.pixelSize:22;color:parent.parent.current ? Theme.onSecondaryContainer : Theme.subtext}}
                        MText {anchors.horizontalCenter:parent.horizontalCenter;y:38;text:parent.modelData.name;role:"labelS";font.weight:parent.current ? Font.Bold : Font.Medium;color:parent.current ? Theme.text : Theme.subtext}
                        MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{c.menuTab=parent.index;c.menuIndex=0;}}
                    }
                }
                Item {Layout.fillHeight:true}
            }
            ColumnLayout {
                Layout.fillWidth:true;Layout.fillHeight:true;spacing:8
                MText {text:c.menuTabs[c.menuTab].name;role:"headline"}
                MText {visible:c.menuTab===0&&c.liveEntries.length===0;text:"No game is running.";role:"bodyS";color:Theme.subtext;Layout.bottomMargin:4}
                ListView {
                    id:actionList
                    Layout.fillWidth:true;Layout.fillHeight:true;clip:true;spacing:4
                    model:c.actions;currentIndex:c.menuIndex
                    onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                    delegate:Rectangle {
                        id:row
                        required property var modelData;required property int index
                        readonly property bool current:index===c.menuIndex
                        width:ListView.view.width;height:modelData.slider!==undefined ? 76 : 60
                        radius:Theme.shapeLg
                        color:current ? Theme.primaryContainer : Theme.level(3)
                        RowLayout {
                            anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:18;spacing:14
                            Glyph {name:row.modelData.icon;font.pixelSize:22;color:row.current ? Theme.onContainer : Theme.primary}
                            ColumnLayout {Layout.fillWidth:true;spacing:4
                                RowLayout {Layout.fillWidth:true
                                    MText {text:row.modelData.text;role:"titleS";color:row.current ? Theme.onContainer : Theme.text;Layout.fillWidth:true}
                                    MText {visible:!!row.modelData.detail&&row.modelData.slider!==undefined;text:row.modelData.detail||"";role:"label";color:row.current ? Theme.onContainer : Theme.subtext}
                                }
                                MText {visible:!!row.modelData.detail&&row.modelData.slider===undefined;text:row.modelData.detail||"";role:"labelS";color:row.current ? Theme.alpha(Theme.onContainer,.8) : Theme.subtext;Layout.fillWidth:true}
                                Rectangle {
                                    visible:row.modelData.slider!==undefined;Layout.fillWidth:true;height:6;radius:3
                                    color:Theme.alpha(row.current ? Theme.onContainer : Theme.primary,.2)
                                    Rectangle {width:parent.width*Math.max(0,Math.min(100,row.modelData.slider||0))/100;height:6;radius:3;color:row.current ? Theme.onContainer : Theme.primary}
                                }
                            }
                            MSwitch {visible:row.modelData.on!==undefined;checked:!!row.modelData.on;onToggled:c.runAction(row.index)}
                        }
                        MouseArea {anchors.fill:parent;z:-1;cursorShape:row.modelData.info ? Qt.ArrowCursor : Qt.PointingHandCursor;onClicked:{c.menuIndex=row.index;c.runAction(row.index);}}
                    }
                }
                MText {text:"LB / RB section · ↑ ↓ choose · ← → adjust · "+c.acceptButton+" select · "+c.backButton+" close";role:"labelS";color:Theme.subtext;wrapMode:Text.Wrap;Layout.fillWidth:true}
            }
        }
    }
}
