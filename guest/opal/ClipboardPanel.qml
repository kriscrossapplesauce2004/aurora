import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id:cp
    property bool touchMode:false
    property bool keyboardOpen:false
    property bool confirmingClear:false
    property string filter:""
    onFilterChanged:if(searchField.text!==filter)searchField.text=filter
    readonly property string normalizedFilter:filter.toLowerCase().trim()
    property var items: {
        const query=normalizedFilter;
        const source=Hub.clipboardItems;
        if(!query)return source;
        const matches=[];
        for(let index=0;index<source.length;index++) {
            const item=source[index];
            if(item.text.toLowerCase().indexOf(query)>=0)matches.push(item);
        }
        return matches;
    }
    function copySelected() {if(items.length)Hub.copyClipboard(items[Math.max(0,clipList.currentIndex)].id,true);}
    onItemsChanged:clipList.currentIndex=Math.max(0,Math.min(clipList.currentIndex,items.length-1))
    ColumnLayout {
        anchors {fill:parent;margins:22}
spacing:14
        RowLayout {Layout.fillWidth:true;spacing:14
            Flower {Layout.preferredWidth:48;Layout.preferredHeight:48;fill:Theme.primary;lobes:8;Glyph {anchors.centerIn:parent;name:"clipboard";color:Theme.onPrimary;font.pixelSize:24}}
            ColumnLayout {Layout.fillWidth:true;spacing:4
                MText {text:"Clipboard";font.pixelSize:27;font.weight:Font.DemiBold}
                MText {text:Hub.clipboardItems.length+" of 20 entries · session only";color:Theme.subtext;font.pixelSize:11}
            }
            MButton {icon:"close";compact:true;tooltip:"Close · Escape";onClicked:Hub.close()}
        }
        Rectangle {Layout.fillWidth:true;Layout.preferredHeight:52;radius:26;color:Theme.surfaceHigh
            Glyph {x:18;anchors.verticalCenter:parent.verticalCenter;name:"search";color:Theme.subtext;font.pixelSize:21}
            TextField {
                id:searchField;anchors {fill:parent;leftMargin:50;rightMargin:44}
                background:Item {}
                placeholderText:"Find something you copied…";color:Theme.text;placeholderTextColor:Theme.muted
                font.family:Theme.font;font.pixelSize:14;selectByMouse:true
                onTextEdited:{cp.filter=text;clipList.currentIndex=0;}
                onActiveFocusChanged:if(activeFocus&&cp.touchMode)cp.keyboardOpen=true
                onAccepted:cp.copySelected()
                Keys.onDownPressed:{clipList.currentIndex=0;clipList.forceActiveFocus();}
                Keys.onEscapePressed:Hub.close()
                Component.onCompleted:if(!cp.touchMode)forceActiveFocus()
            }
            MButton {visible:cp.filter!=="";anchors {right:parent.right;verticalCenter:parent.verticalCenter;rightMargin:6}
icon:"close";compact:true;implicitWidth:34;implicitHeight:34;tooltip:"Clear search";onClicked:cp.filter=""}
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            Rectangle {Layout.preferredWidth:8;Layout.preferredHeight:8;radius:4;color:Hub.clipboardPaused ? Theme.tertiary : Hub.clipboardAvailable ? Theme.secondary : Theme.muted}
            MText {text:Hub.clipboardPaused ? "History paused" : Hub.clipboardAvailable ? "Ready for the next good idea" : "Clipboard service unavailable";color:Theme.subtext;font.pixelSize:11;Layout.fillWidth:true}
            MButton {text:Hub.clipboardPaused ? "Resume" : "Pause";icon:Hub.clipboardPaused ? "play" : "pause";compact:true;tonal:true;tooltip:"Pause stops Opal’s clipboard watcher";onClicked:Hub.pauseClipboard()}
        }
        ListView {
            id:clipList;Layout.fillWidth:true;Layout.fillHeight:true
            clip:true;spacing:8;model:cp.items;currentIndex:0;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
            Keys.onReturnPressed:cp.copySelected()
            Keys.onEnterPressed:cp.copySelected()
            Keys.onEscapePressed:Hub.close()
            Keys.onDeletePressed:if(cp.items.length)Hub.deleteClipboard(cp.items[currentIndex].id)
            delegate:ClipboardEntry {
                required property var modelData;required property int index
                width:clipList.width;record:modelData;selected:clipList.currentIndex===index
            }
            Column {anchors.centerIn:parent;visible:cp.items.length===0;width:parent.width;spacing:16
                Flower {width:100;height:100;anchors.horizontalCenter:parent.horizontalCenter;fill:Theme.primaryContainer;lobes:10;Glyph {anchors.centerIn:parent;name:cp.filter ? "search" : "clipboard";font.pixelSize:38;color:Theme.onContainer}}
                MText {text:cp.filter ? "No matching clips." : Hub.clipboardPaused ? "A little privacy break." : "Keep a little thought.";width:parent.width;horizontalAlignment:Text.AlignHCenter;font.pixelSize:21;font.weight:Font.DemiBold}
                MText {text:cp.filter ? "Try another word." : Hub.clipboardPaused ? "Resume when you want to collect text again." : Hub.clipboardAvailable ? "Copy text and it’ll appear here.\nNothing is saved to disk." : Hub.clipboardDetail;width:parent.width;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;color:Theme.subtext;font.pixelSize:12}
            }
        }
        SearchKeyboard {visible:cp.touchMode&&cp.keyboardOpen&&!Hub.systemOskReady;Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,cp.height*.38)
            inputTarget:searchField;contextLabel:"Find clipboard text";returnLabel:"Done"
            onInsert:cp.filter=searchField.text
            onErase:cp.filter=searchField.text
            onAccept:{cp.keyboardOpen=false;searchField.focus=false;}
            onDismiss:{cp.keyboardOpen=false;searchField.focus=false;}
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            MText {text:cp.touchMode ? "Tap to copy · long-press for actions" : "↑ ↓ Choose   ↵ Copy   Del Remove";color:Theme.muted;font.pixelSize:10;Layout.fillWidth:true}
            MButton {text:"Clear";icon:"trash";compact:true;tonal:true;enabled:Hub.clipboardItems.length>0;onClicked:cp.confirmingClear=true}
        }
    }
    Rectangle {
        visible:cp.confirmingClear;anchors.fill:parent;radius:28;color:Theme.alpha(Theme.base,.98)
        MouseArea {anchors.fill:parent}
        ColumnLayout {anchors {left:parent.left;right:parent.right;verticalCenter:parent.verticalCenter;margins:28}
spacing:16
            Glyph {name:"trash";font.pixelSize:42;color:Theme.tertiary;Layout.alignment:Qt.AlignHCenter}
            MText {text:"Clear this little history?";Layout.fillWidth:true;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;font.pixelSize:25;font.weight:Font.DemiBold}
            MText {text:"Only Opal’s in-memory entries will be removed. Your current clipboard and other clipboard managers are untouched.";Layout.fillWidth:true;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;color:Theme.subtext;font.pixelSize:13}
            MButton {Layout.fillWidth:true;text:"Clear "+Hub.clipboardItems.length+" entries";filled:true;onClicked:{Hub.clearClipboard();cp.confirmingClear=false;}}
            MButton {Layout.fillWidth:true;text:"Keep them";tonal:true;onClicked:cp.confirmingClear=false}
        }
    }
}
