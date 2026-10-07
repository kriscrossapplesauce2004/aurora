pragma Singleton
import QtQuick
QtObject {
    id:theme
    readonly property bool light: Hub.prefs.light
    readonly property bool reduceMotion: !!Hub.prefs.reduceMotion
    function motion(ms) {return reduceMotion ? 0 : ms;}
    readonly property var palettes: [
        {name:"Iris", primary:"#cfbdff", onPrimary:"#31205f", secondary:"#c6d6ae", tertiary:"#efb8c8", dark:"#17141f", light:"#f7f0ff", seed:"#7355ad"},
        {name:"Tide", primary:"#a5efff", onPrimary:"#005462", secondary:"#bcecf2", tertiary:"#dfd6bb", dark:"#101b1e", light:"#effbfc", seed:"#006575"},
        {name:"Peach", primary:"#ffc09e", onPrimary:"#54220a", secondary:"#d5c1f0", tertiary:"#c8dba5", dark:"#211711", light:"#fff2e9", seed:"#95512d"},
        {name:"Sky", primary:"#b3ccff", onPrimary:"#13305f", secondary:"#d4c4ef", tertiary:"#a6dfc2", dark:"#131923", light:"#eff3ff", seed:"#435f91"}
    ]
    readonly property var palette: palettes[Hub.prefs.palette] || palettes[0]
    readonly property var generated: Hub.prefs.dynamicColors && Hub.prefs.dynamicPalette ? Hub.prefs.dynamicPalette[light ? "light" : "dark"] || {} : {}
    function role(name,fallback) {return generated[name] || fallback;}
    readonly property color primary: role("primary",light ? palette.seed : palette.primary)
    readonly property color primaryInk: role("on_primary",light ? "#ffffff" : palette.onPrimary)
    readonly property alias onPrimary: theme.primaryInk
    readonly property color primaryContainer: role("primary_container",light ? palette.primary : palette.onPrimary)
    readonly property color containerInk: role("on_primary_container",light ? palette.onPrimary : palette.primary)
    readonly property alias onContainer: theme.containerInk
    readonly property color secondary: role("secondary",palette.secondary)
    readonly property color tertiary: role("tertiary",palette.tertiary)
    readonly property color base: role("background",light ? palette.light : palette.dark)
    readonly property color text: role("on_surface",light ? "#211d29" : "#f0e9f7")
    readonly property color subtext: role("on_surface_variant",light ? "#635c6d" : "#c5bccf")
    readonly property color muted: light ? "#79717e" : "#a59aaf"
    readonly property color surface: role("surface_container",mix(base,primaryContainer,light ? .14 : .10))
    readonly property color surfaceHigh: role("surface_container_high",mix(base,primaryContainer,light ? .25 : .19))
    readonly property color glassTint: mix(base,light ? primaryContainer : primary,light ? .26 : .19)
    readonly property color glassEdge: alpha(light ? "#ffffff" : primary,light ? .48 : .18)
    readonly property color tile: mix(base,light ? primaryContainer : primary,light ? .32 : .24)
    readonly property color tileActive: primary
    readonly property alias onTileActive: theme.primaryInk
    readonly property color dockTint: mix(base,light ? primaryContainer : primary,light ? .46 : .20)
    // M3 surface container ramp. Each step adds more of the tint.
    readonly property color surfaceLowest: mix(base,light ? "#ffffff" : "#000000",light ? .55 : .35)
    readonly property color surfaceLow: mix(base,primaryContainer,light ? .08 : .06)
    readonly property color surfaceHighest: mix(base,primaryContainer,light ? .36 : .28)
    readonly property color secondaryContainer: mix(base,secondary,light ? .42 : .26)
    // QML reads "on" + capital names as signal handlers, so the colours live under "Ink" names with aliases.
    readonly property color secondaryInk: mix(secondary, light ? "#000000" : "#ffffff", light ? .62 : .55)
    readonly property alias onSecondaryContainer: theme.secondaryInk
    readonly property color tertiaryContainer: mix(base,tertiary,light ? .45 : .28)
    readonly property color tertiaryInk: mix(tertiary, light ? "#000000" : "#ffffff", light ? .62 : .55)
    readonly property alias onTertiaryContainer: theme.tertiaryInk
    // Glass roles for islands and cards that sit on the wallpaper.
    readonly property color glassIsland: mix(mix(base,"#ffffff",light ? .25 : .06),light ? primaryContainer : primary,light ? .5 : .24)
    readonly property color glassRaised: mix(mix(base,"#ffffff",light ? .3 : .08),light ? "#ffffff" : primaryContainer,light ? .62 : .42)
    readonly property color glassHighlight: alpha("#ffffff",light ? .6 : .12)
    readonly property color glassShade: alpha("#000000",light ? .05 : .22)
    readonly property color error: role("error",light ? "#ba1a1a" : "#ffb4ab")
    readonly property color stateLayer: light ? containerInk : text
    // M3 shape scale.
    readonly property int shapeXs: 8
    readonly property int shapeSm: 12
    readonly property int shapeMd: 16
    readonly property int shapeLg: 24
    readonly property int shapeXl: 32
    // M3 expressive motion: standard and spatial curves as cubic Bezier lists.
    readonly property var emphasized: [0.2,0,0,1,1,1]
    readonly property var emphasizedDecelerate: [0.05,0.7,0.1,1,1,1]
    readonly property var emphasizedAccelerate: [0.3,0,0.8,0.15,1,1]
    // Restrained motion: the spatial curve has no overshoot.
    readonly property var spatial: [0.2,0,0,1,1,1]
    readonly property var standard: [0.2,0,0,1,1,1]
    // Springy curve with overshoot, used only by the convergence experience.
    readonly property var springy: [0.34,1.56,0.64,1,1,1]
    readonly property int durShort: 140
    readonly property int durMedium: 240
    readonly property int durLong: 360
    // Tonal elevation: level 0 is the base and level 5 is the highest container.
    function level(n) {return [base,surfaceLow,surface,surfaceHigh,surfaceHighest,mix(surfaceHighest,primaryContainer,light ? .35 : .25)][Math.max(0,Math.min(5,n))];}
    // Large panels may show compositor blur, but only a little.
    readonly property real glassFloor: .9
    function panelAlpha(t) {return Math.max(glassFloor,Math.min(1,t));}
    // Type scale. Display roles use the wide, round axes of Google Sans Flex.
    readonly property var type: ({
        displayL:{size:64,weight:Font.Black,width:125,round:100},
        displayM:{size:48,weight:Font.ExtraBold,width:120,round:100},
        displayS:{size:36,weight:Font.Bold,width:115,round:80},
        headline:{size:26,weight:Font.Bold,width:110,round:60},
        title:{size:18,weight:Font.DemiBold,width:100,round:40},
        titleS:{size:15,weight:Font.DemiBold,width:100,round:30},
        body:{size:14,weight:Font.Normal,width:100,round:0},
        bodyS:{size:13,weight:Font.Normal,width:100,round:0},
        label:{size:12,weight:Font.Medium,width:100,round:20},
        labelS:{size:11,weight:Font.Medium,width:100,round:20}
    })
    // Standard spacing steps.
    readonly property int gapXs: 4
    readonly property int gapSm: 8
    readonly property int gapMd: 12
    readonly property int gapLg: 16
    readonly property int gapXl: 24
    function mix(a,b,amount) {const x=Qt.color(a),y=Qt.color(b);return Qt.rgba(x.r+(y.r-x.r)*amount,x.g+(y.g-x.g)*amount,x.b+(y.b-x.b)*amount,1);}
    readonly property color outline: alpha(role("outline_variant",light ? "#604e75" : "#ede1ff"),.14)
    readonly property string font: "Google Sans Flex"
    readonly property var glyphs: ({apps:"apps",search:"search",close:"close",back:"arrow_back",next:"chevron_right",home:"home",settings:"tune",wifi:"wifi",wifiOff:"wifi_off",bluetooth:"bluetooth",volume:"volume_up",mute:"volume_off",mic:"mic",sun:"light_mode",moon:"dark_mode",play:"play_arrow",pause:"pause",previous:"skip_previous",skip:"skip_next",bell:"notifications",quiet:"do_not_disturb_on",power:"power_settings_new",lock:"lock",restart:"restart_alt",sleep:"bedtime",game:"sports_esports",phone:"smartphone",desktop:"desktop_windows",pin:"keep",check:"check",add:"add",timer:"timer",coffee:"coffee",capture:"screenshot_monitor",folder:"folder",terminal:"terminal",web:"language",battery:"battery_full",charging:"battery_charging_full",cpu:"speed",memory:"memory",palette:"palette",music:"music_note",grid:"grid_view",list:"view_list",calendar:"calendar_month",spark:"auto_awesome",convergence:"devices",expand:"expand_more",link:"link",heart:"favorite",clipboard:"content_paste",copy:"content_copy",trash:"delete",logout:"logout"})
    function alpha(c,a) { const v=Qt.color(c); return Qt.rgba(v.r,v.g,v.b,a); }
}
