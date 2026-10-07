import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The Claude assistant: conversation, what it did, confirmations and a composer with Ask or Auto. Desktop, phone and console share it.
Item {
    id:panel
    property string layoutMode:"desktop"
    readonly property bool phone:layoutMode==="phone"
    readonly property bool couch:layoutMode==="console"
    readonly property var turns:AssistantState.turns
    readonly property bool auto:AssistantState.mode==="auto"
    readonly property var lastTurn:turns.length ? turns[turns.length-1] : null
    readonly property var liveStep:{
        if(!AssistantState.busy||!lastTurn||lastTurn.role!=="assistant")return null;
        const r=(lastTurn.tools||[]).filter(t=>t.status==="running");return r.length ? r[r.length-1] : null;
    }
    readonly property bool hasContext:(AssistantState.ctxApp!==""&&AssistantState.useApp)||(AssistantState.ctxSelection!==""&&AssistantState.useSelection)||(AssistantState.ctxClipboard!==""&&AssistantState.useClipboard)
    readonly property real pad:couch ? 28 : phone ? 16 : 20
    readonly property int bodySize:couch ? 17 : 14
    property int suggestIndex:0
    property alias input:field
    readonly property string acceptButton:Hub.prefs.controllerLayout==="nintendo" ? "B" : "A"
    readonly property string backButton:Hub.prefs.controllerLayout==="nintendo" ? "A" : "B"
    function submit() {
        if(AssistantState.busy||field.text.trim()==="")return;
        AssistantState.send(field.text);field.text="";
    }
    // Qt draws markdown links in a fixed blue that is unreadable on dark panels, so links show as bold text with the address in code.
    function plainLinks(text) {return text.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g,"**$1** (`$2`)");}
    function follow() {chat.positionViewAtEnd();}
    onTurnsChanged:Qt.callLater(follow)
    // Controller: up and down pick a suggestion, accept answers a confirmation or sends it, back declines or closes.
    Connections {
        target:Hub
        enabled:Hub.page==="assistant"&&panel.couch
        function onNavigate(key) {
            const pending=AssistantState.approvals;
            if(key==="accept") {
                if(pending.length)AssistantState.approve(pending[0].id,true);
                else if(turns.length===0)AssistantState.send(AssistantState.suggestions[panel.suggestIndex].prompt);
            } else if(key==="back") {
                if(pending.length)AssistantState.approve(pending[0].id,false);
                else if(AssistantState.busy)AssistantState.stop();
                else Hub.close();
            } else if(key==="down") {
                if(turns.length===0)panel.suggestIndex=Math.min(AssistantState.suggestions.length-1,panel.suggestIndex+1);
                else chat.contentY=Math.min(Math.max(0,chat.contentHeight-chat.height),chat.contentY+160);
            } else if(key==="up") {
                if(turns.length===0)panel.suggestIndex=Math.max(0,panel.suggestIndex-1);
                else chat.contentY=Math.max(0,chat.contentY-160);
            } else if(key==="menu")AssistantState.newChat();
            else if(key==="alternate")AssistantState.setMode(panel.auto ? "ask" : "auto");
        }
    }

    ColumnLayout {
        anchors {fill:parent;leftMargin:panel.pad;rightMargin:panel.pad;topMargin:panel.pad-4;bottomMargin:panel.pad}
        spacing:12

        // Header: who, what it is doing now, new chat and close.
        RowLayout {
            Layout.fillWidth:true;spacing:12
            Flower {
                Layout.preferredWidth:38;Layout.preferredHeight:38;fill:Theme.primary;lobes:8
                RotationAnimation on rotation {running:AssistantState.busy&&!Theme.reduceMotion;from:0;to:360;duration:6000;loops:Animation.Infinite}
                Glyph {anchors.centerIn:parent;name:"spark";color:Theme.onPrimary;font.pixelSize:20;rotation:-parent.rotation}
            }
            ColumnLayout {
                Layout.fillWidth:true;spacing:0
                MText {text:"Claude";role:"titleS"}
                MText {
                    Layout.fillWidth:true;role:"labelS";elide:Text.ElideRight
                    color:!AssistantState.available ? Theme.error : AssistantState.busy ? Theme.primary : Theme.subtext
                    text:!AssistantState.available ? "Claude Code is not installed"
                        : panel.liveStep ? panel.liveStep.running+"…"
                        : AssistantState.busy ? (panel.lastTurn&&panel.lastTurn.text ? "Writing…" : "Thinking…")
                        : panel.auto ? "Auto · acts on its own" : "Asks before it changes things"
                }
            }
            MButton {icon:"edit_square";compact:true;implicitWidth:38;implicitHeight:38;tooltip:"New chat";enabled:turns.length>0||AssistantState.busy;onClicked:AssistantState.newChat()}
            MButton {icon:"close";compact:true;implicitWidth:38;implicitHeight:38;tooltip:"Close · Escape";onClicked:Hub.close()}
        }

        Item {
            Layout.fillWidth:true;Layout.fillHeight:true
            ListView {
                id:chat
                anchors.fill:parent;clip:true;spacing:18;model:panel.turns;boundsBehavior:Flickable.StopAtBounds
                visible:panel.turns.length>0
                ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
                onContentHeightChanged:if(AssistantState.busy&&!moving)positionViewAtEnd()
                footer:Item {width:1;height:8}
                delegate:Item {
                    id:row
                    required property var modelData
                    required property int index
                    readonly property bool mine:modelData.role==="user"
                    readonly property bool last:index===panel.turns.length-1
                    readonly property var tools:modelData.tools||[]
                    width:chat.width-8
                    height:mine ? bubble.height : answer.implicitHeight
                    // The user's words: a soft bubble on the right with a tight corner toward the edge.
                    Rectangle {
                        id:bubble
                        visible:row.mine;anchors.right:parent.right
                        width:Math.min(row.width*.82,userText.implicitWidth+32);height:userText.implicitHeight+22
                        radius:20;bottomRightRadius:6;color:Theme.secondaryContainer
                        MText {
                            id:userText;x:16;y:11;width:Math.min(row.width*.82-32,implicitWidth)
                            text:row.modelData.text;wrapMode:Text.Wrap;color:Theme.onSecondaryContainer;font.pixelSize:panel.bodySize
                        }
                    }
                    ColumnLayout {
                        id:answer
                        visible:!row.mine;width:parent.width;spacing:10
                        AssistantSteps {
                            Layout.fillWidth:true
                            visible:row.tools.length>0
                            steps:row.tools;live:!row.modelData.done
                        }
                        // Waiting before the first word: three soft dots.
                        Row {
                            visible:!row.modelData.done&&row.modelData.text===""&&!row.tools.some(t=>t.status==="running")
                            spacing:6;topPadding:4;bottomPadding:4
                            Repeater {
                                model:3
                                Rectangle {
                                    required property int index
                                    width:8;height:8;radius:4;color:Theme.primary
                                    SequentialAnimation on opacity {
                                        running:!Theme.reduceMotion;loops:Animation.Infinite
                                        PauseAnimation {duration:index*160}
                                        NumberAnimation {from:.25;to:1;duration:360}
                                        NumberAnimation {from:1;to:.25;duration:360}
                                        PauseAnimation {duration:(2-index)*160}
                                    }
                                }
                            }
                        }
                        Text {
                            visible:row.modelData.text!==""
                            Layout.fillWidth:true;wrapMode:Text.Wrap
                            textFormat:Text.MarkdownText;text:panel.plainLinks(row.modelData.text)
                            color:row.modelData.error ? Theme.error : Theme.text;linkColor:Theme.primary
                            font.family:Theme.font;font.pixelSize:panel.bodySize;lineHeight:1.18;renderType:Text.NativeRendering
                            onLinkActivated:link=>{if(/^https?:\/\//.test(link))Qt.openUrlExternally(link);}
                        }
                        RowLayout {
                            visible:!!row.modelData.done;spacing:2
                            MText {visible:!!row.modelData.stopped;text:"Stopped";role:"labelS";color:Theme.subtext;Layout.rightMargin:6}
                            MButton {visible:row.modelData.text!=="";icon:"content_copy";compact:true;implicitWidth:34;implicitHeight:34;tooltip:"Copy answer";onClicked:AssistantState.copy(row.modelData.text)}
                            MButton {visible:row.last&&!AssistantState.busy;icon:"refresh";compact:true;implicitWidth:34;implicitHeight:34;tooltip:"Ask again";onClicked:AssistantState.retry()}
                        }
                    }
                }
            }
            // First open: a short welcome and suggestions as chips.
            ColumnLayout {
                visible:panel.turns.length===0
                anchors.fill:parent;spacing:10
                Item {Layout.fillHeight:true}
                MText {text:"What can I do for you?";role:"headline";Layout.fillWidth:true;wrapMode:Text.Wrap}
                MText {
                    Layout.fillWidth:true;Layout.bottomMargin:6;wrapMode:Text.Wrap;role:"bodyS";color:Theme.subtext
                    text:panel.auto ? "I can open apps, move windows, read your screen and use your apps. In Auto I act on my own and only stop to ask before dangerous commands."
                                    : "I can open apps, move windows, read your screen and use your apps. I ask before I close windows, run commands or change files."
                }
                Repeater {
                    model:AssistantState.suggestions
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool picked:panel.couch&&panel.suggestIndex===index
                        Layout.fillWidth:true;Layout.preferredHeight:panel.couch ? 56 : 48;radius:height/2
                        color:picked ? Theme.primaryContainer : Theme.alpha(Theme.level(2),.9)
                        border.width:picked ? 2 : 1;border.color:picked ? Theme.primary : Theme.outline
                        RowLayout {
                            anchors {fill:parent;leftMargin:16;rightMargin:16} spacing:12
                            Glyph {name:modelData.icon;font.pixelSize:20;color:Theme.primary}
                            MText {text:modelData.text;Layout.fillWidth:true;font.pixelSize:panel.couch ? 16 : 14;elide:Text.ElideRight}
                            Glyph {name:"arrow_forward";font.pixelSize:18;color:Theme.subtext}
                        }
                        HoverHandler {cursorShape:Qt.PointingHandCursor}
                        TapHandler {onTapped:AssistantState.send(modelData.prompt)}
                        Accessible.role:Accessible.Button;Accessible.name:modelData.text
                    }
                }
            }
        }

        // Confirmations wait above the composer.
        Repeater {
            model:AssistantState.approvals
            Rectangle {
                required property var modelData
                readonly property bool high:modelData.risk==="high"
                Layout.fillWidth:true;Layout.preferredHeight:ask.implicitHeight+28;radius:24
                color:high ? Theme.alpha(Theme.error,.14) : Theme.tertiaryContainer
                border.width:1;border.color:high ? Theme.alpha(Theme.error,.5) : Theme.alpha(Theme.tertiary,.4)
                ColumnLayout {
                    id:ask;anchors {left:parent.left;right:parent.right;top:parent.top;margins:14} spacing:10
                    RowLayout {
                        spacing:10
                        Rectangle {Layout.preferredWidth:30;Layout.preferredHeight:30;radius:15;color:high ? Theme.alpha(Theme.error,.2) : Theme.alpha(Theme.tertiary,.25)
                            Glyph {anchors.centerIn:parent;name:high ? "warning" : "shield";font.pixelSize:17;color:high ? Theme.error : Theme.onTertiaryContainer}}
                        MText {text:"Allow Claude to "+modelData.label.charAt(0).toLowerCase()+modelData.label.slice(1)+"?";font.weight:Font.DemiBold;color:Theme.text;Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:14}
                    }
                    Rectangle {
                        visible:modelData.detail!=="";Layout.fillWidth:true;Layout.preferredHeight:detailText.implicitHeight+16;radius:12;color:Theme.alpha(Theme.base,.55)
                        MText {id:detailText;x:10;y:8;width:parent.width-20;text:modelData.detail;maximumLineCount:5;wrapMode:Text.WrapAnywhere;font.family:"monospace";font.pixelSize:12;color:Theme.text;elide:Text.ElideRight}
                    }
                    RowLayout {
                        Layout.fillWidth:true;spacing:8
                        MText {visible:panel.couch;text:panel.backButton+" Deny   "+panel.acceptButton+" Allow";role:"labelS";color:Theme.subtext;Layout.fillWidth:true}
                        MButton {visible:!panel.couch&&!high&&!panel.auto;text:"Use Auto";icon:"bolt";compact:true;tooltip:"Allow this and stop asking, except for dangerous commands";onClicked:{AssistantState.setMode("auto");AssistantState.approve(modelData.id,true);}}
                        Item {visible:!panel.couch;Layout.fillWidth:true}
                        MButton {text:"Deny";compact:true;tonal:true;onClicked:AssistantState.approve(modelData.id,false)}
                        MButton {text:"Allow";compact:true;filled:true;onClicked:AssistantState.approve(modelData.id,true)}
                    }
                }
            }
        }

        // Composer: removable context, the text, then Ask or Auto, context and send.
        Rectangle {
            id:composer
            Layout.fillWidth:true
            visible:!panel.couch||panel.turns.length>0
            Layout.preferredHeight:contextFlow.height+Math.max(44,Math.min(150,field.implicitHeight))+tools.height+18
            radius:26;color:Theme.alpha(Theme.level(3),.96)
            border.width:field.activeFocus ? 2 : 1;border.color:field.activeFocus ? Theme.primary : Theme.outline
            Flow {
                id:contextFlow
                x:12;y:visible ? 10 : 0;width:parent.width-24;spacing:6
                visible:panel.hasContext&&!AssistantState.busy
                height:visible ? implicitHeight : 0
                AssistantChip {
                    visible:AssistantState.ctxApp!==""&&AssistantState.useApp;icon:"select_window";removable:true;maxWidth:contextFlow.width
                    text:AssistantState.ctxTitle!=="" ? AssistantState.ctxTitle : AssistantState.ctxApp
                    onRemoved:AssistantState.useApp=false
                }
                AssistantChip {
                    visible:AssistantState.ctxSelection!==""&&AssistantState.useSelection;icon:"format_quote";removable:true;maxWidth:contextFlow.width
                    text:"Selection · "+AssistantState.ctxSelection.length+" characters"
                    onRemoved:AssistantState.useSelection=false
                }
                AssistantChip {
                    visible:AssistantState.ctxClipboard!==""&&AssistantState.useClipboard;icon:"content_paste";removable:true;maxWidth:contextFlow.width
                    text:"Clipboard · "+AssistantState.ctxClipboard.length+" characters"
                    onRemoved:AssistantState.useClipboard=false
                }
            }
            ScrollView {
                id:fieldScroll
                x:16;y:contextFlow.y+contextFlow.height+(contextFlow.visible ? 2 : 4);width:parent.width-32
                height:Math.max(44,Math.min(150,field.implicitHeight))
                TextArea {
                    id:field
                    placeholderText:AssistantState.turns.length ? "Ask a follow-up…" : "Ask Claude or tell it what to do…"
                    placeholderTextColor:Theme.muted;color:Theme.text;wrapMode:TextArea.Wrap;background:Item {}
                    font.family:Theme.font;font.pixelSize:panel.bodySize;selectByMouse:true
                    topPadding:10;bottomPadding:10;leftPadding:2;rightPadding:2
                    Keys.onPressed:e=>{
                        if((e.key===Qt.Key_Return||e.key===Qt.Key_Enter)&&!(e.modifiers&Qt.ShiftModifier)) {panel.submit();e.accepted=true;}
                        else if(e.key===Qt.Key_Escape) {Hub.close();e.accepted=true;}
                    }
                    Component.onCompleted:if(!panel.phone)forceActiveFocus()
                }
            }
            RowLayout {
                id:tools
                x:8;width:parent.width-16;height:48
                anchors.bottom:parent.bottom;anchors.bottomMargin:6
                spacing:6
                // Ask or Auto. Tapping switches; the chip says what will happen.
                Rectangle {
                    id:modeChip
                    Layout.preferredHeight:34;Layout.preferredWidth:modeRow.implicitWidth+24;radius:17
                    color:panel.auto ? Theme.tertiaryContainer : Theme.alpha(Theme.text,.06)
                    Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
                    Row {
                        id:modeRow;anchors.centerIn:parent;spacing:6
                        Glyph {name:panel.auto ? "bolt" : "shield";font.pixelSize:17;color:panel.auto ? Theme.onTertiaryContainer : Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
                        MText {text:panel.auto ? "Auto" : "Ask first";role:"label";color:panel.auto ? Theme.onTertiaryContainer : Theme.text;anchors.verticalCenter:parent.verticalCenter}
                    }
                    HoverHandler {cursorShape:Qt.PointingHandCursor}
                    TapHandler {onTapped:AssistantState.setMode(panel.auto ? "ask" : "auto")}
                    ToolTip.visible:modeHover.hovered;ToolTip.delay:500
                    ToolTip.text:panel.auto ? "Auto: Claude acts without asking. Dangerous commands still ask." : "Ask first: Claude asks before it closes windows, runs commands or writes files."
                    HoverHandler {id:modeHover}
                    Accessible.role:Accessible.Button;Accessible.name:panel.auto ? "Mode: Auto. Switch to Ask first" : "Mode: Ask first. Switch to Auto"
                }
                MButton {
                    visible:!panel.hasContext&&!AssistantState.busy;icon:"add_photo_alternate";compact:true;implicitWidth:34;implicitHeight:34
                    tooltip:"Add the focused window, selection and clipboard";onClicked:AssistantState.capture()
                }
                Item {Layout.fillWidth:true}
                MText {visible:panel.phone===false&&!AssistantState.busy&&field.text!=="";text:"Enter to send";role:"labelS";color:Theme.muted}
                MButton {visible:AssistantState.busy;icon:"stop";filled:true;implicitWidth:40;implicitHeight:40;tooltip:"Stop";onClicked:AssistantState.stop()}
                MButton {visible:!AssistantState.busy;icon:"arrow_upward";filled:true;implicitWidth:40;implicitHeight:40;tooltip:"Send · Enter";enabled:field.text.trim()!=="";onClicked:panel.submit()}
            }
        }
        MText {
            visible:panel.couch;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;role:"labelS";color:Theme.subtext
            text:panel.acceptButton+" Select   "+panel.backButton+" Back   X "+(panel.auto ? "Ask first" : "Auto")+"   Menu New chat"
        }
    }
}
