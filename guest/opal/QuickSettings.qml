import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id:q
    property string tab:Hub.page==="notifications" ? "inbox" : "controls"
    property string confirm:""
    property bool editing:false
    readonly property bool phone:Hub.targetScreen ? Hub.layoutFor(Hub.targetScreen.width,Hub.targetScreen.height,Hub.targetScreen.name)==="phone" : Hub.prefs.mode==="phone"
    Component.onCompleted:{Hub.connection("wifi","refresh");Hub.connection("bluetooth","refresh");}
    Connections {target:Hub;function onPageChanged(){if(Hub.page==="notifications")q.tab="inbox";else if(Hub.page==="controls")q.tab="controls";}}
    // Desktop panels shrink to fit the controls. Zero means the host picks the height.
    readonly property real fitHeight:!q.phone&&q.tab==="controls"&&Hub.controlDetail===""&&q.confirm==="" ? main.implicitHeight+28 : 0
    ColumnLayout {
        id:main
        visible:Hub.controlDetail==="";anchors.fill:parent;anchors.margins:14;spacing:8
        Rectangle {visible:q.phone;Layout.alignment:Qt.AlignHCenter;Layout.preferredWidth:40;Layout.preferredHeight:4;radius:2;color:Theme.outline}
        // Pixel header: a large clock and date, with a compact status cluster on the right.
        RowLayout {Layout.fillWidth:true;Layout.leftMargin:6;Layout.rightMargin:6;Layout.topMargin:2;spacing:8
            ColumnLayout {spacing:0
                MText {text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:36;font.weight:Font.Medium;font.letterSpacing:-1}
                MText {text:Qt.formatDateTime(Hub.now,"ddd d MMM");font.pixelSize:13;font.weight:Font.Medium;color:Theme.subtext}
            }
            Item {Layout.fillWidth:true}
            Row {Layout.alignment:Qt.AlignBottom|Qt.AlignRight;Layout.bottomMargin:3;spacing:6
                Glyph {visible:Hub.status.bluetooth;name:"bluetooth";font.pixelSize:16;color:Theme.subtext}
                Glyph {visible:Hub.dnd;name:"quiet";font.pixelSize:16;color:Theme.subtext}
                Glyph {name:Hub.status.wifi ? "wifi" : "wifiOff";font.pixelSize:16;color:Theme.subtext}
                Glyph {visible:Hub.status.battery>=0;name:Hub.status.charging ? "charging" : "battery";font.pixelSize:16;color:Theme.subtext}
                MText {visible:Hub.status.battery>=0;anchors.verticalCenter:parent.verticalCenter;text:Hub.status.battery+"%";font.pixelSize:12;font.weight:Font.Medium;color:Theme.subtext}
            }
        }
        Flickable {
            visible:q.tab==="controls";Layout.fillWidth:true;Layout.fillHeight:true;Layout.preferredHeight:controls.implicitHeight;contentHeight:controls.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            ColumnLayout {id:controls;width:parent.width;spacing:8
                RowLayout {visible:Hub.status.brightness>=0;Layout.fillWidth:true;Layout.topMargin:6;spacing:8
                    ExpressiveSlider {Layout.fillWidth:true;implicitHeight:58;compact:true;trackHeight:46;icon:"sun";iconAtHandle:true;value:Hub.status.brightness;onMoved:Hub.command({action:"brightness",value:Math.round(value)});Accessible.name:"Display brightness"}
                    MButton {icon:"brightness_auto";implicitWidth:46;implicitHeight:46;contained:true;tooltip:"Display settings";onClicked:Hub.openSettings("display")}
                }
                RowLayout {Layout.fillWidth:true;Layout.bottomMargin:4;spacing:8
                    ExpressiveSlider {Layout.fillWidth:true;implicitHeight:58;compact:true;trackHeight:46;icon:Hub.status.muted ? "mute" : "volume";iconAtHandle:true;value:Hub.status.volume;activeColor:Hub.status.muted ? Theme.subtext : Theme.primary;onMoved:Hub.volume(value);Accessible.name:"Media volume"
                        TapHandler {acceptedButtons:Qt.RightButton;onTapped:Hub.command({action:"mute"})}
                    }
                    MButton {icon:"next";implicitWidth:46;implicitHeight:46;contained:true;tooltip:"Sound and outputs";onClicked:Hub.openAudio(Hub.targetScreen)}
                }
                QuickTileDeck {Layout.fillWidth:true;editing:q.editing;onEditingChanged:if(q.editing!==editing)q.editing=editing}
                MediaCard {visible:Hub.status.track!=="";Layout.fillWidth:true;compact:true;expandable:true}
                FocusCard {visible:Hub.focusRunning&&q.phone;Layout.fillWidth:true}
                RowLayout {visible:q.phone;Layout.fillWidth:true
                    MText {text:"Notifications";font.pixelSize:19;font.weight:Font.DemiBold;Layout.fillWidth:true}
                    MButton {text:"See all";compact:true;onClicked:q.tab="inbox"}
                }
                Repeater {model:q.phone ? Hub.inbox.slice(0,3) : []
                    NotificationCard {required property var modelData;entry:modelData;Layout.fillWidth:true}
                }
                MText {visible:q.phone&&Hub.inbox.length===0;Layout.fillWidth:true;text:"You're all caught up";horizontalAlignment:Text.AlignHCenter;color:Theme.subtext;Layout.topMargin:8;Layout.bottomMargin:16}
            }
        }
        Loader {visible:q.tab==="inbox";active:visible;Layout.fillWidth:true;Layout.fillHeight:true;sourceComponent:Component {NotificationCenter {}}}
        // Utility row: inbox switch on the left, tile editing on the right.
        RowLayout {Layout.fillWidth:true;Layout.topMargin:2;spacing:8
            MButton {text:q.tab==="inbox" ? "Controls" : "Notifications"+(Hub.unread ? " · "+Hub.unread : "");icon:q.tab==="inbox" ? "settings" : Hub.dnd ? "quiet" : "bell";compact:true;implicitHeight:34;onClicked:q.tab=q.tab==="inbox" ? "controls" : "inbox"}
            Item {Layout.fillWidth:true}
            MButton {visible:q.tab==="controls";icon:q.editing ? "check" : "edit";compact:true;implicitWidth:40;implicitHeight:34;filled:q.editing;tooltip:q.editing ? "Done editing" : "Edit tiles";onClicked:q.editing=!q.editing}
        }
        // Pixel footer: connection chip, open-app count, settings and a filled power key.
        RowLayout {Layout.fillWidth:true;spacing:8
            Chip {Layout.fillWidth:true;implicitHeight:46;icon:Hub.status.wifi ? "vpn_key" : "link";trailingIcon:"next";text:Hub.status.wifi&&Hub.status.network ? Hub.status.network : "Offline";tooltip:"Network details";onClicked:Hub.settings("network")}
            Rectangle {
                Layout.preferredWidth:46;Layout.preferredHeight:46;radius:23;color:Theme.alpha(Theme.glassRaised,Theme.light ? .72 : .55)
                MText {anchors.centerIn:parent;text:Hub.windows.length;font.pixelSize:16;font.weight:Font.Medium}
                Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:appsMouse.pressed ? .12 : appsMouse.containsMouse ? .08 : 0}
                MouseArea {id:appsMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:Hub.page="windows"}
                Accessible.role:Accessible.Button;Accessible.name:Hub.windows.length+" active apps. Open the app switcher"
            }
            MButton {icon:"settings";implicitWidth:46;implicitHeight:46;contained:true;tooltip:"Settings";onClicked:Hub.openSettings()}
            MButton {icon:"power";implicitWidth:46;implicitHeight:46;filled:true;tooltip:"Power";onClicked:q.confirm="menu"}
        }
    }
    Loader {anchors.fill:parent;anchors.margins:20;active:Hub.controlDetail!=="";visible:active;sourceComponent:Component {ConnectionPanel {kind:Hub.controlDetail||"wifi"}}}
    Rectangle {visible:q.confirm!=="";anchors.fill:parent;radius:28;color:Theme.base
        MouseArea {anchors.fill:parent}
        ColumnLayout {anchors.centerIn:parent;width:parent.width-48;spacing:12
            MText {Layout.fillWidth:true;text:q.confirm==="menu" ? "Session and power" : "Confirm "+q.confirm+"?";font.pixelSize:26;wrapMode:Text.Wrap}
            Repeater {model:q.confirm==="menu" ? [{id:"suspend",title:"Sleep",icon:"sleep"},{id:"logout",title:"Log out",icon:"logout"},{id:"reboot",title:"Restart",icon:"restart"},{id:"poweroff",title:"Power off",icon:"power"}] : []
                MButton {required property var modelData;Layout.fillWidth:true;text:modelData.title;icon:modelData.icon;tonal:true;onClicked:q.confirm=modelData.id}
            }
            MButton {visible:q.confirm!=="menu";Layout.fillWidth:true;text:"Confirm";filled:true;onClicked:{Hub.command({action:"power",verb:q.confirm});Hub.close();}}
            MButton {Layout.fillWidth:true;text:"Cancel";onClicked:q.confirm=""}
        }
    }
}
