import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id:deck
    property bool editing:false
    property bool expanded:true
    readonly property var defaults:["wifi","bluetooth","dnd","awake","theme","saver","mic","keyboard"]
    readonly property var tiles:[
        {id:"wifi",title:"Internet",icon:"wifi"}, {id:"bluetooth",title:"Bluetooth",icon:"bluetooth"},
        {id:"dnd",title:"Do not disturb",icon:"quiet"}, {id:"awake",title:"Keep awake",icon:"coffee"},
        {id:"theme",title:"Dark theme",icon:"moon"}, {id:"saver",title:"Battery saver",icon:"battery"},
        {id:"mic",title:"Microphone",icon:"mic"}, {id:"keyboard",title:"Keyboard",icon:"keyboard"},
        {id:"motion",title:"Reduced motion",icon:"spark"}, {id:"capture",title:"Screenshot",icon:"capture"},
        {id:"autohide",title:"Auto-hide shelf",icon:"desktop"}, {id:"clipboard",title:"Clipboard",icon:"clipboard"},
        {id:"focus",title:"Focus timer",icon:"timer"}, {id:"convergence",title:"Displays",icon:"convergence"}
    ]
    readonly property var order:(Hub.prefs.quickTiles||defaults).filter(id=>tiles.some(t=>t.id===id))
    readonly property var shown:order.map(id=>tiles.find(t=>t.id===id))
    // A tile with a page asks the sheet to grow that page out of the tile.
    signal pageRequested(string id, Item source)
    function openPage(id,source) {deck.pageRequested(id,source);}
    function state(id) {
        switch(id) {
        case "wifi":return !!Hub.status.wifi;
        case "bluetooth":return !!Hub.status.bluetooth;
        case "dnd":return Hub.dnd;
        case "awake":return Hub.keepAwake||Hub.gameSession;
        case "theme":return !Theme.light;
        case "saver":return Hub.status.profile==="power-saver";
        case "mic":return !Hub.status.micMuted;
        case "keyboard":return Hub.systemOskVisible;
        case "motion":return Theme.reduceMotion;
        case "autohide":return !!Hub.prefs.taskbarAutoHide;
        case "focus":return Hub.focusRunning;
        default:return false;
        }
    }
    function subtitle(id) {
        if(id==="wifi")return Hub.status.wifi ? Hub.status.network : "Off";
        if(id==="bluetooth") {const device=Hub.connectivity.bluetooth.items.find(d=>d.active);return device ? device.name : state(id) ? "On" : "Off";}
        if(id==="keyboard")return Hub.systemOskAvailable ? state(id) ? "Visible" : "Ready" : "Unavailable";
        if(id==="saver"&&!Hub.status.profile)return "Unavailable";
        if(id==="capture")return "Capture screen";
        if(id==="clipboard")return Hub.clipboardItems.length+" items";
        if(id==="convergence")return "Layout & docking";
        if(id==="focus")return Math.ceil(Hub.focusSeconds/60)+" minutes";
        return state(id) ? "On" : "Off";
    }
    function toggle(id) {
        switch(id) {
        case "wifi":Hub.connection("wifi","power",{enabled:!(Hub.connectivity.wifi.powered||Hub.status.wifi)});break;
        case "bluetooth":Hub.connection("bluetooth","power",{enabled:!(Hub.connectivity.bluetooth.powered||Hub.status.bluetooth)});break;
        case "dnd":if(Hub.gameSession)Hub.toggleGameSession();else Hub.set("dnd",!Hub.dnd);break;
        case "awake":if(Hub.gameSession)Hub.toggleGameSession();else Hub.keepAwake=!Hub.keepAwake;break;
        case "theme":Hub.set("light",!Theme.light);break;
        case "saver":if(Hub.status.profile)Hub.command({action:"profile",value:state(id) ? "balanced" : "power-saver"});break;
        case "mic":Hub.command({action:"mic"});break;
        case "keyboard":if(Hub.systemOskAvailable)Hub.systemOsk("toggle");break;
        case "motion":Hub.set("reduceMotion",!Theme.reduceMotion);break;
        case "capture":Hub.screenShot();break;
        case "autohide":Hub.set("taskbarAutoHide",!Hub.prefs.taskbarAutoHide);break;
        case "clipboard":Hub.toggleClipboard();break;
        case "focus":Hub.timerToggle();break;
        case "convergence":Hub.openSettings("displays");break;
        }
    }
    function change(id) {let next=order.slice();const index=next.indexOf(id);if(index>=0)next.splice(index,1);else next.push(id);Hub.set("quickTiles",next);}
    function move(id,delta) {let next=order.slice();const index=next.indexOf(id),dest=index+delta;if(index<0||dest<0||dest>=next.length)return;next.splice(index,1);next.splice(dest,0,id);Hub.set("quickTiles",next);}
    spacing:6
    RowLayout {visible:deck.editing;Layout.fillWidth:true
        MText {text:deck.editing ? "Make it yours" : "Quick settings";font.pixelSize:14;font.weight:Font.DemiBold;Layout.fillWidth:true}
        MButton {text:deck.editing ? "Done" : "Edit";compact:true;tonal:true;onClicked:deck.editing=!deck.editing}
        MButton {visible:!deck.editing;text:deck.expanded ? "Less" : "More";compact:true;onClicked:deck.expanded=!deck.expanded}
    }
    // Pixel pattern: two wide rows, then one row of four round tiles, then repeat.
    readonly property var rows:{
        const pattern=[2,2,4],out=[];let index=0,step=0;
        while(index<deck.shown.length){const size=pattern[step%pattern.length];out.push({wide:size===2,tiles:deck.shown.slice(index,index+size)});index+=size;step++;}
        return out;
    }
    function enabledFor(id) {return !(id==="keyboard"&&!Hub.systemOskAvailable||id==="saver"&&!Hub.status.profile);}
    function hasPage(id) {return id==="wifi"||id==="bluetooth";}
    // Morph: 0 is one row of round tiles, 1 is the full grid. Each tile moves on its own path between the two places.
    property real t:1
    property int collapsedCount:6
    readonly property real gap:8
    readonly property real rowH:64
    readonly property real roundSize:Math.min(56,(width-gap*(collapsedCount-1))/collapsedCount)
    // Places in the full grid, row by row, with the same pattern as before: two wide, two wide, four round.
    readonly property var gridRects:{
        const out=[];let y=0;
        for(const row of deck.rows){
            const n=row.wide ? 2 : 4;const w=(deck.width-gap*(n-1))/n;
            row.tiles.forEach((tile,i)=>out.push({x:i*(w+gap),y:y,w:w,h:rowH,wide:row.wide}));
            y+=rowH+gap;
        }
        return out;
    }
    readonly property real gridHeight:deck.rows.length ? deck.rows.length*(rowH+gap)-gap : 0
    readonly property real rowWidth:Math.min(collapsedCount,deck.shown.length)*(roundSize+gap)-gap
    Item {
        id:morphArea
        visible:!deck.editing
        // Tiles that are still arriving stay inside the growing area.
        clip:deck.t<1
        Layout.fillWidth:true
        Layout.preferredHeight:deck.roundSize+(deck.gridHeight-deck.roundSize)*deck.t
        Repeater {
            model:deck.shown
            ShadeTile {
                id:tile
                required property var modelData
                required property int index
                readonly property var grid:deck.gridRects[index]||{x:0,y:0,w:deck.roundSize,h:deck.rowH,wide:false}
                readonly property bool inRow:index<deck.collapsedCount
                readonly property real rowX:(deck.width-deck.rowWidth)/2+index*(deck.roundSize+deck.gap)
                readonly property real k:deck.t
                x:inRow ? rowX+(grid.x-rowX)*k : grid.x
                y:inRow ? grid.y*k : grid.y
                width:inRow ? deck.roundSize+(grid.w-deck.roundSize)*k : grid.w
                height:inRow ? deck.roundSize+(grid.h-deck.roundSize)*k : grid.h
                // Tiles that are not in the short row arrive as the grid opens.
                opacity:(inRow ? 1 : Math.max(0,(k-.45)/.55))*(enabled ? 1 : .45)
                scale:inRow ? 1 : .92+.08*k
                visible:opacity>0.01
                dense:true;iconOnly:!grid.wide||k<.6
                icon:modelData.icon;title:modelData.title;subtitle:deck.subtitle(modelData.id);active:deck.state(modelData.id)
                settings:deck.hasPage(modelData.id)&&k>.6
                enabled:deck.enabledFor(modelData.id)
                onToggled:deck.toggle(modelData.id)
                onClicked:if(deck.hasPage(modelData.id))deck.openPage(modelData.id,tile);else deck.toggle(modelData.id)
                onOpenSettings:deck.openPage(modelData.id,tile)
            }
        }
    }
    ColumnLayout {visible:deck.editing;Layout.fillWidth:true;spacing:6
        MText {Layout.fillWidth:true;text:"Add or remove tiles. The first four appear in the compact view.";wrapMode:Text.Wrap;color:Theme.subtext;font.pixelSize:12}
        Repeater {model:deck.order.map(id=>deck.tiles.find(t=>t.id===id)).concat(deck.tiles.filter(t=>deck.order.indexOf(t.id)<0))
            RowLayout {required property var modelData;Layout.fillWidth:true;spacing:4
                MButton {Layout.fillWidth:true;text:modelData.title;icon:deck.order.indexOf(modelData.id)>=0 ? "check" : "add";tonal:true;onClicked:deck.change(modelData.id)}
                MButton {visible:deck.order.indexOf(modelData.id)>=0;icon:"back";tooltip:"Move earlier";enabled:deck.order.indexOf(modelData.id)>0;onClicked:deck.move(modelData.id,-1)}
                MButton {visible:deck.order.indexOf(modelData.id)>=0;icon:"next";tooltip:"Move later";enabled:deck.order.indexOf(modelData.id)<deck.order.length-1;onClicked:deck.move(modelData.id,1)}
            }
        }
        MButton {text:"Reset tiles";onClicked:Hub.set("quickTiles",deck.defaults.slice())}
    }
}
