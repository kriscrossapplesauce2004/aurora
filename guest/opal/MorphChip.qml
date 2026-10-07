import QtQuick
import QtQuick.Layouts

// Chip that grows in place into a sheet of controls (container transform). The chip surface itself becomes the sheet, so the change reads as one object.
Item {
    id:chip
    property string icon:""
    property var app:null
    property string iconSource:""
    property string text:""
    property string tag:""
    property bool selected:false
    // A full-size item that holds the expanded sheet and its scrim.
    property Item host:null
    property int sheetWidth:360
    property int sheetHeight:220
    property Component sheet:null
    property bool expanded:false
    // 0 is the chip, 1 is the open sheet. Tests can set it to show a frame of the morph.
    property real t:0
    signal clicked()
    readonly property bool morphing:t>0
    readonly property color chipColor:selected ? Theme.secondaryContainer : Theme.alpha(Theme.level(2),.88)
    readonly property color chipInk:selected ? Theme.onSecondaryContainer : Theme.text
    implicitWidth:row.implicitWidth+(text ? 24 : 16)
    implicitHeight:36
    function open() {if(sheet&&host){expanded=true;}else clicked();}
    function close() {expanded=false;}
    onExpandedChanged:{grow.stop();grow.to=expanded ? 1 : 0;grow.duration=Theme.motion(expanded ? 460 : 320);grow.easing.bezierCurve=expanded ? Theme.emphasizedDecelerate : Theme.emphasizedAccelerate;grow.start();}
    NumberAnimation {id:grow;target:chip;property:"t";easing.type:Easing.BezierSpline}

    // Rest state. It hides while its surface is out as the sheet.
    Rectangle {
        id:rest
        anchors.fill:parent;radius:height/2
        color:chip.chipColor
        border.width:chip.selected ? 0 : 1;border.color:Theme.outline
        opacity:chip.morphing ? 0 : 1
        scale:tap.pressed ? .96 : 1
        Behavior on scale {NumberAnimation {duration:Theme.motion(120)}}
        RowLayout {
            id:row;anchors.centerIn:parent;spacing:7
            AppIcon {visible:chip.app!==null;app:chip.app;style:"raw";Layout.preferredWidth:20;Layout.preferredHeight:20}
            Image {visible:chip.iconSource!=="";source:chip.iconSource;sourceSize:Qt.size(40,40);Layout.preferredWidth:20;Layout.preferredHeight:20;fillMode:Image.PreserveAspectCrop}
            Glyph {visible:chip.icon!=="";name:chip.icon;font.pixelSize:18;color:chip.chipInk}
            MText {visible:chip.text!=="";text:chip.text;role:"label";color:chip.chipInk;Layout.maximumWidth:180;elide:Text.ElideRight}
            Rectangle {visible:chip.tag!=="";implicitWidth:tagText.implicitWidth+12;implicitHeight:20;radius:10;color:Theme.alpha(Theme.tertiary,.2)
                MText {id:tagText;anchors.centerIn:parent;text:chip.tag;role:"labelS";color:Theme.tertiary}}
        }
        TapHandler {id:tap;onTapped:chip.open()}
        Accessible.role:Accessible.Button;Accessible.name:chip.text||chip.icon
    }

    // The scrim and the travelling surface live in the host so the sheet can leave the chip's layout.
    Item {
        id:stage
        parent:chip.host
        anchors.fill:parent
        visible:chip.morphing&&chip.host!==null
        z:100
        Rectangle {anchors.fill:parent;color:"#000000";opacity:.32*chip.t
            TapHandler {onTapped:chip.close()}}
        // Start and end rectangles in host coordinates.
        readonly property point origin:chip.host&&visible ? chip.mapToItem(chip.host,0,0) : Qt.point(0,0)
        readonly property real endW:Math.min(chip.sheetWidth,(chip.host ? chip.host.width : 400)-24)
        readonly property real endH:chip.sheetHeight
        readonly property real endX:Math.max(12,Math.min(origin.x+chip.width/2-endW/2,(chip.host ? chip.host.width : 400)-endW-12))
        readonly property bool below:origin.y+chip.height+8+endH<=(chip.host ? chip.host.height : 800)-16
        readonly property real endY:below ? origin.y : Math.max(16,origin.y+chip.height-endH)
        Rectangle {
            id:surface
            x:stage.origin.x+(stage.endX-stage.origin.x)*chip.t
            y:stage.origin.y+(stage.endY-stage.origin.y)*chip.t
            width:chip.width+(stage.endW-chip.width)*chip.t
            height:chip.height+(stage.endH-chip.height)*chip.t
            radius:Math.min(height/2,chip.height/2+(28-chip.height/2)*chip.t)
            color:Qt.tint(chip.chipColor,Theme.alpha(Theme.level(3),Math.min(1,chip.t*1.6)))
            clip:true
            // The chip content leaves first, then the sheet content arrives.
            RowLayout {
                x:12;y:(chip.height-height)/2;spacing:7
                opacity:Math.max(0,1-chip.t/.3)
                Glyph {visible:chip.icon!=="";name:chip.icon;font.pixelSize:18;color:chip.chipInk}
                AppIcon {visible:chip.app!==null;app:chip.app;style:"raw";Layout.preferredWidth:20;Layout.preferredHeight:20}
                MText {text:chip.text;role:"label";color:chip.chipInk}
            }
            Loader {
                id:content
                active:chip.morphing&&chip.sheet!==null
                sourceComponent:chip.sheet
                x:0;y:0;width:stage.endW;height:stage.endH
                opacity:Math.max(0,(chip.t-.35)/.65)
                scale:.94+.06*chip.t
                transformOrigin:Item.TopLeft
            }
        }
    }
}
