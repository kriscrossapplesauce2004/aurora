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
    readonly property var shown:order.slice(0,expanded ? order.length : 4).map(id=>tiles.find(t=>t.id===id))
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
        if(id==="clipboard")return Hub.clipboardItems.length+" saved this session";
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
        case "convergence":Hub.openSettings("display");break;
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
    ColumnLayout {visible:!deck.editing;Layout.fillWidth:true;spacing:8
        Repeater {model:deck.rows
            RowLayout {
                id:tileRow
                required property var modelData
                required property int index
                Layout.fillWidth:true;spacing:8
                // Rows cascade in one after another when the panel opens.
                property real enter:Theme.reduceMotion ? 1 : 0
                opacity:enter
                transform:Translate {y:(1-tileRow.enter)*14}
                SequentialAnimation on enter {
                    running:!Theme.reduceMotion
                    PauseAnimation {duration:60+tileRow.index*45}
                    NumberAnimation {to:1;duration:340;easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
                }
                Repeater {model:tileRow.modelData.tiles
                    ShadeTile {
                        required property var modelData
                        Layout.fillWidth:true;Layout.preferredWidth:1;implicitHeight:64
                        dense:true;iconOnly:!tileRow.modelData.wide
                        icon:modelData.icon;title:modelData.title;subtitle:deck.subtitle(modelData.id);active:deck.state(modelData.id)
                        settings:deck.hasPage(modelData.id)
                        enabled:deck.enabledFor(modelData.id);opacity:enabled ? 1 : .45
                        onToggled:deck.toggle(modelData.id)
                        onClicked:if(settings)Hub.settings(modelData.id==="wifi" ? "network" : "bluetooth");else deck.toggle(modelData.id)
                        onOpenSettings:Hub.settings(modelData.id==="wifi" ? "network" : "bluetooth")
                    }
                }
                // A short last row keeps tile sizes consistent with full rows.
                Repeater {model:Math.max(0,(tileRow.modelData.wide ? 2 : 4)-tileRow.modelData.tiles.length)
                    Item {Layout.fillWidth:true;Layout.preferredWidth:1;implicitHeight:64}
                }
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
