; ArkSense - lib\State.ahk
; All settings and runtime state. Every class here is a bag of statics.
; Part of ArkSense.ahk; run that file, not this one.

; ARK: SE Automatic Antidote - fires only while the buff is absent, verifies
; it landed, retries on failure. Run ARK in Borderless Window mode.
; Hotkeys (rebindable in menu): Insert=menu F8=toggle F9=apply now F10=eyedrop

class Cfg {
    static AntidoteKey   := "7"
    static IntervalSec   := 150
    static SkipIfActive  := 0
    static KeyHoldMs     := 55
    static AirborneMs    := 1400
    static VerifyDelayMs := 300
    static RetryDelayMs  := 200
    static MaxRetries    := 70
    static BuffColor     := "8FBF3A"
    static Tolerance     := 20
    static Relentless    := 1     ; refire the moment the buff is gone, ignoring the interval
    static RecheckMs     := 300   ; how often to look for a missing buff while idle
}

class Theme {
    static FontName := "Segoe UI"   ; interface font; glyph + data panels stay fixed
    static Preset   := "Crimson"    ; last theme preset picked (Visuals > Look > Style)
    static StyleVer := 0            ; 12 = moved to the step-12 look (see ClampLoaded)
    static Panel    := "14101A"     ; window background (content area)
    static Header   := "1B1622"     ; sidebar and group panels
    static Panel2   := "110E16"     ; value boxes, dropdowns, slider bars
    static Accent   := "EE2F5F"    ; primary pink-red
    static Accent2  := "A06BFF"    ; second colour: gradients (top line, wordmark)
    static Text     := "E4DEEB"
    static Dim      := "736A85"
    static Line     := "2A2334"
    static Ok       := "4ADE80"
    static Bad      := "FF5C7A"
    static Opacity  := 248
    static HudOn    := 1
    static HudX     := 0
    static HudY     := 0
    static PillH    := 24     ; minimum pill height in pixels (grows to fit the font)
    static PillGap  := 4      ; space between pills
    static PillVertical := 1  ; 1 = stacked top to bottom, 0 = one row
    static HudFontSize   := 9
    static HudShowState  := 1
    static HudShowMsg    := 1
    static HudShowCounts := 1
    static HudShowDesmo  := 1    ; add-on status segments follow this pattern
    static HudShowBag    := 1
    static HudShowMammoth := 1
    static HudShowOc := 1           ; "OC: On" pill while the OC macro runs
    static HudShowStreamer := 1
    static HudBorderOn   := 0    ; thin outline around each pill
    static HudBgOn       := 1    ; overlay background fill
    static HudBgOpacity  := 205  ; overlay window transparency 0-255
    static HudTextColor  := "FFFFFF"  ; status-bar text colour (overlay only)
    static HudBorderColor := "FF2836" ; pill + card outline colour (overlay only)
    static StreamerMode  := 0    ; hide from screen capture
    static StreamerScope := "Menu + overlays"   ; what it hides: + "Overlays only" | "Menu only"
    static OverlayGameOnly := 1  ; pills + card only while ARK is focused or this menu is open
    static WallOn    := 0          ; picture behind the menu's panels
    static WallPath  := ""
    static Splash    := 1          ; startup animation
    static SelfCheck := 1          ; self-check report after start
    static ShotStamp := 1          ; time / server stamp on clean screenshots
    static Renderer  := "Classic"  ; overlay look: Classic (step 9 look, AutoHotkey windows) |
                                   ; Smooth ("Modern look": lib\ArkSenseOverlay.cs)
    static UserName  := "pseidonx" ; the name in the sidebar's profile box (click it to edit)
    static MenuEngine := "Web"     ; menu: Web (lib\menu on Edge WebView2) | Native
    ; Visuals > Look (step 21) - web menu + startup animation; "None"/0 = the plain look
    static Look      := "None"     ; None | Aurora | Embers | Frosted glass | Holo
    static Grade     := "None"     ; None | Cinematic | Warm | Cold | Vivid | Mono
    static NeonEdges := 0          ; turning gradient edge round every panel
    static Spotlight := 0          ; soft light under the mouse, panels lift
    static LookSplash := 1         ; the startup animation follows the look
}

class Keys {
    static Menu   := "Insert"
    static Toggle := "F7"
    static Fire   := "F9"
    static Pick   := "F10"
    static Kill   := ""
    static Shot   := ""      ; clean screenshot
    static Bad    := []      ; runtime: keys that failed to bind on the last ApplyHotkeys
}

class Store {
    static Ini      := A_ScriptDir . "\ArkSense.ini"
    static IniOld   := A_ScriptDir . "\ark_antidote.ini"   ; pre-rename settings file
    static Profiles := Map()          ; name -> Map of Cfg fields
    static Regions  := Map()          ; "1920x1080" -> [x1,y1,x2,y2]
    static Active   := "Default"
    static GameExe  := ""             ; optional user override (ahk_exe / ahk_class / title)
    static GameTargets := ["ahk_exe ShooterGame.exe", "ahk_exe ArkAscended.exe"]
}

class S {
    static Killing      := false      ; the killswitch is closing ArkSense: no waiting on exit
    static enabled      := false
    static phase        := "idle"     ; idle | armed | verify
    static nextFireAt   := 0
    static readyAt      := 0
    static verifyAt     := 0
    static airborneTill := 0
    static recheckAt    := 0          ; throttles the relentless buff re-check
    static menuOpen     := false      ; in-game inventory, not this menu
    static attempts     := 0
    static applied      := 0
    static failed       := 0     ; presses that didn't bring the buff up
    static gaveUp       := 0     ; cycles that ran out of tries
    static lastHud      := ""
    static hudMsg        := ""
    static hudCol        := ""
    static sessionStart  := 0
}

; Ported E double-press remount macro - global hotkey, unscoped to ARK
class Desmo {
    static DelayMs  := 20
    static Toggle   := "F3"
    static Active   := false
    static HoldOn   := 0       ; 1 = hold-E spam replaces the double-press
    static HoldMs   := 10      ; spam period while E is held
    static Holding  := false   ; runtime: spam timer currently running
    static LastE    := 0       ; A_TickCount of the last physical E (watchdog)
}

; Mammoth war drum: click on a fixed beat after arming, plus a tap-along beat meter
class Mammoth {
    static Toggle     := "F6"
    static IntervalMs := 600      ; gap between clicks
    static HoldMs     := 30       ; button held down per click (UE can miss 0-length clicks)
    static Button     := "Left"   ; Left | Right | Middle
    static GameOnly   := 1        ; skip clicks while ARK is not focused
    static ClickOnArm := 1        ; first click lands the instant you arm
    static Active     := false
    static NextAt     := 0.0      ; runtime: QPC ms of the next scheduled click
    static HiRes      := false    ; runtime: timeBeginPeriod(1) currently held
    static Measuring  := false    ; runtime: tap-along meter running
    static MeasureAt  := 0.0
    static Taps       := []
    static Result     := 0        ; last measured median interval, 0 = none
    static ResultText := "no measurement yet"
}

; opens the in-game console, pastes a preset command line, closes it again
class Fps {
    static GenRangeOn  := 0      ; white gen range currently toggled on
    static ConsoleKey  := "NumpadDiv"
    static OpenDelayMs := 200
    static CloseDelayMs := 150
}

; MP3 background music + click sound via winmm MCI - no external libs
class Audio {
    static MusicOn     := 0
    static MusicPath   := ""
    static ClickOn     := 0
    static ClickPath   := ""
    static MusicOpen   := false   ; is an MCI music device currently open
    ; absolute path to a custom logo; if the file is missing the built-in "A"
    ; badge is drawn instead. Blank here means "use logo.png beside the script".
    static LogoPath    := "C:\Users\uku\Downloads\ce44624b-7c78-414d-beaf-e553d1489e40.png"
    static LogoW       := 34
    static LogoH       := 34
    static LogoX       := 14      ; horizontal position of the logo in the header
}

; insta-take bag: hold-to-repeat left-click at a picked point (OP Auto Clicker style)
class Bag {
    static Toggle      := ""      ; arms/disarms the feature
    static TriggerKey  := "g"     ; while armed, one press = one click
    static Active      := false   ; armed state
    static X           := 900
    static Y           := 340
    static UseCurrent  := 0       ; 1 = click at cursor instead of the fixed point
    static GameOnly    := 1       ; only fire while ARK is focused
}

; sampled system stats for the overlay; -1 means "couldn't read it"
class Stats {
    static ShowClock := 1
    static ShowCpu   := 1
    static ShowRam   := 1
    static ShowGpu   := 1
    static CardOn    := 1           ; the stats card overlay as a whole
    static ShowPing  := 1           ; ping graph + jitter / loss on the card
    ; stats bar (lib\Bar.ahk, step 24): the card as one slim bar instead of the graph
    static Bar     := 0
    static BarPing := 1
    static BarFps  := 1
    static BarCpu  := 0
    static BarGpu  := 0
    static BarRam  := 0
    static BarTag  := 0             ; the clantag in the bar
    static BarLogo := "Lightning"   ; step 25: the logo in front of "ArkSense" (BarLogos())
    static BarLogoColor := ""       ; its colour, "" = the overlay accent
    static PingHost  := "1.1.1.1"   ; manual ping target (used when PingAuto is off)
    static PingAuto  := 1           ; ping the ARK server found by lib\ServerDetect.ps1
    static QueryPort := 0           ; server query port, 0 = find it automatically
    static IntervalSec := 1
    static HudFontSize := 11      ; default card size (until resized in EDIT LAYOUT)
    static HudX := 0              ; default card position (until moved in EDIT LAYOUT)
    static HudY := 30
    static Cpu  := -1
    static Ram  := -1
    static Gpu  := -1
    static Ping := -1
    static Query := -1            ; server reply time (Steam query), ms
    static HistCpu := []
    static HistRam := []
    static HistGpu := []
    static HistPing := []         ; last 60 pings from the helper, -1 = no answer
    static HistQuery := []        ; last 60 server reply times, -1 = no answer
    static Err := Map("cpu", "", "ram", "", "gpu", "", "ping", "", "query", "")   ; last sampler failure
    static GpuPid := 0          ; background GPU helper process, 0 = not running
    static GpuRetryAt := 0      ; earliest tick the helper may be (re)started
    static PingPid := 0         ; background ping helper process
    static Server     := ""     ; detected ARK server address, "" = none yet
    static ServerPort := ""
    static ServerNote := ""     ; detector status shown beside / instead of it
    static Local      := false  ; the game runs against this PC (local server / singleplayer): ping 0
    static DetectPid  := 0      ; running ServerDetect.ps1, 0 = none
    static DetectGame := 0      ; ARK process id the last detection was for
    static DetectAt   := 0      ; earliest tick for the next detection
    static QueryPid   := 0      ; running ServerQuery.ps1, 0 = none
    static QueryRetryAt := 0
    static QueryFound := 0      ; query port in use, 0 = not known
    static QueryInfo  := ""     ; query helper status text
    static PingRetryAt := 0
    static ShowFps    := 1      ; FPS line on the card's graph (lib\ArkSenseFps.cs)
    static ShowPlayers := 1     ; live player count on the card (from the Steam query reply)
    static QueryHow   := ""     ; how the query port was picked: manual | matched | listed | other-server
    static QuerySeen  := ""     ; every server answering on the address (logged once)
    static Players    := -1     ; online now, -1 = unknown
    static MaxPlayers := -1
    static Fps        := -1     ; ARK's frames in the last second, -1 = none
    static HistFps    := []     ; last 60 FPS samples
    static FpsPid     := 0      ; running ArkSenseFps.exe, 0 = none
    static FpsGame    := 0      ; ARK process it counts
    static FpsRetryAt := 0
    static FpsInfo    := ""     ; why there is no FPS (shown in the live readout)
}

; streamer mode bookkeeping (lib\Overlay.ahk ApplyStreamerMode)
class Stream {
    static Hidden := 0           ; windows hidden from capture on the last pass
    static Failed := 0           ; windows Windows refused
}

; autoclicker (lib\AutoClick.ahk)
class Ac {
    static Toggle   := ""        ; hotkey, none by default
    static Mode     := "Toggle"  ; Toggle | Hold
    static Button   := "Left"    ; Left | Right | Middle | Mouse 4 | Mouse 5
    static Cps      := 10        ; clicks per second (1-60)
    static HoldMs   := 15        ; button held down per click
    static Vary     := 1         ; vary each gap / hold around the set value
    static VaryPct  := 15        ; how much (1-50 %)
    static GameOnly := 1         ; stops when ARK isn't the focused window
    static Limit    := 0         ; stop after this many clicks, 0 = never
    static Active   := false     ; runtime
    static Clicks   := 0
    static StartAt  := 0
    static Rate     := 0
    static Why      := ""
}

; OC macro (lib\Oc.ahk): holds Shift and spams the hotbar keys 1 2 3 in turn
class Oc {
    static Toggle   := ""        ; hotkey, none by default
    static Mode     := "Toggle"  ; Toggle: press to start / stop | Hold: runs while the key is held
    static Keys     := "1 2 3"   ; sent in turn
    static GapMs    := 20        ; pause after each key
    static HoldMs   := 12        ; each key held down this long (UE can miss 0-length presses)
    static Shift    := 1         ; hold Shift while it runs
    static GameOnly := 1         ; stops as soon as ARK isn't the focused window
    static StopSec  := 0         ; stops by itself after this long, 0 = never
    static Active   := false     ; runtime
    static StartAt  := 0
    static Pressed  := false     ; runtime: this macro pressed Shift down
    static Sent     := 0         ; runtime: keys sent this run
    static Why      := ""        ; runtime: why it stopped last
}

; Clantag (lib\Clantag.ahk, step 23): an animated tag drawn on your own screen only -
; on its own (a small movable box) or in the top line of the stats card
class Ct {
    static On       := 1
    static Text     := "pseidonx"    ; the tag (up to 24 characters)
    static Style    := "Build-up"    ; Build-up (types itself out, CS style) | Decode (symbols lock in)
    static Speed    := 100           ; animation speed in % (25-300)
    static Where    := "On its own"  ; On its own | On the stats card
    static Font     := "Consolas"    ; Consolas | Bahnschrift | Segoe UI | Menu font
    static Bold     := 1
    static Scale    := 100           ; size in % (50-300)
    static Alpha    := 170           ; background opacity 0-255 (the text stays solid)
    static Outline  := 1             ; a line around the box
    static TextColor := "FFFFFF"
    static Accent   := "FF2836"      ; the cursor and the letters still scrambling
    static BgColor  := "1C1C24"
    static OutlineColor := "FF2836"
    static Key      := ""            ; show / hide hotkey
    static Record   := 0             ; 1 = stays in recordings even when streamer mode hides overlays
    static X        := -1            ; top-left corner; -1 = top centre of the main screen
    static Y        := -1
    ; runtime
    static Win      := ""            ; the box window (on its own)
    static Moving   := false         ; MOVE pressed: the box takes clicks and can be dragged
    static Jump     := false         ; step 25: go to the typed X / Y on the next draw, even while moving
    static T0       := 0             ; animation clock start
    static Fr       := ""            ; the current frame {txt, mask, cur}
    static Sig      := ""            ; what the box last showed
    static CardSig  := ""            ; what the card last showed
    static W        := 0
    static H        := 0
}

; "Now playing" overlay (lib\NowPlaying.ahk + lib\NowPlaying.ps1)
class Np {
    static On       := 1         ; show the card while something plays
    static Source   := "Browsers" ; Browsers (YouTube in Chrome/Edge/Firefox/...) | Any app
    static Cover    := 1         ; show the video thumbnail / album art
    static Progress := 1         ; progress bar + times
    static HidePaused := 1       ; hide after 5 s paused
    static Alpha    := 175       ; background opacity 0-255 (text stays solid)
    static Scale    := 100       ; size in %
    static X        := -1        ; top-left corner; -1 = default spot (bottom left of the screen)
    static Y        := -1
    static Accent   := ""        ; progress bar colour, "" = the overlay accent
    static Outline  := 1         ; outline around the card
    static OutlineColor := ""    ; its colour, "" = the bar colour
    static GameOnly := 1         ; only while ARK or the ArkSense menu is the focused window
    ; runtime
    static Win      := ""        ; the card window
    static Pid      := 0         ; NowPlaying.ps1
    static RetryAt  := 0
    static Moving   := false     ; MOVE pressed: the card takes clicks and can be dragged
    static Jump     := false     ; step 25: go to the typed X / Y on the next draw, even while moving
    static Title    := ""
    static Artist   := ""
    static App      := ""
    static Status   := ""        ; Playing | Paused | Stopped | ""
    static PosSec   := -1
    static LenSec   := -1
    static PosAt    := 0         ; tick when PosSec was read (playing: it runs on)
    static CoverPath := ""
    static Img      := 0         ; GDI+ image of the cover
    static ImgPath  := ""
    static PausedAt := 0
    static Via      := ""        ; media session | window title | ""
    static Note     := ""        ; helper status
    static Sig      := ""        ; last drawn content
    static W        := 0
    static H        := 0
    static Gdip     := 0         ; GDI+ token
}

; stats card overlay (lib\Stats.ahk): drawn into one bitmap; the window is UI.StatHud
class Card {
    static N      := 60        ; graph columns = ping samples shown
    static Order  := []        ; metric keys in the top row (fixed per build)
    static Graph  := false     ; built with the ping graph (fixed per build)
    static Size   := 0         ; font size it was last drawn at, 0 = not yet
    static W      := 1         ; last drawn size in pixels
    static H      := 1
    static GripX  := 0         ; resize grip position (client pixels)
    static GripY  := 0
    static FxCol  := ""        ; outline colour from the active effect, "" = none
    static Moving := false     ; step 25: the card / bar alone is being moved (pills untouched)
    ; classic card + clantag (step 23): the card without the tag, kept between tag frames
    static BaseDC  := 0
    static BaseBmp := 0
    static BaseOld := 0
    static BaseW   := 0
    static BaseH   := 0
    static Alpha   := 255       ; opacity it was last pushed with
    static TagX    := 0         ; where the tag's first letter sits (client pixels)
    static TagY    := 0
    static TagLay  := ""        ; the tag's letter positions at the card's font
    static Chip    := ""        ; step 25: [x1, y1, x2, y2] of the tag's own box on the card, "" = none
}

; colour-only UI animation - all driven by one AnimTick loop
class Anim {
    static HoverOn    := 1
    static TabOn      := 1
    static PulseOn    := 1        ; legacy flag: only used to pick Effect on first run
    static HoverSpeed := 22
    static TabSpeed   := 18
    static PulseDepth := 40       ; glow strength for Pulse / Neon
    static RainbowOn  := 1        ; legacy flag: only used to pick Effect on first run
    static RainbowSpeed := 3      ; 1-15: effect speed (frame clock advance)
    static Effect     := ""       ; Off Pulse Rainbow Flame Neon Scanner ("" = from legacy flags)
    static GlowOn     := 0        ; glowing rings around group panels
    static TitleOn    := 0        ; "Ark" wordmark follows the effect colour
    static FadeIn     := 0        ; fade the menu in when it opens
    static FadeLevel  := 0        ; runtime: current fade-in opacity
    static Heat       := Map()    ; runtime: per-piece flicker state for Flame
    static Hue        := 0        ; current hue 0-359
    static TimerHue   := 120      ; session-timer hue (offset from border)
    static Fades      := Map()
    static Busy       := false    ; true while the menu is being rebuilt
}

; Bounded history of the script's OWN outbound actions only. Deliberately not a
; global input hook - that would read other input and add detectable behaviour.
class Log {
    static Items := []            ; each: {t: "HH:mm:ss", src, msg}
    static Max   := 300
    static TextColor := "4CD07A"  ; green by default
}

; runtime state of the in-game pill overlay (lib\Overlay.ahk) - one window per pill
class Pill {
    static Items  := Map()     ; key -> {win, border, fill, icon, grip, text, size, w, h, gx}
    static Order  := []        ; keys in on-screen order
    static ByHwnd := Map()     ; pill window hwnd -> key
    static Pos    := Map()     ; key -> [x, y, size] saved by LOCK; missing = auto stack
    static KeyCol := "010203"  ; window background, knocked out to see-through
}

; startup animation (lib\Extras.ahk)
class Splash {
    static Win    := ""        ; splash window, "" when not showing
    static Dur    := 3600      ; minimum time to fill the bar, ms
    static T0     := 0
    static Cur    := 0         ; shown progress 0-100
    static Target := 0         ; real boot progress 0-100
    static Done   := false     ; boot finished: show the menu when the splash closes
    static EndAt  := 0         ; tick the fade-out ends, 0 = not fading
    static Text   := ""        ; status line
    static Logo   := 0         ; GDI+ image of the custom logo, 0 = the "A" badge
    static S      := 1         ; DPI scale
    static W      := 1
    static H      := 1
    static X      := 0
    static Y      := 0
    ; the look it is drawn in (from Visuals > Look, fixed when it opens)
    static Look   := "none"    ; none | aurora | embers | glass | holo
    static Grade  := "none"
    static Neon   := 0
    static Spot   := 0
    static P      := ""        ; palette after the look + grade: {acc, acc2, panel, header, text, dim, white}
    static Bg     := 0         ; Frosted glass: blurred picture behind the card (GDI+ bitmap)
    static Ia     := 0         ; grade for the custom logo (GDI+ image attributes)
    static Preview := false    ; opened from Visuals > Look (not the real boot)
}

; settings search (lib\Extras.ahk)
class Search {
    static Idx   := []         ; {page, ctrl, text, group, hay} for every searchable control
    static Group := ""         ; group being built, recorded with each entry
    static Hits  := []         ; matches shown in the popup
    static Popup := ""
}

; self-check report window (lib\Extras.ahk)
class Check {
    static Win := ""
}

; smooth overlay renderer (lib\Ovl.ahk drives lib\ArkSenseOverlay.exe)
class Ovl {
    static State    := "off"     ; off | ready | failed (then the classic renderer draws)
    static Hwnd     := 0         ; the helper's message window
    static Pid      := 0
    static Ver      := ""
    static Live     := Map()     ; key -> [x, y, size] the helper last reported (what LOCK saves)
    static Why      := ""        ; why the classic renderer is in use
    static LastFx   := ""
    static FxAt     := 0
    static Fails    := 0         ; sends in a row that got no answer
    static Restarts := 0
    static CheckAt  := 0
    static ThemeDirty := false   ; the last theme message didn't get through
}

; the web menu (lib\Web.ahk + lib\menu)
class Web {
    static State   := "off"      ; off | starting | ready | failed (then the native menu shows)
    static Why     := ""
    static Gui     := ""         ; its window
    static Ctl     := ""         ; WebView2 controller
    static Core    := ""         ; WebView2 core
    static Loaded  := false      ; the page has said "ready"
    static Visible := false
    static Dirty   := true       ; the model must be sent again (menu rebuilt)
    static Model   := Map()      ; page -> {groups: [...], foot: [...]}
    static Reg     := []         ; id -> widget record
    static Group   := ""         ; group being built
    static Foot    := ""         ; page whose footer buttons are being built
    static Mute    := false      ; don't record (a widget made of other widgets)
    static Last    := Map()      ; id -> state string last sent
    static SentPage := ""
    static Queue   := []         ; messages from the page, handled on their own thread
    static Capture := false      ; a key chip is listening (hotkeys paused)
    static CapAt   := 0
    static Test    := false      ; test harness (lib\menu\test.flag)
}

; slide-in alerts (lib\Alerts.ahk)
class Alerts {
    static On       := 1
    static AntiFail := 2         ; antidote gave up this many times in a row, 0 = off
    static LagMs    := 150       ; server reply slower than this for 3 s, 0 = off
    static LossPct  := 20        ; answers missing over the last 30 s, 0 = off
    static Server   := 1         ; server found / server stopped answering
    static Feedback := 1         ; layout or filter switched by its hotkey
    static Sound    := 0         ; system sound on warnings
    static Pos      := "tr"      ; tr br tl bl tc
    static Secs     := 4
    static Streak   := 0         ; runtime: antidote give-ups in a row
    static LagRun   := 0         ; runtime: slow server replies in a row
    static Lagging  := false
    static Lossy    := false
    static Silent   := 0         ; runtime: server query answers missing in a row
    static Down     := false
    static Last     := Map()     ; alert id -> tick it last showed (cooldown)
    static Classic  := []        ; toast windows when the classic renderer is in use
}

; overlay layouts (lib\Layouts.ahk)
class Lay {
    static Names   := ["PvP minimal", "PvE full", "Clean"]
    static Keys    := ["", "", ""]
    static NextKey := ""
    static Cur     := 0          ; slot loaded last, 0 = none
    static Data    := Map()      ; slot -> Map(setting -> value, "Pos" -> Map(key -> [x, y, size]))
}

; screen colour filter (lib\Filters.ahk)
class Filter {
    static Name     := "Off"
    static Strength := 100
    static Key      := ""        ; turns the filter off / back on
    static NextKey  := ""        ; steps to the next filter
    static Last     := "Vivid"   ; what the key turns back on
    static Applied  := ""        ; runtime: what is on screen now, "" = nothing
    static Ready    := 0         ; runtime: 1 magnifier started, -1 unavailable
    static PreviewTill := 0
    static Err      := ""
}

; PC tune-up (lib\Tune.ahk)
class Tune {
    static AutoPlan  := 0        ; switch power plan while ARK runs
    static GamePlan  := ""       ; that plan's GUID
    static Prio      := "AboveNormal"
    static AutoPrio  := 0        ; set ARK's priority whenever it starts
    static SavedPlan := ""       ; runtime: plan to go back to when ARK closes
    static LastPid   := 0        ; runtime: ARK process last seen
    static Plans     := []       ; runtime: [{guid, name}]
    static Undo      := Map()    ; original values before ArkSense changed them
}

class UI {
    static Menu      := ""
    static Hwnd      := 0
    static Visible   := false
    static Page      := "antidote"
    static PagesReady := false        ; false until the first full visibility sweep
    static Ctrl      := Map()         ; name -> control
    static Pages     := Map()         ; page -> [controls]
    static Tabs      := Map()
    static TabBars   := Map()         ; page -> accent bar control
    static TabIcons  := Map()         ; page -> glyph control
    static ChkState  := Map()         ; checkbox hwnd -> 0/1
    static ChkLbl    := Map()         ; checkbox hwnd -> its label (dimmed while unticked)
    static Sliders   := Map()         ; slider hit-area hwnd -> slider object
    static SliderByName := Map()      ; name -> slider object
    static SliderVal := Map()         ; name -> current value
    static Drops     := Map()         ; name -> dropdown object
    static DropVal   := Map()         ; name -> selected item
    static DropPopup := ""            ; open dropdown list window, "" when closed
    static DropWatchOn := false
    static DropLastName := ""         ; lets a second click on an open dropdown close it
    static DropLastClose := 0
    static CustomBg  := Map()         ; control hwnd -> colour hex
    static CustomFg  := Map()
    static Hover     := Map()         ; control hwnd -> [normal, hover]
    static Tips      := Map()         ; control hwnd -> hover tooltip text
    static Groups    := []            ; group panel backgrounds (sent to the bottom)
    static Round     := []            ; [control, corner diameter, sides] to round after build
    static Brushes   := Map()
    static LastHover := 0
    static HudDragging := false
    static StatHud     := ""         ; stats card window, "" when not built
    static AccentSegs  := []         ; header line, in segments so effects can flow along it
    static GlowSegs    := []         ; the dimmer row under it
    static Rings       := []         ; {ring, halo, page} glow edges around group panels
    static Borders     := []         ; every group panel's 1px border (pushed under its panel)
    static Halos       := []         ; glow halos (pushed under the borders)
    static Strips      := []         ; group title-strip segments (pushed under all controls)
    static HotChips    := Map()      ; key-box name -> the chip that shows its value
    static HotEditing  := ""         ; key box being edited right now
    static TabBgs      := Map()      ; page -> sidebar row background
    static TabX        := 0          ; layout cursor while the tabs are built
}
