import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id:p
    property string kind:"wifi"
    property var backAction:()=>{Hub.controlDetail="";}
    property bool embedded:false
    readonly property bool wifi:kind==="wifi"
    readonly property var state:Hub.connectivity[kind]
    readonly property var items:state.items
    property var selected:null
    spacing:12
    Component.onCompleted:Hub.connection(kind,"refresh")
    onKindChanged:{selected=null;password.clear();Hub.connection(kind,"refresh");}
    RowLayout {
        Layout.fillWidth:true
        MButton {visible:!p.embedded;icon:"back";tooltip:"Back";onClicked:p.backAction()}
        MText {text:p.embedded ? (p.state.powered ? "On" : "Off") : p.wifi ? "Wi-Fi" : "Bluetooth";font.pixelSize:p.embedded ? 16 : 24;font.weight:p.embedded ? Font.Medium : Font.Normal;Layout.fillWidth:true}
        MButton {text:p.state.powered ? "Turn off" : "Turn on";tonal:true;enabled:!p.state.busy;onClicked:Hub.connection(p.kind,"power",{enabled:!p.state.powered})}
    }
    MText {Layout.fillWidth:true;wrapMode:Text.Wrap;text:p.state.busy ? "Working…" : p.state.error || (p.wifi ? "Choose a network. Saved credentials are reused." : "Scan for nearby devices. Pairing that needs a PIN confirmation requires a system Bluetooth agent.");color:Theme.subtext;font.pixelSize:12}
    MButton {Layout.fillWidth:true;text:p.state.busy ? "Please wait…" : "Scan nearby";icon:"search";tonal:true;enabled:!p.state.busy&&p.state.powered;onClicked:Hub.connection(p.kind,"scan")}
    ListView {
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true;spacing:8;model:p.items;reuseItems:true
        ScrollBar.vertical:ScrollBar {}
        delegate:Rectangle {
            required property var modelData
            width:ListView.view.width;height:76;radius:20;color:modelData.active ? Theme.primaryContainer : Theme.surfaceHigh
            RowLayout {anchors.fill:parent;anchors.margins:14;spacing:12
                Glyph {name:p.wifi ? "wifi" : "bluetooth";color:Theme.primary}
                ColumnLayout {Layout.fillWidth:true;spacing:4
                    MText {Layout.fillWidth:true;text:p.wifi ? modelData.ssid : modelData.name;font.weight:Font.DemiBold}
                    MText {Layout.fillWidth:true;text:modelData.active ? "Connected" : p.wifi ? modelData.signal+"% signal · "+(modelData.security||"Open network") : modelData.paired ? "Paired" : "Not paired";font.pixelSize:11;color:Theme.subtext}
                }
                Glyph {name:"next";color:Theme.subtext}
            }
            MouseArea {anchors.fill:parent;enabled:!p.state.busy;onClicked:{p.selected=modelData;password.clear();}}
        }
        MText {anchors.centerIn:parent;width:parent.width;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;visible:!p.state.busy&&!p.items.length;text:p.state.powered ? "No devices found. Try scanning nearby." : "Radio is off or unavailable.";color:Theme.subtext}
    }
    ColumnLayout {
        visible:p.selected!==null;Layout.fillWidth:true;spacing:8
        MText {Layout.fillWidth:true;text:p.selected ? (p.wifi ? p.selected.ssid : p.selected.name) : "";font.weight:Font.DemiBold}
        TextField {id:password;Layout.fillWidth:true;visible:p.wifi&&p.selected!==null&&!p.selected.active&&!!p.selected.security;placeholderText:"Password (blank for saved network)";echoMode:TextInput.Password;color:Theme.text;selectByMouse:true}
        RowLayout {Layout.fillWidth:true
            MButton {Layout.fillWidth:true;filled:true;enabled:!p.state.busy;text:p.selected&&p.selected.active ? "Disconnect" : !p.wifi&&p.selected&&!p.selected.paired ? "Pair" : "Connect";onClicked:{let s=p.selected;Hub.connection(p.kind,s.active ? "disconnect" : !p.wifi&&!s.paired ? "pair" : "connect",{ssid:s.ssid,device:s.device,address:s.address,password:password.text});password.clear();p.selected=null;}}
            MButton {text:"Cancel";onClicked:{p.selected=null;password.clear();}}
        }
    }
}
