import QtQuick
Text {
    property string name:"apps"
    readonly property var glyphs: Theme.glyphs
    text:glyphs[name]||name
    font.family:"Material Symbols Rounded"
    font.pixelSize:22
    color:Theme.text
    horizontalAlignment:Text.AlignHCenter
    verticalAlignment:Text.AlignVCenter
    renderType:Text.QtRendering
}
