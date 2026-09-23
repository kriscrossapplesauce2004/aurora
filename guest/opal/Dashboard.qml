import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Flickable {
    id:d
    property bool compact:false
    property date month:new Date(Hub.now.getFullYear(),Hub.now.getMonth(),1)
    readonly property int startOffset:(month.getDay()+6)%7
    readonly property int days:new Date(month.getFullYear(),month.getMonth()+1,0).getDate()
    contentHeight:body.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
    ScrollBar.vertical:ScrollBar {}
    ColumnLayout {id:body;width:d.width;spacing:16
        GridLayout {columns:d.compact ? 1 : 2;Layout.fillWidth:true;columnSpacing:16;rowSpacing:16
            FocusCard {Layout.fillWidth:true;Layout.preferredHeight:180}
            MediaCard {Layout.fillWidth:true;Layout.preferredHeight:180;compact:true}
        }
        ClipboardCard {Layout.fillWidth:true;compact:d.compact}
        GridLayout {columns:d.compact ? 1 : 2;Layout.fillWidth:true;columnSpacing:16;rowSpacing:16
            Rectangle {Layout.fillWidth:true;Layout.preferredHeight:330;radius:30;color:Theme.alpha(Theme.surfaceHigh,.65)
                ColumnLayout {anchors {fill:parent;margins:22}
spacing:10
                    RowLayout {Layout.fillWidth:true
                        MText {text:Qt.formatDateTime(d.month,"MMMM yyyy");font.pixelSize:20;font.weight:Font.DemiBold;Layout.fillWidth:true}
                        MButton {icon:"back";compact:true;tooltip:"Previous month";onClicked:d.month=new Date(d.month.getFullYear(),d.month.getMonth()-1,1)}
                        MButton {icon:"next";compact:true;tooltip:"Next month";onClicked:d.month=new Date(d.month.getFullYear(),d.month.getMonth()+1,1)}
                    }
                    GridLayout {columns:7;Layout.fillWidth:true;Layout.fillHeight:true;columnSpacing:4;rowSpacing:4
                        Repeater {model:["M","T","W","T","F","S","S"];MText {required property string modelData;text:modelData;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;color:Theme.muted;font.pixelSize:11}}
                        Repeater {model:42
                            Rectangle {required property int index
                                property int day:index-d.startOffset+1
                                property bool today:day===Hub.now.getDate()&&d.month.getMonth()===Hub.now.getMonth()&&d.month.getFullYear()===Hub.now.getFullYear()
                                Layout.fillWidth:true;Layout.fillHeight:true;radius:12;color:today ? Theme.primary : "transparent"
                                MText {anchors.centerIn:parent;text:parent.day>0&&parent.day<=d.days ? parent.day : "";font.pixelSize:12;color:parent.today ? Theme.onPrimary : Theme.subtext}
                            }
                        }
                    }
                }
            }
            Rectangle {Layout.fillWidth:true;Layout.preferredHeight:330;radius:30;color:Theme.alpha(Theme.tertiary,Theme.light ? .35 : .12)
                ColumnLayout {anchors {fill:parent;margins:24}
spacing:18
                    RowLayout {Glyph {name:"cpu";color:Theme.tertiary}MText {text:"Under the hood";font.pixelSize:21;font.weight:Font.DemiBold}}
                    // Keep these delegates mounted. Hub.status is replaced on
                    // every poll, and an inline array model rebuilt this card
                    // every time, which replayed its entrance animation.
                    ColumnLayout {Layout.fillWidth:true;spacing:10
                        RowLayout {MText {text:"Processor";Layout.fillWidth:true;color:Theme.subtext}MText {text:Hub.status.cpu+"%";font.weight:Font.Bold}}
                        Rectangle {Layout.fillWidth:true;height:12;radius:6;color:Theme.surfaceHigh
                            Rectangle {width:parent.width*Math.max(0,Math.min(100,Hub.status.cpu))/100;height:12;radius:6;color:Theme.tertiary;Behavior on width {NumberAnimation {duration:400}}}
                        }
                    }
                    ColumnLayout {Layout.fillWidth:true;spacing:10
                        RowLayout {MText {text:"Memory";Layout.fillWidth:true;color:Theme.subtext}MText {text:Hub.status.memory+"%";font.weight:Font.Bold}}
                        Rectangle {Layout.fillWidth:true;height:12;radius:6;color:Theme.surfaceHigh
                            Rectangle {width:parent.width*Math.max(0,Math.min(100,Hub.status.memory))/100;height:12;radius:6;color:Theme.tertiary;Behavior on width {NumberAnimation {duration:400}}}
                        }
                    }
                    Item {Layout.fillHeight:true}
                    MText {text:"Uptime  "+Hub.status.uptime+"  ·  "+(Hub.status.profile||"Default power profile");color:Theme.subtext;font.pixelSize:11;Layout.fillWidth:true}
                    MButton {text:"Take a screenshot";icon:"capture";tonal:true;Layout.fillWidth:true;onClicked:Hub.screenShot()}
                }
            }
        }
    }
}
