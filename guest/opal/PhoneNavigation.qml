import QtQuick
import QtQuick.Layouts

Item {
    id:nav
    property var output:null
    implicitHeight:Hub.prefs.phoneButtons ? 64 : 48
    function go(tab) {if(output)Hub.targetScreen=output;Hub.mobileTab=tab;Hub.page="launcher";}
    // Home closes every Opal surface; the embedded home screen is then what remains.
    function home() {if(output)Hub.targetScreen=output;Hub.query="";Hub.mobileTab="home";Hub.close();}
    function back() {if(Hub.page==="settings"&&Hub.settingsSection!=="")Hub.settingsSection="";else if(Hub.controlDetail!==""&&(Hub.page==="controls"||Hub.page==="notifications"))Hub.controlDetail="";else if(Hub.page==="launcher"&&Hub.mobileTab!=="home")go("home");else Hub.close();}
    // No bar background: the navigation floats over the wallpaper or app, like a modern phone.
    Rectangle {anchors.fill:parent;color:Hub.page===""||Hub.page==="launcher" ? "transparent" : Theme.alpha(Theme.base,.6)}
    // Three buttons: back triangle, home circle and recents square, drawn as outlines.
    RowLayout {
        visible:!!Hub.prefs.phoneButtons;anchors.centerIn:parent;width:Math.min(parent.width-48,300);spacing:0
        NavKey {
            tooltip:"Back";onActivated:nav.back()
            Glyph {anchors.centerIn:parent;name:"play_arrow";rotation:180;font.pixelSize:26;color:Theme.text}
        }
        NavKey {
            tooltip:"Home · hold for apps";onActivated:nav.home();onHeld:nav.go("apps")
            Rectangle {anchors.centerIn:parent;width:18;height:18;radius:9;color:"transparent";border.width:2.5;border.color:Theme.text}
        }
        NavKey {
            tooltip:"Recent apps";onActivated:nav.go("recent")
            Rectangle {anchors.centerIn:parent;width:16;height:16;radius:4;color:"transparent";border.width:2.5;border.color:Theme.text}
        }
    }
    // Gesture pill: tap for home, swipe up for apps, hold for recents, swipe sideways for back.
    Item {
        visible:!Hub.prefs.phoneButtons;anchors.fill:parent
        Rectangle {
            id:pill
            anchors.centerIn:parent
            width:gesture.pressed ? 132 : 108;height:5;radius:2.5
            color:gesture.pressed ? Theme.primary : Theme.alpha(Theme.text,.75)
            transform:Translate {y:gesture.pressed ? Math.max(-14,Math.min(0,gesture.mouseY-gesture.startY)*.3) : 0}
            Behavior on width {NumberAnimation {duration:Theme.motion(200);easing.type:Easing.OutBack}}
            Behavior on color {ColorAnimation {duration:Theme.motion(120)}}
        }
        MouseArea {
            id:gesture
            anchors.horizontalCenter:parent.horizontalCenter;width:Math.min(parent.width,260);height:parent.height
            property real startX:0
            property real startY:0
            property bool held:false
            onPressed:e=>{startX=e.x;startY=e.y;held=false;}
            onPressAndHold:{held=true;nav.go("recent");}
            onCanceled:held=true
            onReleased:e=>{
                if(held)return;
                const dx=e.x-startX,dy=startY-e.y;
                if(Math.abs(dx)>50&&Math.abs(dx)>dy)nav.back();
                else if(dy>28&&(Hub.page===""||Hub.page==="launcher"&&Hub.mobileTab==="home"))nav.go("apps");
                else nav.home();
            }
            Accessible.role:Accessible.Button;Accessible.name:"Home. Swipe up for apps, hold for recent apps"
        }
    }
    component NavKey: Item {
        id:key
        property string tooltip:""
        signal activated()
        signal held()
        Layout.fillWidth:true;Layout.preferredHeight:48
        Rectangle {anchors.centerIn:parent;width:56;height:40;radius:20;color:Theme.stateLayer;opacity:keyMouse.pressed ? .14 : 0;Behavior on opacity {NumberAnimation {duration:Theme.motion(120)}}}
        MouseArea {id:keyMouse;anchors.fill:parent;onClicked:key.activated();onPressAndHold:key.held()}
        Accessible.role:Accessible.Button;Accessible.name:tooltip;Accessible.onPressAction:activated()
    }
}
