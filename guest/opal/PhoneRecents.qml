import QtQuick
import QtQuick.Layouts
// Recents: a header with the window count, the touch card carousel, and a way back home.
Item {
    id:recents
    ColumnLayout {
        anchors.fill:parent;anchors.margins:16;spacing:12
        RowLayout {
            Layout.fillWidth:true
            ColumnLayout {
                spacing:0
                MText {text:"Recent apps";font.pixelSize:26;font.weight:Font.Medium}
                MText {text:Hub.windows.length===1 ? "1 open window" : Hub.windows.length+" open windows";font.pixelSize:12;color:Theme.subtext}
            }
            Item {Layout.fillWidth:true}
            MButton {icon:"home";contained:true;implicitWidth:44;implicitHeight:44;tooltip:"Home";onClicked:{Hub.mobileTab="home";if(Hub.page==="launcher")Hub.close();}}
        }
        Loader {
            Layout.fillWidth:true;Layout.fillHeight:true
            active:Hub.mobileTab==="recent"
            sourceComponent:Component {WindowSwitcher {layoutMode:"phone";active:true}}
        }
    }
}
