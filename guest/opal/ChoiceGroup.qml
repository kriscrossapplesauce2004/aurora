import QtQuick
import QtQuick.Layouts

// A setting with a few options, shown as a heading and a row of filter chips. Every option is visible; the current one is selected.
Rectangle {
    id:group
    property string icon:""
    property string title:""
    property string detail:""
    property var options:[]
    property var current:null
    signal picked(var id)
    implicitHeight:column.implicitHeight+28
    radius:Theme.shapeLg
    color:Theme.alpha(Theme.tile,.82)
    ColumnLayout {
        id:column
        anchors {left:parent.left;right:parent.right;top:parent.top;margins:14}
        spacing:10
        RowLayout {
            Layout.fillWidth:true;spacing:12
            Rectangle {
                Layout.preferredWidth:36;Layout.preferredHeight:36;radius:18;color:Theme.alpha(Theme.primary,.18)
                Glyph {anchors.centerIn:parent;name:group.icon;font.pixelSize:20;color:Theme.primary}
            }
            ColumnLayout {
                Layout.fillWidth:true;spacing:0
                MText {Layout.fillWidth:true;text:group.title;role:"label";font.weight:Font.DemiBold;elide:Text.ElideRight}
                MText {visible:group.detail!=="";Layout.fillWidth:true;text:group.detail;role:"labelS";color:Theme.subtext;elide:Text.ElideRight}
            }
        }
        Flow {
            Layout.fillWidth:true;spacing:6
            Repeater {
                model:group.options
                Chip {
                    required property var modelData
                    text:modelData.name;icon:modelData.icon||"";glass:false
                    selected:modelData.id===group.current
                    onClicked:group.picked(modelData.id)
                }
            }
        }
    }
    Accessible.role:Accessible.Grouping;Accessible.name:title
}
