#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Relaunch elevated via RunAs. The UAC prompt is inherent and can't be suppressed.
if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run('*RunAs "' . A_ScriptFullPath . '" /restart')
        else
            Run('*RunAs "' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '"')
    }
    ExitApp
}

SetWorkingDir A_ScriptDir
CoordMode "Pixel",   "Screen"
CoordMode "Mouse",   "Screen"
CoordMode "ToolTip", "Screen"
DetectHiddenWindows true   ; menu/HUD are built hidden before first shown
; SendLevel 0: a hotkey fires on input whose SendLevel EXCEEDS its InputLevel (0),
; so at 1 remount's own "e" re-fired ~e:: endlessly (and tripped the
; hotkeys-per-interval dialog). 0 = this script never triggers its own hotkeys.
SendLevel 0

; MUST stay above Boot: top-level code runs in file order, so registering these
; later would miss the first paint. (Function defs hoist; these calls don't.)
OnMessage(0x0132, CtlColor)   ; WM_CTLCOLORMSGBOX
OnMessage(0x0133, CtlColor)   ; WM_CTLCOLOREDIT
OnMessage(0x0134, CtlColor)   ; WM_CTLCOLORLISTBOX (was missing: list boxes stayed white)
OnMessage(0x0135, CtlColor)   ; WM_CTLCOLORBTN
OnMessage(0x0138, CtlColor)   ; WM_CTLCOLORSTATIC
OnMessage(0x201,  GuiDrag)    ; menu window drag
OnMessage(0x201,  HudDrag)    ; overlay reposition drag
OnMessage(0x201,  WidgetMouseDown) ; widget kit: dropdown dismiss + slider drag
OnMessage(0x20A,  SliderWheel)      ; widget kit: mouse wheel nudges a slider
OnMessage(0x4A,   OvlReceive)       ; WM_COPYDATA from the smooth overlay renderer

; An uncaught error normally kills the thread behind a modal dialog, which looks
; like the whole app crashing. Record it instead - to the Logs tab and to
; ArkSense-errors.log next to the script - so one bad tick can't take the menu
; down and the exact file/line is recoverable afterwards.
OnError(GlobalError)

; Everything else lives in lib\ beside this file. #Include is resolved when the
; script loads, so these must exist or the script will not start. Function and
; class definitions are visible everywhere regardless of the file they are in.
#Include %A_ScriptDir%\lib\State.ahk
#Include %A_ScriptDir%\lib\Log.ahk
#Include %A_ScriptDir%\lib\Antidote.ahk
#Include %A_ScriptDir%\lib\Macros.ahk
#Include %A_ScriptDir%\lib\Stats.ahk
#Include %A_ScriptDir%\lib\Overlay.ahk
#Include %A_ScriptDir%\lib\Audio.ahk
#Include %A_ScriptDir%\lib\Paint.ahk
#Include %A_ScriptDir%\lib\Widgets.ahk
#Include %A_ScriptDir%\lib\Pages.ahk
#Include %A_ScriptDir%\lib\Menu.ahk
#Include %A_ScriptDir%\lib\Settings.ahk
#Include %A_ScriptDir%\lib\Hotkeys.ahk
#Include %A_ScriptDir%\lib\Extras.ahk
#Include %A_ScriptDir%\lib\Ovl.ahk
#Include %A_ScriptDir%\lib\Alerts.ahk
#Include %A_ScriptDir%\lib\Layouts.ahk
#Include %A_ScriptDir%\lib\Filters.ahk
#Include %A_ScriptDir%\lib\Tune.ahk
#Include %A_ScriptDir%\lib\Web.ahk
#Include %A_ScriptDir%\lib\Draw.ahk
#Include %A_ScriptDir%\lib\Look.ahk
#Include %A_ScriptDir%\lib\NowPlaying.ahk
#Include %A_ScriptDir%\lib\Clantag.ahk
#Include %A_ScriptDir%\lib\Bar.ahk
#Include %A_ScriptDir%\lib\Oc.ahk
#Include %A_ScriptDir%\lib\AutoClick.ahk
#Include %A_ScriptDir%\lib\vendor\WebView2\WebView2.ahk


; ---- Boot --------------------------------------------------------------
S.sessionStart := A_TickCount
; carry settings over from the old filename the first time this build runs
if (!FileExist(Store.Ini) && FileExist(Store.IniOld))
    try FileCopy(Store.IniOld, Store.Ini)

LoadIni()
ClampLoaded()
SplashShow()                          ; startup animation (Visuals > Look)
SplashStep(30, "building the menu")
BuildMenu()
WebStart()                            ; web menu (loads in the background); native if it can't
SplashStep(40, "starting the overlay renderer")
OvlStart()                            ; smooth renderer; the classic one if it can't start
SplashStep(55, "starting overlays")
BuildHud()
BuildStatHud()
SplashStep(75, "binding hotkeys")
ApplyHotkeys()
BuildTray()
SyncMusic()
TuneBoot()                            ; a power plan left switched by a crash goes back
OnExit(AppExit)                       ; music, screen filter, power plan, renderer

SetTimer Tick,       100
SetTimer HoverTick,   60
SetTimer StatusTick, 250
SetTimer HudTick,    200
SetTimer AnimTick,    33
SetTimer StatsTick, Stats.IntervalSec * 1000
NpBoot()                              ; Now playing overlay (every second)
CtBoot()                              ; clantag (40 ms timer while it is on)

SplashStep(100, "ready")
WebTestStart()                        ; test harness only (lib\menu\test.flag)
BootDone()                            ; shows the menu (after the splash, if any)

; ---- In-game hooks (only while ARK is focused) ------------------------------
#HotIf GameActive()
~$Space::  S.airborneTill := A_TickCount + Cfg.AirborneMs
~$i::      S.menuOpen := !S.menuOpen
~$Tab::    S.menuOpen := !S.menuOpen
~$Escape:: S.menuOpen := false
#HotIf

; own #HotIf, deliberately not gated on GameActive() - works in any window
#HotIf Desmo.Active
~e::    DesmoOnE()
~e up:: DesmoHoldStop()     ; stop on the release itself, not just on polling
#HotIf

^F12:: ExitApp()

; settings search: Ctrl+F jumps into the search box; Enter opens the first match
#HotIf UI.Visible && WinActive("ahk_id " . UI.Hwnd)
^f:: SearchFocus()
#HotIf SearchHasFocus()
Enter::  SearchEnter()
Escape:: SearchClear()
#HotIf
