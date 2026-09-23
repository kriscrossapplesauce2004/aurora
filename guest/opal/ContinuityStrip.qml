import QtQuick
import QtQuick.Layouts
import Quickshell
// Continuity: windows that live on your other screens. Tap to bring one onto this display; the arrow jumps to it where it is.
ColumnLayout {
    id:strip
    property string here:Hub.prefs.phoneDisplay||""
    readonly property var monitors:Hub.status.monitors||[]
    readonly property var hereMonitor:monitors.find(m=>m.name===here)||null
    readonly property var away:Hub.status.hypr&&here!=="" ? Hub.windows.filter(w=>w.monitor&&w.monitor!==here) : []
    readonly property var screensAway:away.map(w=>w.monitor).filter((m,i,all)=>all.indexOf(m)===i)
    visible:away.length>0
    spacing:6
    RowLayout {
        Layout.fillWidth:true;Layout.leftMargin:8
        Glyph {name:"devices";font.pixelSize:16;color:Theme.primary}
        MText {Layout.fillWidth:true;text:"On "+strip.screensAway.join(" and ");font.pixelSize:13;font.weight:Font.Medium;color:Theme.primary}
        MText {text:"Tap to bring here";font.pixelSize:11;color:Theme.subtext}
    }
    Flickable {
        Layout.fillWidth:true;Layout.preferredHeight:64;contentWidth:row.width;clip:true
        flickableDirection:Flickable.HorizontalFlick;boundsBehavior:Flickable.StopAtBounds
        Row {
            id:row;spacing:8
            Repeater {
                model:strip.away
                Rectangle {
                    id:card
                    required property var modelData
                    readonly property var app:Hub.appForWindow(modelData)
                    width:Math.min(220,Math.max(150,label.implicitWidth+100));height:64;radius:22
                    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
                    scale:cardMouse.pressed ? .96 : 1
                    Behavior on scale {NumberAnimation {duration:Theme.motion(140)}}
                    RowLayout {
                        anchors.fill:parent;anchors.leftMargin:12;anchors.rightMargin:6;spacing:10
                        Image {Layout.preferredWidth:30;Layout.preferredHeight:30;sourceSize:Qt.size(60,60);asynchronous:true;source:Quickshell.iconPath((card.app||{}).icon||"application-x-executable",true)}
                        ColumnLayout {
                            Layout.fillWidth:true;spacing:0
                            MText {id:label;Layout.fillWidth:true;text:card.modelData.title||card.modelData.className;font.pixelSize:13;font.weight:Font.Medium}
                            MText {Layout.fillWidth:true;text:card.modelData.monitor+" · workspace "+card.modelData.workspace;font.pixelSize:10;color:Theme.subtext}
                        }
                        MButton {icon:"open_in_new";compact:true;implicitWidth:34;implicitHeight:34;hoverHalo:true;ink:Theme.subtext;tooltip:"Go to it on "+card.modelData.monitor;onClicked:Hub.focusWindow(card.modelData)}
                    }
                    MouseArea {
                        id:cardMouse;anchors.fill:parent;z:-1
                        enabled:!!strip.hereMonitor
                        onClicked:Hub.command({action:"move-window",address:card.modelData.address,number:strip.hereMonitor.workspace,follow:true})
                    }
                    Accessible.role:Accessible.Button
                    Accessible.name:"Bring "+(modelData.title||modelData.className)+" to this screen"
                }
            }
        }
    }
}
