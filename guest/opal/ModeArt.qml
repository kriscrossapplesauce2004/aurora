import QtQuick
// Layout miniature for convergence: workspace, touch, play, flow and mirror. Simple shapes in theme roles.
Item {
    id:art
    property string mode:"auto"
    property bool active:false
    readonly property color ink:active ? Theme.onContainer : Theme.primary
    readonly property color soft:Theme.alpha(ink,.18)
    // Workspace, Flow and Play share a landscape frame.
    Rectangle {
        visible:art.mode!=="phone"&&art.mode!=="mirror"
        width:Math.min(parent.width*(art.mode==="auto" ? .78 : .92),parent.height*1.6);height:width*.62
        anchors.verticalCenter:parent.verticalCenter;x:art.mode==="auto" ? 0 : (parent.width-width)/2
        radius:8;color:"transparent";border.width:2;border.color:art.ink
        Row {
            visible:art.mode!=="console";anchors.left:parent.left;anchors.top:parent.top;anchors.margins:7;spacing:4
            Rectangle {width:(parent.parent.width-18)*.55;height:parent.parent.height-26;radius:4;color:art.soft}
            Rectangle {width:(parent.parent.width-18)*.45;height:parent.parent.height-26;radius:4;color:art.soft;opacity:.6}
        }
        Row {
            visible:art.mode!=="console";anchors.bottom:parent.bottom;anchors.bottomMargin:4;anchors.horizontalCenter:parent.horizontalCenter;spacing:3
            Repeater {model:5;Rectangle {width:6;height:6;radius:3;color:art.ink;opacity:index===1 ? 1 : .5}}
        }
        Grid {
            visible:art.mode==="console";anchors.centerIn:parent;columns:3;spacing:4
            Repeater {model:6;Rectangle {width:(art.width*.92-34)/3*.9;height:width*.62;radius:4;color:index===0&&art.active ? art.ink : art.soft
                scale:index===0&&art.active&&!Theme.reduceMotion ? 1.08 : 1;Behavior on scale {NumberAnimation {duration:Theme.motion(300);easing.type:Easing.OutCubic}}}}
        }
    }
    // Touch and Flow show a phone.
    Rectangle {
        visible:art.mode==="phone"||art.mode==="auto"
        height:parent.height*(art.mode==="phone" ? .98 : .78);width:height*.5
        anchors.verticalCenter:parent.verticalCenter
        x:art.mode==="phone" ? (parent.width-width)/2 : parent.width-width
        radius:width*.18;color:art.mode==="auto" ? (art.active ? Theme.primaryContainer : Theme.base) : "transparent";border.width:2;border.color:art.ink
        Grid {
            anchors.horizontalCenter:parent.horizontalCenter;y:parent.height*.2;columns:3;spacing:3
            Repeater {model:6;Rectangle {width:(art.height*.4-12)/3*(art.mode==="phone" ? 1.1 : .8);height:width;radius:width/2;color:art.soft}}
        }
        Rectangle {anchors.bottom:parent.bottom;anchors.bottomMargin:5;anchors.horizontalCenter:parent.horizontalCenter;width:parent.width*.4;height:3;radius:1.5;color:art.ink}
    }
    // Flow: an arrow suggests the layout moving between screens.
    Glyph {visible:art.mode==="auto";anchors.centerIn:parent;anchors.horizontalCenterOffset:parent.width*.06;name:"sync_alt";font.pixelSize:18;color:art.ink
        rotation:art.active&&!Theme.reduceMotion ? 180 : 0;Behavior on rotation {NumberAnimation {duration:Theme.motion(600);easing.type:Easing.OutCubic}}}
    // Mirror: the phone screen shown inside the monitor.
    Rectangle {
        visible:art.mode==="mirror"
        width:Math.min(parent.width*.92,parent.height*1.6);height:width*.62
        anchors.centerIn:parent;radius:8;color:"transparent";border.width:2;border.color:art.ink
        Rectangle {anchors.centerIn:parent;height:parent.height*.8;width:height*.5;radius:width*.18;color:art.soft;border.width:2;border.color:art.ink
            scale:art.active&&!Theme.reduceMotion ? 1.06 : 1;Behavior on scale {NumberAnimation {duration:Theme.motion(400);easing.type:Easing.OutBack}}}
    }
}
