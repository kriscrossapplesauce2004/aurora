import QtQuick
import QtQuick.Effects

Item {
    id:backdrop
    readonly property real tint:Math.min(.35,Hub.prefs.glass)
    Rectangle {anchors.fill:parent;color:Theme.base}
    Wallpaper {
        anchors.fill:parent
        showWidgets:false
        layer.enabled:GraphicsInfo.api!==GraphicsInfo.Software
        layer.effect:MultiEffect {
            blurEnabled:true
            blurMax:32
            blur:.65
            autoPaddingEnabled:false
        }
    }
    Rectangle {anchors.fill:parent;color:Theme.alpha(Theme.base,backdrop.tint)}
}
