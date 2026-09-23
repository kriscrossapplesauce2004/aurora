pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: h
    property var prefs: ({mode:"desktop", palette:0, light:false, glass:0.78, favorites:[], recent:[], wallpaper:0, wallpaperPath:"", wallpaperFit:"crop", wallpaperDim:.15, desktopWidgets:true, dynamicColors:false, dynamicPalette:{}, colorScheme:"scheme-tonal-spot"})
    property var status: ({workspace:1, workspaces:[], windows:[], title:"Your desktop", volume:0, muted:false, network:"Connecting…", wifi:false, bluetooth:false, track:"", artist:"", art:"", playing:false, battery:-1, batteries:[], charging:false, brightness:-1, cpu:0, memory:0, uptime:"", profile:"", governor:"", hypr:false})
    property var connectivity: ({wifi:{items:[],busy:false,error:"",powered:false},bluetooth:{items:[],busy:false,error:"",powered:false}})
    property string controlDetail: ""
    property string settingsSection: ""
    function openSettings(section) { settingsSection=section||"";page="settings"; }
    property bool taskbarContextOpen:false
    property var taskbarContextScreen:null
    property real taskbarContextX:0
    property real taskbarContextY:0
    property bool taskbarContextCentered:false
    property var taskbarContextEntries:[]
    property int taskbarContextRequest:0
    property string taskbarContextTitle:"Taskbar"
    property string taskbarContextIcon:"desktop"
    function openTaskbarContext(screen, x, y, entries, centered, title, icon) {
        taskbarContextScreen=screen||chooseScreen();
        taskbarContextX=x;
        taskbarContextY=y;
        taskbarContextCentered=!!centered;
        taskbarContextEntries=(entries||taskbarMenu()).slice();
        taskbarContextTitle=title||"Taskbar";
        taskbarContextIcon=icon||"desktop";
        taskbarContextOpen=true;
        taskbarContextRequest++;
    }
    function closeTaskbarContext() {taskbarContextOpen=false;}
    property bool powerProfileOpen:false
    property var powerProfileScreen:null
    property real powerProfileX:0
    property real powerProfileY:0
    function openPowerProfile(screen,x,y) {
        powerProfileScreen=screen||chooseScreen();
        powerProfileX=x;
        powerProfileY=y;
        powerProfileOpen=true;
    }
    function closePowerProfile() {powerProfileOpen=false;}
    function togglePowerProfile(screen,x,y) {
        if(powerProfileOpen&&powerProfileScreen===screen)closePowerProfile();
        else openPowerProfile(screen,x,y);
    }
    function connection(kind,verb,extra) { command(Object.assign({action:"connectivity",kind:kind,verb:verb},extra||{})); }
    property bool audioOpen:false
    property var audioScreen:null
    onAudioScreenChanged:if(!audioScreen)audioOpen=false
    function openAudio(screen) {audioScreen=screen||chooseScreen();controlDetail="";page="";audioOpen=true;}
    function closeAudio() {audioOpen=false;}
    function toggleAudio(screen) {if(audioOpen)closeAudio();else openAudio(screen);}
    // Wheel input changes the volume but does not open the drawer.
    function audioScroll(steps,screen) {osdScreen=screen||chooseScreen();volume(Math.max(0,Math.min(100,status.volume+steps*2)));}
    property string page: ""
    onPageChanged:if(page!=="") {closeAudio();closePowerProfile();}
    property string category: "All apps"
    property string query: ""
    property string calculation: ""
    readonly property bool dnd: Notifier.dnd
    property bool keepAwake: false
    property bool themeBusy: false
    property var wallpaperLibrary: []
    property var wallpaperFolders: []
    property string wallpaperFolder:""
    property string wallpaperParent:""
    function browseWallpaperFolder(folder) {
        wallpaperRequest++;wallpaperLibraryBusy=true;wallpaperLibraryError="";
        command({action:"wallpaper-list",folder:folder||"",browse:true,request:wallpaperRequest});
    }
    property bool wallpaperLibraryBusy: false
    property string wallpaperLibraryError: ""
    property int wallpaperRequest: 0
    function browseWallpapers(folder) {
        wallpaperRequest++;wallpaperLibraryBusy=true;wallpaperLibraryError="";
        command({action:"wallpaper-list",folder:folder||"",request:wallpaperRequest});
    }
    property bool gameSession: false
    property date gameStarted: new Date()
    readonly property int gameMinutes: gameSession ? Math.max(0,Math.floor((now-gameStarted)/60000)) : 0
    function toggleGameSession() {
        if(!gameSession)gameStarted=new Date();
        gameSession=!gameSession;
        message(gameSession ? "Play session on · popups quiet, idle inhibited, shelf hidden" : "Play session ended · your settings are unchanged");
    }
    property bool controller: false
    property string controllerName: ""
    property bool systemOskAvailable:false
    property bool systemOskRunning:false
    property bool systemOskVisible:false
    property string systemOskDetail:""
    readonly property bool systemOskReady:systemOskAvailable&&systemOskRunning
    property var clipboardItems: []
    property bool clipboardPaused: false
    property bool clipboardAvailable: false
    property string clipboardDetail: "Starting clipboard service"
    property string clipboardPendingId: ""
    property bool clipboardCloseAfterCopy: true
    property var gameArt: ({})
    function artFor(app) {
        if(!app)return {}

        const match=((app.execString||"")+" "+app.id).match(/(?:rungameid\/|run\/|steam_app_)(\d+)/);
        return match ? gameArt[match[1]]||{} : {}

    }
    property string toast: ""
    property string osd: ""
    property var osdScreen:null
    property bool osdHovered:false
    function showVolumeOsd() {
        if(!osdScreen)osdScreen=chooseScreen();
        osd=status.muted ? "Muted" : "Volume";
        osdTimer.restart();
    }
    property int focusSeconds: 25*60
    property bool focusRunning: false
    property bool preferencesLoaded: false
    // Normalize desktop entries once; search, taskbar, and window cards all use
    // these indexes instead of scanning the complete application list.
    property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a,b) => a.name.localeCompare(b.name))
    readonly property var appIndex: {
        const index=Object.create(null);
        const add=(value,app) => {
            const key=String(value||"").toLowerCase().replace(/\.desktop$/i,"").trim();
            if(key && !index[key]) index[key]=app;
        };
        apps.forEach(a => {
            add(a.id,a); add(a.startupClass,a);
        });
        // Exact identifiers win over the legacy basename fallback.
        apps.forEach(a => {
            add(String(a.id||"").split(".").pop(),a);
        });
        return index;
    }
    readonly property var appSearchIndex: apps.map(a => ({
        app:a,
        name:String(a.name||"").toLowerCase(),
        hay:(String(a.name||"")+" "+String(a.genericName||"")+" "+(a.keywords||[]).join(" ")).toLowerCase(),
        categories:(a.categories||[]).join(" ").toLowerCase()
    }))
    readonly property var searchCategories: ({Games:["game"], Create:["graphics","audiovideo","audio","video"], Work:["office","development","education"], System:["system","settings","utility"], Internet:["network"]})
    property var favoriteApps: {
        let ids = prefs.favorites;
        if (prefs.pinsConfigured || ids.length) return ids.map(id => appIndex[String(id).toLowerCase()]).filter(Boolean);
        const choices = ["firefox", "google-chrome", "chromium", "kitty", "org.kde.dolphin", "org.gnome.Nautilus", "steam", "code", "org.kde.kate"];
        return choices.map(id => appIndex[id.toLowerCase()]).filter(Boolean).slice(0,6);
    }
    readonly property var favoriteSearchIndex: {
        const ids=Object.create(null);
        favoriteApps.forEach(app => ids[app.id]=true);
        return appSearchIndex.filter(record => ids[record.app.id]);
    }
    property var dockScreen: null
    property bool dockNotice: false
    property bool displaysReady: false
    property var knownDisplays: []
    property var resolvedDisplays: Quickshell.screens.map(s=>({name:s.name,mode:layoutFor(s.width,s.height,s.name)}))
    property string displayLayoutState:JSON.stringify({mode:prefs.mode,displays:resolvedDisplays})
    onDisplayLayoutStateChanged:if(preferencesLoaded)layoutSync.restart()
    onPreferencesLoadedChanged:if(preferencesLoaded)layoutSync.restart()
    Timer {id:layoutSync;interval:200;onTriggered:if(h.preferencesLoaded&&["auto","desktop","phone","console"].indexOf(h.prefs.mode)>=0&&h.resolvedDisplays.every(d=>d.name!==""))h.command({action:"display-layouts",mode:h.prefs.mode,displays:h.resolvedDisplays})}
    property var displayTopology: Quickshell.screens.map(s=>s.name)
    onDisplayTopologyChanged: updateDisplays(Quickshell.screens)
    function updateDisplays(screens) {
        if(!displaysReady)return;
        const names=screens.map(s=>s.name);
        const added=screens.filter(s=>knownDisplays.indexOf(s.name)<0);
        knownDisplays=names;
        if(dockScreen&&names.indexOf(dockScreen.name)<0) {dockNotice=false;dockScreen=null;}
        if(added.length) {dockScreen=added[added.length-1];dockNotice=true;dockTimer.restart();}
    }
    Timer {interval:3000;running:true;onTriggered:{h.knownDisplays=h.displayTopology.slice();h.displaysReady=true;}}
    Timer {id:dockTimer;interval:30000;onTriggered:h.dockNotice=false}
    function pauseDockNotice(){if(dockNotice)dockTimer.stop();}
    function resumeDockNotice(){if(dockNotice)dockTimer.restart();}
    function useDockedWorkspace(phoneScreen) {
        if(!dockScreen)return;
        const overrides=Object.assign({},prefs.displayModes||{});
        if(phoneScreen)overrides[phoneScreen.name]="phone";
        overrides[dockScreen.name]="desktop";
        set("displayModes",overrides);
        targetScreen=dockScreen;dockNotice=false;
        mode("auto");openSection("apps");
    }
    property var targetScreen: null
    function chooseScreen() {
        return Quickshell.screens.find(s=>s.name===status.activeMonitor) ||
            (ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.screens.length ? ToplevelManager.activeToplevel.screens[0] : null) || Quickshell.screens[0];
    }
    property string launcherSection: "apps"
    property string mobileTab: "home"
    // Phone drawer handoff: the embedded home passes drag progress to the overlay, and asks for search focus.
    property real drawerHandoff: 0
    property bool drawerSearch: false
    // Resource telemetry changes frequently; compositor topology does not. Keep
    // the latter on its own properties so every CPU tick does not rebuild the
    // taskbar's complete window grouping model.
    property bool compositorActive: false
    property var compositorWindows: []
    property var windows: compositorActive ? compositorWindows : ToplevelManager.toplevels.values.map(w => ({title:w.title,className:w.appId,handle:w,workspace:0,address:""}))
    property var taskGroups: {
        let groups=[];
        const byKey=Object.create(null);
        const addGroup=(key,app,name,icon) => {
            key=key||"unknown";
            let group=byKey[key];
            if(!group) {group={app:app,key:key,name:name,icon:icon,windows:[]};byKey[key]=group;groups.push(group);}
            return group;
        };
        favoriteApps.forEach(app => addGroup(app.id,app,app.name,app.icon));
        windows.forEach(w => {
            const app=appForWindow(w);
            const key=app ? app.id : w.className;
            const group=addGroup(key,app,app ? app.name : w.className||w.title,app ? app.icon : "application-x-executable");
            group.windows.push(w);
        });
        const order=prefs.taskbarOrder||[];
        const ranks=Object.create(null);
        order.forEach((key,index)=>{if(ranks[key]===undefined)ranks[key]=index;});
        return groups.sort((a,b)=>{const ai=ranks[a.key],bi=ranks[b.key];return (ai===undefined ? order.length : ai)-(bi===undefined ? order.length : bi);});
    }
    function reorderTask(key,index) {
        let order=taskGroups.map(g=>g.key);const from=order.indexOf(key);
        if(from<0||index<0||index>=order.length)return;
        order.splice(from,1);order.splice(index,0,key);
        set("taskbarOrder",order.concat((prefs.taskbarOrder||[]).filter(k=>order.indexOf(k)<0)).slice(0,128));
    }
    property var recentApps: prefs.recent.map(id => appIndex[String(id).toLowerCase()]).filter(Boolean).slice(0,6)
    readonly property var inbox: Notifier.inbox
    readonly property int unread: Notifier.unread
    property date now: clock.date
    signal navigate(string key)
    function command(data) { bridge.write(JSON.stringify(data)+"\n"); }
    function systemOsk(verb) { command({action:"system-osk",verb:verb||"toggle"}); }
    function set(key,value) { let p = Object.assign({},prefs); p[key]=value; prefs=p; command({action:"preference",key:key,value:value}); }
    function toggle(p) { page = page === p ? "" : p; if(page === "launcher") query = ""; }
    function mode(m) { if(m==="phone") {const screen=targetScreen||chooseScreen();if(screen)set("phoneDisplay",screen.name);} set("mode",m); page=""; query=""; mobileTab="home"; launcherSection="apps"; category=m==="console" ? "Games" : "All apps"; }
    function close() { page="";closeAudio();closePowerProfile(); }
    property int startSearchRequest:0
    // Search surface that grows from the shelf pill. It is separate from Start.
    function openSearch() { if(page==="search"){close();return;} query="";calculation="";page="search";startSearchRequest++; }
    // Calculator input: an explicit "=" prefix, or a bare arithmetic expression.
    function calcExpression(text) {
        const q=String(text||"").trim();
        const body=q.startsWith("=") ? q.slice(1).trim() : q;
        return body.replace(/[×x]/g,"*").replace(/÷/g,"/");
    }
    function looksLikeMath(text) { const q=String(text||"").trim(); return /^[\d\s.+\-*/%()^×x÷]+$/.test(q)&&/\d/.test(q)&&/[+\-*/%^×x÷]/.test(q.replace(/^-/,"")); }
    function openStart(searchOnly) {
        launcherSection="apps";
        if(page==="launcher"&&!searchOnly){close();return;}
        query="";page="launcher";startSearchRequest++;
    }
    function launch(app) {
        if(!app)return;
        const running=windows.filter(w=>appForWindow(w)===app);
        if(running.length){command({action:"recent",id:app.id});activateGroup({app:app,windows:running});}
        else launchNew(app);
    }
    function launchNew(app) {if(!app)return;command({action:"recent",id:app.id});app.execute();page="";}
    function pinned(app) { return prefs.favorites.indexOf(app.id)>=0; }
    function glyphForApp(app) {
        const words=app ? ((app.id||"")+" "+(app.name||"")+" "+(app.categories||[]).join(" ")).toLowerCase() : "";
        if(/firefox|chrom|browser|network/.test(words))return "web";
        if(/file|dolphin|nautilus/.test(words))return "folder";
        if(/terminal|kitty|konsole|development|code/.test(words))return "terminal";
        if(/music|audio|video/.test(words))return "music";
        if(/note|office|text/.test(words))return "clipboard";
        if(/game|steam/.test(words))return "game";
        if(/setting|system/.test(words))return "settings";
        return "apps";
    }
    function pin(app) { command({action:"pin",id:app.id,initial:favoriteApps.map(a=>a.id)}); }
    function settings(which) { if(which==="network"||which==="bluetooth") {controlDetail=which==="network" ? "wifi" : which;page="controls";return;} page=""; command({action:"settings",which:which}); }
    function volume(value) { value=Math.max(0,Math.min(100,Math.round(value)));command({action:"volume",value:value}); let s=Object.assign({},status); s.volume=value; status=s;showVolumeOsd(); }
    function workspace(n) { if(status.hypr)command({action:"workspace",number:Number(n)}); }
    property var pendingFocus:null
    function focusWindow(w) {
        // Release layer-shell keyboard exclusivity before transferring app focus.
        pendingFocus=w;close();focusTransfer.restart();
    }
    Timer {id:focusTransfer;interval:100;onTriggered:{
        const w=h.pendingFocus;h.pendingFocus=null;if(!w)return;
        if(h.status.hypr&&w.address)h.command({action:"focus-window",address:w.address});
        else if(w.handle)w.handle.activate();
    }}
    function closeWindow(w) {
        if(w.handle) w.handle.close();
        else if(status.hypr) Quickshell.execDetached(["hyprctl","dispatch","closewindow","address:"+w.address]);
    }
    function displayMode(name,mode) {
        const overrides=Object.assign({},prefs.displayModes||{});
        if(mode==="auto")delete overrides[name];else overrides[name]=mode;
        set("displayModes",overrides);
    }
    function layoutFor(width,height,name) {
        if(prefs.mode==="phone"&&name) {
            const phoneName=prefs.phoneDisplay||(Quickshell.screens[0] ? Quickshell.screens[0].name : "");
            return name===phoneName ? "phone" : "desktop";
        }
        if(prefs.mode!=="auto") return prefs.mode;
        const override=(prefs.displayModes||{})[name];
        if(override)return override;
        return width<680 || (height>width && width<1000) ? "phone" : "desktop";
    }
    function openSection(section) { launcherSection=section;if(section==="windows")mobileTab="recent";page=section==="windows"&&prefs.mode==="console" ? "windows" : "launcher"; }
    function appForWindow(w) {
        const key=String(w.className||"").toLowerCase().replace(/\.desktop$/i,"").trim();
        return appIndex[key]||null;
    }
    function active(w) { return w.handle ? w.handle.activated : w.address===status.activeAddress; }
    function activateGroup(g) {
        if(!g.windows.length) { if(g.app)launch(g.app);return; }
        let index=g.windows.findIndex(w=>active(w));
        focusWindow(g.windows[(index+1)%g.windows.length]);
    }
    // Menu entries: quick entries become large buttons, chip entries share a labelled row, checked entries show a switch.
    function appMenu(app) {
        if(!app)return [];
        const matching=windows.filter(w=>appForWindow(w)===app);
        let entries=[{text:matching.length ? "New window" : "Open",icon:"add",quick:true,run:()=>launchNew(app)},
                     {text:pinned(app) ? "Unpin" : "Pin",icon:pinned(app) ? "keep_off" : "keep",quick:true,run:()=>pin(app)}];
        if(matching.length) entries.push({text:matching.length===1 ? "Close" : "Close all",icon:"close",quick:true,danger:true,run:()=>matching.forEach(w=>closeWindow(w))});
        (app.actions||[]).forEach(a=>entries.push({text:a.name,icon:"bolt",run:()=>{a.execute();close();}}));
        matching.forEach(w=>entries.push({text:w.title||app.name,detail:w.workspace ? "Workspace "+w.workspace : "",icon:"desktop",run:()=>focusWindow(w)}));
        return entries;
    }
    function windowMenu(w) {
        let entries=[];
        if(w.handle) {
            entries.push({text:w.handle.maximized ? "Restore" : "Maximize",icon:w.handle.maximized ? "close_fullscreen" : "open_in_full",quick:true,run:()=>w.handle.maximized=!w.handle.maximized});
            entries.push({text:"Minimize",icon:"minimize",quick:true,run:()=>w.handle.minimized=true});
        }
        entries.push({text:"Close",icon:"close",quick:true,danger:true,run:()=>closeWindow(w)});
        entries.push({text:"Switch to window",icon:"desktop",run:()=>focusWindow(w)});
        if(status.hypr) status.workspaces.filter(n=>n!==w.workspace).sort((a,b)=>a-b).forEach(n=>entries.push({text:String(n),chip:true,group:"Move to workspace",run:()=>command({action:"move-window",address:w.address,number:Number(n),follow:false})}));
        return entries;
    }
    function taskbarMenu() {
        return [{text:"Apps",icon:"apps",quick:true,run:()=>openSection("apps")},
                {text:"Windows",icon:"desktop",quick:true,run:()=>openSection("windows")},
                {text:"Settings",icon:"settings",quick:true,run:()=>openSettings("taskbar")},
                {text:"Hide automatically",icon:"vertical_align_bottom",checked:!!prefs.taskbarAutoHide,run:()=>set("taskbarAutoHide",!prefs.taskbarAutoHide)},
                {text:"Center apps",icon:"format_align_center",checked:!!prefs.taskbarCenter,run:()=>set("taskbarCenter",!prefs.taskbarCenter)},
                {text:"Window labels",icon:"label",checked:!!prefs.taskbarLabels,run:()=>set("taskbarLabels",!prefs.taskbarLabels)},
                {text:"Displays & convergence",icon:"convergence",run:()=>page="convergence"},
                {text:"Wallpaper & style",icon:"palette",run:()=>page="appearance"}];
    }
    function message(s) { toast=s; toastTimer.restart(); }
    function screenShot() { close(); command({action:"screenshot"}); }
    function media(verb) { command({action:"media",verb:verb}); }
    function refreshClipboard() { command({action:"clipboard-list"}); }
    function toggleClipboard() { page=page==="clipboard" ? "" : "clipboard";if(page==="clipboard")refreshClipboard(); }
    function copyClipboard(id,closeAfter) {
        clipboardPendingId=id;clipboardCloseAfterCopy=closeAfter!==false;
        command({action:"clipboard-copy",id:id});
    }
    function deleteClipboard(id) { command({action:"clipboard-delete",id:id}); }
    function clearClipboard() { command({action:"clipboard-clear"}); }
    function pauseClipboard() { command({action:"clipboard-pause",paused:!clipboardPaused}); }
    function timerToggle() { if(focusSeconds<=0) focusSeconds=25*60; focusRunning=!focusRunning; }
    function searchApps(text,cat) {
        const q=text.toLowerCase().trim();
        const source=cat==="Pinned" ? favoriteSearchIndex : appSearchIndex;
        const category=searchCategories[cat];
        const matches=[];
        for(let index=0;index<source.length;index++) {
            const record=source[index];
            const a=record.app;
            const name=record.name;
            if(category) {
                let inCategory=false;
                for(let tokenIndex=0;tokenIndex<category.length;tokenIndex++)if(record.categories.indexOf(category[tokenIndex])>=0){inCategory=true;break;}
                if(!inCategory)continue;
            }
            let score=0;
            if(q) {
                if(name===q) score=1000;
                else if(name.startsWith(q)) score=800;
                else if(name.indexOf(q)>=0) score=600;
                else if(record.hay.indexOf(q)>=0) score=400;
                else { let j=0; for(let i=0;i<name.length && j<q.length;i++) if(name[i]===q[j]) j++; if(j===q.length) score=100-name.length; else continue; }
            }
            matches.push({app:a,score:score});
        }
        matches.sort((a,b)=>b.score-a.score||a.app.name.localeCompare(b.app.name));
        return matches.map(match => match.app);
    }
    SystemClock { id: clock; precision: SystemClock.Seconds }
    Process {
        id: bridge
        command: ["/usr/local/bin/aurora-opal-bridge"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const e=JSON.parse(line);
                    if(e.event === "status") {
                        if (h.preferencesLoaded && (e.data.volume !== h.status.volume || e.data.muted !== h.status.muted)) { h.osdScreen=h.chooseScreen();h.showVolumeOsd(); }
                        h.status=Object.assign({},h.status,e.data);
                    } else if(e.event === "compositor") {
                        if (e.data.hypr !== undefined) h.compositorActive=!!e.data.hypr;
                        if (e.data.windows !== undefined) h.compositorWindows=e.data.windows;
                        h.status=Object.assign({},h.status,e.data);
                    } else if(e.event === "preferences") {
                        h.prefs=e.data;
                        // Startup/reload must NEVER open a keyboard-exclusive overlay.
                        // Only an explicit user action may open the drawer.
                        h.preferencesLoaded=true;
                    } else if(e.event === "wallpapers" && e.request===h.wallpaperRequest) {
                        h.wallpaperLibrary=e.items;h.wallpaperLibraryError=e.error;h.wallpaperLibraryBusy=false;
                        if(!e.error){h.wallpaperFolders=e.folders||[];h.wallpaperFolder=e.folder||"";h.wallpaperParent=e.parent||"";}
                    } else if(e.event === "connectivity") {
                        let data=Object.assign({},h.connectivity);
                        data[e.kind]=Object.assign({},data[e.kind],e);h.connectivity=data;
                    } else if(e.event === "themeBusy") h.themeBusy=e.busy;
                    else if(e.event === "message") h.message(e.text);
                    else if(e.event === "controller") { h.controller=e.connected;h.controllerName=e.name||""; }
                    else if(e.event === "systemOsk") {h.systemOskAvailable=!!e.available;h.systemOskRunning=!!e.running;h.systemOskVisible=!!e.visible;h.systemOskDetail=e.detail||"";}
                    else if(e.event === "libraryArt") h.gameArt=e.data;
                    else if(e.event === "navigation" && h.prefs.mode === "console") { if(e.key==="home") h.toggle("launcher"); else if(h.page!=="") h.navigate(e.key); }
                    else if(e.event === "calculation" && e.query===h.calcExpression(h.query)) h.calculation=e.result;
                    else if(e.event === "clipboard") {
                        h.clipboardItems=e.items||[];h.clipboardPaused=!!e.paused;
                        h.clipboardAvailable=!!e.available;h.clipboardDetail=e.detail||"";
                    } else if(e.event === "clipboardCopied") {
                        if(e.id===h.clipboardPendingId) {
                            if(e.success&&h.clipboardCloseAfterCopy)h.close();
                            h.clipboardPendingId="";
                        }
                        h.message(e.success ? "Copied. Ctrl+V to paste." : "Couldn’t copy this entry.");
                    }
                } catch(error) { console.warn("Opal bridge:",error); }
            }
        }
        onExited: (code,status) => { h.message("System bridge stopped. Restart Opal to reconnect."); }
    }
    Timer { id: toastTimer; interval: 4500; onTriggered: h.toast="" }
    Timer { id: osdTimer; interval: 1800; onTriggered: {if(h.osdHovered)restart();else h.osd="";} }
    Timer { interval:1000; running:h.focusRunning; repeat:true; onTriggered: { h.focusSeconds--; if(h.focusSeconds<=0) { h.focusRunning=false; h.message("Focus complete. Time to take a breath."); Quickshell.execDetached(["notify-send","-a","Opal","Focus complete","Time to take a break."]); } } }
}
