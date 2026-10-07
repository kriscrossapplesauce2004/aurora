import QtQuick
import QtQuick.Layouts

// Small context or activity chip. A removable chip shows a close mark.
Rectangle {
    id:chip
    property string text:""
    property string icon:""
    property bool removable:false
    property bool active:false
    property string tone:"neutral"
    property real maxWidth:260
    signal clicked()
    signal removed()
    readonly property color ink:tone==="error" ? Theme.error : tone==="primary" ? Theme.onContainer : Theme.text
    implicitWidth:Math.min(maxWidth,row.implicitWidth+22)
    implicitHeight:30
    radius:15
    color:tone==="primary" ? Theme.primaryContainer : Theme.alpha(Theme.glassRaised,Theme.light ? .8 : .6)
    Rectangle {anchors.fill:parent;radius:parent.radius;color:chip.ink;opacity:body.pressed ? .12 : body.containsMouse ? .07 : 0}
    MouseArea {id:body;anchors.fill:parent;hoverEnabled:true;onClicked:chip.clicked()}
    RowLayout {
        id:row;anchors.verticalCenter:parent.verticalCenter;x:11;width:chip.width-22;spacing:6
        Glyph {visible:chip.icon!=="";name:chip.icon;font.pixelSize:16;color:chip.ink}
        MText {text:chip.text;font.pixelSize:12;color:chip.ink;Layout.fillWidth:true;elide:Text.ElideRight}
        Item {
            visible:chip.removable;Layout.preferredWidth:18;Layout.preferredHeight:18
            Glyph {anchors.centerIn:parent;name:"close";font.pixelSize:14;color:chip.ink}
            MouseArea {anchors.fill:parent;anchors.margins:-6;onClicked:chip.removed()}
        }
    }
    Accessible.role:Accessible.Button;Accessible.name:text
}
