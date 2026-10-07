import QtQuick
import QtQuick.Layouts

// Automatic convergence preferences. Every trigger is on unless its key is false.
ColumnLayout {
    id:box
    spacing:2
    readonly property bool master:Hub.prefs.convergeAuto!==false
    readonly property var rows:[
        {key:"convergeKeyboard",icon:"keyboard",title:"Keyboard attach and detach",description:"A USB or Bluetooth keyboard turns a tablet into a desktop."},
        {key:"convergePointer",icon:"mouse",title:"Mouse attach and detach",description:"A USB or Bluetooth mouse does the same."},
        {key:"convergeLid",icon:"laptop_mac",title:"Lid",description:"Closing the lid with a monitor attached hands over to the monitor."},
        {key:"convergeTablet",icon:"tablet_mac",title:"Tablet mode switch",description:"Convertibles follow their tablet-mode switch."},
        {key:"convergeRotate",icon:"screen_rotation",title:"Rotation",description:"The screen follows the sensor and offers undo."},
        {key:"convergeHotplug",icon:"settings_input_hdmi",title:"Monitor plug and unplug",description:"A new monitor becomes a desktop."}
    ]
    SettingToggle {
        Layout.fillWidth:true;first:true;last:false;icon:"auto_mode";title:"Switch layouts automatically"
        description:"Opal offers an undo for every automatic change."
        checked:box.master;onToggled:Hub.set("convergeAuto",!box.master)
    }
    Repeater {
        model:box.rows
        SettingToggle {
            required property var modelData
            Layout.fillWidth:true;first:false;last:false;icon:modelData.icon;title:modelData.title;description:modelData.description
            opacity:box.master ? 1 : .5;enabled:box.master
            checked:Hub.prefs[modelData.key]!==false;onToggled:Hub.set(modelData.key,Hub.prefs[modelData.key]===false)
        }
    }
    SettingToggle {
        Layout.fillWidth:true;first:false;last:true;icon:"open_with";title:"Move apps with me"
        description:Hub.status.hypr ? "Windows follow you to a monitor and come back when you unplug it." : "Needs Hyprland. Opal cannot move windows in this session."
        opacity:box.master&&Hub.status.hypr ? 1 : .5;enabled:box.master&&!!Hub.status.hypr
        checked:Hub.prefs.convergeMoveApps!==false;onToggled:Hub.set("convergeMoveApps",Hub.prefs.convergeMoveApps===false)
    }
}
