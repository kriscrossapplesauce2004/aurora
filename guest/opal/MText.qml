import QtQuick
Text {
    // Set role to a Theme.type key to use the shared type scale.
    property string role: ""
    readonly property var roleSpec: role !== "" ? Theme.type[role] : null
    color: Theme.text
    font.family: Theme.font
    font.pixelSize: roleSpec ? roleSpec.size : 14
    font.weight: roleSpec ? roleSpec.weight : Font.Normal
    font.variableAxes: roleSpec ? ({"wdth": roleSpec.width, "ROND": roleSpec.round}) : ({})
    elide: Text.ElideRight
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
}
