import QtQuick
import QtQuick.Layouts

Item {
    id:nav
    property var output:null
    // On a tablet the app dock is part of this bar: keys at the left, apps in the middle, the gesture strip at the bottom edge.
    readonly property bool tablet:!!output&&PhoneState.isTablet(output)&&Hub.prefs.tabletDock!==false
    implicitHeight:tablet ? (Hub.prefs.phoneButtons ? 68 : 80) : Hub.prefs.phoneButtons ? 64 : 48
    function go(tab) {if(output)Hub.targetScreen=output;Hub.mobileTab=tab;Hub.page="launcher";}
    // Home closes every Opal surface; the embedded home screen is then what remains.
    function home() {if(output)Hub.targetScreen=output;PhoneState.goHome();}
    function back() {if(Hub.page==="settings"&&Hub.settingsSection!=="")Hub.settingsSection="";else if(Hub.controlDetail!==""&&(Hub.page==="controls"||Hub.page==="notifications"))Hub.controlDetail="";else if(Hub.page==="launcher"&&Hub.mobileTab!=="home")go("home");else if(Hub.page===""&&PhoneState.appInFront&&PhoneState.previousWindow())PhoneState.back();else Hub.close();}
    // No bar background: the navigation floats over the wallpaper or app, like a modern phone.
    Rectangle {anchors.fill:parent;color:Hub.page===""||Hub.page==="launcher" ? "transparent" : Theme.alpha(Theme.base,.6)}
    // Three buttons: back triangle, home circle and recents square, drawn as outlines.
    RowLayout {
        visible:!!Hub.prefs.phoneButtons&&!nav.tablet;spacing:0
        width:Math.min(parent.width-48,300)
        x:(parent.width-width)/2;y:(parent.height-height)/2
        NavKey {
            tooltip:"Back";onActivated:nav.back()
            Glyph {anchors.centerIn:parent;name:"play_arrow";rotation:180;font.pixelSize:26;color:Theme.text}
        }
        NavKey {
            tooltip:"Home · hold for assistant";onActivated:nav.home();onHeld:Hub.openAssistant("")
            Rectangle {anchors.centerIn:parent;width:18;height:18;radius:9;color:"transparent";border.width:2.5;border.color:Theme.text}
        }
        NavKey {
            tooltip:"Recent apps";onActivated:nav.go("recent")
            Rectangle {anchors.centerIn:parent;width:16;height:16;radius:4;color:"transparent";border.width:2.5;border.color:Theme.text}
        }
    }
    // Tablet: full-width islands. With gestures the keys island is left out and the gesture strip sits under the bar.
    Loader {
        active:nav.tablet
        anchors {left:parent.left;right:parent.right;top:parent.top}
        height:68
        sourceComponent:Component {
            TabletBar {
                screenObj:nav.output;keys:!!Hub.prefs.phoneButtons
                onBack:nav.back();onHome:nav.home();onRecents:nav.go("recent")
            }
        }
    }
    // Gesture pill: the finger moves a live card. Up goes home, up and hold shows recents, sideways switches apps.
    Item {
        visible:!Hub.prefs.phoneButtons
        anchors {left:parent.left;right:parent.right;bottom:parent.bottom}
        height:nav.tablet ? 16 : parent.height
        Rectangle {
            id:pill
            anchors.centerIn:parent
            width:gesture.pressed ? 132 : 108;height:5;radius:2.5
            color:gesture.pressed ? Theme.primary : Theme.alpha(Theme.text,.75)
            transform:Translate {
                x:gesture.pressed&&PhoneState.phase==="switch" ? Math.max(-40,Math.min(40,PhoneState.dx*.15)) : 0
                y:gesture.pressed ? Math.max(-14,Math.min(0,PhoneState.dy*.3)) : 0
            }
            Behavior on width {NumberAnimation {duration:Theme.motion(200);easing.type:Easing.OutCubic}}
            Behavior on color {ColorAnimation {duration:Theme.motion(120)}}
        }
        MouseArea {
            id:gesture
            anchors.horizontalCenter:parent.horizontalCenter;width:Math.min(parent.width,320);height:parent.height
            preventStealing:true
            property real startX:0
            property real startY:0
            property real lastX:0
            property real lastY:0
            property real lastTime:0
            property real vx:0
            property real vy:0
            property bool moved:false
            property bool assistantOpened:false
            // Holding the pill without moving opens the Claude assistant.
            Timer {id:holdTimer;interval:550;onTriggered:if(gesture.pressed&&!gesture.moved){gesture.assistantOpened=true;PhoneState.cancel();Hub.openAssistant("");}}
            onPressed:e=>{
                assistantOpened=false;holdTimer.restart();
                startX=e.x;startY=e.y;lastX=e.x;lastY=e.y;lastTime=Date.now();vx=0;vy=0;moved=false;
                PhoneState.begin(nav.output);
            }
            onPositionChanged:e=>{
                const now=Date.now(),dt=Math.max(1,now-lastTime);
                // Smooth the velocity so one jittery sample cannot start a fling.
                vx=vx*.6+(e.x-lastX)/dt*1000*.4;vy=vy*.6+(e.y-lastY)/dt*1000*.4;
                lastX=e.x;lastY=e.y;lastTime=now;
                if(Math.abs(e.x-startX)>10||Math.abs(e.y-startY)>10)moved=true;
                PhoneState.move(e.x-startX,e.y-startY,vx,vy);
            }
            onReleased:{
                holdTimer.stop();
                if(assistantOpened)return;
                if(!moved){PhoneState.cancel();nav.home();return;}
                // A pause before release must not count as a fling.
                if(Date.now()-lastTime>90){vx=0;vy=0;}
                PhoneState.velocityX=vx;PhoneState.velocityY=vy;
                if(PhoneState.phase===""){PhoneState.cancel();nav.home();return;}
                PhoneState.end();
            }
            onCanceled:{holdTimer.stop();PhoneState.cancel();}
            Accessible.role:Accessible.Button;Accessible.name:"Home. Swipe up for home or apps, hold while swiping for recent apps, swipe sideways to switch apps"
            Accessible.onPressAction:nav.home()
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
