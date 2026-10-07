import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Grouped list row with an M3 switch. The whole row toggles; first and last rows round the group ends.
Rectangle {
    id:row
    property string title:""
    property string description:""
    property string icon:""
    property bool checked:false
    property bool first:true
    property bool last:true
    signal toggled()
    implicitHeight:description ? 76 : 60
    topLeftRadius:first ? 24 : 6;topRightRadius:topLeftRadius
    bottomLeftRadius:last ? 24 : 6;bottomRightRadius:bottomLeftRadius
    color:Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
    Rectangle {anchors.fill:parent;topLeftRadius:row.topLeftRadius;topRightRadius:row.topRightRadius;bottomLeftRadius:row.bottomLeftRadius;bottomRightRadius:row.bottomRightRadius;color:Theme.stateLayer;opacity:rowMouse.pressed ? .12 : rowMouse.containsMouse ? .06 : 0}
    MouseArea {id:rowMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:row.toggled()}
    RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:16;spacing:16
        Glyph {visible:row.icon!=="";name:row.icon;font.pixelSize:22;color:Theme.subtext}
        ColumnLayout {Layout.fillWidth:true;spacing:3
            MText {Layout.fillWidth:true;text:row.title;font.pixelSize:15;font.weight:Font.Medium}
            MText {visible:row.description!=="";Layout.fillWidth:true;text:row.description;font.pixelSize:12;color:Theme.subtext;wrapMode:Text.Wrap;maximumLineCount:2}
        }
        // M3 switch: the thumb grows when on and carries a check mark; it squeezes wider while pressed.
        Rectangle {
            id:track
            implicitWidth:52;implicitHeight:32;radius:16
            color:row.checked ? Theme.primary : Theme.alpha(Theme.tile,1)
            border.width:row.checked ? 0 : 2;border.color:Theme.alpha(Theme.subtext,.7)
            Behavior on color {ColorAnimation {duration:Theme.motion(180)}}
            Rectangle {
                readonly property real size:rowMouse.pressed ? 28 : row.checked ? 24 : 16
                width:size;height:size;radius:size/2
                x:row.checked ? track.width-width-4 : (rowMouse.pressed ? 2 : 8);anchors.verticalCenter:parent.verticalCenter
                color:row.checked ? Theme.onPrimary : Theme.subtext
                Behavior on x {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic;easing.overshoot:1.4}}
                Behavior on width {NumberAnimation {duration:Theme.motion(180);easing.type:Easing.OutCubic}}
                Behavior on height {NumberAnimation {duration:Theme.motion(180);easing.type:Easing.OutCubic}}
                Glyph {anchors.centerIn:parent;visible:row.checked;name:"check";font.pixelSize:16;color:Theme.primary}
            }
        }
    }
    activeFocusOnTab:true
    Keys.onReturnPressed:toggled()
    Keys.onSpacePressed:toggled()
    Rectangle {anchors.fill:parent;anchors.margins:-3;topLeftRadius:row.topLeftRadius+3;topRightRadius:row.topRightRadius+3;bottomLeftRadius:row.bottomLeftRadius+3;bottomRightRadius:row.bottomRightRadius+3;color:"transparent";border.width:2;border.color:Theme.primary;visible:row.activeFocus}
    Accessible.role:Accessible.CheckBox
    Accessible.name:title
    Accessible.checked:checked
    Accessible.onPressAction:toggled()
}
