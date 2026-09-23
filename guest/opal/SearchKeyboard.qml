import QtQuick
import QtQuick.Layouts

Rectangle {
    id:k
    property bool controllerMode:false
    property bool shift:false
    property bool capsLock:false
    property bool numbers:false
    property int selection:0
    property var inputTarget:null
    property string contextLabel:"Search"
    property string returnLabel:"Search"
    property bool secureInput:false
    readonly property bool narrow:width<370
    readonly property real keyGap:narrow ? 3 : 5
    readonly property real rowGap:narrow ? 4 : 6
    readonly property real sidePadding:narrow ? 7 : 10
    readonly property var rows:numbers ? [
        "1234567890".split(""),
        ["@","#","$","%","&","-","+","(",")","/"],
        ["ABC","*",'"',"'",":",";","!","?","⌫"],
        ["=","<",">","SPACE","_","LEFT","RIGHT","DONE"]
    ] : [
        "qwertyuiop".split(""),
        "asdfghjkl".split(""),
        ["SHIFT","z","x","c","v","b","n","m","⌫"],
        ["123",",","SPACE",".","LEFT","RIGHT","DONE"]
    ]
    readonly property var rowOffsets:rows.reduce((offsets,row,index)=>{offsets.push(index ? offsets[index-1]+rows[index-1].length : 0);return offsets;},[])
    readonly property var keys:rows.reduce((all,row)=>all.concat(row),[])
    readonly property var upSelections:rows.reduce((all,row,r)=>all.concat(row.map((key,c)=>{
        const target=Math.max(0,r-1);
        return rowOffsets[target]+Math.min(rows[target].length-1,Math.floor((c+.5)*rows[target].length/row.length));
    })),[])
    readonly property var downSelections:rows.reduce((all,row,r)=>all.concat(row.map((key,c)=>{
        const target=Math.min(rows.length-1,r+1);
        return rowOffsets[target]+Math.min(rows[target].length-1,Math.floor((c+.5)*rows[target].length/row.length));
    })),[])
    signal insert(string text)
    signal erase()
    signal accept()
    signal dismiss()
    implicitHeight:controllerMode ? 318 : narrow ? 272 : 286
    radius:narrow ? 24 : 28
    color:Theme.alpha(Theme.surface,.96)
    border.width:1
    border.color:Theme.outline
    clip:false

    function keyWeight(value) {
        if(value==="SPACE")return narrow ? 2.65 : 3.8;
        if(value==="DONE")return narrow ? 1.4 : 1.65;
        if(value==="SHIFT"||value==="⌫"||value==="ABC"||value==="123")return 1.35;
        if(value==="LEFT"||value==="RIGHT")return narrow ? .90 : 1.05;
        return 1;
    }
    function keyGlyph(value) {
        if(value==="SHIFT")return capsLock ? "keyboard_capslock" : "shift";
        if(value==="⌫")return "backspace";
        if(value==="SPACE")return "space_bar";
        if(value==="LEFT")return "arrow_left_alt";
        if(value==="RIGHT")return "arrow_right_alt";
        return "";
    }
    function keyLabel(value) {
        if(value==="DONE")return returnLabel;
        if(value==="ABC"||value==="123")return value;
        if(value.length===1&&/[a-z]/.test(value))return shift||capsLock ? value.toUpperCase() : value;
        return value;
    }
    function isRegional(cp) {return cp>=0x1f1e6&&cp<=0x1f1ff;}
    function isExtend(cp) {
        return (cp>=0x0300&&cp<=0x036f)||(cp>=0x1ab0&&cp<=0x1aff)||(cp>=0x1dc0&&cp<=0x1dff)||(cp>=0x20d0&&cp<=0x20ff)||(cp>=0xfe00&&cp<=0xfe0f)||(cp>=0xfe20&&cp<=0xfe2f)||(cp>=0x1f3fb&&cp<=0x1f3ff)||(cp>=0xe0100&&cp<=0xe01ef);
    }
    function codePointAtIndex(text,index) {
        const first=text.charCodeAt(index);
        if(first>=0xd800&&first<=0xdbff&&index+1<text.length) {
            const second=text.charCodeAt(index+1);
            if(second>=0xdc00&&second<=0xdfff)return ((first-0xd800)<<10)+(second-0xdc00)+0x10000;
        }
        return first;
    }
    function previousCodePointStart(text,index) {
        let start=Math.max(0,index-1);
        if(start>0) {
            const unit=text.charCodeAt(start);
            if(unit>=0xdc00&&unit<=0xdfff)start--;
        }
        return start;
    }
    function nextCodePointEnd(text,index) {
        if(index>=text.length)return text.length;
        const first=text.charCodeAt(index);
        return first>=0xd800&&first<=0xdbff&&index+1<text.length ? index+2 : index+1;
    }
    function previousBoundary(text,index) {
        if(index<=0)return 0;
        let start=previousCodePointStart(text,index);
        while(start>0&&isExtend(codePointAtIndex(text,start)))start=previousCodePointStart(text,start);
        while(start>0) {
            const previous=previousCodePointStart(text,start);
            const previousCp=codePointAtIndex(text,previous);
            if(previousCp===0x200d) {
                start=previous;
                if(start>0)start=previousCodePointStart(text,start);
                while(start>0&&isExtend(codePointAtIndex(text,start)))start=previousCodePointStart(text,start);
                continue;
            }
            if(isRegional(codePointAtIndex(text,start))&&isRegional(previousCp))start=previous;
            break;
        }
        return start;
    }
    function nextBoundary(text,index) {
        if(index>=text.length)return text.length;
        let end=nextCodePointEnd(text,index);
        while(end<text.length&&isExtend(codePointAtIndex(text,end)))end=nextCodePointEnd(text,end);
        while(end<text.length&&codePointAtIndex(text,end)===0x200d) {
            end=nextCodePointEnd(text,end);
            if(end<text.length)end=nextCodePointEnd(text,end);
            while(end<text.length&&isExtend(codePointAtIndex(text,end)))end=nextCodePointEnd(text,end);
        }
        return end;
    }
    function selectionRange() {
        if(!inputTarget)return {start:0,end:0};
        const a=inputTarget.selectionStart===undefined ? inputTarget.cursorPosition : inputTarget.selectionStart;
        const b=inputTarget.selectionEnd===undefined ? inputTarget.cursorPosition : inputTarget.selectionEnd;
        return {start:Math.max(0,Math.min(a,b)),end:Math.max(0,Math.max(a,b))};
    }
    function refocusTarget() {
        if(inputTarget&&inputTarget.forceActiveFocus)Qt.callLater(()=>inputTarget.forceActiveFocus());
    }
    function insertIntoTarget(text) {
        if(!inputTarget||!inputTarget.insert)return false;
        const range=selectionRange();
        if(range.end>range.start)inputTarget.remove(range.start,range.end);
        inputTarget.insert(range.start,text);
        inputTarget.cursorPosition=range.start+text.length;
        refocusTarget();
        return true;
    }
    function eraseFromTarget() {
        if(!inputTarget||!inputTarget.remove)return false;
        const range=selectionRange();
        if(range.end>range.start) {
            inputTarget.remove(range.start,range.end);
            inputTarget.cursorPosition=range.start;
        } else if(inputTarget.cursorPosition>0) {
            const end=inputTarget.cursorPosition;
            const start=previousBoundary(inputTarget.text,end);
            inputTarget.remove(start,end);
            inputTarget.cursorPosition=start;
        }
        refocusTarget();
        return true;
    }
    function moveCursor(direction) {
        if(!inputTarget)return;
        const range=selectionRange();
        if(range.end>range.start)inputTarget.cursorPosition=direction<0 ? range.start : range.end;
        else inputTarget.cursorPosition=direction<0 ? previousBoundary(inputTarget.text,inputTarget.cursorPosition) : nextBoundary(inputTarget.text,inputTarget.cursorPosition);
        refocusTarget();
    }
    function performErase() {
        eraseFromTarget();
        erase();
    }
    function beginBackspace() {
        performErase();
        repeatDelay.restart();
    }
    function endBackspace() {
        repeatDelay.stop();
        repeatPulse.stop();
    }
    function toggleCaps() {
        capsLock=!capsLock;
        shift=capsLock;
    }
    function press(value) {
        if(value==="CLOSE")dismiss();
        else if(value==="DONE")accept();
        else if(value==="⌫")performErase();
        else if(value==="LEFT")moveCursor(-1);
        else if(value==="RIGHT")moveCursor(1);
        else if(value==="SHIFT") {
            if(capsLock){capsLock=false;shift=false;}else shift=!shift;
        }
        else if(value==="123"||value==="ABC") {numbers=!numbers;selection=0;}
        else {
            const text=value==="SPACE" ? " " : shift||capsLock ? value.toUpperCase() : value;
            insertIntoTarget(text);
            insert(text);
            if(shift&&!capsLock)shift=false;
        }
    }
    function navigation(direction) {
        const index=Math.min(selection,keys.length-1);
        const key=keys[index];
        if(direction==="accept") {press(key);return;}
        if(direction==="back") {dismiss();return;}
        if(direction==="left")selection=Math.max(0,selection-1);
        if(direction==="right")selection=Math.min(keys.length-1,selection+1);
        if(direction==="up")selection=upSelections[index];
        if(direction==="down")selection=downSelections[index];
    }
    onVisibleChanged:if(!visible)endBackspace()
    onInputTargetChanged:endBackspace()
    Component.onDestruction:endBackspace()

    Timer {id:repeatDelay;interval:360;repeat:false;onTriggered:{k.performErase();repeatPulse.start();}}
    Timer {id:repeatPulse;interval:54;repeat:true;onTriggered:k.performErase()}

    ColumnLayout {
        anchors {fill:parent;margins:k.sidePadding}
        spacing:k.rowGap
        RowLayout {
            Layout.fillWidth:true
            Layout.preferredHeight:k.narrow ? 27 : 31
            spacing:8
            Rectangle {
                Layout.preferredWidth:k.narrow ? 27 : 31;Layout.preferredHeight:width;radius:height/2
                color:Theme.alpha(Theme.primaryContainer,.72)
                Glyph {anchors.centerIn:parent;name:"keyboard";font.pixelSize:k.narrow ? 16 : 18;color:Theme.onContainer}
            }
            ColumnLayout {
                Layout.fillWidth:true;spacing:0
                MText {text:k.contextLabel;font.pixelSize:k.narrow ? 11 : 12;font.weight:Font.DemiBold;Layout.fillWidth:true}
                MText {visible:!k.narrow;text:k.controllerMode ? "D-pad · A type · B close" : k.capsLock ? "CAPS LOCK" : k.numbers ? "Symbols & numbers" : "QWERTY";font.pixelSize:9;color:k.capsLock ? Theme.primary : Theme.subtext;Layout.fillWidth:true}
            }
            Rectangle {
                visible:k.capsLock||k.shift
                Layout.preferredWidth:k.narrow ? 34 : 44;Layout.preferredHeight:k.narrow ? 24 : 27;radius:height/2
                color:k.capsLock ? Theme.primary : Theme.primaryContainer
                MText {anchors.centerIn:parent;text:k.capsLock ? "CAPS" : "⇧";font.pixelSize:9;font.weight:Font.Bold;color:k.capsLock ? Theme.onPrimary : Theme.onContainer}
            }
            Rectangle {
                id:hideKey
                Layout.preferredWidth:k.narrow ? 31 : 35;Layout.preferredHeight:width;radius:height/2
                color:hideMouse.pressed ? Theme.primaryContainer : Theme.alpha(Theme.surfaceHigh,.72)
                scale:hideMouse.pressed ? .92 : 1
                Behavior on scale {NumberAnimation {duration:Theme.motion(90)}}
                Glyph {anchors.centerIn:parent;name:"keyboard_hide";font.pixelSize:k.narrow ? 17 : 19;color:Theme.subtext}
                MouseArea {id:hideMouse;anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:k.dismiss()}
                Accessible.role:Accessible.Button
                Accessible.name:"Hide keyboard"
            }
        }
        Repeater {
            model:k.rows
            RowLayout {
                id:keyRow
                required property var modelData
                required property int index
                Layout.fillWidth:true
                Layout.fillHeight:true
                Layout.leftMargin:index===1&&!k.numbers ? (k.narrow ? 9 : 16) : 0
                Layout.rightMargin:Layout.leftMargin
                spacing:k.keyGap
                Repeater {
                    model:keyRow.modelData
                    Rectangle {
                        id:keyCap
                        required property string modelData
                        required property int index
                        property int keyIndex:k.rowOffsets[keyRow.index]+index
                        property bool controllerSelected:k.controllerMode&&k.selection===keyIndex
                        property bool actionKey:modelData==="DONE"
                        property bool modifierKey:modelData==="SHIFT"||modelData==="123"||modelData==="ABC"||modelData==="⌫"||modelData==="LEFT"||modelData==="RIGHT"
                        property bool heldAction:false
                        readonly property bool activeShift:modelData==="SHIFT"&&(k.shift||k.capsLock)
                        Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumWidth:0
                        Layout.preferredWidth:48*k.keyWeight(modelData)
                        radius:keyMouse.pressed ? Math.min(13,height*.27) : actionKey ? Math.min(18,height*.38) : activeShift ? Math.min(16,height*.34) : Math.min(12,height*.25)
                        color:controllerSelected||actionKey ? Theme.primary : activeShift ? Theme.primaryContainer : keyMouse.pressed ? Theme.alpha(Theme.primaryContainer,.88) : modifierKey ? Theme.alpha(Theme.surfaceHigh,.92) : Theme.alpha(Theme.surfaceHigh,.68)
                        border.width:controllerSelected ? 2 : 1
                        border.color:controllerSelected ? Theme.onPrimary : Theme.alpha(Theme.text,.06)
                        scale:keyMouse.pressed ? .95 : 1
                        Behavior on radius {NumberAnimation {duration:Theme.motion(120);easing.type:Easing.OutCubic}}
                        Behavior on color {ColorAnimation {duration:Theme.motion(100)}}
                        Behavior on scale {NumberAnimation {duration:Theme.motion(85);easing.type:Easing.OutCubic}}
                        Glyph {
                            visible:k.keyGlyph(keyCap.modelData)!==""
                            anchors.centerIn:parent
                            name:k.keyGlyph(keyCap.modelData)
                            font.pixelSize:k.narrow ? 18 : 20
                            color:keyCap.controllerSelected||keyCap.actionKey ? Theme.onPrimary : keyCap.activeShift ? Theme.onContainer : Theme.text
                        }
                        MText {
                            visible:k.keyGlyph(keyCap.modelData)===""
                            anchors.centerIn:parent
                            text:k.keyLabel(keyCap.modelData)
                            font.pixelSize:keyCap.actionKey ? (k.narrow ? 10 : 11) : keyCap.modelData==="ABC"||keyCap.modelData==="123" ? 10 : k.narrow ? 15 : 17
                            font.weight:keyCap.actionKey||keyCap.modifierKey ? Font.DemiBold : Font.Medium
                            color:keyCap.controllerSelected||keyCap.actionKey ? Theme.onPrimary : keyCap.activeShift ? Theme.onContainer : Theme.text
                        }
                        Rectangle {
                            visible:keyMouse.pressed&&!k.controllerMode&&!k.secureInput&&keyCap.modelData.length===1&&!keyCap.modifierKey
                            anchors.horizontalCenter:parent.horizontalCenter
                            y:-height-5;z:20;width:Math.max(42,keyCap.width);height:48;radius:16
                            color:Theme.primaryContainer;border.width:1;border.color:Theme.outline
                            MText {anchors.centerIn:parent;text:k.keyLabel(keyCap.modelData);font.pixelSize:24;font.weight:Font.DemiBold;color:Theme.onContainer}
                        }
                        MouseArea {
                            id:keyMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                            onPressed:{keyCap.heldAction=false;if(keyCap.modelData==="⌫")k.beginBackspace();}
                            onReleased:if(keyCap.modelData==="⌫")k.endBackspace()
                            onCanceled:if(keyCap.modelData==="⌫")k.endBackspace()
                            onExited:if(pressed&&keyCap.modelData==="⌫")k.endBackspace()
                            onPressAndHold:{if(keyCap.modelData==="SHIFT"){keyCap.heldAction=true;k.toggleCaps();}}
                            onClicked:{if(keyCap.modelData!=="⌫"&&!keyCap.heldAction)k.press(keyCap.modelData);}
                        }
                        Accessible.role:Accessible.Button
                        Accessible.name:keyCap.modelData==="⌫" ? "Backspace" : keyCap.modelData==="SHIFT" ? "Shift" : keyCap.modelData==="SPACE" ? "Space" : keyCap.modelData==="LEFT" ? "Move cursor left" : keyCap.modelData==="RIGHT" ? "Move cursor right" : keyCap.modelData==="DONE" ? k.returnLabel : k.keyLabel(keyCap.modelData)
                    }
                }
            }
        }
    }
}
