import QtQuick
import QtQuick.Layouts

// Toast for an automatic layout switch. It never takes keyboard focus; the Undo button is for touch and pointer.
Rectangle {
    id:toast
    property string text:""
    property string detail:""
    property string icon:"convergence"
    property string actionText:"Undo"
    property real remaining:1
    signal undo()
    signal dismissed()
    implicitWidth:380;implicitHeight:detail!=="" ? 100 : 72
    radius:28
    color:Theme.level(3)
    border.width:1;border.color:Theme.outline
    RowLayout {
        anchors {fill:parent;leftMargin:18;rightMargin:10;topMargin:10;bottomMargin:14} spacing:12
        Rectangle {
            Layout.preferredWidth:40;Layout.preferredHeight:40;radius:20;color:Theme.primaryContainer
            Glyph {anchors.centerIn:parent;name:toast.icon;font.pixelSize:22;color:Theme.onContainer}
        }
        ColumnLayout {
            Layout.fillWidth:true;spacing:1
            MText {Layout.fillWidth:true;text:toast.text;font.pixelSize:14;font.weight:Font.Medium;elide:Text.ElideRight;maximumLineCount:2;wrapMode:Text.Wrap}
            MText {visible:toast.detail!=="";Layout.fillWidth:true;text:toast.detail;font.pixelSize:12;color:Theme.subtext;elide:Text.ElideRight}
        }
        MButton {text:toast.actionText;compact:true;tonal:true;tooltip:"Undo this automatic change";onClicked:toast.undo()}
    }
    // Time left is a thin line along the bottom edge.
    Rectangle {
        anchors {left:parent.left;right:parent.right;bottom:parent.bottom;leftMargin:24;rightMargin:24;bottomMargin:6}
        height:3;radius:2;color:Theme.alpha(Theme.text,.08)
        Rectangle {height:parent.height;radius:2;width:parent.width*Math.max(0,Math.min(1,toast.remaining));color:Theme.primary}
    }
    Accessible.role:Accessible.AlertMessage;Accessible.name:text
}
