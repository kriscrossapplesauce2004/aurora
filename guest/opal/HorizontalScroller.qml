import QtQuick
import QtQuick.Controls
Flickable {
    id:scroller
    clip:true
    flickableDirection:Flickable.HorizontalFlick
    boundsBehavior:Flickable.StopAtBounds
    contentHeight:height
    readonly property real maximumContentX:Math.max(0,contentWidth-width)
    function moveContent(delta) {
        const next=Math.max(0,Math.min(maximumContentX,contentX-delta));
        if(next!==contentX)contentX=next;
    }
    ScrollBar.horizontal:ScrollBar {policy:ScrollBar.AsNeeded;height:3}
    // Vertical mouse wheels and horizontal trackpad deltas both move a horizontal shelf.
    WheelHandler {
        target:null
        onWheel:event=>{
            const delta=event.pixelDelta.x||event.pixelDelta.y||event.angleDelta.x/3||event.angleDelta.y/3;
            if(delta)scroller.moveContent(delta);
            event.accepted=true;
        }
    }
}
