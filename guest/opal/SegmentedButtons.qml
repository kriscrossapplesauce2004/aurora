import QtQuick
import QtQuick.Layouts
// M3 connected button group: the selected segment fills and rounds fully, neighbours keep tight inner corners.
RowLayout {
    id:group
    property var options:[]
    property var current:null
    property bool enabledAll:true
    signal picked(var value)
    spacing:3
    Repeater {
        model:group.options
        Rectangle {
            id:segment
            required property var modelData
            required property int index
            readonly property bool selected:modelData.value===group.current
            readonly property bool first:index===0
            readonly property bool last:index===group.options.length-1
            readonly property real outer:height/2
            readonly property real inner:selected ? height/2 : 8
            Layout.fillWidth:true;Layout.preferredHeight:48
            topLeftRadius:first ? outer : inner;bottomLeftRadius:topLeftRadius
            topRightRadius:last ? outer : inner;bottomRightRadius:topRightRadius
            color:selected ? Theme.primary : Theme.alpha(Theme.light ? "#ffffff" : Theme.glassRaised,Theme.light ? .8 : .6)
            opacity:group.enabledAll ? 1 : .45
            Behavior on color {ColorAnimation {duration:Theme.motion(180)}}
            Behavior on topLeftRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
            Behavior on topRightRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
            Behavior on bottomLeftRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
            Behavior on bottomRightRadius {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.OutCubic}}
            Row {
                anchors.centerIn:parent;spacing:6
                Glyph {visible:!!segment.modelData.icon||segment.selected;name:segment.selected&&!segment.modelData.icon ? "check" : segment.modelData.icon||"";font.pixelSize:18;color:segment.selected ? Theme.onPrimary : Theme.text;anchors.verticalCenter:parent.verticalCenter}
                MText {text:segment.modelData.label;font.pixelSize:13;font.weight:Font.Medium;color:segment.selected ? Theme.onPrimary : Theme.text;anchors.verticalCenter:parent.verticalCenter}
            }
            MouseArea {anchors.fill:parent;enabled:group.enabledAll;cursorShape:Qt.PointingHandCursor;onClicked:group.picked(segment.modelData.value)}
            Accessible.role:Accessible.RadioButton;Accessible.name:modelData.label;Accessible.checked:selected
        }
    }
}
