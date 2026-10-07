import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi or Bluetooth detail page. A switch in the header, grouped lists, and inline connect.
ColumnLayout {
    id:p
    property string kind:"wifi"
    property var backAction:()=>{Hub.controlDetail="";}
    property bool embedded:false
    readonly property bool wifi:kind==="wifi"
    readonly property var state:Hub.connectivity[kind]
    readonly property var items:state.items||[]
    readonly property string label:wifi ? "Wi-Fi" : "Bluetooth"
    property var selected:null
    readonly property var groups:{
        const active=items.filter(i=>i.active);
        const known=items.filter(i=>!i.active&&(wifi ? i.saved : i.paired));
        const other=items.filter(i=>!i.active&&!(wifi ? i.saved : i.paired));
        return [{title:wifi ? "Connected" : "Connected",list:active},{title:wifi ? "Saved" : "My devices",list:known},{title:wifi ? "Available" : "Nearby",list:other}].filter(g=>g.list.length);
    }
    function key(item) {return wifi ? item.ssid : item.address;}
    spacing:12
    Component.onCompleted:Hub.connection(kind,"refresh")
    onKindChanged:{selected=null;Hub.connection(kind,"refresh");}

    // Header: back, title, scan and a power switch.
    RowLayout {
        Layout.fillWidth:true;spacing:4
        MButton {visible:!p.embedded;icon:"back";compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Back";onClicked:p.backAction()}
        MText {text:p.embedded ? (p.state.powered ? "On" : "Off") : p.label;role:p.embedded ? "titleS" : "headline";Layout.fillWidth:true;Layout.leftMargin:4}
        MButton {visible:p.state.powered;icon:"refresh";compact:true;implicitWidth:40;implicitHeight:40;ink:Theme.subtext;enabled:!p.state.busy;tooltip:"Scan";onClicked:Hub.connection(p.kind,"scan")
            RotationAnimation on rotation {running:p.state.busy&&!Theme.reduceMotion;from:0;to:360;duration:1000;loops:Animation.Infinite}
        }
        MSwitch {
            checked:!!p.state.powered;enabled:!p.state.busy;Layout.leftMargin:6
            onToggled:value=>Hub.connection(p.kind,"power",{enabled:value})
            Accessible.name:p.label
        }
    }
    // Only show a line when something needs saying.
    MText {
        visible:text!=="";Layout.fillWidth:true;Layout.leftMargin:6;wrapMode:Text.Wrap;role:"bodyS"
        text:p.state.error ? p.state.error : p.state.busy ? "Searching…" : ""
        color:p.state.error ? Theme.error : Theme.subtext
    }
    // Radio off: one clear message.
    Item {
        visible:!p.state.powered;Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:offColumn.implicitHeight
        Column {
            id:offColumn;anchors.centerIn:parent;spacing:10
            Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:p.wifi ? "wifiOff" : "bluetooth_disabled";font.pixelSize:40;color:Theme.muted}
            MText {anchors.horizontalCenter:parent.horizontalCenter;text:p.label+" is off";role:"title"}
            MButton {anchors.horizontalCenter:parent.horizontalCenter;text:"Turn on";tonal:true;enabled:!p.state.busy;onClicked:Hub.connection(p.kind,"power",{enabled:true})}
        }
    }
    Flickable {
        visible:p.state.powered;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        contentHeight:listColumn.implicitHeight;boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:ScrollBar {}
        Column {
            id:listColumn;width:parent.width;spacing:14
            Repeater {
                model:p.groups
                Column {
                    id:group
                    required property var modelData
                    width:listColumn.width;spacing:3
                    MText {text:group.modelData.title;role:"label";color:Theme.primary;leftPadding:8;bottomPadding:4}
                    Repeater {
                        model:group.modelData.list
                        Rectangle {
                            id:row
                            required property var modelData
                            required property int index
                            readonly property bool open:p.selected!==null&&p.key(p.selected)===p.key(modelData)
                            readonly property bool first:index===0
                            readonly property bool last:index===group.modelData.list.length-1
                            width:group.width;height:rowContent.implicitHeight+(open ? actions.implicitHeight+12 : 0)+24
                            topLeftRadius:first ? Theme.shapeLg : Theme.shapeXs;topRightRadius:topLeftRadius
                            bottomLeftRadius:last ? Theme.shapeLg : Theme.shapeXs;bottomRightRadius:bottomLeftRadius
                            color:modelData.active ? Theme.primaryContainer : Theme.level(3)
                            clip:true
                            Behavior on height {NumberAnimation {duration:Theme.motion(Theme.durShort);easing.type:Easing.OutCubic}}
                            Rectangle {anchors.fill:parent;topLeftRadius:parent.topLeftRadius;topRightRadius:parent.topRightRadius;bottomLeftRadius:parent.bottomLeftRadius;bottomRightRadius:parent.bottomRightRadius;color:Theme.stateLayer;opacity:rowMouse.pressed ? .10 : rowMouse.containsMouse ? .05 : 0}
                            MouseArea {id:rowMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;enabled:!p.state.busy;onClicked:{p.selected=row.open ? null : row.modelData;password.clear();}}
                            RowLayout {
                                id:rowContent;x:16;y:12;width:parent.width-32;spacing:14
                                Glyph {
                                    font.pixelSize:22;color:row.modelData.active ? Theme.onContainer : Theme.primary
                                    name:p.wifi ? (row.modelData.signal>66 ? "wifi" : row.modelData.signal>33 ? "wifi_2_bar" : "wifi_1_bar") : (row.modelData.icon&&/audio|head/.test(row.modelData.icon) ? "headphones" : "bluetooth")
                                }
                                ColumnLayout {Layout.fillWidth:true;spacing:0
                                    MText {Layout.fillWidth:true;text:p.wifi ? row.modelData.ssid : row.modelData.name;role:"titleS";color:row.modelData.active ? Theme.onContainer : Theme.text}
                                    MText {
                                        Layout.fillWidth:true;role:"labelS";color:row.modelData.active ? Theme.alpha(Theme.onContainer,.8) : Theme.subtext
                                        text:row.modelData.active ? "Connected" : p.wifi ? (row.modelData.security ? "Secured" : "Open") : row.modelData.paired ? "Not connected" : "Tap to pair"
                                    }
                                }
                                Glyph {visible:p.wifi&&!!row.modelData.security;name:"lock";font.pixelSize:16;color:Theme.subtext}
                            }
                            ColumnLayout {
                                id:actions;visible:row.open;x:16;y:rowContent.y+rowContent.implicitHeight+12;width:parent.width-32;spacing:8
                                TextField {
                                    id:password;Layout.fillWidth:true
                                    visible:p.wifi&&row.open&&!row.modelData.active&&!!row.modelData.security&&!row.modelData.saved
                                    placeholderText:"Password";echoMode:TextInput.Password;color:Theme.text;selectByMouse:true
                                    font.family:Theme.font;font.pixelSize:14;leftPadding:14
                                    background:Rectangle {radius:Theme.shapeMd;color:Theme.level(1);border.width:password.activeFocus ? 2 : 0;border.color:Theme.primary}
                                    onAccepted:connectButton.clicked()
                                }
                                RowLayout {Layout.fillWidth:true;spacing:8
                                    Item {Layout.fillWidth:true}
                                    MButton {text:"Cancel";compact:true;onClicked:{p.selected=null;password.clear();}}
                                    MButton {
                                        id:connectButton;compact:true;filled:true;enabled:!p.state.busy
                                        text:row.modelData.active ? "Disconnect" : !p.wifi&&!row.modelData.paired ? "Pair" : "Connect"
                                        onClicked:{const s=row.modelData;Hub.connection(p.kind,s.active ? "disconnect" : !p.wifi&&!s.paired ? "pair" : "connect",{ssid:s.ssid,device:s.device,address:s.address,password:password.text});password.clear();p.selected=null;}
                                    }
                                }
                            }
                        }
                    }
                }
            }
            MText {
                visible:!p.state.busy&&!p.items.length;width:parent.width;topPadding:24;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap
                text:p.wifi ? "No networks found" : "No devices found";role:"bodyS";color:Theme.subtext
            }
        }
    }
}
