import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: card
    property var flow: null
    property string message: flow ? flow.message : ""
    property string identity: flow && flow.selectedIdentity ? identityName(flow.selectedIdentity) : (Quickshell.env("USER") || "Administrator")
    property string actionId: flow ? flow.actionId : ""
    property bool failed: flow ? flow.failed : false
    property bool echo: flow ? flow.responseVisible : false
    property bool responseRequired: flow ? flow.isResponseRequired : true
    property bool completed: flow ? flow.isCompleted : false
    property string prompt: flow && flow.inputPrompt ? flow.inputPrompt.replace(/:\s*$/, "") : "Password"
    property string supplementaryMessage: flow ? flow.supplementaryMessage : ""
    property bool supplementaryIsError: flow ? flow.supplementaryIsError : false
    property bool submitted: false
    property bool revealed: false
    property bool detailsOpen: false
    readonly property bool busy: !completed && (submitted || !responseRequired)
    readonly property bool canSubmit: responseRequired && !submitted && !completed && input.text.length > 0
    readonly property string feedback: supplementaryMessage || (failed && !busy ? "That password didn’t work. Try again." : "")
    readonly property bool hasError: !busy && (supplementaryIsError || failed)

    function identityName(account) {
        if (!account) return "Administrator";
        if (typeof account === "string") return account.replace(/^unix-user:/, "");
        return account.displayName || account.string || String(account.id);
    }
    function resetInput() {
        input.clear();
        revealed = false;
        submitted = false;
        if (responseRequired && !completed) Qt.callLater(() => input.forceActiveFocus());
    }
    function submit() {
        if (!flow || !canSubmit) return;
        const response = input.text;
        input.clear();
        revealed = false;
        submitted = true;
        flow.submit(response);
    }
    function cancel() {
        input.clear();
        revealed = false;
        if (flow && !completed) flow.cancelAuthenticationRequest();
    }
    onFlowChanged: { resetInput(); detailsOpen = false; accountChoices.visible = false; }
    onResponseRequiredChanged: if (responseRequired) resetInput()
    onCompletedChanged: if (completed) resetInput()
    Connections {
        target: card.flow
        function onSelectedIdentityChanged() { card.resetInput(); }
        function onAuthenticationFailed() { card.resetInput(); }
        function onInputPromptChanged() { card.resetInput(); }
    }
    width: 456
    height: column.implicitHeight + 48
    radius: Theme.shapeXl
    color: Theme.level(2)
    border.width: 1
    border.color: Theme.outline
    Keys.onEscapePressed: cancel()
    Accessible.role: Accessible.Dialog
    Accessible.name: "Authentication required"
    ColumnLayout {
        id: column
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 24
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                radius: Theme.shapeLg
                color: Theme.primaryContainer
                Glyph { anchors.centerIn: parent; name: "admin_panel_settings"; font.pixelSize: 30; color: Theme.onContainer }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                MText { text: "OPAL · AUTHENTICATION"; role: "labelS"; color: Theme.primary; font.letterSpacing: 1; Layout.fillWidth: true }
                MText { text: "Permission to proceed"; role: "title"; Layout.fillWidth: true; wrapMode: Text.Wrap }
            }
        }
        MText {
            text: card.message || "Confirm your identity to continue."
            role: "body"; color: Theme.subtext
            Layout.fillWidth: true; wrapMode: Text.Wrap
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: accountRow.implicitHeight + 24
            radius: Theme.shapeMd
            color: Theme.level(3)
            RowLayout {
                id: accountRow
                anchors.fill: parent; anchors.margins: 12
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: 19
                    color: Theme.secondaryContainer
                    MText { anchors.centerIn: parent; text: card.identity.charAt(0).toUpperCase(); role: "titleS"; color: Theme.onSecondaryContainer }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    MText { text: "AUTHENTICATE AS"; role: "labelS"; color: Theme.subtext }
                    MText { text: card.identity; role: "titleS"; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                MButton {
                    text: "Change"; compact: true; tonal: true
                    visible: !!card.flow && card.flow.identities.length > 1
                    enabled: !card.busy && !card.completed
                    onClicked: accountChoices.visible = !accountChoices.visible
                }
            }
        }
        ColumnLayout {
            id: accountChoices
            visible: false
            Layout.fillWidth: true
            Repeater {
                model: accountChoices.visible && card.flow ? card.flow.identities : []
                MButton {
                    required property var modelData
                    Layout.fillWidth: true
                    text: card.identityName(modelData)
                    tonal: card.flow && card.flow.selectedIdentity === modelData
                    enabled: !card.busy
                    onClicked: { card.flow.selectedIdentity = modelData; accountChoices.visible = false; }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            MText { text: card.prompt; role: "label"; color: Theme.subtext }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 54; radius: Theme.shapeMd
                color: Theme.level(1)
                border.width: input.activeFocus || card.hasError ? 2 : 1
                border.color: card.hasError ? Theme.error : input.activeFocus ? Theme.primary : Theme.outline
                TextInput {
                    id: input
                    objectName: "polkitResponse"
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: revealButton.visible ? 58 : 16
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: card.echo || card.revealed ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    passwordMaskDelay: 0
                    inputMethodHints: card.echo ? Qt.ImhNone : Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    color: Theme.text; selectionColor: Theme.primary; selectedTextColor: Theme.onPrimary
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    enabled: card.responseRequired && !card.submitted && !card.completed
                    focus: true
                    activeFocusOnTab: true
                    Component.onCompleted: forceActiveFocus()
                    onAccepted: card.submit()
                    Accessible.name: card.prompt
                    MText { anchors.verticalCenter: parent.verticalCenter; visible: input.text === ""; text: card.busy ? "Waiting for authentication…" : "Enter " + card.prompt.toLowerCase(); role: "body"; color: Theme.muted; width: parent.width }
                }
                MButton {
                    id: revealButton
                    anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 42; compact: true
                    visible: !card.echo
                    enabled: input.enabled && input.text.length > 0
                    icon: card.revealed ? "visibility_off" : "visibility"
                    tooltip: card.revealed ? "Hide password" : "Show password"
                    onClicked: { card.revealed = !card.revealed; input.forceActiveFocus(); }
                }
            }
            RowLayout {
                visible: card.busy || card.feedback !== ""
                Layout.fillWidth: true
                spacing: 8
                Glyph {
                    name: card.busy ? "progress_activity" : card.hasError ? "error" : "info"
                    font.pixelSize: 18; color: card.hasError ? Theme.error : Theme.primary
                    RotationAnimator on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: card.busy && !Theme.reduceMotion }
                }
                MText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: card.busy ? "Checking your identity…" : card.feedback
                    role: "bodyS"; color: card.hasError ? Theme.error : Theme.subtext
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.actionId !== ""
            spacing: 6
            MButton { text: card.detailsOpen ? "Hide request details" : "Request details"; icon: card.detailsOpen ? "expand_less" : "expand_more"; compact: true; onClicked: card.detailsOpen = !card.detailsOpen }
            MText { visible: card.detailsOpen; text: card.actionId; role: "bodyS"; color: Theme.subtext; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            MButton { objectName: "polkitCancel"; text: "Cancel"; onClicked: card.cancel() }
            MButton { objectName: "polkitAuthenticate"; text: card.busy ? "Checking…" : "Authenticate"; filled: true; enabled: card.canSubmit; onClicked: card.submit() }
        }
    }
}
