import QtQuick
// Analog clock inside an expressive four-lobe "cookie" shape.
Item {
    id: clock
    property Item backdrop: null
    property date time: Hub.now
    readonly property bool seconds: !Theme.reduceMotion
    readonly property real hourAngle: (time.getHours() % 12 + time.getMinutes() / 60) * 30
    readonly property real minuteAngle: (time.getMinutes() + time.getSeconds() / 60) * 6
    readonly property real secondAngle: time.getSeconds() * 6
    Shape4 { id: shape; anchors.fill: parent; backdrop: clock.backdrop }
    // Hour ticks at the four quarters keep the face readable without clutter.
    Repeater {
        model: 12
        Rectangle {
            required property int index
            readonly property bool major: index % 3 === 0
            width: major ? 4 : 2; height: major ? 4 : 2; radius: width / 2
            color: Theme.alpha(Theme.light ? Theme.containerInk : Theme.text, major ? .55 : .3)
            x: clock.width / 2 + Math.sin(index * Math.PI / 6) * clock.width * .36 - width / 2
            y: clock.height / 2 - Math.cos(index * Math.PI / 6) * clock.height * .36 - height / 2
        }
    }
    Hand { length: clock.width * .21; thickness: Math.max(6, clock.width * .06); angle: clock.hourAngle; color: Theme.light ? Theme.containerInk : Theme.primary }
    Hand { length: clock.width * .32; thickness: Math.max(3, clock.width * .03); angle: clock.minuteAngle; color: Theme.light ? Theme.alpha(Theme.containerInk, .8) : Theme.text }
    Hand { visible: clock.seconds; length: clock.width * .36; thickness: 1.5; tail: clock.width * .06; angle: clock.secondAngle; color: Theme.light ? Theme.mix(Theme.tertiary, "#000000", .35) : Theme.tertiary }
    Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: Theme.light ? Theme.containerInk : Theme.text }
    component Hand: Rectangle {
        id: hand
        property real length: 30
        property real thickness: 3
        property real tail: 0
        property real angle: 0
        width: thickness; height: length + tail; radius: thickness / 2
        x: clock.width / 2 - width / 2
        y: clock.height / 2 - length
        antialiasing: true
        transform: Rotation { origin.x: hand.thickness / 2; origin.y: hand.length; angle: hand.angle }
    }
    component Shape4: Item {
        property Item backdrop: null
        // The shape is a soft square with concave sides: a four-lobe flower turned 45 degrees.
        Flower {
            anchors.fill: parent; lobes: 4; depth: .13; phase: 45
            fill: Theme.alpha(Theme.light ? Theme.primaryContainer : Theme.glassRaised, Theme.light ? .86 : .78)
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: Qt.formatDateTime(time, "HH:mm")
}
