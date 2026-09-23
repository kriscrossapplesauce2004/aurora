import QtQuick
import QtQuick.Layouts
// Phone stage: home, drawer and recents are layers of one surface, and one progress value moves the drawer.
Item {
    id:mobile
    property bool embedded:false
    property bool reachable:false
    property alias keyboardOpen:drawer.keyboardOpen
    // 0 is home, 1 is the open drawer.
    property real progress:0
    property bool dragging:false
    readonly property bool recents:Hub.mobileTab==="recent"&&!embedded
    function go(tab) {
        if(tab==="apps"){openDrawer(false);return;}
        Hub.mobileTab=tab;
        if(embedded&&tab!=="home")Hub.page="launcher";
    }
    function openDrawer(search) {
        if(embedded){Hub.drawerHandoff=progress;Hub.mobileTab="apps";Hub.page="launcher";if(search)Hub.drawerSearch=true;return;}
        Hub.mobileTab="apps";settle.to=1;settle.restart();
        if(search)Qt.callLater(drawer.focusSearch);
    }
    function closeDrawer() {
        drawer.keyboardOpen=false;
        if(embedded){settle.to=0;settle.restart();return;}
        settle.to=0;settle.restart();
    }
    Component.onCompleted:{
        if(!embedded&&Hub.mobileTab==="apps"){progress=Hub.drawerHandoff;settle.to=1;settle.restart();if(Hub.drawerSearch){Hub.drawerSearch=false;Qt.callLater(drawer.focusSearch);}}
        Hub.drawerHandoff=0;
    }
    Connections {
        target:Hub
        function onMobileTabChanged() {
            if(mobile.embedded)return;
            if(Hub.mobileTab==="apps"&&mobile.progress<1){settle.to=1;settle.restart();}
            else if(Hub.mobileTab!=="apps"&&mobile.progress>0){settle.to=0;settle.restart();}
        }
    }
    NumberAnimation {
        id:settle;target:mobile;property:"progress";duration:Theme.motion(380)
        easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate
        onFinished:{
            if(to===0&&!mobile.embedded&&Hub.mobileTab==="apps"){Hub.query="";Hub.mobileTab="home";if(Hub.page==="launcher")Hub.close();}
        }
    }

    // Home recedes as the drawer rises.
    PhoneHome {
        id:homeLayer
        anchors.fill:parent
        visible:mobile.progress<1&&!mobile.recents
        opacity:1-mobile.progress*.7
        scale:1-mobile.progress*.06
        onDragProgress:value=>{settle.stop();mobile.dragging=true;mobile.progress=value;}
        onDragFinished:open=>{mobile.dragging=false;if(open)mobile.openDrawer(false);else {settle.to=0;settle.restart();}}
        onOpenDrawer:search=>mobile.openDrawer(search)
    }
    Rectangle {anchors.fill:parent;color:"#000000";opacity:mobile.progress*.28;visible:opacity>0}
    PhoneDrawer {
        id:drawer
        width:parent.width;height:parent.height
        y:parent.height*(1-mobile.progress)
        visible:mobile.progress>0
        onCloseRequested:mobile.closeDrawer()
    }
    // Recents slide up from below and settle with a small scale.
    PhoneRecents {
        anchors.fill:parent
        visible:opacity>0
        opacity:mobile.recents ? 1 : 0
        scale:mobile.recents ? 1 : .92
        Behavior on opacity {NumberAnimation {duration:Theme.motion(260)}}
        Behavior on scale {NumberAnimation {duration:Theme.motion(360);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}}
    }
}
