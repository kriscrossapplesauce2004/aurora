import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
// App drawer sheet: search, suggested apps, categories, an A-Z grid with a fast scrubber, and pull-down to close.
Item {
    id:drawer
    property bool keyboardOpen:false
    property string category:"All apps"
    readonly property string filter:Hub.query.trim()
    readonly property bool math:filter!==""&&(filter.startsWith("=")||Hub.looksLikeMath(filter))
    readonly property int columns:Math.max(4,Math.min(Hub.prefs.phoneRows||5,Math.floor((width-40)/76)))
    readonly property var apps:math ? [] : Hub.searchApps(filter,filter ? "All apps" : category)
    readonly property var letters:{
        const seen=[];
        apps.forEach(a=>{const l=(a.name||"#").charAt(0).toUpperCase();const k=/[A-Z]/.test(l) ? l : "#";if(seen.indexOf(k)<0)seen.push(k);});
        return seen;
    }
    signal closeRequested()
    function focusSearch() {search.forceActiveFocus();keyboardOpen=true;}
    function jump(letter) {
        const index=apps.findIndex(a=>{const l=(a.name||"#").charAt(0).toUpperCase();return letter==="#" ? !/[A-Z]/.test(l) : l===letter;});
        if(index>=0)grid.positionViewAtIndex(index,GridView.Beginning);
    }
    Connections {
        target:Hub
        function onQueryChanged() {
            if(search.text!==Hub.query)search.text=Hub.query;
            Hub.calculation="";calc.stop();
            if(drawer.math)calc.restart();
        }
    }
    Timer {id:calc;interval:120;onTriggered:if(drawer.math)Hub.command({action:"calculate",text:Hub.calcExpression(drawer.filter)})}

    Rectangle {
        id:sheet
        anchors.fill:parent
        topLeftRadius:32;topRightRadius:32
        color:Theme.alpha(Theme.light ? Theme.surfaceLow : Theme.mix(Theme.base,Theme.primaryContainer,.12),.97)
        ColumnLayout {
            anchors.fill:parent;anchors.leftMargin:16;anchors.rightMargin:16;anchors.topMargin:8;anchors.bottomMargin:8;spacing:12
            // Handle and header: dragging down here closes the drawer.
            Item {
                Layout.fillWidth:true;Layout.preferredHeight:20
                Rectangle {anchors.centerIn:parent;width:36;height:4;radius:2;color:Theme.alpha(Theme.text,.35)}
                DragHandler {target:null;xAxis.enabled:false;onActiveChanged:if(!active&&translation.y>50)drawer.closeRequested()}
                TapHandler {onTapped:drawer.closeRequested()}
            }
            Rectangle {
                Layout.fillWidth:true;Layout.preferredHeight:56;radius:28
                color:Theme.light ? "#ffffff" : Theme.mix(Theme.base,Theme.primaryContainer,.5)
                RowLayout {
                    anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:8;spacing:10
                    Glyph {name:"search";font.pixelSize:22;color:Theme.subtext}
                    TextField {
                        id:search
                        Layout.fillWidth:true;Layout.fillHeight:true
                        placeholderText:"Search apps";text:Hub.query
                        color:Theme.text;placeholderTextColor:Theme.subtext
                        font.family:Theme.font;font.pixelSize:16;selectByMouse:true
                        onTextEdited:Hub.query=text
                        onActiveFocusChanged:if(activeFocus)drawer.keyboardOpen=true
                        onAccepted:{if(drawer.math){if(Hub.calculation!=="")Hub.command({action:"clipboard",text:Hub.calculation});}else if(drawer.apps.length)Hub.launch(drawer.apps[0]);}
                        Keys.onEscapePressed:{if(Hub.query!=="")Hub.query="";else drawer.closeRequested();}
                        background:Item {}
                    }
                    MButton {visible:search.text!=="";icon:"close";compact:true;implicitWidth:40;implicitHeight:40;onClicked:{Hub.query="";search.forceActiveFocus();}}
                    MButton {visible:search.text==="";icon:"settings";compact:true;implicitWidth:40;implicitHeight:40;hoverHalo:true;tooltip:"Phone settings";onClicked:Hub.openSettings("phone")}
                }
            }
            // Suggested: recent apps as a single row when not searching.
            ColumnLayout {
                visible:drawer.filter===""&&Hub.recentApps.length>0;Layout.fillWidth:true;spacing:2
                MText {text:"Suggested";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6}
                RowLayout {
                    Layout.fillWidth:true;spacing:0
                    Repeater {
                        model:Hub.recentApps.slice(0,drawer.columns)
                        Item {
                            required property var modelData
                            Layout.fillWidth:true;Layout.preferredHeight:100
                            PhoneAppIcon {anchors.centerIn:parent;app:parent.modelData;size:54;onActivated:Hub.launch(app)}
                        }
                    }
                }
            }
            Flickable {
                visible:drawer.filter==="";Layout.fillWidth:true;Layout.preferredHeight:38;contentWidth:chipRow.width;clip:true
                flickableDirection:Flickable.HorizontalFlick;boundsBehavior:Flickable.StopAtBounds
                Row {
                    id:chipRow;spacing:6
                    Repeater {
                        model:["All apps","Games","Create","Work","Internet","System"]
                        Chip {required property string modelData;text:modelData;implicitHeight:36;selected:drawer.category===modelData;glass:!selected;onClicked:drawer.category=modelData}
                    }
                }
            }
            // Arithmetic answers appear in place of results.
            Rectangle {
                visible:drawer.math;Layout.fillWidth:true;Layout.preferredHeight:110;radius:28;color:Theme.primaryContainer
                ColumnLayout {
                    anchors.fill:parent;anchors.margins:20;spacing:2
                    MText {text:Hub.calcExpression(drawer.filter)+" =";font.pixelSize:13;color:Theme.alpha(Theme.onContainer,.75)}
                    RowLayout {
                        Layout.fillWidth:true
                        MText {Layout.fillWidth:true;text:Hub.calculation||"…";font.pixelSize:36;font.weight:Font.Medium;color:Theme.onContainer}
                        MButton {text:"Copy";icon:"content_copy";compact:true;filled:true;accent:Theme.onContainer;fillInk:Theme.primaryContainer;enabled:Hub.calculation!=="";onClicked:Hub.command({action:"clipboard",text:Hub.calculation})}
                    }
                }
            }
            Item {
                visible:!drawer.math;Layout.fillWidth:true;Layout.fillHeight:true
                GridView {
                    id:grid
                    anchors.fill:parent;anchors.rightMargin:rail.visible ? 26 : 0
                    clip:true;model:drawer.apps;cacheBuffer:400
                    cellWidth:width/drawer.columns;cellHeight:108
                    boundsBehavior:Flickable.DragOverBounds
                    // Pulling past the top closes the drawer, like a phone launcher.
                    onDragEnded:if(contentY<-70)drawer.closeRequested()
                    delegate:Item {
                        required property var modelData
                        width:GridView.view.cellWidth;height:GridView.view.cellHeight
                        PhoneAppIcon {anchors.centerIn:parent;app:parent.modelData;size:54;onActivated:Hub.launch(app)}
                    }
                    Column {
                        anchors.centerIn:parent;visible:drawer.apps.length===0;spacing:10
                        MText {anchors.horizontalCenter:parent.horizontalCenter;text:drawer.filter ? "No apps match “"+drawer.filter+"”" : "Nothing here yet";color:Theme.subtext}
                        MButton {visible:drawer.filter!=="";anchors.horizontalCenter:parent.horizontalCenter;text:"Search the web";icon:"language";tonal:true;onClicked:{Hub.command({action:"web",text:drawer.filter});Hub.close();}}
                    }
                }
                // A-Z scrubber: slide along the edge to jump; a bubble shows the letter under the finger.
                Item {
                    id:rail
                    visible:drawer.filter===""&&drawer.letters.length>6
                    anchors.right:parent.right;anchors.top:parent.top;anchors.bottom:parent.bottom;width:24
                    property string active:""
                    Column {
                        anchors.centerIn:parent
                        Repeater {
                            model:drawer.letters
                            MText {
                                required property string modelData
                                width:24;height:Math.min(20,(rail.height-8)/Math.max(1,drawer.letters.length))
                                horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter
                                text:modelData;font.pixelSize:10;font.weight:rail.active===modelData ? Font.Bold : Font.Medium
                                color:rail.active===modelData ? Theme.primary : Theme.subtext
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill:parent;preventStealing:true
                        function pick(y) {
                            const step=Math.min(20,(rail.height-8)/Math.max(1,drawer.letters.length));
                            const top=(rail.height-step*drawer.letters.length)/2;
                            const i=Math.max(0,Math.min(drawer.letters.length-1,Math.floor((y-top)/step)));
                            if(rail.active!==drawer.letters[i]){rail.active=drawer.letters[i];drawer.jump(rail.active);}
                        }
                        onPressed:e=>pick(e.y)
                        onPositionChanged:e=>pick(e.y)
                        onReleased:rail.active=""
                        onCanceled:rail.active=""
                    }
                    Rectangle {
                        visible:rail.active!=="";width:56;height:56;radius:28;x:-72
                        y:Math.max(0,Math.min(rail.height-height,drawer.letters.indexOf(rail.active)*Math.min(20,(rail.height-8)/Math.max(1,drawer.letters.length))+(rail.height-Math.min(20,(rail.height-8)/Math.max(1,drawer.letters.length))*drawer.letters.length)/2-18))
                        color:Theme.primary
                        MText {anchors.centerIn:parent;text:rail.active;font.pixelSize:24;font.weight:Font.Medium;color:Theme.onPrimary}
                    }
                }
            }
            SearchKeyboard {
                visible:drawer.keyboardOpen&&!Hub.systemOskReady
                Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,drawer.height*.42)
                inputTarget:search;contextLabel:"Search apps";returnLabel:"Go"
                onInsert:Hub.query=search.text
                onErase:Hub.query=search.text
                onAccept:{search.accepted();drawer.keyboardOpen=false;}
                onDismiss:{drawer.keyboardOpen=false;search.focus=false;}
            }
        }
    }
}
