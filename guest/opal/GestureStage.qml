import QtQuick
// Gesture feedback: a live card follows the finger, with a scrim, labels and the back bubble.
Item {
    id: stage
    readonly property string phase: PhoneState.phase
    readonly property bool settling: PhoneState.outcome !== ""
    readonly property bool cardPhase: phase === "home" || phase === "recents" || phase === "switch"
    // Settle: 0 follows the finger and 1 is the end pose of the outcome.
    property real settle: 0
    NumberAnimation on settle {
        id: settleAnim; from: 0; to: 1; running: false; duration: Theme.motion(240)
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate
        onFinished: PhoneState.finish()
    }
    Connections {
        target: PhoneState
        function onOutcomeChanged() { if (PhoneState.outcome !== "") { stage.settle = 0; settleAnim.restart(); } }
        function onPhaseChanged() { if (PhoneState.phase === "") { settleAnim.stop(); stage.settle = 0; } }
    }
    readonly property real p: PhoneState.progress
    // The scrim gives way to a quiet wallpaper while a card moves.
    Item {
        anchors.fill: parent
        opacity: stage.cardPhase ? (stage.settling && PhoneState.outcome === "cancel" ? 1 - stage.settle : Math.min(1, .35 + stage.p * 1.2)) : 0
        visible: opacity > 0
        PhoneBackdrop { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.base, .35) }
    }
    // The moving card follows the finger. Home shrinks it, recents holds it small, switch slides it.
    GestureCard {
        id: current
        visible: stage.cardPhase
        entry: PhoneState.activeWindow()
        readonly property real shrink: stage.phase === "recents" ? .58 : 1 - Math.min(1, stage.p) * .5
        readonly property real endShrink: PhoneState.outcome === "home" ? .12 : PhoneState.outcome === "recents" ? .58 : 1
        readonly property real k: stage.settling ? shrink + (endShrink - shrink) * stage.settle : shrink
        width: stage.width; height: stage.height
        scale: stage.phase === "switch" ? .86 : k
        transformOrigin: Item.Center
        radius: 12 + 28 * (1 - Math.min(1, scale))
        x: stage.phase === "switch" ? PhoneState.dx * (stage.settling && PhoneState.outcome === "switch" ? 1 + stage.settle : 1) : PhoneState.dx * .35
        y: stage.phase === "switch" ? 0 : PhoneState.dy * .8 * (stage.settling ? 1 - stage.settle : 1) - (stage.phase === "recents" ? stage.height * .08 : 0)
        opacity: stage.settling && PhoneState.outcome === "home" ? 1 - stage.settle : 1
    }
    // The next app slides in from the side opposite to the swipe.
    GestureCard {
        visible: stage.phase === "switch"
        entry: PhoneState.dx > 0 ? PhoneState.previousWindow() : PhoneState.neighbour(1)
        width: stage.width; height: stage.height; scale: .86; radius: 40
        x: PhoneState.dx > 0 ? PhoneState.dx - stage.width * 1.04 : PhoneState.dx + stage.width * 1.04
    }
    // A label tells which action release will take.
    Rectangle {
        visible: stage.phase === "recents" || (stage.phase === "home" && stage.p > .28)
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 120
        width: hint.implicitWidth + 32; height: 40; radius: 20; color: Theme.primaryContainer
        MText { id: hint; anchors.centerIn: parent; text: stage.phase === "recents" ? "Release for recent apps" : "Release to go home"; role: "label"; color: Theme.onContainer }
    }
    // Back: a bubble leans out of the edge and fills when the swipe is long enough.
    Rectangle {
        id: bubble
        visible: stage.phase === "back"
        readonly property real pull: PhoneState.progress * 64
        width: 44 + (PhoneState.progress >= 1 ? 6 : 0); height: 56; radius: width / 2
        y: stage.height * .5 - height / 2 + PhoneState.dy * .0
        x: PhoneState.edge < 0 ? -width + pull + (stage.settling ? -stage.settle * width : 0) : stage.width - pull + (stage.settling ? stage.settle * width : 0)
        color: PhoneState.progress >= 1 ? Theme.primary : Theme.level(4)
        Behavior on color { ColorAnimation { duration: Theme.motion(120) } }
        Glyph { anchors.centerIn: parent; name: "chevron_left"; rotation: PhoneState.edge < 0 ? 0 : 180; font.pixelSize: 26; color: PhoneState.progress >= 1 ? Theme.onPrimary : Theme.text }
    }
}
