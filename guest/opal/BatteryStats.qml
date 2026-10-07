import QtQuick
import QtQuick.Layouts
// Battery page: level, time left, draw, health and a history chart for this session.
Item {
    id: page
    signal closeRequested()
    readonly property var b: PhoneState.battery
    readonly property var history: PhoneState.batteryHistory
    readonly property bool charging: b.status === "Charging"
    readonly property string timeText: {
        if (!b.hours) return "";
        const minutes = Math.round(b.hours * 60);
        const text = minutes >= 60 ? Math.floor(minutes / 60) + " h " + (minutes % 60) + " min" : minutes + " min";
        return text + (charging ? " until full" : " left");
    }
    readonly property var tiles: {
        const list = [];
        if (b.watts !== null && b.watts !== undefined) list.push({icon: "bolt", label: charging ? "Charging power" : "Power draw", value: b.watts.toFixed(1) + " W"});
        if (b.health) list.push({icon: "ecg_heart", label: "Battery health", value: b.health + "%"});
        if (b.cycles) list.push({icon: "autorenew", label: "Charge cycles", value: String(b.cycles)});
        if (b.celsius) list.push({icon: "thermostat", label: "Temperature", value: b.celsius.toFixed(1) + " °C"});
        if (b.volts) list.push({icon: "electric_meter", label: "Voltage", value: b.volts.toFixed(2) + " V"});
        return list;
    }
    Component.onCompleted: PhoneState.refreshBattery()
    Timer { interval: 15000; repeat: true; running: page.visible; onTriggered: PhoneState.refreshBattery() }
    onHistoryChanged: chart.requestPaint()
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 14
        RowLayout {
            Layout.fillWidth: true
            MButton { icon: "arrow_back"; contained: true; implicitWidth: PhoneState.hit; implicitHeight: PhoneState.hit; tooltip: "Back"; onClicked: page.closeRequested() }
            MText { text: "Battery"; font.pixelSize: 26; font.weight: Font.Medium; Layout.leftMargin: 8; Layout.fillWidth: true }
        }
        // Level hero: a pill filled to the charge level.
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 132; radius: 36; color: Theme.level(2); clip: true
            Rectangle {
                height: parent.height; radius: parent.radius
                width: parent.width * Math.max(.06, (b.percent !== null && b.percent !== undefined ? b.percent : Math.max(0, Hub.status.battery)) / 100)
                color: (b.percent || 0) <= 15 && !page.charging ? Theme.alpha(Theme.error, .45) : Theme.alpha(Theme.primary, .3)
                Behavior on width { NumberAnimation { duration: Theme.motion(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter; x: 24; spacing: 2
                MText { text: (b.percent !== null && b.percent !== undefined ? b.percent : Math.max(0, Hub.status.battery)) + "%"; font.pixelSize: 52; font.weight: Font.Black; font.variableAxes: ({"wdth": 125, "ROND": 100}); color: Theme.text }
                MText { text: (b.status || (Hub.status.charging ? "Charging" : "Discharging")) + (page.timeText ? " · " + page.timeText : ""); font.pixelSize: 14; color: Theme.text }
            }
            Glyph { anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; name: page.charging ? "bolt" : "battery_full"; font.pixelSize: 40; color: Theme.text }
        }
        Grid {
            Layout.fillWidth: true; columns: 2; spacing: 8
            visible: page.tiles.length > 0
            Repeater {
                model: page.tiles
                Rectangle {
                    required property var modelData
                    width: (page.width - 32 - 8) / 2; height: 72; radius: 24; color: Theme.level(3)
                    Row {
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        Glyph { name: modelData.icon; font.pixelSize: 22; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            MText { text: modelData.value; font.pixelSize: 18; font.weight: Font.DemiBold }
                            MText { text: modelData.label; font.pixelSize: 11; color: Theme.subtext }
                        }
                    }
                }
            }
        }
        // History: percent over time since this page opened.
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 120; Layout.maximumHeight: 260; radius: 28; color: Theme.level(2)
            MText { x: 18; y: 14; text: "Since you opened this page"; font.pixelSize: 12; color: Theme.subtext }
            MText { anchors.centerIn: parent; visible: page.history.length < 2; text: "Collecting readings…"; color: Theme.subtext; font.pixelSize: 13 }
            Canvas {
                id: chart
                anchors.fill: parent; anchors.margins: 18; anchors.topMargin: 40
                visible: page.history.length >= 2
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const h = page.history;
                    if (h.length < 2) return;
                    const lo = Math.max(0, Math.min.apply(null, h.map(p => p.percent)) - 3), hi = Math.min(100, Math.max.apply(null, h.map(p => p.percent)) + 3);
                    const t0 = h[0].t, span = Math.max(1, h[h.length - 1].t - t0);
                    const x = p => (p.t - t0) / span * width, y = p => height - (p.percent - lo) / Math.max(1, hi - lo) * height;
                    ctx.beginPath();
                    h.forEach((p, i) => i ? ctx.lineTo(x(p), y(p)) : ctx.moveTo(x(p), y(p)));
                    ctx.lineWidth = 3; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.strokeStyle = Theme.primary; ctx.stroke();
                    ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath();
                    ctx.fillStyle = Theme.alpha(Theme.primary, .16); ctx.fill();
                }
            }
        }
        SegmentedButtons {
            Layout.fillWidth: true
            options: [{value: "power-saver", label: "Saver", icon: "eco"}, {value: "balanced", label: "Balanced", icon: "balance"}, {value: "performance", label: "Performance", icon: "speed"}]
            current: Hub.status.profile || "balanced"
            onPicked: value => Hub.command({action: "profile", value: value})
        }
    }
}
