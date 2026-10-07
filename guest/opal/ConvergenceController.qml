import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Runs convergence_service.py, applies the layouts it picks and shows an undo toast. It never opens a keyboard-exclusive surface.
Scope {
    id:c
    readonly property bool enabled:Hub.preferencesLoaded&&Hub.prefs.convergeAuto!==false&&Hub.prefs.mode!=="console"
    property var owned:({})
    property var undoModes:({})
    property bool undoWindows:false
    property int undoRotation:-1
    property string toastText:""
    property string toastDetail:""
    property real remaining:0
    property int lastOrientation:-1
    readonly property bool toastVisible:toastText!==""
    readonly property var toastScreen:Hub.targetScreen||Quickshell.screens[0]||null
    property var pendingState:null
    readonly property bool canUndo:Object.keys(undoModes).length>0||undoWindows||undoRotation>=0
    Component.onCompleted:Hub.convergence=c
    // A user choice on the docking card wins over the automatic layout for that screen.
    function disown(name) {const own=Object.assign({},owned);delete own[name];owned=own;const modes=Object.assign({},undoModes);delete modes[name];undoModes=modes;}
    function revertWindows() {if(undoWindows){send({cmd:"undo"});undoWindows=false;}}

    function outputs() {return Quickshell.screens.map(s=>({name:s.name,width:s.width,height:s.height}));}
    function send(obj) {if(service.running)service.write(JSON.stringify(obj)+"\n");}
    function pushState() {if(enabled)send({cmd:"state",outputs:outputs(),prefs:Hub.prefs});}
    function show(text,detail) {toastText=text;toastDetail=detail||"";remaining=1;countdown.restart();}
    function hide() {countdown.stop();toastText="";toastDetail="";undoModes=({});undoWindows=false;undoRotation=-1;}
    function undo() {
        if(undoRotation>=0){const phone=Quickshell.screens.find(s=>Hub.layoutFor(s.width,s.height,s.name)==="phone");if(phone)Hub.command({action:"rotate",output:phone.name,transform:undoRotation});}
        const next=Object.assign({},Hub.sessionModes);
        for(const name in undoModes){if(undoModes[name]==="")delete next[name];else next[name]=undoModes[name];}
        Hub.sessionModes=next;
        if(undoWindows)send({cmd:"undo"});
        hide();
    }
    // Apply layouts, skipping outputs the user set by hand and outputs another feature owns.
    function apply(e) {
        const manual=Hub.prefs.displayModes||{};
        const next=Object.assign({},Hub.sessionModes);
        const prior={};
        const own=Object.assign({},owned);
        for(const name in e.layouts) {
            if(manual[name]||(next[name]&&!own[name]))continue;
            if(next[name]!==e.layouts[name]){prior[name]=next[name]||"";next[name]=e.layouts[name];}
            own[name]=true;
        }
        // Forget owned outputs that are gone.
        const present=Quickshell.screens.map(s=>s.name);
        for(const name in own)if(present.indexOf(name)<0){delete own[name];delete next[name];}
        owned=own;
        Hub.sessionModes=next;
        return prior;
    }
    function onEvent(e) {
        if(e.event==="convergence") {
            if(!enabled)return;
            const prior=apply(e);
            if(e.initial||e.trigger==="")return;
            undoModes=prior;
            undoWindows=!!(e.windows&&e.windows.moved>0);
            undoRotation=-1;
            const detail=e.windows&&e.windows.error ? e.windows.error : (e.off&&e.off.length ? "Built-in display idle while the lid is closed" : "");
            // A new screen gets the docking card, not a second toast.
            if(e.trigger==="Hotplug"&&Hub.dockScreen&&(e.externalAdded||[]).indexOf(Hub.dockScreen.name)>=0) {
                if(Hub.dockMirrored)revertWindows();
                Hub.dockResult=Object.assign({},Hub.dockResult||{},{moved:!Hub.dockMirrored&&e.windows ? e.windows.moved||0 : 0,error:e.windows&&e.windows.error ? e.windows.error : ""});
                return;
            }
            show(e.text,detail);
        } else if(e.event==="windows") {
            if(e.error)Hub.message(e.error);
        }
    }
    function release() {
        const next=Object.assign({},Hub.sessionModes);
        for(const name in owned)delete next[name];
        Hub.sessionModes=next;owned=({});
    }
    onEnabledChanged:{if(enabled)sendTimer.restart();else{hide();release();}}
    Connections {target:Quickshell;function onScreensChanged(){sendTimer.restart();}}
    Connections {target:Hub;function onPrefsChanged(){sendTimer.restart();}}
    Connections {
        target:Hub
        function onOrientationChanged() {
            const previous=c.lastOrientation;c.lastOrientation=Hub.orientation;
            if(!c.enabled||Hub.prefs.convergeRotate===false||Hub.prefs.autoRotate===false||previous<0||Hub.orientation<0||previous===Hub.orientation)return;
            c.undoModes=({});c.undoWindows=false;c.undoRotation=previous;
            c.show(Hub.orientation%2===1 ? "Rotated to landscape" : "Rotated to portrait","");
        }
    }
    Timer {id:sendTimer;interval:700;onTriggered:c.pushState()}
    Timer {id:countdown;interval:100;repeat:true;onTriggered:{if(!hoverHold)c.remaining-=interval/8000;if(c.remaining<=0)c.hide();}}
    property bool hoverHold:false
    Process {
        id:service
        command:["python3",Qt.resolvedUrl("convergence_service.py").toString().replace("file://","")]
        running:c.enabled
        stdinEnabled:true
        stdout:SplitParser {
            onRead:line=>{try{c.onEvent(JSON.parse(line));}catch(error){}}
        }
        onRunningChanged:if(running)sendTimer.restart()
    }
    PanelWindow {
        screen:c.toastScreen
        visible:c.toastVisible
        anchors {bottom:true}
        margins {bottom:96}
        implicitWidth:Math.min(400,(c.toastScreen ? c.toastScreen.width : 400)-24);implicitHeight:c.toastDetail!=="" ? 100 : 72
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-convergence-toast"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        UndoToast {
            anchors.fill:parent;text:c.toastText;detail:c.toastDetail;remaining:c.remaining
            onUndo:c.undo()
            HoverHandler {onHoveredChanged:c.hoverHold=hovered}
        }
    }
}
