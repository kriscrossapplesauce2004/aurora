pragma Singleton
import QtQuick
import Quickshell

// Assistant conversation, desktop context and pending approvals. History lives in memory only.
Scope {
    id:s
    property var turns:[]
    property bool busy:false
    property int request:0
    property string lastText:""
    property var lastContext:({})
    property var approvals:[]
    // Ask: risky actions wait for Allow. Auto: Claude acts on its own and only dangerous commands still ask.
    readonly property string mode:Hub.prefs.assistantMode==="auto" ? "auto" : "ask"
    function setMode(next) {Hub.set("assistantMode",next);Hub.command({action:"assistant-mode",mode:next});}
    // Switching to auto while a card waits also lets that action through.
    onModeChanged:if(mode==="auto")approvals.filter(a=>a.risk!=="high").forEach(a=>approve(a.id,true))
    property bool available:true
    property bool jev:false
    // Context chips. The user can remove each one before sending.
    property string ctxApp:""
    property string ctxTitle:""
    property string ctxSelection:""
    property string ctxClipboard:""
    property bool useApp:true
    property bool useSelection:true
    property bool useClipboard:true
    readonly property var suggestions:[
        {icon:"spark",text:"What can you do here?",prompt:"What can you do for me in this desktop? Give a short list."},
        {icon:"desktop",text:"Summarize what I have open",prompt:"List my open windows and say in two lines what I seem to be working on."},
        {icon:"moon",text:"Switch to dark mode",prompt:"Switch the shell to dark mode."},
        {icon:"clipboard",text:"Explain my selection",prompt:"Explain the text I selected."}
    ]
    // Read the focused window before the panel takes focus. Selection and clipboard arrive from the backend.
    function capture() {
        const active=Hub.windows.find(w=>Hub.active(w));
        ctxApp=active ? (active.className||"") : "";ctxTitle=active ? (active.title||"") : "";
        ctxSelection="";ctxClipboard="";useApp=true;useSelection=true;useClipboard=true;
        Hub.command({action:"assistant-context"});
    }
    function contextPayload() {
        return {app:useApp ? ctxApp : "",title:useApp ? ctxTitle : "",selection:useSelection ? ctxSelection : "",clipboard:useClipboard ? ctxClipboard : ""};
    }
    function dispatch(text,context) {
        request++;lastText=text;lastContext=context;busy=true;
        turns=turns.concat([{role:"user",text:text},{role:"assistant",id:request,text:"",tools:[],done:false,error:false,stopped:false}]);
        Hub.command({action:"assistant-ask",text:text,id:request,context:context,mode:mode});
    }
    function send(text) {
        const t=(text||"").trim();if(!t||busy)return;
        const context=contextPayload();
        // Context goes once. The next question can add it again.
        ctxSelection="";ctxClipboard="";ctxApp="";ctxTitle="";
        dispatch(t,context);
    }
    function retry() {
        if(busy||turns.length<2||lastText==="")return;
        turns=turns.slice(0,turns.length-2);
        dispatch(lastText,lastContext);
    }
    function stop() {Hub.command({action:"assistant-stop"});busy=false;}
    function newChat() {
        Hub.command({action:"assistant-new"});
        turns=[];busy=false;approvals=[];lastText="";request++;
    }
    function approve(id,allow) {
        Hub.command({action:"assistant-approve",id:id,allow:allow});
        approvals=approvals.filter(a=>a.id!==id);
    }
    function copy(text) {Hub.command({action:"clipboard",text:text});}
    function ingest(e) {
        if(e.event==="assistant"&&e.id===request&&turns.length) {
            const list=turns.slice();
            list[list.length-1]=Object.assign({},list[list.length-1],{text:e.text||"",tools:e.tools||[],done:!!e.done,error:!!e.error,stopped:!!e.stopped});
            turns=list;
            if(e.done)busy=false;
        } else if(e.event==="assistantApprovals") approvals=e.items||[];
        else if(e.event==="assistantContext") {
            ctxSelection=e.selection||"";ctxClipboard=e.clipboard||"";available=e.available!==false;jev=!!e.jev;
        }
    }
}
