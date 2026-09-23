import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id:entry
    required property var record
    property bool selected:false
    property bool compact:false
    property bool closeAfterCopy:true
    implicitHeight:compact ? 64 : 108
    radius:selected ? 24 : 18
    color:selected ? Theme.primaryContainer : hit.containsMouse ? Theme.surfaceHigh : Theme.alpha(Theme.surfaceHigh,.55)
    border.width:selected ? 1 : 0
    border.color:Theme.alpha(Theme.primary,.6)
    scale:hit.pressed ? .985 : 1
    Behavior on color {ColorAnimation {duration:140}}
    Behavior on radius {NumberAnimation {duration:160;easing.type:Easing.OutCubic}}
    Behavior on scale {NumberAnimation {duration:120}}
    function showMenu(x,y) {
        menuX=x;menuY=y;
        if(entryMenu.item)entryMenu.item.popup(x,y);
        else entryMenu.active=true;
    }
    property real menuX:0
    property real menuY:0
    Component {id:entryMenuComponent;OpalMenu {entries:[
        {text:"Copy this entry",icon:"copy",run:()=>Hub.copyClipboard(entry.record.id,entry.closeAfterCopy)},
        {text:"Remove from history",icon:"trash",run:()=>Hub.deleteClipboard(entry.record.id)}
    ]}}
    Loader {id:entryMenu;active:false;sourceComponent:entryMenuComponent;onLoaded:item.popup(entry.menuX,entry.menuY)}
    MouseArea {
        id:hit;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton;cursorShape:Qt.PointingHandCursor
        property bool held:false
        onPressed:held=false
        onClicked:e=>{if(held)return;if(e.button===Qt.RightButton)entry.showMenu(e.x,e.y);else Hub.copyClipboard(entry.record.id,entry.closeAfterCopy);}
        onPressAndHold:e=>{held=true;entry.showMenu(e.x,e.y);}
    }
    RowLayout {
        anchors {fill:parent;margins:entry.compact ? 10 : 14}
spacing:12
        Rectangle {
            Layout.preferredWidth:entry.compact ? 34 : 42;Layout.preferredHeight:width
            radius:entry.record.kind==="Link" ? width/2 : 12
            color:Theme.alpha(entry.record.kind==="Link" ? Theme.secondary : entry.record.kind==="Snippet" ? Theme.tertiary : Theme.primary,.18)
            Glyph {anchors.centerIn:parent;name:entry.record.kind==="Link" ? "link" : entry.record.kind==="Snippet" ? "terminal" : "clipboard";color:entry.selected ? Theme.onContainer : Theme.primary;font.pixelSize:entry.compact ? 18 : 22}
        }
        ColumnLayout {Layout.fillWidth:true;spacing:7
            MText {text:entry.record.text;Layout.fillWidth:true;wrapMode:Text.Wrap;maximumLineCount:entry.compact ? 1 : 3;font.pixelSize:entry.compact ? 12 : 13;font.family:entry.record.kind==="Snippet" ? "CaskaydiaCove Nerd Font" : Theme.font;color:entry.selected ? Theme.onContainer : Theme.text}
            MText {visible:!entry.compact;text:entry.record.kind+"  ·  "+entry.record.chars+" characters"+(entry.record.lines>1 ? "  ·  "+entry.record.lines+" lines" : "");Layout.fillWidth:true;color:Theme.subtext;font.pixelSize:10}
        }
        MButton {icon:entry.compact ? "copy" : "trash";compact:true;implicitWidth:entry.compact ? 34 : 38;implicitHeight:38;tooltip:entry.compact ? "Copy entry" : "Remove from history";onClicked:entry.compact ? Hub.copyClipboard(entry.record.id,entry.closeAfterCopy) : Hub.deleteClipboard(entry.record.id)}
    }
    Accessible.role:Accessible.Button
    Accessible.name:"Copy "+record.kind.toLowerCase()+": "+record.text.substring(0,100)
    Accessible.onPressAction:Hub.copyClipboard(record.id,closeAfterCopy)
}
