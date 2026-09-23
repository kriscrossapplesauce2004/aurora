import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
Rectangle {
    id:m
    property bool compact:false
    property bool expandable:false
    readonly property bool hasTrack:Hub.status.track!==""
    readonly property bool hasArt:Hub.status.art!==""&&art.status===Image.Ready
    implicitHeight:compact ? 150 : 176
    radius:30;color:Theme.alpha(Theme.secondary,Theme.light ? .5 : .16)
    // Ambient art: the cover, blurred and masked to the card shape, tints the background.
    Image {id:ambient;visible:false;source:Hub.status.art;asynchronous:true;fillMode:Image.PreserveAspectCrop;sourceSize:Qt.size(96,96);width:m.width;height:m.height}
    Rectangle {id:ambientMask;visible:false;width:m.width;height:m.height;radius:m.radius;layer.enabled:true}
    MultiEffect {anchors.fill:parent;visible:m.hasArt;opacity:Theme.light ? .28 : .22;source:ambient;blurEnabled:true;blur:1;blurMax:40;saturation:.2;maskEnabled:true;maskSource:ambientMask;maskThresholdMin:.5;maskSpreadAtMin:1;autoPaddingEnabled:false}
    MButton {visible:m.expandable;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:6;implicitWidth:32;implicitHeight:32;compact:true;icon:"expand";tooltip:"Open sound & music";z:2;onClicked:Hub.openAudio(Hub.targetScreen)}
    RowLayout {anchors {fill:parent;margins:m.compact ? 16 : 20}
        spacing:m.compact ? 14 : 18
        Item {Layout.preferredWidth:m.compact ? 72 : 110;Layout.preferredHeight:width;Layout.alignment:Qt.AlignVCenter
            Flower {id:disc;anchors.fill:parent;fill:Theme.secondary;lobes:10
                NumberAnimation on rotation {from:0;to:360;duration:45000;loops:Animation.Infinite;running:Hub.status.playing&&!Theme.reduceMotion}
            }
            Rectangle {id:hole;anchors.centerIn:parent;width:parent.width*.62;height:width;radius:width/2;color:Theme.base
                Glyph {anchors.centerIn:parent;name:"music";color:Theme.secondary;font.pixelSize:m.compact ? 24 : 28}
            }
            // Album art fills the centre of the disc, masked to a circle.
            Image {id:art;visible:false;source:Hub.status.art;asynchronous:true;fillMode:Image.PreserveAspectCrop;sourceSize:Qt.size(160,160);width:hole.width;height:hole.height}
            Rectangle {id:artMask;visible:false;width:hole.width;height:hole.height;radius:width/2;layer.enabled:true}
            MultiEffect {anchors.centerIn:parent;width:hole.width;height:hole.height;visible:m.hasArt;source:art;maskEnabled:true;maskSource:artMask;maskThresholdMin:.5;maskSpreadAtMin:1;autoPaddingEnabled:false}
        }
        ColumnLayout {Layout.fillWidth:true;Layout.minimumWidth:0;spacing:m.compact ? 4 : 8
            MText {Layout.fillWidth:true;text:Hub.status.playing ? "NOW PLAYING" : m.hasTrack ? "PAUSED" : "YOUR SOUNDTRACK";color:Theme.subtext;font.pixelSize:9;font.letterSpacing:1.8}
            MText {text:Hub.status.track||"A little music goes a long way.";Layout.fillWidth:true;maximumLineCount:m.compact ? 1 : 2;wrapMode:Text.Wrap;font.pixelSize:m.compact ? 15 : 19;font.weight:Font.DemiBold}
            MText {text:Hub.status.artist||"Start playback in any MPRIS player";color:Theme.subtext;font.pixelSize:11;Layout.fillWidth:true}
            RowLayout {spacing:m.compact ? 2 : 8;Layout.topMargin:m.compact ? 4 : 0
                MButton {icon:"previous";compact:true;implicitWidth:m.compact ? 36 : 42;enabled:m.hasTrack;tooltip:"Previous";onClicked:Hub.media("previous")}
                MButton {icon:Hub.status.playing ? "pause" : "play";filled:true;morph:true;checked:Hub.status.playing;accent:Theme.secondary;fillInk:Theme.light ? Theme.onSecondaryContainer : Theme.base;implicitWidth:m.compact ? 56 : 66;implicitHeight:m.compact ? 38 : 42;enabled:m.hasTrack;tooltip:Hub.status.playing ? "Pause" : "Play";onClicked:Hub.media("play-pause")}
                MButton {icon:"skip";compact:true;implicitWidth:m.compact ? 36 : 42;enabled:m.hasTrack;tooltip:"Next";onClicked:Hub.media("next")}
            }
        }
    }
}
