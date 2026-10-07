import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id:root
    Component.onCompleted:Quickshell.watchFiles=false
    readonly property bool fpsEnabled:Quickshell.env("DET_OPAL_FPS")==="1"
    property int fpsFrames:0
    property int fps:0
    function show(page) {Hub.targetScreen=Hub.chooseScreen();Hub.toggle(page);}
    FrameAnimation {running:root.fpsEnabled;onTriggered:root.fpsFrames++}
    Timer {interval:500;repeat:true;running:root.fpsEnabled;onTriggered:{root.fps=Math.round(root.fpsFrames*2);root.fpsFrames=0;}}
    IpcHandler {
        target:"opal"
        function launcher():void {Hub.launcherSection="apps";root.show("launcher");}
        function clipboard():void {Hub.targetScreen=Hub.chooseScreen();Hub.toggleClipboard();}
        function controls():void {root.show("controls");}
        function audio():void {Hub.toggleAudio(Hub.chooseScreen());}
        function notifications():void {root.show("notifications");}
        function phone():void {Hub.targetScreen=Hub.chooseScreen();Hub.mode("phone");}
        function gaming():void {Hub.mode("console");}
        function desktop():void {Hub.mode("desktop");}
        function adaptive():void {Hub.mode("auto");}
        function appearance():void {root.show("appearance");}
        function settings():void {Hub.targetScreen=Hub.chooseScreen();Hub.openSettings();}
        function convergence():void {root.show("convergence");}
        function assistant():void {if(Hub.page==="assistant")Hub.close();else Hub.openAssistant("");}
        function ask(text:string):void {Hub.openAssistant(text);}
        function close():void {Hub.close();}
        function quickaccess():void {GameState.toggleQuickAccess();}
        function lock():void {Hub.lock();}
        // Used by the Opal MCP server. The backend validates every preference.
        function setPreference(key:string, value:string):string {let parsed;try{parsed=JSON.parse(value);}catch(error){return "Value must be JSON";}Hub.set(key,parsed);return "Sent "+key;}
        // The quickshell CLI splits arguments at commas, so arrays and objects come base64-encoded.
        function setPreferenceEncoded(key:string, value:string):string {let parsed;try{parsed=JSON.parse(Qt.atob(value));}catch(error){return "Value must be base64 JSON";}Hub.set(key,parsed);return "Sent "+key;}
        function preferences():string {return JSON.stringify(Hub.prefs);}
        function listNotifications():string {return JSON.stringify(Notifier.inbox.map(e=>({app:e.notification.appName||"",summary:e.notification.summary||"",body:(e.notification.body||"").slice(0,300),read:e.read,received:new Date(e.received).toISOString()})));}
        function media(action:string):string {if(["play-pause","next","previous"].indexOf(action)<0)return "Unknown action";Hub.media(action);return "ok";}
        function volume(value:int):string {Hub.volume(value);return "Volume "+Math.max(0,Math.min(100,value));}
        function toast(text:string):void {Hub.message(text);}
        function windows():string {return JSON.stringify(Hub.windows.map(w=>({title:w.title||"",app:w.className||"",workspace:w.workspace||0})));}
        function navigate(key:string):void {Hub.navigate(key);}
        function search(text:string):void {Hub.targetScreen=Hub.chooseScreen();Hub.openSection("apps");Hub.query=text;if(text.startsWith("="))Hub.command({action:"calculate",text:text.slice(1).trim()});}
        function inspect():string {return JSON.stringify({page:Hub.page,mode:Hub.prefs.mode,apps:Hub.apps.length,query:Hub.query,controller:Hub.controller,notifications:Hub.unread,gameSession:Hub.gameSession,status:Hub.status});}
    }
    Variants {
        model:Quickshell.screens
        delegate:Scope {
            id:output
            required property var modelData
            readonly property string layoutMode:Hub.layoutFor(modelData.width,modelData.height,modelData.name)
            function show(page) {Hub.targetScreen=modelData;Hub.toggle(page);}
            PanelWindow {
                id:desktop
                screen:output.modelData
                anchors {top:true;bottom:true;left:true;right:true}
                exclusionMode:ExclusionMode.Ignore
                WlrLayershell.layer:WlrLayer.Background
                WlrLayershell.namespace:"opal-wallpaper"
                WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
                color:Theme.base
                IdleInhibitor {window:desktop;enabled:Hub.keepAwake||Hub.gameSession}
                // The morph swaps the layout between two short phases; reduced motion swaps at once.
                LayoutMorph {
                    id:morph;anchors.fill:parent;layout:output.layoutMode
                    Loader {
                        anchors.fill:parent
                        sourceComponent:morph.shown==="phone" ? phoneBackdrop : desktopBackdrop
                    }
                    Component {id:phoneBackdrop;PhoneBackdrop {}}
                    Component {id:desktopBackdrop;Wallpaper {showWidgets:morph.shown==="desktop"&&Hub.prefs.desktopWidgets!==false}}
                    // Non-exclusive homes live behind applications. Only the explicit overlay takes keys.
                    Loader {
                        anchors {fill:parent;topMargin:Hub.prefs.mode==="console" ? 0 : morph.shown==="phone" ? 48 : 56;bottomMargin:Hub.prefs.mode==="console" ? 0 : morph.shown==="phone" ? (PhoneState.isTablet(output.modelData)&&Hub.prefs.tabletDock!==false ? 68 : Hub.prefs.phoneButtons ? 64 : 48) : 84}
                        active:morph.shown!=="desktop"&&Hub.page===""
                        sourceComponent:morph.shown==="phone" ? phoneHome : gameHome
                    }
                    Component {id:phoneHome;MobileHome {embedded:true}}
                    Component {id:gameHome;ConsoleHome {embedded:true}}
                }
                OpalMenu {id:desktopMenu;title:"Desktop";icon:"desktop_windows";entries:[
                    {text:"Apps",icon:"apps",quick:true,run:()=>{Hub.launcherSection="apps";output.show("launcher");}},
                    {text:"Wallpaper",icon:"wallpaper",quick:true,run:()=>output.show("wallpaper")},
                    {text:"Settings",icon:"settings",quick:true,run:()=>{Hub.targetScreen=output.modelData;Hub.openSettings();}},
                    {text:"Dark theme",icon:"dark_mode",checked:!Theme.light,run:()=>Hub.set("light",!Theme.light)},
                    {text:"Desktop widgets",icon:"widgets",checked:Hub.prefs.desktopWidgets!==false,run:()=>Hub.set("desktopWidgets",Hub.prefs.desktopWidgets===false)},
                    {text:"Style and colours",icon:"palette",run:()=>output.show("appearance")},
                    {text:"Displays & convergence",icon:"convergence",run:()=>output.show("convergence")}
                ]}
                MouseArea {anchors.fill:parent;acceptedButtons:Qt.RightButton;onClicked:e=>{Hub.targetScreen=output.modelData;desktopMenu.popup(e.x,e.y);}}
            }
            PanelWindow {
                id:statusbar
                screen:output.modelData
                visible:output.layoutMode==="phone"&&(Hub.status.fullscreenMonitors||[]).indexOf(output.modelData.name)<0
                anchors {top:true;left:true;right:true}
                implicitHeight:output.layoutMode==="phone" ? 48 : 44
                exclusiveZone:visible ? implicitHeight : 0
                // Keep bar hover effects above transient utility surfaces.
                WlrLayershell.layer:WlrLayer.Overlay
                WlrLayershell.namespace:"opal-bar"
                color:Theme.alpha(Theme.base,.48)
                Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:1;color:Theme.outline}
                Loader {anchors.fill:parent;active:statusbar.visible;sourceComponent:phoneStatusContent}
                Component {id:phoneStatusContent;PhoneStatus {anchors.fill:parent;output:statusbar.screen;fpsEnabled:root.fpsEnabled;fps:root.fps}}
            }
            Loader {active:output.layoutMode!=="console";sourceComponent:Component {Taskbar {target:output.modelData}}}
            Loader {active:output.layoutMode==="desktop"&&Hub.prefs.barStyle==="split";sourceComponent:Component {TopBar {screen:output.modelData}}}
            PanelWindow {
                screen:output.modelData
                visible:Hub.toast!==""&&Hub.page===""&&!Hub.audioOpen
                anchors {bottom:true;right:true}
                margins {bottom:90;right:12}
                implicitWidth:Math.min(390,output.modelData.width-24);implicitHeight:100
                exclusionMode:ExclusionMode.Ignore
                WlrLayershell.namespace:"opal-toast"
                color:"transparent"
                Surface {
                    anchors.fill:parent;radius:30
                    RowLayout {anchors {fill:parent;margins:18} spacing:12
                        Glyph {name:"bell";color:Theme.primary}
                        MText {text:Hub.toast;Layout.fillWidth:true;font.pixelSize:13;maximumLineCount:4;wrapMode:Text.Wrap}
                    }
                    MouseArea {anchors.fill:parent;onClicked:{Hub.toast="";Hub.osd="";}}
                }
            }
        }
    }
    PanelWindow {
        id:volumeOsd
        screen:Hub.osdScreen||Hub.chooseScreen()
        // Desktop bars show volume feedback in the status pill instead.
        readonly property bool inBar:screen&&Hub.layoutFor(screen.width,screen.height,screen.name)==="desktop"&&(Hub.status.fullscreenMonitors||[]).indexOf(screen.name)<0
        visible:Hub.osd!==""&&Hub.page===""&&!Hub.audioOpen&&!inBar
        anchors {bottom:true}
        margins.bottom:100
        implicitWidth:Math.min(340,screen ? screen.width-24 : 340)
        implicitHeight:112
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-volume-osd"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        Loader {anchors.fill:parent;active:Hub.osd!=="";sourceComponent:Component {VolumeOsd {}}}
    }
    // First start: a quiet card offers the tour. It never takes the keyboard.
    PanelWindow {
        id:tourPrompt
        property bool dismissed:false
        screen:Hub.chooseScreen()
        visible:Hub.preferencesLoaded&&Hub.prefs.onboarded!==true&&!dismissed&&Hub.page===""&&tourDelay.elapsed
        anchors {bottom:true;right:true}
        margins {bottom:90;right:18}
        implicitWidth:360;implicitHeight:tourCard.implicitHeight
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-toast"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        Timer {id:tourDelay;property bool elapsed:false;interval:4000;running:Hub.preferencesLoaded;onTriggered:elapsed=true}
        Rectangle {
            id:tourCard;anchors.fill:parent;implicitHeight:tourColumn.implicitHeight+32;radius:Theme.shapeXl;color:Theme.primaryContainer
            ColumnLayout {id:tourColumn;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:6
                RowLayout {spacing:10
                    Glyph {name:"auto_awesome";font.pixelSize:22;color:Theme.onContainer}
                    MText {text:"Opal has a new look";role:"titleS";color:Theme.onContainer}}
                MText {Layout.fillWidth:true;wrapMode:Text.Wrap;text:"Take a one-minute tour to pick your bar, icons and theme.";role:"bodyS";color:Theme.alpha(Theme.onContainer,.85)}
                RowLayout {Layout.fillWidth:true;Layout.topMargin:4
                    Item {Layout.fillWidth:true}
                    MButton {text:"Not now";compact:true;ink:Theme.onContainer;onClicked:{tourPrompt.dismissed=true;Hub.set("onboarded",true);}}
                    MButton {text:"Take the tour";compact:true;filled:true;onClicked:{tourPrompt.dismissed=true;Hub.targetScreen=tourPrompt.screen;Hub.page="welcome";}}
                }
            }
        }
    }
    // Opal Link pairing request. It never takes the keyboard.
    PanelWindow {
        screen:Hub.chooseScreen()
        visible:Hub.linkPairRequest!==null
        anchors {bottom:true;right:true}
        margins {bottom:90;right:18}
        implicitWidth:360;implicitHeight:pairCard.implicitHeight
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-toast"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        Rectangle {
            id:pairCard;anchors.fill:parent;implicitHeight:pairColumn.implicitHeight+32;radius:Theme.shapeXl;color:Theme.level(3)
            ColumnLayout {id:pairColumn;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:6
                RowLayout {spacing:10
                    Glyph {name:"devices";font.pixelSize:22;color:Theme.primary}
                    MText {text:"Pair with "+(Hub.linkPairRequest ? Hub.linkPairRequest.name : "")+"?";role:"titleS";Layout.fillWidth:true}}
                MText {Layout.fillWidth:true;wrapMode:Text.Wrap;text:"Check that both screens show "+(Hub.linkPairRequest ? Hub.linkPairRequest.code : "")+".";role:"bodyS";color:Theme.subtext}
                RowLayout {Layout.fillWidth:true;Layout.topMargin:4
                    Item {Layout.fillWidth:true}
                    MButton {text:"Reject";compact:true;onClicked:{Hub.link("reject",Hub.linkPairRequest.id);Hub.linkPairRequest=null;}}
                    MButton {text:"Pair";compact:true;filled:true;onClicked:{Hub.link("accept",Hub.linkPairRequest.id);Hub.linkPairRequest=null;}}
                }
            }
        }
    }
    WorkspaceOsd {}
    // Quick Access floats above games. Only a keyboard or IPC open takes keyboard focus.
    PanelWindow {
        screen:Hub.targetScreen||Quickshell.screens[0]
        visible:GameState.quickAccess||quickAccess.reveal>.001
        anchors {top:true;bottom:true;left:true;right:true}
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-quick-access"
        WlrLayershell.keyboardFocus:GameState.quickAccess&&GameState.keyboardOpened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color:"transparent"
        QuickAccess {id:quickAccess;anchors.fill:parent}
    }
    LockScreen {}
    PolkitDialog {}
    SystemServices {}
    AudioDrawer {}
    ShadeWindow {}
    AssistantWindow {}
    PowerProfileWindow {}
    TaskbarContextWindow {}
    DockWindow {}
    DockWelcomeWindow {}
    PhoneDock {}
    ConvergenceController {}
    PhoneGestureLayer {}
    PanelWindow {
        id:notificationPopups
        screen:Notifier.popupScreen || Quickshell.screens[0]
        readonly property bool phone:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")==="phone"
        visible:Notifier.popups.length>0 && Hub.page===""&&!Hub.audioOpen
        anchors {top:notificationPopups.phone;bottom:!notificationPopups.phone;right:true}
        margins {top:notificationPopups.phone ? 64 : 0;bottom:notificationPopups.phone ? 0 : 76;right:18}
        implicitWidth:Math.min(360,screen ? screen.width-24 : 360)
        implicitHeight:Math.min(popupColumn.implicitHeight,screen ? screen.height-110 : 700)
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-toast"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        Flickable {
            anchors.fill:parent;contentHeight:popupColumn.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            Column {id:popupColumn;width:parent.width;spacing:8
                Repeater {model:Notifier.popups;NotificationCard {required property var modelData;entry:modelData;popup:true;width:popupColumn.width}}
            }
        }
    }
    // Utility pills also dismiss from outputs other than their own.
    Variants {
        model:Quickshell.screens
        delegate:PanelWindow {
            required property var modelData
            screen:modelData
            visible:overlay.visible&&screen!==overlay.screen
            anchors {top:true;bottom:true;left:true;right:true}
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.layer:WlrLayer.Overlay
            WlrLayershell.namespace:"opal-shade-dismiss"
            WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
            color:"transparent"
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
        }
    }
    PanelWindow {
        id:overlay
        screen:Hub.targetScreen || Quickshell.screens[0]
        visible:Hub.page!==""&&Hub.page!=="controls"&&Hub.page!=="notifications"&&Hub.page!=="assistant"
        readonly property string layoutMode:Hub.layoutFor(width,height,screen ? screen.name : "")
        anchors {top:true;bottom:true;left:true;right:true}
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        readonly property bool phoneLauncher:layoutMode==="phone"&&Hub.page==="launcher"
        readonly property bool desktopStart:layoutMode==="desktop"&&Hub.page==="launcher"&&Hub.launcherSection==="apps"
        readonly property bool searchPanel:Hub.page==="search"&&layoutMode!=="phone"
        WlrLayershell.namespace:"opal-overlay"
        WlrLayershell.keyboardFocus:visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Transparent backdrop keeps the desktop sharp; only the panel blurs.
        // The scrim stays below the compositor blur threshold (alpha 0.1), so the screen behind a panel is never blurred.
        color:phoneLauncher||desktopStart||searchPanel ? "transparent" : Theme.alpha("#000000",.07)
        mask:Region {
            Region {x:0;y:0;width:overlay.width;height:overlay.height}
            Region {intersection:Intersection.Subtract;x:0;y:overlay.height-64;width:overlay.width;height:overlay.desktopStart||overlay.searchPanel ? 64 : 0}
        }
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
        Surface {
            id:panel
            property real arrival:1
            opacity:arrival
            // Reveal from the bottom edge. Animate local content only: the
            // panel's final x/y geometry is never interpolated from (0, 0).
            transform: [
                Scale {origin.x:overlay.desktopStart||overlay.searchPanel ? 0 : panel.width/2;origin.y:panel.height;xScale:overlay.searchPanel ? .94+.06*panel.arrival : 1;yScale:panel.launcher||overlay.searchPanel ? .9+.1*panel.arrival : 1},
                Translate {y:(1-panel.arrival)*(panel.launcher||overlay.searchPanel ? 18 : 8)}
            ]
            Connections {target:overlay;function onVisibleChanged(){if(overlay.visible)panelArrival.restart();}}
            NumberAnimation {id:panelArrival;target:panel;property:"arrival";from:0;to:1;duration:Theme.motion(400);easing.type:Easing.BezierSpline;easing.bezierCurve:Theme.emphasizedDecelerate}
            readonly property bool phone:overlay.layoutMode==="phone"
            readonly property bool game:overlay.layoutMode==="console"
            readonly property bool launcher:Hub.page==="launcher"
            width:phone||game&&launcher ? overlay.width : Math.min(overlay.width-36,overlay.searchPanel ? 640 : overlay.desktopStart ? 760 : Hub.page==="settings" ? 880 : launcher ? 960 : Hub.page==="windows" ? 1100 : Hub.page==="convergence"||Hub.page==="wallpaper" ? 800 : Hub.page==="appearance"||Hub.page==="welcome" ? 660 : 490)
            readonly property real contentFit:overlayContent.item&&overlayContent.item.fitHeight!==undefined ? overlayContent.item.fitHeight : 0
            height:phone||game&&launcher ? overlay.height : Math.min(overlay.height-88,overlay.desktopStart ? 620 : launcher ? 740 : Hub.page==="settings" ? 720 : Hub.page==="clipboard" ? 650 : contentFit>0 ? contentFit : 860)
            Behavior on height {enabled:overlay.visible;NumberAnimation {duration:Theme.motion(Theme.durMedium);easing.type:Easing.OutCubic}}
            x:phone||game&&launcher ? 0 : overlay.searchPanel ? 18+54 : overlay.desktopStart ? 18 : launcher||Hub.page==="settings"||Hub.page==="appearance"||Hub.page==="welcome"||Hub.page==="convergence"||Hub.page==="wallpaper" ? (overlay.width-width)/2 : overlay.width-width-12
            y:phone||game&&launcher ? 0 : overlay.desktopStart||overlay.searchPanel ? overlay.height-height-72 : launcher||Hub.page==="settings"||Hub.page==="welcome" ? Math.max(60,(overlay.height-height)/2) : 62
            radius:phone||game&&launcher ? 0 : overlay.desktopStart ? 28 : overlay.searchPanel ? 32 : 36
            translucency:phone&&launcher ? Math.min(.35,Hub.prefs.glass) : Hub.prefs.glass
            border.width:phone&&launcher ? 0 : 1
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons}
            Loader {
                id:overlayContent
                anchors.fill:parent;anchors.topMargin:panel.phone ? 48 : 0;anchors.bottomMargin:panel.phone ? (Hub.prefs.phoneButtons ? 64 : 48) : 0;active:overlay.visible
                onLoaded:contentArrival.restart()
                NumberAnimation {id:contentArrival;target:overlayContent;property:"opacity";from:0;to:1;duration:Theme.motion(180)}
                sourceComponent:Hub.page==="search" ? (panel.phone ? mobileComponent : searchComponent) : Hub.page==="settings" ? settingsComponent : Hub.page==="launcher" ? (panel.phone ? mobileComponent : panel.game ? consoleComponent : overlay.desktopStart ? startComponent : launcherComponent) : Hub.page==="clipboard" ? clipboardComponent : Hub.page==="appearance" ? appearanceComponent : Hub.page==="convergence" ? convergenceComponent : Hub.page==="wallpaper" ? wallpaperComponent : Hub.page==="windows" ? windowsComponent : Hub.page==="welcome" ? welcomeComponent : controlsComponent
            }
            PhoneStatus {visible:panel.phone;anchors.top:parent.top;width:parent.width;height:48;output:overlay.screen}
            PhoneNavigation {visible:panel.phone;anchors.bottom:parent.bottom;width:parent.width;height:implicitHeight;output:overlay.screen}
            Rectangle {visible:Hub.toast!=="";anchors {bottom:parent.bottom;left:parent.left;right:parent.right;margins:12} height:72;radius:24;color:Theme.surfaceHigh;z:5
                MText {anchors {fill:parent;margins:14} text:Hub.toast;font.pixelSize:12;wrapMode:Text.Wrap;maximumLineCount:3;verticalAlignment:Text.AlignVCenter}
                MouseArea {anchors.fill:parent;onClicked:Hub.toast=""}
            }
        }
        Component {id:windowsComponent;ColumnLayout {anchors.fill:parent;anchors.margins:24;spacing:16
            RowLayout {Layout.fillWidth:true;MText {text:"App switcher";font.pixelSize:28;Layout.fillWidth:true}MButton {icon:"close";onClicked:Hub.close()}}
            WindowSwitcher {Layout.fillWidth:true;Layout.fillHeight:true;layoutMode:panel.game ? "console" : panel.phone ? "phone" : "desktop";focus:true}
        }}
        Component {id:wallpaperComponent;WallpaperPicker {}}
        Component {id:welcomeComponent;Onboarding {}}
        Component {id:searchComponent;SearchPanel {}}
        Component {id:settingsComponent;Settings {}}
        Component {id:convergenceComponent;Convergence {}}
        Component {id:launcherComponent;Launcher {}}
        Component {id:startComponent;StartMenu {}}
        Component {id:mobileComponent;MobileHome {}}
        Component {id:consoleComponent;ConsoleHome {}}
        Component {id:controlsComponent;QuickSettings {}}
        Component {id:clipboardComponent;ClipboardPanel {touchMode:panel.phone}}
        Component {id:appearanceComponent;ColumnLayout {
            anchors {fill:parent;margins:20} spacing:16
            RowLayout {Layout.fillWidth:true;MText {text:"Make it yours";font.pixelSize:26;font.weight:Font.DemiBold;Layout.fillWidth:true}MButton {icon:"close";tonal:true;onClicked:Hub.close()}}
            Appearance {Layout.fillWidth:true;Layout.fillHeight:true;compact:panel.phone}
        }}
        Shortcut {sequence:"Escape";enabled:!overlay.desktopStart&&!overlay.searchPanel&&!(panel.game&&panel.launcher);onActivated:Hub.close()}
        // Controller focus for every page in this window. Pages may define controllerTab(delta) and controllerBack().
        ControllerFocus {
            anchors.fill:parent;root:overlayContent;priority:0;closeOnBack:false;tabHints:true
            active:overlay.visible&&!(panel.game&&panel.launcher)&&!GameState.quickAccess
            onBack:{const page=overlayContent.item;if(!(page&&page.controllerBack&&page.controllerBack()))Hub.close();}
            onTab:delta=>{const page=overlayContent.item;if(page&&page.controllerTab)page.controllerTab(delta);}
        }
    }
}
