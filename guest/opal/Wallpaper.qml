import QtQuick
Item {
    id:w
    property bool showWidgets:Hub.prefs.desktopWidgets!==false
    property string imagePath:Hub.prefs.wallpaperPath||""
    property string fit:Hub.prefs.wallpaperFit||"crop"
    property real dim:Hub.prefs.wallpaperDim||0
    readonly property bool custom:!!imagePath
    readonly property bool imageReady:!custom||photo.status===Image.Ready
    clip:true
    Rectangle {anchors.fill:parent;color:Theme.base}
    Image {id:photo;anchors.fill:parent;visible:w.custom;source:w.imagePath;fillMode:w.fit==="fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop;asynchronous:true;autoTransform:true;sourceSize.width:Math.max(1,w.width);sourceSize.height:Math.max(1,w.height)}
    Rectangle {anchors.fill:parent;visible:w.custom;color:Theme.alpha("#000000",w.dim)}
    MText {visible:w.custom&&photo.status===Image.Error;anchors.centerIn:parent;text:"Wallpaper unavailable · choose another image in Appearance";color:Theme.text}
    Loader {
        id:widgets
        active:w.showWidgets
        x:20;y:Math.max(24,w.height*.035);width:Math.min(270,w.width-40)
        sourceComponent:Component {DesktopWidgets {width:widgets.width;backdrop:photo;tall:w.height>=820;available:w.height-widgets.y-80}}
    }
}
