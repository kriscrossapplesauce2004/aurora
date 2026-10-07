import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:c
    property string selected:["auto","desktop","phone","console"].indexOf(Hub.prefs.mode)>=0 ? Hub.prefs.mode : "auto"
    property string focusScreen:Quickshell.screens.length ? Quickshell.screens[0].name : ""
    readonly property bool narrow:width<620
    property bool embedded:false
    readonly property var modes:[
        {id:"auto",title:"Flow",icon:"auto_awesome",tag:"Adaptive",description:"Each screen picks touch or desktop by its size."},
        {id:"desktop",title:"Workspace",icon:"desktop_windows",tag:"Desktop",description:"Windows, a bar and search."},
        {id:"phone",title:"Touch",icon:"smartphone",tag:"Phone and tablet",description:"A touch home with big targets."},
        {id:"console",title:"Play",icon:"sports_esports",tag:"Controller",description:"Your games, controller first."}
    ]
    readonly property var choice:modes.find(m=>m.id===selected)||modes[0]
    readonly property var screenFocus:Quickshell.screens.find(s=>s.name===focusScreen)||Quickshell.screens[0]||null

    ColumnLayout {
        anchors.fill:parent;anchors.margins:c.embedded ? 0 : c.narrow ? 16 : 24;spacing:16
        RowLayout {
            visible:!c.embedded
            Layout.fillWidth:true;spacing:12
            ColumnLayout {
                Layout.fillWidth:true;spacing:2
                MText {text:"Convergence";font.pixelSize:c.narrow ? 26 : 32;font.weight:Font.Medium}
                MText {text:"One shell for every screen you plug in";font.pixelSize:13;color:Theme.subtext}
            }
            Item {Layout.fillWidth:true}
            MButton {icon:"close";contained:true;compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Close convergence";onClicked:Hub.close()}
        }
        Flickable {
            Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentHeight:body.implicitHeight;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            ColumnLayout {
                id:body;width:parent.width;spacing:10
                // Mode cards: each one draws a small picture of its layout.
                GridLayout {
                    Layout.fillWidth:true;columns:c.narrow ? 2 : 4;columnSpacing:8;rowSpacing:8
                    Repeater {
                        model:c.modes
                        Rectangle {
                            id:card
                            required property var modelData
                            readonly property bool picked:c.selected===modelData.id
                            readonly property bool live:Hub.prefs.mode===modelData.id
                            Layout.fillWidth:true;Layout.preferredHeight:c.narrow ? 150 : 172
                            radius:picked ? 32 : 20
                            color:picked ? Theme.primaryContainer : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .75 : .55)
                            scale:cardMouse.pressed ? .97 : 1
                            Behavior on radius {NumberAnimation {duration:Theme.motion(300);easing.type:Easing.OutCubic}}
                            Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
                            Behavior on scale {NumberAnimation {duration:Theme.motion(140)}}
                            Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:cardMouse.containsMouse&&!card.picked ? .06 : 0}
                            ModeArt {
                                mode:card.modelData.id;active:card.picked
                                anchors.horizontalCenter:parent.horizontalCenter;y:14
                                width:parent.width-28;height:parent.height-62
                            }
                            Column {
                                anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.margins:14;spacing:0
                                MText {text:card.modelData.title;font.pixelSize:15;font.weight:Font.Medium;color:card.picked ? Theme.onContainer : Theme.text}
                                MText {text:card.live ? "In use" : card.modelData.tag;font.pixelSize:11;color:card.picked ? Theme.alpha(Theme.onContainer,.75) : Theme.subtext}
                            }
                            Rectangle {
                                visible:card.live;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:14
                                width:24;height:24;radius:12;color:Theme.primary
                                Glyph {anchors.centerIn:parent;name:"check";font.pixelSize:16;color:Theme.onPrimary}
                            }
                            MouseArea {id:cardMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:c.selected=card.modelData.id;onDoubleClicked:Hub.mode(card.modelData.id)}
                            Accessible.role:Accessible.RadioButton;Accessible.name:modelData.title;Accessible.checked:picked
                        }
                    }
                }
                MText {Layout.fillWidth:true;Layout.leftMargin:6;Layout.bottomMargin:8;text:c.choice.description;wrapMode:Text.Wrap;font.pixelSize:13;color:Theme.subtext}

                // Display map: every output at its real position and proportion.
                MText {text:"Your displays";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6}
                Rectangle {
                    id:map
                    Layout.fillWidth:true;Layout.preferredHeight:c.narrow ? 170 : 200;radius:28
                    color:Theme.alpha(Theme.light ? Theme.surfaceLow : Theme.surfaceLowest,.7)
                    readonly property var screens:Quickshell.screens
                    readonly property real minX:Math.min.apply(null,screens.map(s=>s.x).concat([0]))
                    readonly property real minY:Math.min.apply(null,screens.map(s=>s.y).concat([0]))
                    readonly property real spanX:Math.max(1,Math.max.apply(null,screens.map(s=>s.x+s.width).concat([1]))-minX)
                    readonly property real spanY:Math.max(1,Math.max.apply(null,screens.map(s=>s.y+s.height).concat([1]))-minY)
                    readonly property real unit:Math.min((width-60)/spanX,(height-50)/spanY)
                    Item {
                        anchors.centerIn:parent
                        width:map.spanX*map.unit;height:map.spanY*map.unit
                        Repeater {
                            model:map.screens
                            Rectangle {
                                id:screenBox
                                required property var modelData
                                readonly property string layout:Hub.layoutFor(modelData.width,modelData.height,modelData.name)
                                readonly property bool current:c.focusScreen===modelData.name
                                x:(modelData.x-map.minX)*map.unit+3;y:(modelData.y-map.minY)*map.unit+3
                                width:modelData.width*map.unit-6;height:modelData.height*map.unit-6
                                radius:10
                                color:layout==="phone" ? Theme.tertiaryContainer : layout==="console" ? Theme.secondaryContainer : Theme.primaryContainer
                                border.width:current ? 3 : 0;border.color:Theme.primary
                                Behavior on border.width {NumberAnimation {duration:Theme.motion(160)}}
                                Column {
                                    anchors.centerIn:parent;spacing:2;width:parent.width-12
                                    Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:screenBox.layout==="phone" ? "smartphone" : screenBox.layout==="console" ? "sports_esports" : "desktop_windows";font.pixelSize:Math.min(26,screenBox.height*.3);color:screenBox.layout==="phone" ? Theme.onTertiaryContainer : Theme.onContainer}
                                    MText {width:parent.width;horizontalAlignment:Text.AlignHCenter;visible:screenBox.height>70;text:screenBox.modelData.name;font.pixelSize:11;font.weight:Font.Medium;color:screenBox.layout==="phone" ? Theme.onTertiaryContainer : Theme.onContainer}
                                }
                                MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:c.focusScreen=screenBox.modelData.name}
                                Accessible.role:Accessible.Button;Accessible.name:modelData.name+", "+layout
                            }
                        }
                    }
                    MText {visible:map.screens.length===0;anchors.centerIn:parent;text:"No displays reported";color:Theme.subtext}
                }
                // Per-display layout for the selected screen.
                Rectangle {
                    visible:!!c.screenFocus;Layout.fillWidth:true;Layout.preferredHeight:displayCol.implicitHeight+28;radius:24
                    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                    ColumnLayout {
                        id:displayCol;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:10
                        RowLayout {
                            Layout.fillWidth:true;spacing:12
                            Glyph {name:"monitor";font.pixelSize:22;color:Theme.subtext}
                            ColumnLayout {
                                Layout.fillWidth:true;spacing:0
                                MText {Layout.fillWidth:true;text:c.screenFocus ? c.screenFocus.name : "";font.pixelSize:15;font.weight:Font.Medium}
                                MText {Layout.fillWidth:true;text:c.screenFocus ? c.screenFocus.width+" × "+c.screenFocus.height+" · "+Hub.layoutFor(c.screenFocus.width,c.screenFocus.height,c.screenFocus.name)+" now" : "";font.pixelSize:12;color:Theme.subtext}
                            }
                        }
                        SegmentedButtons {
                            Layout.fillWidth:true
                            current:c.screenFocus ? ((Hub.prefs.displayModes||{})[c.screenFocus.name]||"auto") : "auto"
                            options:[{value:"auto",label:"Auto",icon:"auto_awesome"},{value:"desktop",label:"Desktop",icon:"desktop_windows"},{value:"phone",label:"Touch",icon:"smartphone"}]
                            onPicked:value=>{if(c.screenFocus)Hub.displayMode(c.screenFocus.name,value);}
                        }
                        MText {Layout.fillWidth:true;text:"Used while Flow is active. Opal remembers it for this connector.";wrapMode:Text.Wrap;font.pixelSize:11;color:Theme.subtext}
                    }
                }

                MText {text:"Automatic";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6;Layout.topMargin:10}
                ConvergenceSettings {Layout.fillWidth:true}
                MText {text:"Feel";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6;Layout.topMargin:10}
                SettingToggle {Layout.fillWidth:true;first:true;last:false;icon:"animation";title:"Expressive motion";description:"Springy shape and panel transitions.";checked:!Theme.reduceMotion;onToggled:Hub.set("reduceMotion",!Theme.reduceMotion)}
                SettingToggle {Layout.fillWidth:true;first:false;last:false;icon:"swipe";title:"Gesture navigation";description:"Touch layouts use a gesture strip instead of buttons.";checked:!Hub.prefs.phoneButtons;onToggled:Hub.set("phoneButtons",!Hub.prefs.phoneButtons)}
                SettingToggle {Layout.fillWidth:true;first:false;last:true;icon:"vertical_align_bottom";title:"Hide the shelf automatically";checked:!!Hub.prefs.taskbarAutoHide;onToggled:Hub.set("taskbarAutoHide",!Hub.prefs.taskbarAutoHide)}
                MText {text:"Glass · "+Math.round(Hub.prefs.glass*100)+"%";font.pixelSize:12;font.weight:Font.Medium;color:Theme.primary;Layout.leftMargin:6;Layout.topMargin:10}
                ExpressiveSlider {Layout.fillWidth:true;implicitHeight:58;compact:true;trackHeight:46;icon:"opacity";iconAtHandle:true;from:45;to:100;value:Hub.prefs.glass*100;onMoved:Hub.set("glass",Math.round(value)/100)}
                MText {Layout.fillWidth:true;Layout.topMargin:6;text:"New displays get a quick setup prompt.";wrapMode:Text.Wrap;font.pixelSize:11;color:Theme.subtext}
            }
        }
        MButton {
            Layout.fillWidth:true;filled:c.selected!==Hub.prefs.mode;tonal:!filled;implicitHeight:56
            icon:c.selected===Hub.prefs.mode ? "check" : "arrow_forward"
            text:c.selected===Hub.prefs.mode ? c.choice.title+" is in use" : "Switch to "+c.choice.title
            onClicked:if(c.selected!==Hub.prefs.mode)Hub.mode(c.selected)
        }
    }
}
