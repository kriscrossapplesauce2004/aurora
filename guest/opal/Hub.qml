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
    function openSettings(section) { settingsSection=section==="display"||section==="screens" ? "displays" : section||"";page="settings"; }

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
    // The old convergence page now lives in Settings → Displays.
    onPageChanged:{if(page==="convergence"){settingsSection="displays";page="settings";return;}if(page!=="") {closeAudio();closePowerProfile();}}
    property string category: "All apps"
    property string query: ""
    property string calculation: ""
    readonly property bool dnd: polkitMode ? false : Notifier.dnd
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
    // Console library from game_library.py. Launching sends only the id.
    // Auto-rotate: only the touch display in phone layout follows the accelerometer.
    property int orientation: -1
    function applyOrientation(transform) {
        // The first reading is a baseline: startup never rewrites a monitor rule unless the device is already turned.
        const first=orientation<0;
        const changed=orientation!==transform;
        orientation=transform;
        if(prefs.autoRotate===false||prefs.convergeAuto===false||prefs.convergeRotate===false||!changed||first&&transform===0)return;
        const phone=Quickshell.screens.find(s=>layoutFor(s.width,s.height,s.name)==="phone"&&(!prefs.phoneDisplay||s.name===prefs.phoneDisplay));
        if(phone)command({action:"rotate",output:phone.name,transform:transform});
    }
    // Claude: "!" in search asks the Claude Code CLI. Answers stream in.
    property int claudeRequest: 0
    property string claudeAnswer: ""
    property var claudeTools: []
    property bool claudeBusy: false
    property bool claudeError: false
    function askClaude(text) { const t=text.trim();if(!t)return;claudeRequest++;claudeAnswer="";claudeTools=[];claudeError=false;claudeBusy=true;command({action:"claude-ask",text:t,id:claudeRequest}); }
    // The assistant panel. Super+A, the Assistant key, Home long-press and "!" in Start open it.
    function openAssistant(text) {targetScreen=chooseScreen();query="";AssistantState.capture();closeAudio();page="assistant";if(text&&text.trim()!=="")AssistantState.send(text);}
    function stopClaude() { command({action:"claude-stop"});claudeBusy=false; }
    // System reports from system_tools.py.
    property var health: ({disks:[],temperatures:{},hottest:0})
    property var updates: ({pacman:null,flatpak:null})
    property var monitors: []
    property var themeChoices: ({})
    property var sun: ({sunrise:"07:00",sunset:"19:00",estimated:true})
    // Opal Link devices and status from opal_link.py.
    property string linkStatus: "off"
    property string linkDetail: ""
    property var linkDevices: []
    property var linkPairRequest: null
    function link(action, id, extra) { command(Object.assign({action:"link-"+action,id:id||""},extra||{})); }
    function appForClass(name) { const c=(name||"").toLowerCase();return c ? apps.find(a=>(a.id||"").toLowerCase()===c||(a.id||"").toLowerCase().endsWith("."+c)||(a.name||"").toLowerCase()===c)||null : null; }
    property var games: []
    function launchGame(game) { if(!game)return; command({action:"game-launch",id:game.id}); close(); }
    function gameRunning(game) { return !!game&&!!game.windowClass&&windows.some(w=>(w.className||"").toLowerCase().startsWith(game.windowClass.toLowerCase())); }
    function gameWindows(game) { return !game||!game.windowClass ? [] : windows.filter(w=>(w.className||"").toLowerCase().startsWith(game.windowClass.toLowerCase())); }
    function pinGame(game) { const pins=(prefs.gamePins||[]).slice();const i=pins.indexOf(game.id);if(i>=0)pins.splice(i,1);else pins.unshift(game.id);set("gamePins",pins); }
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
    property var apps: polkitMode ? [] : DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a,b) => a.name.localeCompare(b.name))
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
        if(dockScreen&&names.indexOf(dockScreen.name)<0) {
            const gone=dockScreen.name;
            dockNotice=false;dockMenu=false;dockScreen=null;dockResult=null;dockMirrored=false;
            if(docked&&dockOutput===gone) {
                docked=false;command({action:"pointer-stop"});phoneDark=false;
                const next=Object.assign({},sessionModes);delete next[gone];sessionModes=next;
                message("Undocked. Your apps are back on the phone.");
            }
        }
        if(added.length) {
            dockScreen=added[added.length-1];dockResult=null;dockMirrored=false;dockMenu=false;
            command({action:"monitors"});
            // A remembered choice applies at once; the card only confirms it.
            const saved=(prefs.dockChoices||{})[dockScreen.name];
            if(saved)Qt.callLater(()=>{if(dockScreen){dockAs(saved.mode,saved.phoneMode);dockResult=Object.assign({},dockResult||{},{remembered:true});}});
            dockNotice=true;dockTimer.restart();
        }
    }
    // The full dock menu. The compact card opens it with "More options".
    property bool dockMenu: false
    // What convergence did for the new screen: {moved, error, remembered}. The card shows it.
    property var dockResult: null
    property bool dockMirrored: false
    // The convergence controller registers itself here so the card can undo its work.
    property var convergence: null
    function dockAs(screenMode,phoneMode) {
        if(!dockScreen)return;
        const out=dockScreen.name;
        const monitor=monitors.find(m=>m.name===out);
        const phone=phoneMode||phoneDockMode||"trackpad";
        if(convergence){convergence.disown(out);if(screenMode==="mirror")convergence.revertWindows();}
        if(dockMirrored&&screenMode!=="mirror"&&monitor)command({action:"monitors-apply",displays:[{name:out,mode:"preferred",x:monitor.x,y:monitor.y,scale:monitor.scale,transform:0,mirror:"none"}],keep:false});
        dockMirrored=screenMode==="mirror"&&phoneScreen!==null;
        applyDock({mode:screenMode,phoneMode:phone,apps:[],resolution:"",scale:monitor ? monitor.scale : 1,remember:true});
        dockNotice=true;dockTimer.restart();
    }
    function dockPhoneAs(phoneMode) {
        if(!dockScreen)return;
        setPhoneDockMode(phoneMode);docked=phoneScreen!==null;dockOutput=dockScreen.name;
        const saved=Object.assign({},prefs.dockChoices||{});
        saved[dockScreen.name]=Object.assign({mode:sessionModes[dockScreen.name]||"desktop",resolution:"",scale:1},saved[dockScreen.name]||{},{phoneMode:phoneMode});
        set("dockChoices",saved);
    }
    Timer {interval:3000;running:true;onTriggered:{h.knownDisplays=h.displayTopology.slice();h.displaysReady=true;}}
    Timer {id:dockTimer;interval:120000;onTriggered:h.dockNotice=false}
    function pauseDockNotice(){if(dockNotice)dockTimer.stop();}
    function resumeDockNotice(){if(dockNotice)dockTimer.restart();}
    // Docking: the dock menu's choice for a connected screen, and the phone's role while docked.
    property var sessionModes: ({})
    property bool docked: false
    property string dockOutput: ""
    property string phoneDockMode: "trackpad"
    property bool phoneDark: false
    readonly property var phoneScreen: Quickshell.screens.find(s=>(!dockScreen||s.name!==dockScreen.name)&&layoutFor(s.width,s.height,s.name)==="phone")||null
    // The dock menu runs on the phone display so the new screen stays clean.
    readonly property var internalScreen: phoneScreen || Quickshell.screens.find(s=>!dockScreen||s.name!==dockScreen.name) || Quickshell.screens[0] || null
    function setPhoneDockMode(next) {
        phoneDockMode=next;
        if(next==="trackpad"&&docked)command({action:"pointer-start",output:dockOutput});
        else command({action:"pointer-stop"});
    }
    function applyDock(choice) {
        if(!dockScreen)return;
        const out=dockScreen.name;
        const phone=phoneScreen ? phoneScreen.name : "";
        const monitor=monitors.find(m=>m.name===out);
        if(choice.mode==="mirror"&&phone) {
            command({action:"monitors-apply",displays:[{name:out,mode:"preferred",x:monitor ? monitor.x : 0,y:monitor ? monitor.y : 0,scale:1,transform:0,mirror:phone}],keep:false});
        } else {
            const modes=Object.assign({},sessionModes);modes[out]=choice.mode==="mirror" ? "desktop" : choice.mode;sessionModes=modes;
            if(monitor&&(choice.resolution&&choice.resolution!=="preferred"||choice.scale!==monitor.scale))
                command({action:"monitors-apply",displays:[{name:out,mode:choice.resolution&&choice.resolution!=="preferred" ? choice.resolution.replace("Hz","") : monitor.width+"x"+monitor.height+"@"+monitor.refresh.toFixed(2),x:monitor.x,y:monitor.y,scale:choice.scale||1,transform:monitor.transform,mirror:"none"}],keep:false});
            const target=(status.monitors||[]).find(m=>m.name===out);
            if(target&&target.workspace>0)(choice.apps||[]).forEach(address=>command({action:"move-window",address:address,number:target.workspace,follow:false}));
        }
        if(choice.remember) {
            const saved=Object.assign({},prefs.dockChoices||{});
            saved[out]={mode:choice.mode,phoneMode:choice.phoneMode,resolution:choice.resolution||"",scale:choice.scale||1};
            set("dockChoices",saved);
        }
        docked=!!phone;dockOutput=out;dockNotice=false;dockMenu=false;dockTimer.stop();
        if(phone)setPhoneDockMode(choice.phoneMode||"trackpad");
        targetScreen=dockScreen;
    }
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
    readonly property var inbox: polkitMode ? [] : Notifier.inbox
    readonly property int unread: polkitMode ? 0 : Notifier.unread
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
    // Session lock. The Opal lock screen owns unlocking through PAM.
    property bool locked: false
    function lock() { page=""; locked=true; }
    function settings(which) { if(which==="lock") {lock();return;} if(which==="network"||which==="bluetooth") {controlDetail=which==="network" ? "wifi" : which;page="controls";return;} page=""; command({action:"settings",which:which}); }
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
        else if(status.hypr) command({action:"close-window",address:w.address});
    }
    function displayMode(name,mode) {
        const overrides=Object.assign({},prefs.displayModes||{});
        if(mode==="auto")delete overrides[name];else overrides[name]=mode;
        set("displayModes",overrides);
    }
    function layoutFor(width,height,name) {
        // A dock choice for this session wins over everything else.
        if(name&&sessionModes[name])return sessionModes[name];
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
    function urgent(w) { return !!w.address&&(status.urgent||[]).indexOf(w.address)>=0; }
    function active(w) { return w.handle ? w.handle.activated : w.address===status.activeAddress; }
    function activateGroup(g) {
        if(!g.windows.length) { if(g.app)launch(g.app);return; }
        let index=g.windows.findIndex(w=>active(w));
        focusWindow(g.windows[(index+1)%g.windows.length]);
    }
    // Menu entries: quick entries become large buttons, chip entries share a labelled row, checked entries show a switch.
    // Phone home layout: pages of widgets and items. An item is an app id or a folder {folder, apps}.
    readonly property var phoneWidgetKinds:["glance","stack","media","calendar","battery","focus"]
    readonly property var phoneHome:{
        const saved=prefs.phoneHome;
        if(saved&&Array.isArray(saved.pages)&&saved.pages.length)return saved;
        const ids=favoriteApps.slice(4).map(a=>a.id).concat(recentApps.filter(a=>favoriteApps.indexOf(a)<0).map(a=>a.id)).slice(0,16);
        return {pages:[{widgets:["glance","stack"],items:ids}]};
    }
    function setPhoneHome(layout) { set("phoneHome",{pages:layout.pages.filter((p,i)=>i===0||p.widgets.length||p.items.length)}); }
    function homeHas(id) { return phoneHome.pages.some(p=>p.items.some(item=>item===id||(item.apps||[]).indexOf(id)>=0)); }
    function addToHome(app) {
        if(!app||homeHas(app.id))return;
        const layout=JSON.parse(JSON.stringify(phoneHome));
        const last=layout.pages[layout.pages.length-1];
        if(last.items.length>=24)layout.pages.push({widgets:[],items:[app.id]});else last.items.push(app.id);
        setPhoneHome(layout);message("Added to Home");
    }
    function appMenu(app) {
        if(!app)return [];
        const matching=windows.filter(w=>appForWindow(w)===app);
        let entries=[{text:matching.length ? "New window" : "Open",icon:"add",quick:true,run:()=>launchNew(app)},
                     {text:pinned(app) ? "Unpin" : "Pin",icon:pinned(app) ? "keep_off" : "keep",quick:true,run:()=>pin(app)}];
        if(prefs.mode==="phone"||prefs.mode==="auto")entries.push({text:homeHas(app.id) ? "On Home" : "Add to Home",icon:"add_to_home_screen",run:()=>addToHome(app)});
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
    // Greeter mode: no session backend. Theme roles come from a cache the user session writes.
    readonly property bool greeterMode: Quickshell.env("OPAL_GREETER") === "1"
    readonly property bool polkitMode: Quickshell.env("OPAL_POLKIT") === "1"
    FileView {
        id: greeterTheme
        path: h.polkitMode ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/opal/preferences.json" : h.greeterMode ? (Quickshell.env("OPAL_GREETER_THEME") || "/var/cache/opal-greeter/theme.json") : ""
        watchChanges: h.greeterMode || h.polkitMode
        onFileChanged: reload()
        onLoaded: {
            try { h.prefs = Object.assign({}, h.prefs, JSON.parse(text())); } catch (error) { console.warn("Greeter theme is not valid JSON"); }
            h.preferencesLoaded = true;
        }
    }
    Process {
        id: bridge
        command: ["/usr/local/bin/aurora-opal-bridge"]
        running: !h.greeterMode && !h.polkitMode
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
                        // A title patch edits one window without a full refresh.
                        if (e.data.windowTitle) h.compositorWindows=h.compositorWindows.map(w=>w.address===e.data.windowTitle.address ? Object.assign({},w,{title:e.data.windowTitle.title}) : w);
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
                    else if(e.event === "lock") h.lock();
                    else if(e.event === "unlock") h.locked=false;
                    else if(e.event === "controller") { h.controller=e.connected;h.controllerName=e.name||""; }
                    else if(e.event === "systemOsk") {h.systemOskAvailable=!!e.available;h.systemOskRunning=!!e.running;h.systemOskVisible=!!e.visible;h.systemOskDetail=e.detail||"";}
                    else if(e.event === "libraryArt") h.gameArt=e.data;
                    else if(e.event === "gameLibrary") h.games=e.data;
                    else if(e.event === "link") {h.linkStatus=e.status||"off";h.linkDetail=e.detail||"";h.linkDevices=e.devices||[];if(h.linkPairRequest&&!h.linkDevices.some(d=>d.id===h.linkPairRequest.id&&d.pairRequested))h.linkPairRequest=null;}
                    else if(e.event === "linkPairRequest") h.linkPairRequest={id:e.id,name:e.name,code:e.code};
                    else if(e.event === "health") h.health={disks:e.disks,temperatures:e.temperatures,hottest:e.hottest};
                    else if(e.event === "updates") h.updates={pacman:e.pacman,flatpak:e.flatpak};
                    else if(e.event === "themeChoices") h.themeChoices=e.data||({});
                    else if(e.event === "recentActivity"||e.event === "torch"||e.event === "batteryStats") PhoneState.ingest(e);
                    else if(e.event === "monitors") h.monitors=e.data;
                    else if(e.event === "sun") h.sun={sunrise:e.sunrise,sunset:e.sunset,estimated:e.estimated};
                    else if(e.event.indexOf("assistant") === 0) AssistantState.ingest(e);
                    else if(e.event === "claude" && e.id===h.claudeRequest) {h.claudeAnswer=e.text||"";h.claudeTools=e.tools||[];if(e.done){h.claudeBusy=false;h.claudeError=!!e.error;}}
                    else if(e.event === "orientation") h.applyOrientation(e.transform);
                    else if(e.event === "navigation") ControllerNav.input(e.key);
                    else if(e.event === "gamePerf" || e.event === "gameDetail") GameState.receive(e);
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
