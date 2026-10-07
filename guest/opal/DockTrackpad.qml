import QtQuick
import QtQuick.Layouts

// Use one finger to move and two fingers to scroll.
Item {
    id: pad
    property real speed: 1.8
    property bool holding: false
    property var send: function(data) { Hub.command(Object.assign({action: "pointer"}, data)); }
    ColumnLayout {
        anchors.fill: parent; spacing: 10
        Rectangle {
            id: surface
            Layout.fillWidth: true; Layout.fillHeight: true
            radius: Theme.shapeXl; color: Theme.level(2)
            border.width: pad.holding ? 3 : 0; border.color: Theme.primary
            MText { anchors.centerIn: parent; text: pad.holding ? "Dragging" : "Trackpad"; role: "headline"; color: Theme.alpha(Theme.text, .18) }
            MultiPointTouchArea {
                id: touch
                objectName: "trackpadTouch"
                anchors.fill: parent
                maximumTouchPoints: 2
                mouseEnabled: false
                touchPoints: [TouchPoint { id: firstFinger }, TouchPoint { id: secondFinger }]
                property var last: ({})
                property real travel: 0
                property int fingers: 0
                property double began: 0
                property int previousCount: 0
                function reset() {
                    hold.stop();
                    if (pad.holding) pad.send({op: "up", button: "left"});
                    pad.holding = false;
                    last = ({}); fingers = 0; began = 0; travel = 0; previousCount = 0;
                }
                Component.onDestruction: reset()
                onCanceled: reset()
                Timer { id: hold; interval: 450; onTriggered: if (touch.fingers === 1 && touch.travel < 8) { pad.holding = true; pad.send({op: "down", button: "left"}); } }
                onPressed: points => {
                    const live = [firstFinger, secondFinger].filter(p => p.pressed);
                    fingers = Math.max(fingers, live.length);
                    if (began === 0) { began = Date.now(); travel = 0; hold.restart(); }
                    if (live.length > 1) {
                        hold.stop();
                        if (pad.holding) { pad.send({op: "up", button: "left"}); pad.holding = false; }
                    }
                    live.forEach(p => last[p.pointId] = Qt.point(p.x, p.y));
                    previousCount = live.length;
                }
                onUpdated: points => {
                    let dx = 0, dy = 0, n = 0;
                    const active = [firstFinger, secondFinger].filter(p => p.pressed);
                    active.forEach(p => { const before = last[p.pointId]; if (before) { dx += p.x - before.x; dy += p.y - before.y; n++; } last[p.pointId] = Qt.point(p.x, p.y); });
                    if (active.length !== previousCount) { previousCount = active.length; return; }
                    if (!n) return;
                    dx /= n; dy /= n;
                    travel += Math.abs(dx) + Math.abs(dy);
                    if (travel >= 8) hold.stop();
                    const live = active.length;
                    const gain = pad.speed;
                    if (live >= 2) pad.send({op: "scroll", dx: -dx * .6, dy: -dy * .6});
                    else if (fingers === 1) pad.send({op: "move", dx: dx * gain, dy: dy * gain});
                }
                onReleased: points => {
                    points.forEach(p => delete last[p.pointId]);
                    if (firstFinger.pressed || secondFinger.pressed) return;
                    hold.stop();
                    const quick = Date.now() - began < 250 && travel < 10;
                    if (pad.holding) { pad.send({op: "up", button: "left"}); pad.holding = false; }
                    else if (quick) pad.send({op: "click", button: fingers >= 2 ? "right" : "left"});
                    reset();
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: false; Layout.preferredHeight: 64; Layout.maximumHeight: 64; spacing: 10
            Repeater {
                model: [{b: "left", label: "Left"}, {b: "right", label: "Right"}]
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: Theme.shapeLg
                    color: buttonArea.pressed ? Theme.primaryContainer : Theme.level(3)
                    MText { anchors.centerIn: parent; text: parent.modelData.label; role: "titleS"; color: buttonArea.pressed ? Theme.onContainer : Theme.text }
                    MouseArea { id: buttonArea; anchors.fill: parent
                        onPressed: pad.send({op: "down", button: parent.modelData.b})
                        onReleased: pad.send({op: "up", button: parent.modelData.b})
                        onCanceled: pad.send({op: "up", button: parent.modelData.b}) }
                }
            }
            MButton { Layout.fillHeight: true; implicitWidth: 64; icon: "keyboard"; contained: true; tooltip: "Keyboard"; onClicked: Hub.systemOsk("show") }
        }
    }
}
