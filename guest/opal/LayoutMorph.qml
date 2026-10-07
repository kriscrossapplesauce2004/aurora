import QtQuick

// Wraps any layout content. Bind the content to "shown", not to "layout", so the swap happens between two short phases.
Item {
    id:morph
    property string layout:""
    property string shown:layout
    property bool morphing:false
    default property alias content:holder.data
    signal committed(string layout)
    readonly property var rank:({phone:0,desktop:1,console:2})
    // The incoming layout grows from a smaller scale when the screen gets bigger, and settles from a larger scale when it gets smaller.
    property real fromScale:1
    property real inScale:1
    function begin() {
        if(Theme.motion(1)===0||width<=0||height<=0||!visible) {commit();return;}
        const grow=(rank[layout]??1)>=(rank[shown]??1);
        fromScale=grow ? 1.04 : .96;
        inScale=grow ? .94 : 1.06;
        morphing=true;
        phaseOut.restart();
    }
    function commit() {
        shown=layout;
        morphing=false;
        committed(shown);
    }
    onLayoutChanged:if(layout!==shown&&!morphing)begin()
    Item {
        id:holder
        anchors.fill:parent
        transformOrigin:Item.Center
    }
    SequentialAnimation {
        id:phaseOut
        ParallelAnimation {
            NumberAnimation {target:holder;property:"opacity";to:0;duration:Theme.motion(130);easing.type:Easing.InCubic}
            NumberAnimation {target:holder;property:"scale";to:morph.fromScale;duration:Theme.motion(130);easing.type:Easing.InCubic}
        }
        ScriptAction {script:{morph.commit();holder.scale=morph.inScale;}}
        ParallelAnimation {
            NumberAnimation {target:holder;property:"opacity";to:1;duration:Theme.motion(260);easing.type:Easing.OutCubic}
            NumberAnimation {target:holder;property:"scale";to:1;duration:Theme.motion(340);easing.type:Easing.OutBack;easing.overshoot:.8}
        }
        // A layout that changed during the animation gets its own pass.
        ScriptAction {script:if(morph.layout!==morph.shown)morph.begin()}
    }
}
