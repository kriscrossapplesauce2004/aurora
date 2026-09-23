import QtQuick
import QtQuick.Layouts
// Month calendar card. Arrows browse months; the title returns to today.
Rectangle {
    id:cal
    property date shown:new Date(Hub.now.getFullYear(),Hub.now.getMonth(),1)
    property bool solid:false
    readonly property int year:shown.getFullYear()
    readonly property int month:shown.getMonth()
    readonly property bool thisMonth:year===Hub.now.getFullYear()&&month===Hub.now.getMonth()
    // Weeks start on Monday.
    readonly property int lead:(new Date(year,month,1).getDay()+6)%7
    readonly property int days:new Date(year,month+1,0).getDate()
    readonly property int cells:Math.ceil((lead+days)/7)*7
    readonly property real cell:Math.floor((width-24)/7)
    function step(delta) {shown=new Date(year,month+delta,1);}
    implicitHeight:header.height+weekdays.height+Math.ceil((lead+days)/7)*cell+30
    radius:28
    color:solid ? (Theme.light ? "#ffffff" : Theme.surfaceHigh) : Theme.alpha(Theme.light ? Theme.primaryContainer : Theme.glassRaised,Theme.light ? .86 : .78)
    RowLayout {
        id:header
        x:12;y:10;width:parent.width-24;height:36;spacing:2
        MText {
            Layout.fillWidth:true;Layout.leftMargin:6
            text:Qt.formatDateTime(cal.shown,"MMMM")+(cal.year!==Hub.now.getFullYear() ? " "+cal.year : "")
            font.pixelSize:15;font.weight:Font.Medium;color:Theme.light ? Theme.containerInk : Theme.text
            MouseArea {anchors.fill:parent;cursorShape:cal.thisMonth ? Qt.ArrowCursor : Qt.PointingHandCursor;onClicked:cal.shown=new Date(Hub.now.getFullYear(),Hub.now.getMonth(),1)}
        }
        MButton {icon:"chevron_left";compact:true;implicitWidth:30;implicitHeight:30;hoverHalo:true;tooltip:"Previous month";onClicked:cal.step(-1)}
        MButton {icon:"chevron_right";compact:true;implicitWidth:30;implicitHeight:30;hoverHalo:true;tooltip:"Next month";onClicked:cal.step(1)}
    }
    Row {
        id:weekdays
        x:12;y:header.y+header.height+4;height:18
        Repeater {
            model:["M","T","W","T","F","S","S"]
            MText {required property string modelData;required property int index;width:cal.cell;horizontalAlignment:Text.AlignHCenter;text:modelData;font.pixelSize:10;font.weight:Font.Medium;color:index>=5 ? Theme.primary : Theme.subtext}
        }
    }
    Grid {
        x:12;y:weekdays.y+weekdays.height+4;columns:7
        Repeater {
            model:cal.cells
            Item {
                required property int index
                readonly property int day:index-cal.lead+1
                readonly property bool real:day>=1&&day<=cal.days
                readonly property bool today:real&&cal.thisMonth&&day===Hub.now.getDate()
                width:cal.cell;height:cal.cell
                Rectangle {
                    anchors.centerIn:parent;width:Math.min(parent.width,parent.height)-4;height:width
                    radius:parent.today ? width*.32 : width/2
                    color:parent.today ? (Theme.light ? Theme.containerInk : Theme.primary) : "transparent"
                }
                MText {
                    anchors.centerIn:parent;visible:parent.real;text:parent.day
                    font.pixelSize:11;font.weight:parent.today ? Font.Bold : Font.Normal
                    color:parent.today ? (Theme.light ? Theme.primaryContainer : Theme.onPrimary) : Theme.light ? Theme.containerInk : Theme.text
                }
            }
        }
    }
    WheelHandler {onWheel:e=>cal.step(e.angleDelta.y<0 ? 1 : -1)}
    Accessible.role:Accessible.Table
    Accessible.name:Qt.formatDateTime(shown,"MMMM yyyy")
}
