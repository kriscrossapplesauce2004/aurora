import QtQuick
import QtQuick.Layouts

// Compact docking card. It tells what Opal did with a new screen and lets you change it with one tap.
Surface {
    id:d
    property string output:Hub.dockScreen ? Hub.dockScreen.name : ""
    property string displayName:{const m=Hub.monitors.find(m=>m.name===d.output);return m&&m.description ? m.description.replace(/\s+\(?[A-Z]{2,4}-[A-Z0-9-]+\)?$/,"") : (d.output||"External display");}
    property bool phone:false
    property bool hasPhone:Hub.phoneScreen!==null
    property var result:Hub.dockResult
    property string screenMode:Hub.dockMirrored ? "mirror" : Hub.sessionModes[d.output]||(Hub.prefs.displayModes||{})[d.output]||""
    readonly property bool applied:d.result!==null||d.screenMode!==""
    readonly property var screenChoices:[{id:"desktop",text:"Desktop",icon:"desktop_windows"},{id:"phone",text:"Touch",icon:"touch_app"},{id:"console",text:"Play",icon:"sports_esports"}].concat(d.hasPhone ? [{id:"mirror",text:"Mirror",icon:"screen_share"}] : [])
    readonly property var phoneChoices:[{id:"trackpad",text:"Trackpad",icon:"touchpad_mouse"},{id:"screen",text:"Second screen",icon:"smartphone"},{id:"panel",text:"Controls",icon:"dashboard"}]
    readonly property string modeLabel:({desktop:"Desktop",phone:"Touch home",console:"Game library",mirror:"Mirroring your phone"})[d.screenMode]||""
    readonly property string summary:{
        if(!d.applied)return "Choose what this screen is for.";
        const parts=[d.modeLabel];
        if(d.result&&d.result.moved>0)parts.push(d.result.moved+(d.result.moved===1 ? " app moved here" : " apps moved here"));
        if(d.result&&d.result.remembered)parts.push("your usual setup");
        if(d.result&&d.result.error)parts.push(d.result.error);
        return parts.filter(p=>p).join(" · ");
    }
    property real connection:0
    property real remaining:1
    implicitHeight:column.implicitHeight+36
    radius:28;translucency:Math.min(Hub.prefs.glass,.72)
    function replay(){connectAnimation.restart();remaining=1;}
    Component.onCompleted:replay()
    SequentialAnimation {id:connectAnimation
        PauseAnimation {duration:Theme.motion(100)}
        NumberAnimation {target:d;property:"connection";from:0;to:1;duration:Theme.motion(650);easing.type:Easing.OutCubic}
    }
    // The card closes itself after 30 seconds. Hover stops the count.
    HoverHandler {id:hover;onHoveredChanged:{if(hovered)Hub.pauseDockNotice();else Hub.resumeDockNotice();}}
    Timer {interval:100;repeat:true;running:Hub.dockNotice&&!hover.hovered;onTriggered:{d.remaining-=interval/30000;if(d.remaining<=0)Hub.dockNotice=false;}}
    ColumnLayout {id:column;anchors {left:parent.left;right:parent.right;top:parent.top;margins:18} spacing:14
        RowLayout {Layout.fillWidth:true;spacing:14
            // Phone and screen art: the phone slides into the monitor while the card arrives.
            Item {Layout.preferredWidth:92;Layout.preferredHeight:64
                Rectangle {x:30+12*(1-d.connection);y:4;width:62;height:42;radius:9;color:Theme.alpha(Theme.primary,.12);border.width:2;border.color:Theme.primary;opacity:d.connection;scale:.8+.2*d.connection
                    Row {anchors.centerIn:parent;spacing:4
                        Repeater {model:3;Rectangle {required property int index;width:11;height:15+index*3;radius:4;color:Theme.alpha(Theme.primary,.4+index*.2)}}
                    }
                    Rectangle {anchors.top:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter;width:3;height:7;color:Theme.primary}
                    Rectangle {anchors.top:parent.bottom;anchors.topMargin:7;anchors.horizontalCenter:parent.horizontalCenter;width:26;height:3;radius:1.5;color:Theme.primary}
                }
                Rectangle {visible:d.hasPhone;x:2+14*(1-d.connection);y:16;width:24;height:44;radius:7;color:Theme.base;border.width:2;border.color:Theme.primary
                    Glyph {anchors.centerIn:parent;name:Hub.phoneDockMode==="trackpad" ? "touchpad_mouse" : Hub.phoneDockMode==="panel" ? "dashboard" : "apps";font.pixelSize:13;color:Theme.primary}
                }
            }
            ColumnLayout {Layout.fillWidth:true;spacing:2
                MText {text:d.applied ? "DOCKED" : "SCREEN CONNECTED";font.pixelSize:10;font.letterSpacing:1.5;color:Theme.primary}
                MText {text:d.displayName;Layout.fillWidth:true;role:"title";elide:Text.ElideRight}
                MText {text:d.summary;Layout.fillWidth:true;role:"body";color:Theme.subtext;wrapMode:Text.WordWrap;maximumLineCount:2;elide:Text.ElideRight}
            }
            MButton {Layout.alignment:Qt.AlignTop;icon:"close";implicitWidth:36;implicitHeight:36;tooltip:"Dismiss";onClicked:Hub.dockNotice=false}
        }
        MText {text:"This screen";role:"labelS";color:Theme.subtext}
        Flow {Layout.fillWidth:true;spacing:8
            Repeater {model:d.screenChoices
                Chip {required property var modelData
                    text:modelData.text;icon:modelData.icon;selected:d.screenMode===modelData.id
                    onClicked:{Hub.dockAs(modelData.id);d.remaining=1;}
                }
            }
        }
        MText {visible:d.hasPhone&&d.screenMode!=="mirror";text:"Your phone";role:"labelS";color:Theme.subtext}
        Flow {visible:d.hasPhone&&d.screenMode!=="mirror";Layout.fillWidth:true;spacing:8
            Repeater {model:d.phoneChoices
                Chip {required property var modelData
                    text:modelData.text;icon:modelData.icon;selected:Hub.docked&&Hub.phoneDockMode===modelData.id
                    onClicked:{Hub.dockPhoneAs(modelData.id);d.remaining=1;}
                }
            }
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            MText {Layout.fillWidth:true;text:d.applied ? "Opal remembers this for next time." : "";role:"labelS";color:Theme.subtext;elide:Text.ElideRight}
            MButton {visible:Hub.convergence!==null&&Hub.convergence.canUndo;text:"Undo";icon:"undo";compact:true;onClicked:{Hub.convergence.undo();Hub.dockResult=null;}}
            MButton {text:"More options";icon:"tune";compact:true;tonal:true;onClicked:{Hub.dockNotice=false;Hub.dockMenu=true;}}
        }
    }
    // Time left is a thin line along the bottom edge.
    Rectangle {anchors {left:parent.left;right:parent.right;bottom:parent.bottom;leftMargin:28;rightMargin:28;bottomMargin:7}
        height:3;radius:2;color:Theme.alpha(Theme.text,.08)
        Rectangle {height:parent.height;radius:2;width:parent.width*Math.max(0,Math.min(1,d.remaining));color:Theme.primary}
    }
    Accessible.role:Accessible.AlertMessage;Accessible.name:(d.applied ? "Docked to " : "Screen connected: ")+d.displayName+". "+d.summary
}
