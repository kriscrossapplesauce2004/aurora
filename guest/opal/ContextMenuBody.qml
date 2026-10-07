import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Shared context menu content: header, quick buttons, list rows, chip groups and switches.
Item {
    id:body
    property var entries:[]
    property string title:""
    property string icon:""
    property string subtitle:""
    property real maxHeight:600
    signal activated(var entry)
    readonly property var quick:entries.filter(e=>e.quick)
    readonly property var rows:entries.filter(e=>!e.quick&&!e.chip)
    readonly property var chipGroups:{
        const out=[];
        entries.filter(e=>e.chip).forEach(e=>{let g=out.find(x=>x.title===e.group);if(!g){g={title:e.group,items:[]};out.push(g);}g.items.push(e);});
        return out;
    }
    implicitWidth:300
    implicitHeight:Math.min(maxHeight,content.implicitHeight+16)
    Flickable {
        anchors.fill:parent;anchors.margins:8;contentHeight:content.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
        interactive:contentHeight>height
        ColumnLayout {
            id:content;width:parent.width;spacing:4
            RowLayout {
                visible:body.title!=="";Layout.fillWidth:true;Layout.margins:6;Layout.bottomMargin:4;spacing:12
                Rectangle {Layout.preferredWidth:40;Layout.preferredHeight:40;radius:20;color:Theme.primaryContainer
                    Glyph {anchors.centerIn:parent;name:body.icon||"apps";font.pixelSize:21;color:Theme.onContainer}
                }
                ColumnLayout {Layout.fillWidth:true;spacing:1
                    MText {Layout.fillWidth:true;text:body.title;font.pixelSize:15;font.weight:Font.Medium}
                    MText {visible:body.subtitle!=="";Layout.fillWidth:true;text:body.subtitle;font.pixelSize:11;color:Theme.subtext}
                }
            }
            // Quick actions: equal buttons with the icon above the label.
            RowLayout {
                visible:body.quick.length>0;Layout.fillWidth:true;Layout.bottomMargin:4;spacing:4
                Repeater {
                    model:body.quick
                    Rectangle {
                        id:quickKey
                        required property var modelData
                        required property int index
                        readonly property bool danger:!!modelData.danger
                        Layout.fillWidth:true;Layout.preferredHeight:64
                        topLeftRadius:index===0 ? 20 : 8;bottomLeftRadius:topLeftRadius
                        topRightRadius:index===body.quick.length-1 ? 20 : 8;bottomRightRadius:topRightRadius
                        color:danger ? Theme.alpha(Theme.error,.16) : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .85 : .7)
                        scale:quickMouse.pressed ? .95 : 1
                        Behavior on scale {NumberAnimation {duration:Theme.motion(120)}}
                        Rectangle {anchors.fill:parent;topLeftRadius:parent.topLeftRadius;topRightRadius:parent.topRightRadius;bottomLeftRadius:parent.bottomLeftRadius;bottomRightRadius:parent.bottomRightRadius;color:quickKey.danger ? Theme.error : Theme.stateLayer;opacity:quickMouse.pressed ? .14 : quickMouse.containsMouse ? .08 : 0}
                        Column {
                            anchors.centerIn:parent;spacing:4
                            Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:quickKey.modelData.icon||"next";font.pixelSize:22;color:quickKey.danger ? Theme.error : Theme.primary}
                            MText {anchors.horizontalCenter:parent.horizontalCenter;text:quickKey.modelData.text;font.pixelSize:11;font.weight:Font.Medium;color:quickKey.danger ? Theme.error : Theme.text}
                        }
                        MouseArea {id:quickMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;enabled:quickKey.modelData.enabled!==false;onClicked:body.activated(quickKey.modelData)}
                        Accessible.role:Accessible.Button;Accessible.name:modelData.text;Accessible.onPressAction:body.activated(modelData)
                    }
                }
            }
            Repeater {
                model:body.rows
                Rectangle {
                    id:row
                    required property var modelData
                    readonly property bool usable:modelData.enabled!==false
                    readonly property bool toggle:modelData.checked!==undefined
                    Layout.fillWidth:true;Layout.preferredHeight:row.modelData.detail ? 52 : 44;radius:14
                    color:rowMouse.pressed ? Theme.alpha(Theme.stateLayer,.12) : rowMouse.containsMouse ? Theme.alpha(Theme.stateLayer,.07) : "transparent"
                    RowLayout {
                        anchors.fill:parent;anchors.leftMargin:12;anchors.rightMargin:10;spacing:12
                        Glyph {name:row.modelData.icon||"next";font.pixelSize:20;color:!row.usable ? Theme.muted : row.modelData.danger ? Theme.error : Theme.subtext}
                        ColumnLayout {
                            Layout.fillWidth:true;spacing:0
                            MText {Layout.fillWidth:true;text:row.modelData.text;font.pixelSize:13;font.weight:Font.Medium;color:!row.usable ? Theme.muted : row.modelData.danger ? Theme.error : Theme.text}
                            MText {visible:!!row.modelData.detail;Layout.fillWidth:true;text:row.modelData.detail||"";font.pixelSize:10;color:Theme.subtext}
                        }
                        // Small switch for settings-style entries.
                        Rectangle {
                            visible:row.toggle;Layout.preferredWidth:36;Layout.preferredHeight:22;radius:11
                            color:row.modelData.checked ? Theme.primary : "transparent";border.width:row.modelData.checked ? 0 : 2;border.color:Theme.alpha(Theme.subtext,.7)
                            Rectangle {width:row.modelData.checked ? 16 : 10;height:width;radius:width/2;anchors.verticalCenter:parent.verticalCenter;x:row.modelData.checked ? parent.width-width-3 : 6;color:row.modelData.checked ? Theme.onPrimary : Theme.subtext}
                        }
                    }
                    MouseArea {id:rowMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;enabled:row.usable;onClicked:body.activated(row.modelData)}
                    Accessible.role:row.toggle ? Accessible.CheckBox : Accessible.MenuItem;Accessible.name:modelData.text;Accessible.checked:!!modelData.checked;Accessible.onPressAction:body.activated(modelData)
                }
            }
            Repeater {
                model:body.chipGroups
                ColumnLayout {
                    id:chipGroup
                    required property var modelData
                    Layout.fillWidth:true;Layout.topMargin:4;Layout.leftMargin:12;Layout.rightMargin:8;spacing:6
                    MText {text:chipGroup.modelData.title;font.pixelSize:11;font.weight:Font.Medium;color:Theme.subtext}
                    Flow {
                        Layout.fillWidth:true;spacing:6
                        Repeater {
                            model:chipGroup.modelData.items
                            Rectangle {
                                required property var modelData
                                width:36;height:36;radius:chipMouse.containsMouse ? 12 : 18
                                color:chipMouse.containsMouse ? Theme.primary : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .85 : .7)
                                Behavior on radius {NumberAnimation {duration:Theme.motion(200);easing.type:Easing.OutCubic}}
                                MText {anchors.centerIn:parent;text:modelData.text;font.pixelSize:13;font.weight:Font.Medium;color:chipMouse.containsMouse ? Theme.onPrimary : Theme.text}
                                MouseArea {id:chipMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:body.activated(parent.modelData)}
                                Accessible.role:Accessible.Button;Accessible.name:chipGroup.modelData.title+" "+modelData.text
                            }
                        }
                    }
                }
            }
        }
    }
}
