; ArkSense - lib\Macros.ahk
; Remount, mammoth clicker, FPS console presets and insta-bag.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Desmo: E double-press remount macro --------------------------------
DesmoToggle(*) {
    Desmo.Active := !Desmo.Active
    if Desmo.Active
        DesmoStart()
    else
        DesmoStop()
    DesmoRefreshStatus()
}

DesmoSendExtraE() {
    Send("{e}")
    Logg("remount", "sent extra 'e'")
}

; No on-screen indicator: remount state is reported through the status bar only,
; which the Overlay tab controls.
DesmoStart() {
    DesmoStop()
    Desmo.Active := true
}

DesmoStop() {
    Desmo.Active := false
    DesmoHoldStop()
}

; the ~e hotkey lands here; hold mode replaces the delayed second tap
DesmoOnE() {
    Desmo.LastE := A_TickCount     ; physical auto-repeat keeps this fresh
    if Desmo.HoldOn
        DesmoHoldStart()
    else
        SetTimer(DesmoSendExtraE, -Desmo.DelayMs)
}

; physical auto-repeat re-enters this while E is held, so it must be idempotent
DesmoHoldStart() {
    if Desmo.Holding
        return
    Desmo.Holding := true
    SetTimer(DesmoHoldTick, Desmo.HoldMs)
    Logg("remount", "hold spam started (" . Desmo.HoldMs . " ms)")
}

DesmoHoldTick() {
    ; Watchdog, independent of the key state. GetKeyState can report "down"
    ; forever if the hook misses a release - the one failure the check below
    ; cannot see. Windows repeats a held key at worst every 500 ms after a start
    ; delay of at most 1 s, and each repeat refreshes LastE, so a gap this long
    ; means E is not held whatever the key state says.
    stale := (A_TickCount - Desmo.LastE) > 1500
    if (!Desmo.Active || !Desmo.HoldOn || !GetKeyState("e", "P") || stale) {
        DesmoHoldStop()
        return
    }
    ; SendEvent, not Send: v2's Send defaults to SendInput, which postpones the
    ; user's own input until the send finishes - at 100/s that delays the very
    ; release this loop is waiting for. SendLevel 0 keeps these sends from
    ; re-firing ~e:: or ~e up::. Local on purpose: double-press path untouched.
    SendLevel 0
    SendEvent("{e}")
}

; Unconditional by design. The timer and this flag are separate pieces of state,
; and AHK threads can interrupt between any two statements, so the flag can fall
; out of step with the timer. The old guard returned early in exactly that case
; and left the timer armed for good - E then repeated with the key released until
; the script was reloaded. Always killing the timer makes any bad interleave
; self-correct on the next tick instead of latching.
DesmoHoldStop() {
    SetTimer(DesmoHoldTick, 0)
    if Desmo.Holding
        Logg("remount", "hold spam stopped")
    Desmo.Holding := false
}

DesmoRefreshStatus() {
    if !UI.Ctrl.Has("desmoStatus")
        return
    c := UI.Ctrl["desmoStatus"]
    if !Desmo.Active
        c.Text := "status   off"
    else if Desmo.HoldOn
        c.Text := "status   ON - hold E to spam E"
    else
        c.Text := "status   ON - watching for E"
    Paint(c, "", Desmo.Active ? Theme.Ok : Theme.Dim)
}

; ---- Mammoth: fixed-beat clicker + tap-along beat meter ----------------------
; QueryPerformanceCounter in ms. A_TickCount only moves in ~15.6 ms steps, which
; is too coarse to hold a rhythm or to measure one.
NowMs() {
    static freq := 0
    if (freq = 0)
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    c := 0
    DllCall("QueryPerformanceCounter", "Int64*", &c)
    return c * 1000 / freq
}

; INI and profile values bypass the sliders, so clamp here too
MammothClamp() {
    if (Mammoth.Button != "Left" && Mammoth.Button != "Right" && Mammoth.Button != "Middle")
        Mammoth.Button := "Left"
    Mammoth.IntervalMs := Max(100, Min(3000, Integer(Mammoth.IntervalMs)))
    Mammoth.HoldMs     := Max(5, Min(Mammoth.IntervalMs - 20, Integer(Mammoth.HoldMs)))
}

MammothToggle(*) {
    if Mammoth.Measuring
        MammothMeasureCancel()
    Mammoth.Active := !Mammoth.Active
    if Mammoth.Active {
        MammothClamp()
        if !Mammoth.HiRes {               ; 1 ms Sleep precision while armed only
            DllCall("winmm\timeBeginPeriod", "UInt", 1)
            Mammoth.HiRes := true
        }
        Mammoth.NextAt := NowMs() + (Mammoth.ClickOnArm ? 0 : Mammoth.IntervalMs)
        SetTimer(MammothTick, 10)
    } else {
        SetTimer(MammothTick, 0)
        if Mammoth.HiRes {
            DllCall("winmm\timeEndPeriod", "UInt", 1)
            Mammoth.HiRes := false
        }
    }
    S.lastHud := ""
    MammothRefreshStatus()
    Hud(Mammoth.Active ? "mammoth clicker armed" : "mammoth clicker off", Theme.Dim)
    Logg("mammoth", Mammoth.Active ? "armed (" . Mammoth.IntervalMs . " ms)" : "disarmed")
}

; Clicks sit on a fixed grid: NextAt advances by exactly one interval per click,
; so timer jitter never accumulates into drift.
MammothTick() {
    if !Mammoth.Active
        return
    wait := Mammoth.NextAt - NowMs()
    if (wait > 25)
        return
    Critical "On"                          ; no other thread may shove this click late
    if (wait > 1)
        Sleep Round(wait)
    if !Mammoth.Active
        return
    now := NowMs()
    if (now - Mammoth.NextAt > Mammoth.IntervalMs)   ; stalled (sleep/lag): resync, don't burst
        Mammoth.NextAt := now
    Mammoth.NextAt += Mammoth.IntervalMs
    if (Mammoth.GameOnly && !GameActive())
        return
    SendLevel 0                            ; never trigger this script's own mouse hotkeys
    Click(Mammoth.Button . " Down")
    Sleep Mammoth.HoldMs
    Click(Mammoth.Button . " Up")
}

MammothRefreshStatus() {
    if !UI.Ctrl.Has("mamStatus")
        return
    c := UI.Ctrl["mamStatus"]
    if Mammoth.Active
        c.Text := "status   ARMED - " . Mammoth.Button . " every " . Mammoth.IntervalMs . " ms"
    else if Mammoth.Measuring
        c.Text := "status   measuring..."
    else
        c.Text := "status   off"
    Paint(c, "", (Mammoth.Active || Mammoth.Measuring) ? Theme.Ok : Theme.Dim)
}

MammothRefreshResult() {
    if UI.Ctrl.Has("mamResult")
        UI.Ctrl["mamResult"].Text := Mammoth.ResultText
}

MammothIsMeasuring(*) => Mammoth.Measuring

; ~LButton only exists while measuring, as its own #HotIf variant, so it never
; replaces a global LButton hotkey (e.g. an Insta-Bag trigger) and leaves no
; mouse hook running the rest of the time.
MammothTapHotkey(on) {
    ok := true
    HotIf(MammothIsMeasuring)
    try Hotkey("~LButton", MammothTap, on ? "On" : "Off")
    catch as e {
        ok := false
        Logg("mammoth", "tap hotkey failed: " . e.Message)
    }
    HotIf()
    return ok
}

MammothTap(*) {
    if Mammoth.Measuring
        Mammoth.Taps.Push(NowMs())
}

MammothMeasureStart() {
    if Mammoth.Active
        MammothToggle()
    Mammoth.Taps      := []
    Mammoth.MeasureAt := NowMs()
    Mammoth.Measuring := true
    if !MammothTapHotkey(true) {
        Mammoth.Measuring := false
        Flash("could not start the beat meter (see Logs)")
        return
    }
    SetTimer(MammothMeasureWatch, 200)
    MammothRefreshStatus()
    HideMenu()
    Hud("measuring - click on every drum beat", Theme.Accent)
    Logg("mammoth", "beat meter started")
}

MammothMeasureWatch() {
    if !Mammoth.Measuring {
        SetTimer(MammothMeasureWatch, 0)
        return
    }
    now := NowMs()
    n   := Mammoth.Taps.Length
    done := (n >= 17)
         || (n >= 2 && now - Mammoth.Taps[n] > 3000)
         || (n < 2 && now - Mammoth.MeasureAt > 20000)
    if (!done || Anim.Busy)
        return
    MammothMeasureStop()
    Mammoth.ResultText := MammothAnalyse(Mammoth.Taps)
    MammothRefreshResult()
    MammothRefreshStatus()
    ShowMenu("macros")
    Hud("beat meter done", Theme.Dim)
    Logg("mammoth", "beat meter: " . StrReplace(Mammoth.ResultText, "`n", "  "))
}

MammothMeasureStop() {
    Mammoth.Measuring := false
    SetTimer(MammothMeasureWatch, 0)
    MammothTapHotkey(false)
}

MammothMeasureCancel() {
    MammothMeasureStop()
    Mammoth.ResultText := "measurement cancelled"
    MammothRefreshResult()
    MammothRefreshStatus()
}

; median gap between taps; gaps outside +-35% of it (a stray or missed click)
; are left out of the spread and the count
MammothAnalyse(taps) {
    Mammoth.Result := 0
    if (taps.Length < 3)
        return "not enough clicks - try again`n(need at least 3)"
    gaps := []
    Loop taps.Length - 1
        gaps.Push(taps[A_Index + 1] - taps[A_Index])
    ; insertion sort - a handful of values
    Loop gaps.Length - 1 {
        i := A_Index + 1
        v := gaps[i]
        j := i - 1
        while (j >= 1 && gaps[j] > v) {
            gaps[j + 1] := gaps[j]
            j -= 1
        }
        gaps[j + 1] := v
    }
    m := gaps.Length
    med := Mod(m, 2) ? gaps[(m + 1) // 2] : (gaps[m // 2] + gaps[m // 2 + 1]) / 2
    lo := med * 0.65, hi := med * 1.35
    kept := 0, gMin := 0, gMax := 0
    for gap in gaps {
        if (gap < lo || gap > hi)
            continue
        kept += 1
        gMin := (kept = 1) ? gap : Min(gMin, gap)
        gMax := (kept = 1) ? gap : Max(gMax, gap)
    }
    if (kept < 2)
        return "clicks too uneven to read`ntry again, steadier"
    Mammoth.Result := Round(med)
    return "median " . Round(med) . " ms  (" . kept . " gaps)`nspread " . Round(gMin) . " - " . Round(gMax) . " ms"
}

MammothUseResult() {
    if (Mammoth.Result <= 0) {
        Flash("measure a beat first")
        return
    }
    if UI.SliderByName.Has("mamInterval")
        SliderSet(UI.SliderByName["mamInterval"], Mammoth.Result)
    Flash("interval set to " . Mammoth.Result . " ms - press APPLY to keep it")
}

; ---- FPS commands: paste a preset console line, ARK chains "|"-joined cmds
FpsCommands(preset) {
    if (preset = "debug")
        return "debugstructures"
    if (preset = "draw6x")
        return "DrawDebugBoxForVolumes 999 6 0 0 100"
    if (preset = "genon")
        return "r.Scenecolorformat 0"
    if (preset = "genoff")
        return "r.Scenecolorformat 2"
    cmds := "stat fps | r.mapmaplodbias 10000 | r.ParticleLODBias 10000 | "
        . "r.LandscapeLODBias 10000 | r.SkeletalMeshLODBias 10000 | r.SceneColorFormat 0 | "
        . "r.shadowquality 0 | r.DistanceFieldShadowRaytraceDistance=0 | r.DistanceFieldAO=0 | "
        . "stat unit | r.LightFunctionQuality=0 | r.Shadow.CSM.MaxCascades=0 | "
        . "r.Shadow.CSM.MaxFarCascades=0 | r.Shadow.AllowForegroundShadows=0 | "
        . "r.eyeadaptationquality 0 | r.Shadow.MaxResolution=1 | r.Shadow.RadiusThreshold=0 | "
        . "r.Shadow.DistanceScale=0.3 | r.Shadow.CSM.TransitionScale=0 | r.DistanceFieldShadowing=0 | "
        . "r.SceneColorFringeQuality 0 | T.maxfps 144 | stat unitgraph"
    if (preset != "hard")
        return cmds
    cmds := StrReplace(cmds, "stat unit |", "stat unit | forceskellod LOD=10000 |")
    cmds := StrReplace(cmds, "r.eyeadaptationquality", "r.streaming.mipbias 9 | r.eyeadaptationquality")
    return StrReplace(cmds, "r.SceneColorFringeQuality", "r.Streaming.MipBias 10000 | r.SceneColorFringeQuality")
}

; Hotkey-control strings ("Tab", "^Tab") aren't Send syntax - multi-char keys need bracing
SendKeyByName(name) {
    mods := "", key := name
    while (SubStr(key, 1, 1) ~= "[\^!+#]") {
        mods .= SubStr(key, 1, 1)
        key := SubStr(key, 2)
    }
    if (StrLen(key) = 1)
        Send(mods . key)
    else
        Send(mods . "{" . key . "}")
}

; flips between r.Scenecolorformat 0 (on) and 2 (off), relabelling the button
ToggleGenRange() {
    want := !Fps.GenRangeOn
    if !RunFpsPreset(want ? "genon" : "genoff")
        return
    Fps.GenRangeOn := want
    if UI.Ctrl.Has("fpsGenBtn")
        UI.Ctrl["fpsGenBtn"].Text := BtnCase("TOGGLE WHITE GEN RANGE (" . (want ? "ON" : "OFF") . ")")
}

RunFpsPreset(preset) {
    ; a menu click means the MENU is focused, so bring ARK forward first
    if !ActivateGame() {
        Flash("ARK isn't running")
        return false
    }
    if (Trim(Fps.ConsoleKey) = "") {
        Flash("set a console key first")
        return false
    }
    SendKeyByName(Fps.ConsoleKey)
    Sleep Fps.OpenDelayMs
    SendText(FpsCommands(preset))
    Sleep 50
    Send("{Enter}")
    Sleep Fps.CloseDelayMs
    SendKeyByName(Fps.ConsoleKey)
    Flash(preset . " commands sent")
    Logg("fps", preset . " preset pasted")
    return true
}

; ---- Insta-take bag: repeating auto-click at a picked point ----------------
BagToggle(*) {
    Bag.Active := !Bag.Active
    S.lastHud := ""
    BagRefreshStatus()
    Hud(Bag.Active ? "insta-bag armed" : "insta-bag off", Theme.Dim)
    Logg("bag", Bag.Active ? "armed" : "disarmed")
}

; single click on the trigger key, only while armed
BagFire(*) {
    if (!Bag.Active || (Bag.GameOnly && !GameActive()))
        return
    if Bag.UseCurrent
        Click()
    else
        Click(Bag.X, Bag.Y)
    Logg("bag", "clicked")
}

BagRefreshStatus() {
    if !UI.Ctrl.Has("bagStatus")
        return
    c := UI.Ctrl["bagStatus"]
    c.Text := "status   " . (Bag.Active ? "ARMED - trigger = one click" : "off")
    Paint(c, "", Bag.Active ? Theme.Ok : Theme.Dim)
}

RefreshBagCoordInfo() {
    if !UI.Ctrl.Has("bagCoordInfo")
        return
    c := UI.Ctrl["bagCoordInfo"]
    if (Bag.X = 0 && Bag.Y = 0) {
        c.Text := "not set - click PICK CLICK POINT"
        Paint(c, "", Theme.Bad)
    } else {
        c.Text := Format("click point   {}, {}", Bag.X, Bag.Y)
        Paint(c, "", Theme.Ok)
    }
}

PickBagPoint() {
    HideMenu()
    Sleep 150
    if CaptureClick("Click where the bag-take button is", &x, &y) {
        Bag.X := x, Bag.Y := y
        SaveIni()
    }
    ShowMenu("macros")
    RefreshBagCoordInfo()
}

; shows a full-screen prompt, waits for one left click, returns its coords
CaptureClick(prompt, &cx, &cy) {
    shade := Gui("+AlwaysOnTop -Caption +ToolWindow")
    StreamHide(shade.Hwnd)
    shade.BackColor := "000000"
    shade.SetFont("s12 Bold", Theme.FontName)
    Paint(shade.Add("Text", "x24 y24 w900 h30", prompt . "    (Esc cancels)"),
          "000000", Theme.Accent)
    shade.Show(Format("x0 y0 w{} h{} NoActivate", A_ScreenWidth, A_ScreenHeight))
    WinSetTransparent 90, "ahk_id " . shade.Hwnd

    cx := 0, cy := 0, done := false
    while !done {
        if GetKeyState("Escape", "P") {
            shade.Destroy()
            return false
        }
        if GetKeyState("LButton", "P") {
            MouseGetPos &cx, &cy
            done := true
        }
        Sleep 15
    }
    while GetKeyState("LButton", "P")
        Sleep 10
    shade.Destroy()
    return true
}

