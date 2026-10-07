import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Flickable {
    id:a
    property bool compact:false
    property bool embedded:false
    readonly property int selectedPalette:Hub.prefs.palette
    readonly property bool dynamicColorsEnabled:!!Hub.prefs.dynamicColors
    readonly property string selectedColorScheme:Hub.prefs.colorScheme
    readonly property var colorSchemes:[{id:"scheme-tonal-spot",name:"Tonal"},{id:"scheme-expressive",name:"Expressive"},{id:"scheme-vibrant",name:"Vibrant"},{id:"scheme-neutral",name:"Neutral"}]
    readonly property var layoutModes:[{id:"auto",icon:"expand",title:"Automatic",subtitle:"Adapt to each output: phone, portrait tablet, or desktop."},{id:"desktop",icon:"desktop",title:"Desktop",subtitle:"Compact app drawer and a real running-app taskbar."},{id:"phone",icon:"phone",title:"Phone",subtitle:"Edge-to-edge home, app drawer, recents and touch actions."},{id:"console",icon:"game",title:"Console",subtitle:"Large game tiles; keyboard and D-pad navigation."}]
    clip:true;contentHeight:body.implicitHeight+24;boundsBehavior:Flickable.StopAtBounds
    ScrollBar.vertical:ScrollBar {}
    ColumnLayout {id:body;width:a.width;spacing:22
        MText {visible:!a.embedded;text:"Your device. Your personality.";font.pixelSize:a.compact ? 22 : 28;font.weight:Font.DemiBold;Layout.fillWidth:true}
        Rectangle {Layout.fillWidth:true;Layout.preferredHeight:164;radius:32;clip:true;color:Theme.surface
            Wallpaper {anchors.fill:parent;showWidgets:false}
            MButton {anchors {right:parent.right;bottom:parent.bottom;margins:14} icon:"palette";text:"Wallpaper studio";filled:true;onClicked:Hub.page="wallpaper"}
        }
        MText {Layout.fillWidth:true;text:"Pick an image. Nothing changes until you apply.";wrapMode:Text.Wrap;font.pixelSize:12;color:Theme.subtext}
        MText {text:"COLOR & MOOD";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        RowLayout {Layout.fillWidth:true;spacing:10
            Repeater {model:Theme.palettes
                Rectangle {required property var modelData;required property int index
                    Layout.fillWidth:true;Layout.preferredHeight:94;radius:a.selectedPalette===index ? 28 : 18;color:modelData.primary
                    border.width:a.selectedPalette===index ? 3 : 0;border.color:Theme.text
                    Flower {width:40;height:40;anchors {horizontalCenter:parent.horizontalCenter;top:parent.top;topMargin:10}
fill:modelData.onPrimary;lobes:6
                        Glyph {anchors.centerIn:parent;name:a.selectedPalette===index ? "check" : "";font.pixelSize:20;color:modelData.primary;visible:a.selectedPalette===index}
                    }
                    MText {anchors {bottom:parent.bottom;bottomMargin:12;horizontalCenter:parent.horizontalCenter}
text:modelData.name;color:modelData.onPrimary;font.pixelSize:12;font.weight:Font.DemiBold}
                    MouseArea {anchors.fill:parent;onClicked:{Hub.set("dynamicColors",false);Hub.set("palette",index);}}
                }
            }
        }
        MButton {Layout.fillWidth:true;icon:"palette";text:Hub.themeBusy ? "Extracting wallpaper colors…" : "Matugen · generate from wallpaper";filled:true;enabled:!!Hub.prefs.wallpaperPath&&!Hub.themeBusy;onClicked:Hub.command({action:"matugen"})}
        Flow {Layout.fillWidth:true;spacing:6
            Repeater {model:a.colorSchemes
                MButton {required property var modelData;text:modelData.name;compact:true;filled:a.selectedColorScheme===modelData.id;tonal:true;onClicked:Hub.set("colorScheme",modelData.id)}
            }
        }
        MButton {visible:!!Hub.prefs.dynamicPalette&&!!Hub.prefs.dynamicPalette.dark;Layout.fillWidth:true;text:a.dynamicColorsEnabled ? "Wallpaper colors on" : "Use saved wallpaper colors";tonal:true;icon:"check";onClicked:Hub.set("dynamicColors",!a.dynamicColorsEnabled)}
        MText {Layout.fillWidth:true;text:"Colors come from your wallpaper.";wrapMode:Text.Wrap;color:Theme.subtext;font.pixelSize:11}
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {Layout.fillWidth:true;icon:"moon";text:"Dark";filled:!Theme.light;tonal:Theme.light;onClicked:Hub.set("light",false)}
            MButton {Layout.fillWidth:true;icon:"sun";text:"Light";filled:Theme.light;tonal:!Theme.light;onClicked:Hub.set("light",true)}
        }
        MText {text:"GLASS & MATERIAL";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        MText {text:"Panel density · "+Math.round(Hub.prefs.glass*100)+"%";color:Theme.subtext}
        ExpressiveSlider {Layout.fillWidth:true;from:45;to:100;value:Hub.prefs.glass*100;icon:"sun";onMoved:Hub.set("glass",Math.round(value)/100)}
        MText {text:"APP ICONS";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        SegmentedButtons {Layout.fillWidth:true;current:Hub.prefs.iconStyle||"raw"
            options:[{value:"raw",label:"Original",icon:"apps"},{value:"squircle",label:"Backplate",icon:"rounded_corner"},{value:"themed",label:"Themed",icon:"palette"}]
            onPicked:value=>Hub.set("iconStyle",value)}
        MText {text:"BAR";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        SegmentedButtons {Layout.fillWidth:true;current:Hub.prefs.barStyle||"islands"
            options:[{value:"islands",label:"Islands",icon:"view_column"},{value:"dock",label:"Dock",icon:"call_to_action"},{value:"split",label:"Split",icon:"splitscreen"},{value:"edge",label:"Edge",icon:"bottom_navigation"}]
            onPicked:value=>Hub.set("barStyle",value)}
        MText {text:"LAYOUT";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        Repeater {model:a.layoutModes
            Rectangle {required property var modelData;Layout.fillWidth:true;height:84;radius:24;color:Hub.prefs.mode===modelData.id ? Theme.primaryContainer : Theme.alpha(Theme.surface,.6)
                Glyph {x:22;anchors.verticalCenter:parent.verticalCenter;name:modelData.icon;color:Theme.primary;font.pixelSize:30}
                Column {x:72;anchors.verticalCenter:parent.verticalCenter;width:parent.width-100;spacing:7
                    MText {text:modelData.title;font.pixelSize:17;font.weight:Font.DemiBold;color:Hub.prefs.mode===modelData.id ? Theme.onContainer : Theme.text}
                    MText {text:modelData.subtitle;width:parent.width;font.pixelSize:11;color:Theme.subtext}
                }
                MouseArea {anchors.fill:parent;onClicked:Hub.mode(modelData.id)}
            }
        }
        MButton {Layout.fillWidth:true;icon:"home";text:Hub.prefs.desktopWidgets!==false ? "Desktop widgets on" : "Desktop widgets off";tonal:true;onClicked:Hub.set("desktopWidgets",Hub.prefs.desktopWidgets===false)}
        MText {text:"TASKBAR & NAVIGATION";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        MButton {Layout.fillWidth:true;icon:"expand";text:Hub.prefs.taskbarAutoHide ? "Auto-hide on · zero reserved space" : "Floating shelf · always visible";tonal:true;onClicked:Hub.set("taskbarAutoHide",!Hub.prefs.taskbarAutoHide)}
        MButton {Layout.fillWidth:true;icon:"phone";text:Hub.prefs.phoneButtons ? "Phone: three-button navigation" : "Phone: gesture strip & shortcuts";tonal:true;onClicked:Hub.set("phoneButtons",!Hub.prefs.phoneButtons)}
        MText {text:"CONTROLLER BUTTON ORDER";font.pixelSize:10;font.letterSpacing:2;color:Theme.subtext}
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {Layout.fillWidth:true;text:"Standard / Xbox";filled:Hub.prefs.controllerLayout!=="nintendo";tonal:Hub.prefs.controllerLayout==="nintendo";onClicked:Hub.set("controllerLayout","standard")}
            MButton {Layout.fillWidth:true;text:"Nintendo";filled:Hub.prefs.controllerLayout==="nintendo";tonal:Hub.prefs.controllerLayout!=="nintendo";onClicked:Hub.set("controllerLayout","nintendo")}
        }
        MText {Layout.fillWidth:true;text:"Changes save automatically.";wrapMode:Text.Wrap;color:Theme.muted;font.pixelSize:11}
    }
}
