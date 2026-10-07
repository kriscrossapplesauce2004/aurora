import QtQuick
import QtQuick.Layouts

// What Claude did in one answer. Closed, it is one line: the live step, or a summary. Open, it is a timeline with details and errors.
Rectangle {
    id:group
    property var steps:[]
    property bool live:false
    // A failed step opens the timeline so the reason is visible.
    property bool expanded:failed>0
    readonly property var running:steps.filter(s=>s.status==="running")
    readonly property int failed:steps.filter(s=>s.status==="error").length
    readonly property var current:running.length ? running[running.length-1] : null
    readonly property string summary:{
        const names=[];steps.forEach(s=>{const n=s.status==="running" ? s.running : s.doneLabel||s.label;if(names.indexOf(n)<0)names.push(n);});
        return names.slice(0,2).join(", ")+(names.length>2 ? " and more" : "");
    }
    implicitHeight:column.implicitHeight+16
    radius:20
    color:Theme.alpha(Theme.level(2),.9)
    border.width:failed ? 1 : 0;border.color:Theme.alpha(Theme.error,.4)
    clip:true
    Behavior on implicitHeight {NumberAnimation {duration:Theme.motion(260);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasized}}

    Column {
        id:column
        x:8;y:8;width:parent.width-16;spacing:2
        // Header line. Tap opens or closes the timeline.
        Item {
            width:parent.width;height:40
            RowLayout {
                anchors.fill:parent;anchors.leftMargin:6;anchors.rightMargin:4;spacing:10
                Item {
                    Layout.preferredWidth:26;Layout.preferredHeight:26
                    Rectangle {anchors.fill:parent;radius:13;color:group.failed&&!group.current ? Theme.alpha(Theme.error,.16) : Theme.primaryContainer}
                    Glyph {
                        id:headIcon;anchors.centerIn:parent;font.pixelSize:16
                        name:group.current ? "progress_activity" : group.failed ? "error" : "check"
                        color:group.failed&&!group.current ? Theme.error : Theme.containerInk
                        RotationAnimation on rotation {running:!!group.current&&!Theme.reduceMotion;from:0;to:360;duration:900;loops:Animation.Infinite}
                        onNameChanged:rotation=0
                    }
                }
                ColumnLayout {
                    Layout.fillWidth:true;spacing:0
                    MText {
                        Layout.fillWidth:true;elide:Text.ElideRight;role:"label";font.weight:Font.DemiBold
                        text:group.current ? group.current.running+"…" : group.steps.length+(group.steps.length===1 ? " step" : " steps")+(group.failed ? " · "+group.failed+" failed" : "")
                        color:group.failed&&!group.current ? Theme.error : Theme.text
                    }
                    MText {
                        Layout.fillWidth:true;elide:Text.ElideRight;role:"labelS";color:Theme.subtext
                        visible:text!==""
                        text:group.current ? (group.current.detail||"") : group.summary
                    }
                }
                Glyph {
                    name:"expand_more";font.pixelSize:20;color:Theme.subtext
                    rotation:group.expanded ? 180 : 0
                    Behavior on rotation {NumberAnimation {duration:Theme.motion(200)}}
                }
            }
            TapHandler {onTapped:group.expanded=!group.expanded}
            HoverHandler {cursorShape:Qt.PointingHandCursor}
            Accessible.role:Accessible.Button
            Accessible.name:(group.expanded ? "Hide " : "Show ")+group.steps.length+" steps"
        }
        // Timeline.
        Repeater {
            model:group.expanded ? group.steps : []
            Item {
                id:step
                required property var modelData
                required property int index
                readonly property bool bad:modelData.status==="error"
                readonly property bool busy:modelData.status==="running"
                width:column.width;height:row.implicitHeight+12
                // The line that joins one step to the next.
                Rectangle {x:18;y:28;width:2;height:parent.height-22;radius:1;color:Theme.outline;visible:step.index<group.steps.length-1}
                RowLayout {
                    id:row;x:6;y:6;width:parent.width-12;spacing:10
                    Rectangle {
                        Layout.alignment:Qt.AlignTop;Layout.preferredWidth:26;Layout.preferredHeight:26;radius:13
                        color:step.bad ? Theme.alpha(Theme.error,.16) : step.busy ? Theme.primaryContainer : Theme.level(3)
                        Glyph {anchors.centerIn:parent;name:step.modelData.icon||"bolt";font.pixelSize:15;color:step.bad ? Theme.error : step.busy ? Theme.containerInk : Theme.subtext}
                    }
                    ColumnLayout {
                        Layout.fillWidth:true;spacing:2
                        RowLayout {
                            Layout.fillWidth:true;spacing:6
                            MText {text:step.busy ? step.modelData.running : (step.modelData.doneLabel||step.modelData.label);role:"label";color:step.bad ? Theme.error : Theme.text;Layout.fillWidth:true;elide:Text.ElideRight}
                            Rectangle {
                                visible:!!step.modelData.auto;implicitWidth:autoText.implicitWidth+12;implicitHeight:18;radius:9;color:Theme.alpha(Theme.tertiary,.18)
                                MText {id:autoText;anchors.centerIn:parent;text:"Auto";role:"labelS";color:Theme.tertiary}
                            }
                        }
                        MText {
                            visible:(step.modelData.detail||"")!=="";Layout.fillWidth:true
                            text:step.modelData.detail||"";font.family:"monospace";font.pixelSize:11;color:Theme.subtext;elide:Text.ElideMiddle
                        }
                        MText {
                            visible:step.bad&&(step.modelData.error||"")!=="";Layout.fillWidth:true
                            text:step.modelData.error||"";role:"labelS";color:Theme.error;wrapMode:Text.Wrap;maximumLineCount:3;elide:Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
