import QtQuick

// Spatial D-pad focus for any Opal surface. It finds clickable items under root and moves a focus ring between them.
Item {
    id: cf
    // The item whose descendants can take focus.
    property Item root: parent
    property bool active: true
    // The highest priority claims the controller. Pages use 5, Quick Access 10, lock 20 and polkit 30.
    property int priority: 5
    // When true, B closes the shell page after the back signal.
    property bool closeOnBack: true
    property bool showHints: true
    // Add the LB RB section hint when the owner handles tab.
    property bool tabHints: false
    property var extraHints: []
    property real hintMargin: 16
    property bool textKeyboard: true
    // Start on a text field when the surface has one, as the lock screen and polkit do.
    property bool preferText: false
    property bool moved: false
    property Item current: null
    readonly property bool keyboardOpen: keyboard.open
    readonly property bool hintsVisible: showHints && active && (Hub.controller || ControllerNav.usingController) && !keyboard.open
    // Space that an owner may reserve below its content for the hint bar.
    readonly property real hintSpace: hintsVisible ? 44 + hintMargin : 0
    readonly property bool ringVisible: active && current !== null && ControllerNav.usingController
    signal tab(int delta)
    signal back()
    // The names are pin, search and menu.
    signal action(string name)

    z: 50

    onActiveChanged: {
        if (active) ControllerNav.claim(cf);
        else { ControllerNav.release(cf); current = null; moved = false; keyboard.close(); }
    }
    Component.onCompleted: { if (active) { ControllerNav.claim(cf); if (ControllerNav.usingController) selectSoon(); } }
    // A deferred selection must die with this object; Qt.callLater could run it after the page is destroyed and crash the shell.
    function selectSoon() { selectTimer.restart(); }
    Timer { id: selectTimer; interval: 0; onTriggered: cf.selectInitial() }
    Component.onDestruction: ControllerNav.release(cf)
    Connections { target: ControllerNav; function onKey(name) { cf.handle(name); } }
    // A moving pointer hands focus back to the mouse.
    HoverHandler {
        id: pointer
        property point last: Qt.point(-100, -100)
        onPointChanged: {
            const p = point.position;
            if (pointer.hovered && Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 3 && last.x > -100) ControllerNav.usingController = false;
            last = p;
        }
    }

    // Scanning.
    function modalRoot() {
        const base = root || cf.parent;
        let modal = null;
        (function find(item) {
            for (const child of item.children) {
                if (!child.visible) continue;
                if (child.controllerModal === true) modal = child;
                find(child);
            }
        })(base);
        return modal || base;
    }
    function kindOf(item, scope) {
        if (item.controllerFocusable === true) return "custom";
        if (item.width < 14 || item.height < 14) return "";
        if (typeof item.increase === "function" && typeof item.decrease === "function" && item.visualPosition !== undefined) return "slider";
        if (textKeyboard && typeof item.insert === "function" && item.cursorPosition !== undefined && item.readOnly === false) return "text";
        if (typeof item.click === "function" && item.pressed !== undefined && item.checkable !== undefined) return "button";
        if (item.acceptedButtons !== undefined && item.containsMouse !== undefined && item.preventStealing !== undefined) {
            if (!(item.acceptedButtons & Qt.LeftButton)) return "";
            if (item.drag && item.drag.target) return "";
            // A full-size mouse area is a click-away backdrop, not a control.
            if (item.width >= scope.width * .92 && item.height >= scope.height * .92) return "";
            return "area";
        }
        return "";
    }
    function collect(item, scope, out) {
        for (const child of item.children) {
            if (!child.visible || child.opacity < .05 || child.enabled === false || child.controllerSkip === true) continue;
            if (kindOf(child, scope) !== "") {
                out.push(child);
                // A leaf owns its children, so they never take focus on their own.
                if (child.controllerLeaf === true) continue;
            }
            collect(child, scope, out);
        }
    }
    function candidates() {
        const scope = modalRoot();
        const found = [];
        collect(scope, scope, found);
        const seen = {};
        return found.filter(item => {
            const p = item.mapToItem(cf, 0, 0);
            const id = Math.round(p.x / 3) + ":" + Math.round(p.y / 3) + ":" + Math.round(item.width / 3) + ":" + Math.round(item.height / 3);
            if (seen[id]) return false;
            seen[id] = true;
            return true;
        });
    }
    function rect(item) {
        const p = item.mapToItem(cf, 0, 0);
        return {x: p.x, y: p.y, w: item.width, h: item.height, cx: p.x + item.width / 2, cy: p.y + item.height / 2};
    }
    function valid(item) { return item && item.visible && item.enabled !== false && item.width > 0; }
    function selectInitial() {
        if (!active) return;
        const all = candidates();
        if (!all.length) return;
        const field = preferText ? all.find(item => kindOf(item, cf) === "text") : null;
        if (field) { focusOn(field); return; }
        // Start at the top-left control, but prefer items that are in view.
        let best = null, bestScore = 1e12;
        all.forEach(item => { const r = rect(item); const s = r.y * 3 + r.x; if (r.y >= -4 && s < bestScore) { best = item; bestScore = s; } });
        focusOn(best || all[0]);
    }
    function focusOn(item) {
        if (!item) return;
        current = item;
        reveal(item);
    }

    // Moving.
    function score(cur, c, dir) {
        const horizontal = dir === "left" || dir === "right";
        const sign = dir === "right" || dir === "down" ? 1 : -1;
        const axis = horizontal ? c.cx - cur.cx : c.cy - cur.cy;
        if (axis * sign <= 4) return -1;
        // Gap between the facing edges, never negative.
        const facing = horizontal
            ? (sign > 0 ? c.x - (cur.x + cur.w) : cur.x - (c.x + c.w))
            : (sign > 0 ? c.y - (cur.y + cur.h) : cur.y - (c.y + c.h));
        const cross = horizontal
            ? Math.max(0, Math.max(c.y - (cur.y + cur.h), cur.y - (c.y + c.h)))
            : Math.max(0, Math.max(c.x - (cur.x + cur.w), cur.x - (c.x + c.w)));
        const offset = Math.abs(horizontal ? c.cy - cur.cy : c.cx - cur.cx);
        // Items that start before the facing edge are a weaker choice than items past it.
        return Math.max(0, facing) + (facing < -4 ? 400 : 0) + cross * 3 + offset * .35;
    }
    function move(dir) {
        const all = candidates();
        if (!all.length) return;
        if (!valid(current) || all.indexOf(current) < 0) {
            selectInitial();
            return;
        }
        const cur = rect(current);
        let best = null, bestScore = 1e12;
        all.forEach(item => {
            if (item === current) return;
            const s = score(cur, rect(item), dir);
            if (s >= 0 && s < bestScore) { best = item; bestScore = s; }
        });
        if (best) focusOn(best);
        else if (dir === "up" || dir === "down") scrollPage(dir === "down" ? 1 : -1, .35);
    }

    // Acting on the focused item.
    function chain(item) { const list = []; let p = item; for (let i = 0; p && i < 6; i++) { list.push(p); p = p.parent; } return list; }
    function adjust(item, delta) {
        for (const p of chain(item)) {
            if (typeof p.controllerAdjust === "function") return p.controllerAdjust(delta) !== false;
            if (typeof p.increase === "function" && typeof p.decrease === "function" && p.visualPosition !== undefined) {
                const steps = Math.max(1, Math.round((p.to - p.from) / 20 / Math.max(.0001, p.stepSize || 1)));
                for (let i = 0; i < steps; i++) { if (delta > 0) p.increase(); else p.decrease(); }
                p.moved();
                return true;
            }
        }
        return false;
    }
    function activate(item) {
        if (!valid(item)) return;
        if (textKeyboard && typeof item.insert === "function" && item.cursorPosition !== undefined && item.readOnly === false) { keyboard.openFor(item); return; }
        for (const p of chain(item)) {
            if (typeof p.controllerActivate === "function") { p.controllerActivate(); return; }
        }
        if (typeof item.click === "function" && item.checkable !== undefined) { item.click(); return; }
        // A bare mouse area: its handler must not read the event.
        if (typeof item.clicked === "function") { try { item.clicked(null); } catch (error) { console.warn("Controller activation failed:", error); } }
    }
    function alternate(item) {
        for (const p of chain(item)) {
            if (typeof p.controllerAlternate === "function") { p.controllerAlternate(); return true; }
        }
        return false;
    }

    function handle(name) {
        if (!active || ControllerNav.top !== cf) return;
        if (keyboard.open) { keyboard.handle(name); return; }
        // A surface that wakes on the first press may only now show its field.
        if (preferText && !moved) { selectInitial(); moved = true; }
        if (name === "up" || name === "down" || name === "left" || name === "right") {
            if ((name === "left" || name === "right") && valid(current) && adjust(current, name === "right" ? 1 : -1)) return;
            move(name);
        } else if (name === "accept") {
            if (!valid(current)) selectInitial(); else activate(current);
        } else if (name === "back") {
            back();
            if (closeOnBack) Hub.close();
        } else if (name === "previousTab") tab(-1);
        else if (name === "nextTab") tab(1);
        else if (name === "pageUp") scrollPage(-1, .8);
        else if (name === "pageDown") scrollPage(1, .8);
        else if (name === "pin") { if (!(valid(current) && alternate(current))) action("pin"); }
        else if (name === "search" || name === "menu") action(name);
    }

    // Scrolling. A pool of animations moves any flickable smoothly.
    function flickableOf(item) {
        for (let p = item; p; p = p.parent) {
            if (p.contentItem !== undefined && p.contentY !== undefined && typeof p.flick === "function") return p;
        }
        return null;
    }
    function glide(flick, property, value) {
        const key = property;
        let anim = pool.find(a => a.target === flick && a.property === key) || pool.find(a => !a.running) || pool[0];
        anim.stop();
        anim.target = flick; anim.property = key; anim.from = flick[key]; anim.to = value;
        if (Theme.reduceMotion) { flick[key] = value; return; }
        anim.restart();
    }
    function reveal(item) {
        for (let p = item.parent; p; p = p.parent) {
            if (!(p.contentItem !== undefined && p.contentY !== undefined && typeof p.flick === "function")) continue;
            const margin = 28;
            const r = item.mapToItem(p.contentItem, 0, 0);
            if (p.contentHeight > p.height + 1) {
                const top = p.originY || 0;
                const max = Math.max(top, top + p.contentHeight - p.height);
                let target = p.contentY;
                if (r.y < p.contentY + margin) target = r.y - margin;
                else if (r.y + item.height > p.contentY + p.height - margin) target = r.y + item.height + margin - p.height;
                target = Math.max(top, Math.min(max, target));
                if (Math.abs(target - p.contentY) > 1) { p.cancelFlick(); glide(p, "contentY", target); }
            }
            if (p.contentWidth > p.width + 1) {
                const left = p.originX || 0;
                const max = Math.max(left, left + p.contentWidth - p.width);
                let target = p.contentX;
                if (r.x < p.contentX + margin) target = r.x - margin;
                else if (r.x + item.width > p.contentX + p.width - margin) target = r.x + item.width + margin - p.width;
                target = Math.max(left, Math.min(max, target));
                if (Math.abs(target - p.contentX) > 1) { p.cancelFlick(); glide(p, "contentX", target); }
            }
        }
    }
    function scrollPage(direction, fraction) {
        const flick = valid(current) ? flickableOf(current) : null;
        if (!flick || flick.contentHeight <= flick.height) return;
        const top = flick.originY || 0;
        flick.cancelFlick();
        glide(flick, "contentY", Math.max(top, Math.min(top + flick.contentHeight - flick.height, flick.contentY + direction * flick.height * fraction)));
    }
    property var pool: [anim0, anim1, anim2, anim3]
    NumberAnimation { id: anim0; duration: Theme.motion(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    NumberAnimation { id: anim1; duration: Theme.motion(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    NumberAnimation { id: anim2; duration: Theme.motion(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    NumberAnimation { id: anim3; duration: Theme.motion(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }

    // Focus ring: glides to a new target, then tracks the item exactly while the page scrolls.
    property real fromX: 0
    property real fromY: 0
    property real fromW: 0
    property real fromH: 0
    property real targetX: 0
    property real targetY: 0
    property real targetW: 0
    property real targetH: 0
    property real travel: 1
    function syncRing() {
        if (!valid(current)) return;
        const r = rect(current);
        targetX = r.x; targetY = r.y; targetW = r.w; targetH = r.h;
    }
    function markFocus(item, value) {
        if (!item) return;
        for (const p of chain(item)) { if (p.controllerFocused !== undefined) { p.controllerFocused = value; return; } }
    }
    property Item marked: null
    onCurrentChanged: {
        markFocus(marked, false);
        marked = current;
        markFocus(current, true);
        fromX = ring.x + 4; fromY = ring.y + 4; fromW = ring.width - 8; fromH = ring.height - 8;
        syncRing();
        if (!ringShown) { fromX = targetX; fromY = targetY; fromW = targetW; fromH = targetH; }
        glideAnim.restart();
    }
    property bool ringShown: false
    NumberAnimation { id: glideAnim; target: cf; property: "travel"; from: 0; to: 1; duration: Theme.motion(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate }
    FrameAnimation { running: cf.ringVisible; onTriggered: cf.syncRing() }
    function ringRadius(item) {
        for (let p = item, i = 0; p && i < 4; p = p.parent, i++) {
            if (typeof p.radius === "number" && p.radius > 0) return p.radius;
            if (p.parent && (Math.abs(p.parent.width - p.width) > 8 || Math.abs(p.parent.height - p.height) > 8)) break;
        }
        return Math.min(14, item.height / 2);
    }
    Item {
        id: ring
        visible: cf.ringVisible && cf.targetW > 0
        onVisibleChanged: cf.ringShown = visible
        readonly property real eased: cf.travel
        x: cf.fromX + (cf.targetX - cf.fromX) * eased - 4
        y: cf.fromY + (cf.targetY - cf.fromY) * eased - 4
        width: cf.fromW + (cf.targetW - cf.fromW) * eased + 8
        height: cf.fromH + (cf.targetH - cf.fromH) * eased + 8
        readonly property real corner: valid(cf.current) ? cf.ringRadius(cf.current) + 4 : 12
        // Soft halo, then the M3 focus outline with a gap.
        Rectangle { anchors.fill: parent; anchors.margins: -4; radius: ring.corner + 4; color: "transparent"; border.width: 4; border.color: Theme.alpha(Theme.primary, .22) }
        Rectangle { anchors.fill: parent; radius: ring.corner; color: "transparent"; border.width: 3; border.color: Theme.primary }
    }

    // Hint bar.
    ControllerHints {
        visible: cf.hintsVisible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: cf.hintMargin
        items: {
            const list = [{b: ControllerNav.acceptLabel, t: cf.valid(cf.current) && cf.kindOf(cf.current, cf) === "text" ? "Type" : "Select"}, {b: ControllerNav.backLabel, t: "Back"}];
            if (cf.tabHints) list.push({b: "LB RB", t: "Section"});
            return list.concat(cf.extraHints);
        }
    }

    // Text entry: the on-screen keyboard types into the focused field.
    SearchKeyboard {
        id: keyboard
        property bool open: false
        property Item target: null
        controllerMode: true
        visible: open || slide > 0
        property real slide: open ? 1 : 0
        Behavior on slide { NumberAnimation { duration: Theme.motion(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate } }
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(12, (cf.width - 760) / 2); anchors.rightMargin: anchors.leftMargin; anchors.bottomMargin: 12
        height: Math.min(implicitHeight, cf.height * .6)
        transform: Translate { y: (1 - keyboard.slide) * (keyboard.height + 24) }
        // A solid backing keeps the keys readable over any page.
        Rectangle { z: -1; anchors.fill: parent; radius: keyboard.radius; color: Theme.level(2) }
        // The typed text shows above the keys, because the field itself may sit under the keyboard.
        Rectangle {
            id: preview
            y: -height - 8; width: parent.width; height: 54; radius: height / 2
            color: Theme.level(2)
            border.width: 2; border.color: Theme.primary
            readonly property string typed: keyboard.target ? (keyboard.target.echoMode === TextInput.Password ? "●".repeat(keyboard.target.text.length) : keyboard.target.text) : ""
            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 22; rightMargin: 22 }
                layoutDirection: Qt.LeftToRight
                spacing: 2; clip: true
                MText { id: typedText; text: preview.typed; role: "title"; width: Math.min(implicitWidth, parent.width - 6); elide: Text.ElideLeft; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { width: 2; height: 24; radius: 1; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                MText { visible: preview.typed === ""; text: keyboard.target && keyboard.target.placeholderText ? keyboard.target.placeholderText : keyboard.secureInput ? "Password" : "Type here"; role: "body"; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter; leftPadding: 8 }
            }
        }
        inputTarget: target
        secureInput: !!target && target.echoMode === TextInput.Password
        contextLabel: target && target.objectName === "polkitResponse" ? "Password" : "Type"
        returnLabel: "Done"
        function openFor(item) { target = item; item.forceActiveFocus(); selection = 0; open = true; }
        function close() { open = false; }
        function submit() {
            const item = target;
            open = false;
            if (item && typeof item.accepted === "function") { try { item.accepted(); } catch (error) { console.warn("Controller submit failed:", error); } }
        }
        function handle(name) {
            if (name === "pin") press("⌫");
            else if (name === "search") press("SPACE");
            else if (name === "previousTab") press("LEFT");
            else if (name === "nextTab") press("RIGHT");
            else if (name === "menu") submit();
            else navigation(name);
        }
        onAccept: submit()
        onDismiss: close()
    }
}
