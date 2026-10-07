import QtQuick
// Torch button. It is hidden when the device has no flash LED.
MButton {
    visible: PhoneState.torch.available
    icon: "flashlight_on"
    filled: PhoneState.torch.on
    contained: !PhoneState.torch.on
    implicitWidth: PhoneState.hit
    implicitHeight: PhoneState.hit
    tooltip: PhoneState.torch.on ? "Torch off" : "Torch on"
    onClicked: PhoneState.setTorch(!PhoneState.torch.on)
    Accessible.name: "Torch"
    Accessible.checkable: true
    Accessible.checked: PhoneState.torch.on
}
