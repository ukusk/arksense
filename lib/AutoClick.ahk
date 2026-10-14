; ArkSense - lib\AutoClick.ahk
; Autoclicker (Macros page): any mouse button, a set number of clicks per second,
; optional human-like timing variation, toggle or hold hotkey, optional click limit.
; Only mouse clicks are sent - nothing in the game is read.
; Part of ArkSense.ahk; run that file, not this one.
;
; Timing: the loop runs on its own thread and schedules every click on the
; high-resolution clock (QueryPerformanceCounter), so the rate stays exact over time
; however Sleep jitters - a late click doesn't shift all the following ones. Windows'
; timer is raised to 1 ms only while it runs. Variation draws each gap (and each hold)
; from a bell curve around the set value, clipped to +-2.5 spreads, so the average
; rate stays what you set while no two gaps are the same.

AcButtons() => ["Left", "Right", "Middle", "Mouse 4", "Mouse 5"]
AcButtonKey(name) => (name = "Mouse 4") ? "X1" : (name = "Mouse 5") ? "X2" : name

AcClamp() {
    Ac.Cps     := Max(1, Min(60, Integer(Ac.Cps)))
    Ac.HoldMs  := Max(1, Min(200, Integer(Ac.HoldMs)))
    Ac.VaryPct := Max(1, Min(50, Integer(Ac.VaryPct)))
    Ac.Limit   := Max(0, Min(100000, Integer(Ac.Limit)))
    ok := false
    for b in AcButtons()
        ok := ok || (b = Ac.Button)
    if !ok
        Ac.Button := "Left"
    if (Ac.Mode != "Hold")
        Ac.Mode := "Toggle"
    ; a click can't be held longer than the gap to the next one
    Ac.HoldMs := Min(Ac.HoldMs, Max(1, Floor(1000 / Ac.Cps) - 4))
}

AcToggle(*) {
    if Ac.Active
        AcStop("stopped")
    else
        AcStart()
}

AcHoldDown(*) {
    if !Ac.Active
        AcStart()
}

AcHoldUp(*) {
    if Ac.Active
        AcStop("key released")
}

AcStart() {
    if Ac.Active
        return
    AcClamp()
    if (Ac.GameOnly && !GameActive()) {
        Flash("autoclicker: click into ARK first (or turn off 'Only while ARK is focused')")
        return
    }
    Ac.Active := true
    Ac.Clicks := 0
    Ac.Why := ""
    Ac.StartAt := A_TickCount
    S.lastHud := ""
    AcRefreshStatus()
    Logg("clicker", "started: " . Ac.Button . ", " . Ac.Cps . " per second"
                  . (Ac.Vary ? ", +-" . Ac.VaryPct . "% variation" : "")
                  . (Ac.Limit ? ", stops after " . Ac.Limit : ""))
    SetTimer(AcRun, -1)
}

AcStop(why := "stopped") {
    if !Ac.Active
        return
    Ac.Active := false
    Ac.Why := why
    S.lastHud := ""
}

; the cursor is over one of ArkSense's windows (the menu, its START button ...)
AcOverOwnWindow() {
    try {
        MouseGetPos(, , &win)
        if !win
            return false
        root := DllCall("user32\GetAncestor", "Ptr", win, "UInt", 2, "Ptr")     ; GA_ROOT
        for w in [UI.Menu, Web.Gui, Check.Win, Search.Popup, UI.DropPopup] {
            if (w != "" && root = w.Hwnd)
                return true
        }
    }
    return false
}

; standard normal number (Box-Muller), clipped to +-2.5
AcGauss() {
    u1 := Random(1, 1000000) / 1000001, u2 := Random(0.0, 1.0)
    z := Sqrt(-2 * Ln(u1)) * Cos(6.283185307179586 * u2)
    return Max(-2.5, Min(2.5, z))
}

AcRun() {
    btn := AcButtonKey(Ac.Button)
    f := 0
    DllCall("QueryPerformanceFrequency", "Int64*", &f)
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    down := false
    try {
        next := 0
        DllCall("QueryPerformanceCounter", "Int64*", &next)
        while Ac.Active {
            if (Ac.GameOnly && !GameActive()) {
                AcStop("ARK lost focus")
                break
            }
            base := 1000 / Ac.Cps                              ; ms between clicks
            gap  := Ac.Vary ? base * (1 + AcGauss() * Ac.VaryPct / 250) : base
            hold := Ac.Vary ? Ac.HoldMs * (1 + AcGauss() * Ac.VaryPct / 250) : Ac.HoldMs
            hold := Max(1, Min(hold, gap - 3))
            if !AcOverOwnWindow() {               ; never click ArkSense's own menu / buttons
                Click(btn . " Down")
                down := true
                Sleep Round(hold)
                Click(btn . " Up")
                down := false
                Ac.Clicks += 1
            }
            if (Ac.Limit > 0 && Ac.Clicks >= Ac.Limit) {
                AcStop("click limit reached")
                break
            }
            ; next click on the clock: sleep most of the way, then wait out the rest
            next += gap * f / 1000
            now := 0
            DllCall("QueryPerformanceCounter", "Int64*", &now)
            if (now - next > f / 4)                            ; fell far behind (lag): resync
                next := now
            left := (next - now) * 1000 / f
            if (left > 2)
                Sleep Floor(left - 1.5)
            Loop {
                DllCall("QueryPerformanceCounter", "Int64*", &now)
                if (now >= next || !Ac.Active)
                    break
            }
        }
    } finally {
        if down
            try Click(btn . " Up")
        DllCall("winmm\timeEndPeriod", "UInt", 1)
        Ac.Active := false
        secs := Max(0.001, (A_TickCount - Ac.StartAt) / 1000)
        Ac.Rate := Round(Ac.Clicks / secs, 1)
        Logg("clicker", ((Ac.Why != "") ? Ac.Why : "stopped") . " - " . Ac.Clicks . " clicks, "
                      . Ac.Rate . " per second on average")
        S.lastHud := ""
        AcRefreshStatus()
    }
}

AcRefreshStatus() {
    if !UI.Ctrl.Has("acStatus")
        return
    c := UI.Ctrl["acStatus"]
    if Ac.Active
        c.Text := "status   CLICKING - " . Ac.Button . " " . Ac.Cps . "/s"
    else
        c.Text := "status   off" . ((Ac.Why != "") ? "  (" . Ac.Clicks . " clicks, " . Ac.Rate . "/s)" : "")
                . ((Trim(Ac.Toggle) = "") ? "   - set a hotkey below" : "")
    Paint(c, "", Ac.Active ? Theme.Ok : Theme.Dim)
}

; Macros page, column 3
AcBuildGroup(g, p) {
    gr := GroupBegin(g, p, 2, Layout.TOP, "Autoclicker")
    GText(gr, GRow(gr), "acStatus")
    y := GRow(gr)
    GLabel(gr, y, "Hotkey", "Starts / stops the autoclicker. Any key or mouse button you don't "
        . "need for something else.")
    GHot(gr, y, "acToggle", Ac.Toggle)
    y := GRow(gr), GLabel(gr, y, "Mode", "Toggle: press once to start, again to stop. Hold: clicks "
          . "only while you hold the hotkey down.", 100),
        GDrop(gr, y, "acMode", ["Toggle", "Hold"], Ac.Mode, 110)
    y := GRow(gr), GLabel(gr, y, "Button", "Which mouse button it clicks.", 100),
        GDrop(gr, y, "acButton", AcButtons(), Ac.Button, 110)
    GSlider(gr, GRow(gr), "acCps", "Clicks / second", Ac.Cps, 1, 60, "", 1,
            "How many clicks per second. Scheduled on the high-resolution clock, so the rate "
          . "holds over time.")
    GSlider(gr, GRow(gr), "acHold", "Click hold", Ac.HoldMs, 1, 100, " ms", 1,
            "How long the button stays down per click. Games can miss 0-length clicks.")
    GToggle(gr, GRow(gr), "acVary", "Vary the timing", Ac.Vary,
            "Every gap and every hold is drawn from a bell curve around the set value, so no "
          . "two clicks are timed the same while the average rate stays as set.")
    GSlider(gr, GRow(gr), "acVaryPct", "Variation", Ac.VaryPct, 1, 50, "%", 1,
            "How much the timing spreads. 10-20% is a natural spread; the average doesn't change.")
    GToggle(gr, GRow(gr), "acGameOnly", "Only while ARK is focused", Ac.GameOnly,
            "Stops by itself the moment another window comes to the front.")
    y := GRow(gr)
    GLabel(gr, y, "Stop after (clicks)", "Stops by itself after this many clicks. 0 = never.", 130)
    GField(gr, y, "acLimit", Ac.Limit, true, 70)
    GButtons(gr, GRow(gr), [["START / STOP", (*) => AcToggle(), "accent"]])
    GroupEnd(gr)
}

AcReadUI() {
    if !UI.Ctrl.Has("acToggle")
        return
    Ac.Toggle := Trim(UI.Ctrl["acToggle"].Value)
    Ac.Mode := DropValue("acMode", "Toggle")
    Ac.Button := DropValue("acButton", "Left")
    Ac.Cps := SliderValue("acCps", 10)
    Ac.HoldMs := SliderValue("acHold", 15)
    Ac.Vary := ChkVal(UI.Ctrl["acVary"])
    Ac.VaryPct := SliderValue("acVaryPct", 15)
    Ac.GameOnly := ChkVal(UI.Ctrl["acGameOnly"])
    Ac.Limit := Num("acLimit", 0, 0, 100000)
    AcClamp()
    if Ac.Active
        AcStop("settings changed")
}

; a warning when the hotkey is the very button it clicks (it would stop / start itself)
AcHotkeyWarn() {
    k := Trim(Ac.Toggle)
    b := AcButtonKey(Ac.Button)
    m := Map("Left", "LButton", "Right", "RButton", "Middle", "MButton", "X1", "XButton1", "X2", "XButton2")
    if (k != "" && m.Has(b) && InStr(k, m[b]))
        return "the hotkey is the button it clicks - pick another"
    return ""
}
