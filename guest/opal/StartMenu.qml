import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "StartSearch.js" as Search

FocusScope {
    id:menu
    // Rail selection: "pinned", "all" or a category name.
    property string section:"pinned"
    readonly property bool allApps:section!=="pinned"
    readonly property string appCategory:section==="all"||section==="pinned" ? "All apps" : section
    readonly property var rail:[{id:"pinned",name:"Pinned",icon:"keep"},{id:"all",name:"All apps",icon:"apps"},{id:"Games",name:"Games",icon:"sports_esports"},{id:"Create",name:"Create",icon:"brush"},{id:"Work",name:"Work",icon:"work"},{id:"Internet",name:"Internet",icon:"language"},{id:"System",name:"System",icon:"settings"}]
    property string letter:""
    readonly property var library:Hub.searchApps("",appCategory).filter(app=>!letter||app.name.toUpperCase().startsWith(letter))
    property string scope:"all"
    property string confirmPower:""
    onConfirmPowerChanged:if(confirmPower!=="")Qt.callLater(()=>powerCancel.forceActiveFocus());else searchField.forceActiveFocus()
    property int selection:0
    property alias searchField:searchField
    readonly property string query:Hub.query.trim()
    readonly property bool searching:query!==""
    readonly property bool calculator:query.startsWith("=")
    readonly property bool web:query.startsWith("?")
    readonly property bool claude:query.startsWith("!")
    readonly property int columns:width<520 ? 4 : width>=850 ? 8 : 6
    readonly property var actions:[
        {id:"settings",name:"Settings",detail:"All your device preferences in one place",icon:"settings",keywords:"configure phone taskbar accessibility"},
        {id:"controls",name:"Quick settings",detail:"Connectivity, sound and display",icon:"settings",keywords:"control center volume brightness wifi"},
        {id:"network",name:"Wi-Fi settings",detail:"Choose a network",icon:"wifi",keywords:"internet wireless network"},
        {id:"bluetooth",name:"Bluetooth settings",detail:"Pair and connect devices",icon:"bluetooth",keywords:"headphones pairing wireless"},
        {id:"appearance",name:"Personalize desktop",detail:"Colors, glass and appearance",icon:"palette",keywords:"theme dark light style"},
        {id:"wallpaper",name:"Change wallpaper",detail:"Choose a local image",icon:"palette",keywords:"background photo picture"},
        {id:"windows",name:"Running windows",detail:"Switch to an open application",icon:"desktop",keywords:"tasks switcher"},
        {id:"clipboard",name:"Clipboard history",detail:"Your session clipboard",icon:"clipboard",keywords:"copy paste text"},
        {id:"screenshot",name:"Take a screenshot",detail:"Capture your screen",icon:"capture",keywords:"screen image capture"},
        {id:"lock",name:"Lock device",detail:"Lock your current session",icon:"lock",keywords:"secure screen"},
        {id:"focus",name:"Start focus timer",detail:"25 minutes without distractions",icon:"timer",keywords:"pomodoro concentrate"},
        {id:"welcome",name:"Opal tour",detail:"Pick your bar, icons and theme",icon:"auto_awesome",keywords:"setup onboarding welcome tour"}
    ]
    readonly property var results:searching&&!calculator&&!web&&!claude ? Search.search(query,scope,Hub.appSearchIndex,Hub.windows,actions,Hub.favoriteApps.map(a=>a.id),Hub.prefs.recent||[]) : []
    readonly property var selected:results[selection]||null
    readonly property var recent:Hub.recentApps.slice(0,4)
    onResultsChanged:{selection=0;resultList.positionViewAtBeginning();}
    function move(delta) {selection=Math.max(0,Math.min(results.length-1,selection+delta));resultList.positionViewAtIndex(selection,ListView.Contain);}
    function goBack() {
        if(confirmPower!==""){confirmPower="";return;}
        if(searching){Hub.query="";scope="all";searchField.forceActiveFocus();}
        else if(allApps){section="pinned";searchField.forceActiveFocus();}
        else Hub.close();
    }
    function invoke(result, fresh) {
        if(!result)return;
        if(result.kind==="app"){if(fresh)Hub.launchNew(result.data);else Hub.launch(result.data);}
        else if(result.kind==="window")Hub.focusWindow(result.data);
        else {
            const id=result.data.id;
            if(id==="screenshot")Hub.screenShot();
            else if(id==="lock"||id==="network"||id==="bluetooth")Hub.settings(id);
            else if(id==="focus"){Hub.focusSeconds=25*60;Hub.focusRunning=true;Hub.close();}
            else Hub.page=id;
        }
    }
    function accept(fresh) {
        if(calculator){if(Hub.calculation!=="")Hub.command({action:"clipboard",text:Hub.calculation});}
        else if(claude){if(query.slice(1).trim())Hub.openAssistant(query.slice(1).trim());}
        else if(web){if(query.slice(1).trim()){Hub.command({action:"web",text:query.slice(1).trim()});Hub.close();}}
        else invoke(selected,fresh);
    }
    function focusApp(index) {
        const item=pinnedRepeater.itemAt(Math.max(0,Math.min(Hub.favoriteApps.length-1,index)));
        if(item){item.forceActiveFocus();home.contentY=Math.max(0,item.y-80);}
    }
    Connections {target:Hub;function onStartSearchRequestChanged(){searchField.forceActiveFocus();searchField.selectAll();}function onQueryChanged(){
        if(searchField.text!==Hub.query)searchField.text=Hub.query;
        Hub.calculation="";
        calculationTimer.stop();
        if(menu.calculator)calculationTimer.restart();
    }}
    Timer {id:calculationTimer;interval:140;onTriggered:if(menu.calculator)Hub.command({action:"calculate",text:Hub.calcExpression(menu.query)})}
    Component.onCompleted:{searchField.forceActiveFocus();if(calculator)calculationTimer.restart();}
    Keys.onEscapePressed:event=>{goBack();event.accepted=true;}
    Keys.onPressed:event=>{
        if(confirmPower!=="")return;
        if(event.modifiers&Qt.ControlModifier&&event.key===Qt.Key_K){searchField.forceActiveFocus();searchField.selectAll();event.accepted=true;}
        else if(event.text&&!(event.modifiers&(Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier))&&!searchField.activeFocus&&event.key!==Qt.Key_Return&&event.key!==Qt.Key_Enter&&event.key!==Qt.Key_Tab){searchField.forceActiveFocus();Hub.query+=event.text;event.accepted=true;}
    }

    RowLayout {
        enabled:menu.confirmPower===""
        anchors.fill:parent;anchors.margins:12;spacing:12
    // Left rail: sections, then settings and session at the bottom.
    ColumnLayout {
        Layout.preferredWidth:164;Layout.minimumWidth:164;Layout.maximumWidth:164;Layout.fillWidth:false;Layout.fillHeight:true;spacing:2
        Repeater {model:menu.rail
            Rectangle {
                required property var modelData
                readonly property bool current:!menu.searching&&menu.section===modelData.id
                Layout.fillWidth:true;Layout.preferredHeight:44;radius:height/2
                color:current ? Theme.secondaryContainer : "transparent"
                Rectangle {anchors.fill:parent;radius:parent.radius;color:Theme.stateLayer;opacity:railMouse.pressed ? .12 : railMouse.containsMouse ? .06 : 0}
                Row {anchors.verticalCenter:parent.verticalCenter;x:14;spacing:12
                    Glyph {name:modelData.icon;font.pixelSize:20;color:parent.parent.current ? Theme.onSecondaryContainer : Theme.subtext;anchors.verticalCenter:parent.verticalCenter}
                    MText {text:modelData.name;role:"label";font.weight:parent.parent.current ? Font.DemiBold : Font.Medium;color:parent.parent.current ? Theme.onSecondaryContainer : Theme.text;anchors.verticalCenter:parent.verticalCenter}
                }
                MouseArea {id:railMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{Hub.query="";menu.section=modelData.id;menu.letter="";searchField.forceActiveFocus();}}
                Accessible.role:Accessible.Button;Accessible.name:modelData.name
            }
        }
        Item {Layout.fillHeight:true}
        RowLayout {Layout.fillWidth:true;spacing:0
            MButton {icon:"settings";compact:true;implicitWidth:40;ink:Theme.subtext;tooltip:"Settings";onClicked:Hub.openSettings()}
            MButton {icon:"folder";compact:true;implicitWidth:40;ink:Theme.subtext;tooltip:"Files";onClicked:Hub.settings("files")}
            MButton {icon:"lock";compact:true;implicitWidth:40;ink:Theme.subtext;tooltip:"Lock";onClicked:Hub.settings("lock")}
            MButton {icon:"power";compact:true;implicitWidth:40;ink:Theme.subtext;tooltip:"Power";onClicked:menu.confirmPower="menu"}
        }
    }
    ColumnLayout {
        Layout.fillWidth:true;Layout.fillHeight:true;spacing:12
        // Hero: greeting and clock in a bold colour block.
        Rectangle {
            visible:!menu.searching
            Layout.fillWidth:true;Layout.preferredHeight:112
            radius:Theme.shapeXl;color:Theme.primaryContainer
            ColumnLayout {anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;anchors.leftMargin:24;spacing:0
                MText {text:Hub.now.getHours()<12 ? "Good morning" : Hub.now.getHours()<18 ? "Good afternoon" : "Good evening";role:"headline";color:Theme.onContainer}
                MText {text:Qt.formatDateTime(Hub.now,"dddd d MMMM");role:"label";color:Theme.alpha(Theme.onContainer,.75)}
            }
            MText {visible:parent.width>=520;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;anchors.rightMargin:24;text:Qt.formatDateTime(Hub.now,"HH:mm");role:"displayM";font.features:{"tnum":1};color:Theme.onContainer}
        }
        Rectangle {
            Layout.fillWidth:true;Layout.preferredHeight:52;radius:26
            color:Theme.level(searchField.activeFocus ? 4 : 3)
            border.width:searchField.activeFocus ? 2 : 0;border.color:Theme.primary
            Behavior on color {ColorAnimation {duration:Theme.motion(160)}}
            Glyph {x:18;anchors.verticalCenter:parent.verticalCenter;name:"search";color:Theme.primary}
            TextField {
                id:searchField;anchors.fill:parent;anchors.leftMargin:48;anchors.rightMargin:46
                background:Item {}
                color:Theme.text;placeholderTextColor:Theme.subtext
                font.family:Theme.font;font.pixelSize:15;selectByMouse:true
                placeholderText:"Search apps, windows and actions";text:Hub.query
                onTextEdited:Hub.query=text
                onAccepted:menu.accept(false)
                Keys.onReturnPressed:event=>menu.accept(!!(event.modifiers&Qt.ControlModifier))
                Keys.onDownPressed:{if(menu.searching)menu.move(1);else if(menu.allApps){appGrid.forceActiveFocus();appGrid.currentIndex=0;}else menu.focusApp(0);}
                Keys.onUpPressed:menu.move(-1)
                Keys.onEscapePressed:menu.goBack()
            }
            MButton {visible:menu.searching;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;anchors.rightMargin:5;icon:"close";compact:true;implicitWidth:36;tooltip:"Clear search";onClicked:{Hub.query="";searchField.forceActiveFocus();}}
        }
        RowLayout {
            visible:menu.searching&&!menu.calculator&&!menu.web&&!menu.claude;Layout.fillWidth:true;spacing:6
            Repeater {model:[{id:"all",name:"All"},{id:"app",name:"Apps"},{id:"window",name:"Windows"},{id:"action",name:"Actions"}]
                Chip {required property var modelData;text:modelData.name;selected:menu.scope===modelData.id;glass:false;onClicked:{menu.scope=modelData.id;searchField.forceActiveFocus();}}
            }
            Item {Layout.fillWidth:true}
        }
        Item {
            Layout.fillWidth:true;Layout.fillHeight:true
            Flickable {
                id:home;anchors.fill:parent;visible:!menu.searching&&!menu.allApps;clip:true
                contentHeight:homeBody.implicitHeight;boundsBehavior:Flickable.StopAtBounds
                ScrollBar.vertical:ScrollBar {}
                ColumnLayout {
                    id:homeBody;width:home.width;spacing:12
                    RowLayout {Layout.fillWidth:true
                        MText {text:"Pinned";role:"title";Layout.fillWidth:true}
                    }
                    GridLayout {
                        Layout.fillWidth:true;columns:menu.columns;columnSpacing:4;rowSpacing:4;uniformCellWidths:true
                        Repeater {id:pinnedRepeater;model:Hub.favoriteApps
                            AppTile {
                                required property var modelData;required property int index
                                app:modelData;bare:true;showPin:false;tintIndex:index;selected:activeFocus
                                Layout.fillWidth:true;Layout.maximumWidth:(home.width-20)/menu.columns;Layout.preferredWidth:80;Layout.preferredHeight:96
                                activeFocusOnTab:true;onActivated:Hub.launch(app)
                                Keys.onReturnPressed:Hub.launch(app)
                                Keys.onSpacePressed:Hub.launch(app)
                                Keys.onLeftPressed:menu.focusApp(index-1)
                                Keys.onRightPressed:menu.focusApp(index+1)
                                Keys.onDownPressed:menu.focusApp(index+menu.columns)
                                Keys.onUpPressed:{if(index<menu.columns)searchField.forceActiveFocus();else menu.focusApp(index-menu.columns);}
                            }
                        }
                    }
                    MText {visible:Hub.favoriteApps.length===0;Layout.fillWidth:true;text:"Make this space yours. Right-click an app to pin it here.";wrapMode:Text.Wrap;color:Theme.subtext}
                    RowLayout {Layout.fillWidth:true;Layout.topMargin:8
                        MText {text:"Recent";role:"title";Layout.fillWidth:true}
                        MButton {icon:"desktop";text:"Open windows";compact:true;onClicked:Hub.page="windows"}
                    }
                    GridLayout {Layout.fillWidth:true;columns:2;uniformCellWidths:true;columnSpacing:8;rowSpacing:8
                        Repeater {model:menu.recent
                            Rectangle {required property var modelData;Layout.fillWidth:true;Layout.preferredHeight:58;radius:Theme.shapeLg;color:Theme.level(3)
                                RowLayout {anchors.fill:parent;anchors.margins:12;spacing:10
                                    Item {Layout.preferredWidth:28;Layout.preferredHeight:28
                                        Image {id:recentIcon;anchors.fill:parent;source:Quickshell.iconPath(modelData.icon,true);asynchronous:true}
                                        Glyph {anchors.centerIn:parent;visible:recentIcon.status!==Image.Ready;name:Hub.glyphForApp(modelData);color:Theme.primary}
                                    }
                                    ColumnLayout {Layout.fillWidth:true;spacing:3
                                        MText {Layout.fillWidth:true;text:modelData.name;font.pixelSize:12;font.weight:Font.DemiBold}
                                        MText {Layout.fillWidth:true;text:modelData.genericName||"Application";font.pixelSize:10;color:Theme.subtext}
                                    }
                                }
                                MButton {anchors.fill:parent;radius:18;color:"transparent";tooltip:modelData.name;onClicked:Hub.launch(modelData);menuEntries:Hub.appMenu(modelData)}
                            }
                        }
                    }
                    MText {visible:menu.recent.length===0;Layout.fillWidth:true;text:"Apps you open will appear here.";color:Theme.subtext;font.pixelSize:12}
                    // Search tools: each chip starts a search with its prefix, so the syntax is discoverable.
                    Flow {Layout.fillWidth:true;Layout.topMargin:4;spacing:6
                        Repeater {model:[{text:"Calculate",prefix:"= ",icon:"calculate"},{text:"Actions",prefix:"> ",icon:"bolt"},{text:"Windows",prefix:"@ ",icon:"desktop"},{text:"Web",prefix:"? ",icon:"web"},{text:"Ask Claude",prefix:"! ",icon:"auto_awesome"}]
                            Chip {required property var modelData;text:modelData.text;icon:modelData.icon;trailingIcon:"";tooltip:"Start with "+modelData.prefix.trim();onClicked:{Hub.query=modelData.prefix;searchField.forceActiveFocus();}}
                        }
                    }
                }
            }
            ColumnLayout {
                visible:!menu.searching&&menu.allApps;anchors.fill:parent;spacing:10
                RowLayout {Layout.fillWidth:true
                    MText {text:menu.section==="all" ? "All apps" : menu.section;role:"title";Layout.fillWidth:true}
                    MText {text:menu.library.length+" apps";role:"label";color:Theme.subtext}
                }
                Flickable {Layout.fillWidth:true;Layout.preferredHeight:32;contentWidth:letters.width;clip:true;flickableDirection:Flickable.HorizontalFlick
                    Row {id:letters;spacing:2
                        Repeater {model:["All","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
                            MButton {required property string modelData;text:modelData;compact:true;implicitWidth:modelData==="All" ? 48 : 32;implicitHeight:30;filled:menu.letter===(modelData==="All" ? "" : modelData);onClicked:{menu.letter=modelData==="All" ? "" : modelData;appGrid.positionViewAtBeginning();}}
                        }
                    }
                }
                GridView {
                    id:appGrid;Layout.fillWidth:true;Layout.fillHeight:true;clip:true;model:menu.library
                    cellWidth:width/menu.columns;cellHeight:104;boundsBehavior:Flickable.StopAtBounds
                    ScrollBar.vertical:ScrollBar {}
                    Keys.onReturnPressed:if(currentItem)Hub.launch(currentItem.modelData)
                    delegate:Item {
                        required property var modelData;required property int index
                        width:appGrid.cellWidth;height:appGrid.cellHeight
                        AppTile {anchors.fill:parent;anchors.margins:2;app:parent.modelData;bare:true;showPin:false;selected:appGrid.activeFocus&&appGrid.currentIndex===parent.index;tintIndex:parent.index;onActivated:Hub.launch(app)}
                    }
                }
            }
            ListView {
                id:resultList;anchors.fill:parent;visible:menu.searching&&!menu.calculator&&!menu.web&&!menu.claude
                model:menu.results;clip:true;spacing:5;boundsBehavior:Flickable.StopAtBounds
                ScrollBar.vertical:ScrollBar {}
                delegate:Rectangle {
                    id:resultRow
                    required property var modelData;required property int index
                    width:resultList.width;height:68;radius:18
                    color:menu.selection===index ? Theme.primaryContainer : resultMouse.containsMouse ? Theme.alpha(Theme.glassRaised,.6) : "transparent"
                    Behavior on color {ColorAnimation {duration:Theme.motion(120)}}
                    // Selection bar: a short accent at the leading edge marks the Enter target.
                    Rectangle {visible:menu.selection===resultRow.index;x:4;anchors.verticalCenter:parent.verticalCenter;width:4;height:parent.height*.44;radius:2;color:Theme.primary}
                    RowLayout {anchors.fill:parent;anchors.margins:12;spacing:12
                        Item {Layout.preferredWidth:34;Layout.preferredHeight:34
                            Image {id:resultIcon;anchors.fill:parent;visible:resultRow.modelData.kind==="app";source:visible ? Quickshell.iconPath(resultRow.modelData.icon,true) : "";asynchronous:true;sourceSize:Qt.size(34,34)}
                            Glyph {anchors.centerIn:parent;visible:resultRow.modelData.kind!=="app"||resultIcon.status!==Image.Ready;name:resultRow.modelData.kind==="window" ? "desktop" : resultRow.modelData.kind==="app" ? "apps" : resultRow.modelData.icon;color:Theme.primary}
                        }
                        ColumnLayout {Layout.fillWidth:true;spacing:3
                            MText {Layout.fillWidth:true;text:resultRow.modelData.title;font.weight:Font.DemiBold;color:menu.selection===resultRow.index ? Theme.onContainer : Theme.text}
                            MText {Layout.fillWidth:true;text:resultRow.modelData.detail;font.pixelSize:11;color:menu.selection===resultRow.index ? Theme.onContainer : Theme.subtext}
                        }
                        Rectangle {Layout.preferredWidth:kindLabel.implicitWidth+16;Layout.preferredHeight:22;radius:11;color:Theme.alpha(menu.selection===resultRow.index ? Theme.onContainer : Theme.subtext,.12)
                            MText {id:kindLabel;anchors.centerIn:parent;text:resultRow.modelData.kind==="app" ? "App" : resultRow.modelData.kind==="window" ? "Window" : "Action";font.pixelSize:10;font.weight:Font.Medium;color:menu.selection===resultRow.index ? Theme.onContainer : Theme.subtext}
                        }
                    }
                    MouseArea {id:resultMouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton;onClicked:event=>{
                        menu.selection=resultRow.index;
                        if(event.button===Qt.RightButton&&resultRow.modelData.kind==="app")resultContext.popupFrom(resultRow,event.x,event.y);
                        else if(event.button===Qt.LeftButton)menu.invoke(resultRow.modelData,false);
                    }}
                    OpalMenu {id:resultContext;entries:visible&&resultRow.modelData.kind==="app" ? Hub.appMenu(resultRow.modelData.data) : []}
                    Accessible.role:Accessible.Button;Accessible.name:modelData.title+", "+modelData.kind;Accessible.onPressAction:menu.invoke(modelData,false)
                }
                Column {visible:menu.results.length===0;anchors.centerIn:parent;width:parent.width-24;spacing:12
                    MText {width:parent.width;text:"No local matches";font.pixelSize:22;horizontalAlignment:Text.AlignHCenter}
                    MText {width:parent.width;text:"Try an app name, window title or action.\nNothing is sent online while you type.";wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;color:Theme.subtext}
                    MButton {anchors.horizontalCenter:parent.horizontalCenter;text:"Search the web instead";icon:"web";tonal:true;onClicked:{Hub.command({action:"web",text:menu.query});Hub.close();}}
                }
            }
            // Claude: Enter sends the question; the answer streams in below.
            ColumnLayout {
                visible:menu.searching&&menu.claude;anchors.fill:parent;spacing:12
                RowLayout {Layout.fillWidth:true;spacing:10
                    Rectangle {Layout.preferredWidth:36;Layout.preferredHeight:36;radius:Theme.shapeSm;color:Theme.tertiaryContainer
                        Glyph {anchors.centerIn:parent;name:"auto_awesome";font.pixelSize:20;color:Theme.onTertiaryContainer}}
                    MText {text:"Ask Claude";role:"title";Layout.fillWidth:true}
                    MButton {visible:Hub.claudeBusy;text:"Stop";icon:"stop";compact:true;tonal:true;onClicked:Hub.stopClaude()}
                    MButton {visible:!Hub.claudeBusy;text:"Ask";icon:"send";compact:true;filled:true;enabled:menu.query.slice(1).trim()!=="";onClicked:menu.accept(false)}
                }
                Flow {
                    visible:Hub.claudeTools.length>0;Layout.fillWidth:true;spacing:6
                    Repeater {model:Hub.claudeTools
                        Rectangle {required property string modelData;height:26;width:toolText.implicitWidth+20;radius:13;color:Theme.level(3)
                            MText {id:toolText;anchors.centerIn:parent;text:modelData;role:"labelS";color:Theme.subtext}}}
                }
                Rectangle {
                    Layout.fillWidth:true;Layout.fillHeight:true;radius:Theme.shapeLg;color:Theme.level(3)
                    Flickable {
                        id:answerScroll;anchors.fill:parent;anchors.margins:16;clip:true;contentHeight:answerText.implicitHeight;boundsBehavior:Flickable.StopAtBounds
                        onContentHeightChanged:if(Hub.claudeBusy)contentY=Math.max(0,contentHeight-height)
                        ScrollBar.vertical:ScrollBar {}
                        TextEdit {
                            id:answerText;width:parent.width;readOnly:true;selectByMouse:true;wrapMode:TextEdit.Wrap
                            textFormat:TextEdit.MarkdownText
                            text:Hub.claudeAnswer!=="" ? Hub.claudeAnswer : Hub.claudeBusy ? "Thinking…" : "Type a question after ! and press Enter to continue in the Claude assistant. It can also change Opal for you, like \"switch to dark mode\"."
                            color:Hub.claudeError ? Theme.error : Hub.claudeAnswer!=="" ? Theme.text : Theme.subtext
                            font.family:Theme.font;font.pixelSize:14
                        }
                    }
                }
                RowLayout {Layout.fillWidth:true
                    MText {text:"Uses your Claude Code sign-in.";role:"labelS";color:Theme.subtext;Layout.fillWidth:true}
                    MButton {visible:Hub.claudeAnswer!==""&&!Hub.claudeBusy;text:"Copy";icon:"copy";compact:true;onClicked:Hub.command({action:"clipboard",text:Hub.claudeAnswer})}
                }
            }
            ColumnLayout {
                visible:menu.searching&&(menu.calculator||menu.web);anchors.fill:parent;spacing:16
                Rectangle {Layout.fillWidth:true;Layout.preferredHeight:190;radius:24;color:Theme.primaryContainer
                    ColumnLayout {anchors.fill:parent;anchors.margins:24;spacing:12
                        MText {text:menu.calculator ? "CALCULATOR" : "SEARCH THE WEB";font.pixelSize:11;font.letterSpacing:2;color:Theme.onContainer}
                        MText {Layout.fillWidth:true;Layout.fillHeight:true;wrapMode:Text.Wrap;maximumLineCount:3;text:menu.calculator ? Hub.calculation||"Enter an expression…" : menu.query.slice(1).trim();font.pixelSize:30;color:Theme.onContainer}
                        MButton {text:menu.calculator ? "Copy result" : "Search in browser";icon:menu.calculator ? "copy" : "web";filled:true;enabled:menu.calculator ? Hub.calculation!=="" : menu.query.slice(1).trim()!=="";onClicked:menu.accept(false)}
                    }
                }
                MText {Layout.fillWidth:true;wrapMode:Text.Wrap;text:menu.calculator ? "Local calculation · + − * / % ** ( )" : "Only this explicit search opens your browser.";color:Theme.subtext;font.pixelSize:12}
                Item {Layout.fillHeight:true}
            }
        }
        RowLayout {
            visible:menu.searching&&!menu.calculator&&!menu.web&&!menu.claude&&!!menu.selected;Layout.fillWidth:true
            MText {Layout.fillWidth:true;text:"↑ ↓ choose · Enter open";font.pixelSize:11;color:Theme.subtext}
            MButton {visible:menu.selected&&menu.selected.kind==="app";text:menu.selected&&menu.selected.kind==="app"&&Hub.pinned(menu.selected.data) ? "Unpin" : "Pin";icon:"pin";compact:true;tonal:true;onClicked:if(menu.selected)Hub.pin(menu.selected.data)}
            MButton {text:"Open";icon:"next";compact:true;filled:true;onClicked:menu.accept(false)}
        }
    }
    }
    Rectangle {
        visible:menu.confirmPower!=="";anchors.fill:parent;radius:28;color:Theme.level(2)
        MouseArea {anchors.fill:parent}
        ColumnLayout {anchors.centerIn:parent;width:parent.width-64;spacing:12
            MText {Layout.fillWidth:true;text:menu.confirmPower==="menu" ? "Session and power" : "Confirm "+menu.confirmPower+"?";font.pixelSize:24;wrapMode:Text.Wrap}
            Repeater {model:menu.confirmPower==="menu" ? [{id:"suspend",name:"Sleep"},{id:"logout",name:"Log out"},{id:"reboot",name:"Restart"},{id:"poweroff",name:"Shut down"}] : []
                MButton {required property var modelData;text:modelData.name;tonal:true;Layout.fillWidth:true;onClicked:menu.confirmPower=modelData.id}
            }
            MButton {visible:menu.confirmPower!=="menu";text:"Confirm";filled:true;Layout.fillWidth:true;onClicked:{Hub.command({action:"power",verb:menu.confirmPower});Hub.close();}}
            MButton {id:powerCancel;text:"Cancel";Layout.fillWidth:true;onClicked:menu.confirmPower=""}
        }
    }
}
