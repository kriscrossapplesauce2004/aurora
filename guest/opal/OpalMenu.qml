import QtQuick
import QtQuick.Controls

// In-panel context menu. It uses the same content as the shelf menu, so every right click looks and behaves the same.
Popup {
    id:menu
    property var entries:[]
    property string title:""
    property string icon:""
    popupType:Popup.Window
    implicitWidth:300
    implicitHeight:body.implicitHeight
    padding:0
    margins:8
    dim:false
    // Popup.Window ignores Popup.open coordinates in a layer-shell panel, so the geometry is set before it opens.
    function popupFrom(item, clickX, clickY) {
        const point=item.mapToItem(null,clickX,clickY);
        const panelWidth=item.window ? item.window.width : 0;
        const panelHeight=item.window ? item.window.height : 0;
        const menuWidth=Math.max(width,implicitWidth);
        const menuHeight=Math.max(height,implicitHeight);
        const margin=8;
        const maxX=Math.max(margin,panelWidth-menuWidth-margin);
        const maxY=Math.max(margin,panelHeight-menuHeight-margin);
        menu.x=Math.round(panelWidth ? Math.max(margin,Math.min(point.x,maxX)) : point.x);
        menu.y=Math.round(panelHeight ? Math.max(margin,Math.min(point.y-menuHeight-margin,maxY)) : point.y);
        menu.open();
    }
    // Menu-compatible entry point: coordinates are local to the parent item; no coordinates means its centre.
    function popup(px, py) {
        const owner=menu.parent;
        if(!owner){menu.open();return;}
        popupFrom(owner,px===undefined ? owner.width/2 : px,py===undefined ? owner.height/2 : py);
    }
    closePolicy:Popup.CloseOnEscape|Popup.CloseOnPressOutside
    enter:Transition {
        ParallelAnimation {
            NumberAnimation {property:"opacity";from:0;to:1;duration:Theme.motion(150)}
            NumberAnimation {property:"scale";from:.92;to:1;duration:Theme.motion(220);easing.type:Easing.OutCubic;easing.overshoot:1.2}
        }
    }
    exit:Transition {NumberAnimation {property:"opacity";to:0;duration:Theme.motion(110)}}
    background:Rectangle {
        radius:24
        color:Theme.alpha(Theme.light ? Theme.surfaceLowest : Theme.surfaceHigh,.98)
        border.width:1;border.color:Theme.glassEdge
    }
    contentItem:ContextMenuBody {
        id:body
        entries:menu.entries
        title:menu.title
        icon:menu.icon
        onActivated:entry=>{menu.close();if(entry.run)entry.run();}
    }
}
