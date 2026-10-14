; ArkSense - lib\Settings.ahk
; INI persistence, load-time clamping and profiles.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Profiles ---------------------------------------------------------------
ProfileNames() {
    out := []
    for name, _ in Store.Profiles
        out.Push(name)
    return out
}


CfgToMap() {
    return Map(
        "AntidoteKey",   Cfg.AntidoteKey,   "IntervalSec",   Cfg.IntervalSec,
        "SkipIfActive",  Cfg.SkipIfActive,  "KeyHoldMs",     Cfg.KeyHoldMs,
        "AirborneMs",    Cfg.AirborneMs,    "VerifyDelayMs", Cfg.VerifyDelayMs,
        "RetryDelayMs",  Cfg.RetryDelayMs,  "MaxRetries",    Cfg.MaxRetries,
        "BuffColor",     Cfg.BuffColor,     "Tolerance",     Cfg.Tolerance,
        "Relentless",    Cfg.Relentless,    "RecheckMs",     Cfg.RecheckMs)
}

MapToCfg(m) {
    Cfg.AntidoteKey   := m.Get("AntidoteKey", "6")
    Cfg.IntervalSec   := Integer(m.Get("IntervalSec",   600))
    Cfg.SkipIfActive  := Integer(m.Get("SkipIfActive",    1))
    Cfg.KeyHoldMs     := Integer(m.Get("KeyHoldMs",      55))
    Cfg.AirborneMs    := Integer(m.Get("AirborneMs",   1400))
    Cfg.VerifyDelayMs := Integer(m.Get("VerifyDelayMs", 450))
    Cfg.RetryDelayMs  := Integer(m.Get("RetryDelayMs",  300))
    Cfg.MaxRetries    := Integer(m.Get("MaxRetries",     15))
    Cfg.BuffColor     := m.Get("BuffColor", "8FBF3A")
    Cfg.Tolerance     := Integer(m.Get("Tolerance", 30))
    Cfg.Relentless    := Integer(m.Get("Relentless",   1))
    Cfg.RecheckMs     := Integer(m.Get("RecheckMs",  500))
}

ProfStatus(msg, col := "") {
    if !UI.Ctrl.Has("profStatus")
        return
    c := UI.Ctrl["profStatus"]
    c.Text := msg
    Paint(c, "", (col = "") ? Theme.Dim : col)
}

; the profile picker is a dropdown: refresh its items and show `select`
RefreshProfList(select) {
    if !UI.Drops.Has("profList")
        return
    d := UI.Drops["profList"]
    d.items := ProfileNames()
    UI.DropVal["profList"] := select
    d.body.Text := "  " . select
}

NewProfile() {
    ReadUI()
    name := Trim(UI.Ctrl["newName"].Value)
    if (name = "") {
        ProfStatus("enter a name first", Theme.Bad)
        return
    }
    if Store.Profiles.Has(name) {
        ProfStatus("that name already exists", Theme.Bad)
        return
    }
    Store.Profiles[name] := CfgToMap()
    Store.Active := name
    UI.Ctrl["newName"].Value := ""
    RefreshProfList(name)
    SaveIni()
    ProfStatus("created and switched to '" . name . "'", Theme.Ok)
}

LoadProfile() {
    name := DropValue("profList", "")
    if (name = "" || !Store.Profiles.Has(name)) {
        ProfStatus("select a profile first", Theme.Bad)
        return
    }
    MapToCfg(Store.Profiles[name])
    ClampLoaded()
    Store.Active := name
    SaveIni()
    if S.enabled
        Schedule(A_TickCount)
    Rebuild("settings")
    ProfStatus("loaded '" . name . "'", Theme.Ok)
}

SaveIntoSelected() {
    ReadUI()
    name := DropValue("profList", "")
    if (name = "" || !Store.Profiles.Has(name)) {
        ProfStatus("select a profile first", Theme.Bad)
        return
    }
    Store.Profiles[name] := CfgToMap()
    Store.Active := name
    SaveIni()
    ProfStatus("saved into '" . name . "'", Theme.Ok)
}

DeleteProfile() {
    name := DropValue("profList", "")
    if (name = "" || !Store.Profiles.Has(name)) {
        ProfStatus("select a profile first", Theme.Bad)
        return
    }
    if (Store.Profiles.Count <= 1) {
        ProfStatus("cannot delete the last profile", Theme.Bad)
        return
    }
    Store.Profiles.Delete(name)
    try IniDelete(Store.Ini, "Profile " . name)
    if (Store.Active = name)
        Store.Active := ProfileNames()[1]
    RefreshProfList(Store.Active)
    SaveIni()
    ProfStatus("deleted '" . name . "'", Theme.Ok)
}

; ---- Persistence -----------------------------------------------------------
; section -> [class, string props, integer props]. The property name IS the INI
; key, so a setting can never be loaded without also being saved.
Words(s) => (Trim(s) = "") ? [] : StrSplit(Trim(s), " ")

; INI files and profiles bypass the UI, so a hand-edited value like IntervalSec=0
; would reach the timers unchecked. Same ranges the UI enforces.
ClampLoaded() {
    try Anim.HoverSpeed := Max(4, Min(64, Integer(Anim.HoverSpeed)))
    try Anim.TabSpeed := Max(4, Min(64, Integer(Anim.TabSpeed)))
    ; first run of this build: carry the old pulse / rainbow switches over
    ok := false
    for m in FxModes() {
        if (m = Anim.Effect)
            ok := true
    }
    if !ok
        Anim.Effect := Anim.RainbowOn ? "Rainbow" : Anim.PulseOn ? "Pulse" : "Off"
    try Anim.PulseDepth := Max(10, Min(120, Integer(Anim.PulseDepth)))
    try Anim.RainbowSpeed := Max(1, Min(15, Integer(Anim.RainbowSpeed)))
    try Desmo.DelayMs := Max(1, Min(2000, Integer(Desmo.DelayMs)))
    try Desmo.HoldMs := Max(1, Min(1000, Integer(Desmo.HoldMs)))
    try Fps.OpenDelayMs := Max(0, Min(5000, Integer(Fps.OpenDelayMs)))
    try Fps.CloseDelayMs := Max(0, Min(5000, Integer(Fps.CloseDelayMs)))
    try Cfg.IntervalSec := Max(1, Min(86400, Integer(Cfg.IntervalSec)))
    try Cfg.KeyHoldMs := Max(10, Min(500, Integer(Cfg.KeyHoldMs)))
    try Cfg.AirborneMs := Max(0, Min(10000, Integer(Cfg.AirborneMs)))
    try Cfg.Tolerance := Max(0, Min(255, Integer(Cfg.Tolerance)))
    try Cfg.VerifyDelayMs := Max(50, Min(5000, Integer(Cfg.VerifyDelayMs)))
    try Cfg.RetryDelayMs := Max(50, Min(5000, Integer(Cfg.RetryDelayMs)))
    try Cfg.MaxRetries := Max(1, Min(200, Integer(Cfg.MaxRetries)))
    try Cfg.RecheckMs := Max(100, Min(10000, Integer(Cfg.RecheckMs)))
    try Theme.Opacity := Max(120, Min(255, Integer(Theme.Opacity)))
    try Theme.PillH := Max(16, Min(60, Integer(Theme.PillH)))
    try Theme.PillGap := Max(0, Min(30, Integer(Theme.PillGap)))
    try Theme.HudFontSize := Max(6, Min(24, Integer(Theme.HudFontSize)))
    try Theme.HudBgOpacity := Max(0, Min(255, Integer(Theme.HudBgOpacity)))
    try Stats.IntervalSec := Max(1, Min(60, Integer(Stats.IntervalSec)))
    try Stats.HudFontSize := Max(6, Min(48, Integer(Stats.HudFontSize)))
    try Stats.HudX := Max(-5000, Min(20000, Integer(Stats.HudX)))
    try Stats.HudY := Max(-5000, Min(20000, Integer(Stats.HudY)))
    try Stats.QueryPort := Max(0, Min(65535, Integer(Stats.QueryPort)))
    try Audio.LogoW := Max(8, Min(200, Integer(Audio.LogoW)))
    try Audio.LogoH := Max(8, Min(200, Integer(Audio.LogoH)))
    try Audio.LogoX := Max(0, Min(560, Integer(Audio.LogoX)))
    try MammothClamp()
    try Alerts.AntiFail := Max(0, Min(50, Integer(Alerts.AntiFail)))
    try Alerts.LagMs := Max(0, Min(5000, Integer(Alerts.LagMs)))
    try Alerts.LossPct := Max(0, Min(100, Integer(Alerts.LossPct)))
    try Alerts.Secs := Max(2, Min(10, Integer(Alerts.Secs)))
    if (AlertPosName(Alerts.Pos) = "Top right")
        Alerts.Pos := "tr"                              ; also fixes an unknown code
    try Filter.Strength := Max(0, Min(100, Integer(Filter.Strength)))
    ok := false
    for n in FilterNames() {
        if (n = Filter.Name)
            ok := true
    }
    if !ok
        Filter.Name := "Off"
    if (Theme.Renderer != "Smooth")
        Theme.Renderer := "Classic"
    Theme.Look  := ListPick(LookNames(), Theme.Look)
    Theme.Grade := ListPick(GradeNames(), Theme.Grade)
    Theme.NeonEdges := Theme.NeonEdges ? 1 : 0
    Theme.Spotlight := Theme.Spotlight ? 1 : 0
    Theme.LookSplash := Theme.LookSplash ? 1 : 0
    Theme.UserName := SubStr(RegExReplace(Trim(Theme.UserName), "[\r\n\t]"), 1, 20)
    if (Theme.UserName = "")
        Theme.UserName := "pseidonx"
    try Np.Alpha := Max(0, Min(255, Integer(Np.Alpha)))
    try Np.Scale := Max(60, Min(250, Integer(Np.Scale)))
    try Np.X := Max(-1, Min(20000, Integer(Np.X)))
    try Np.Y := Max(-1, Min(20000, Integer(Np.Y)))
    if (Np.Source != "Any app")
        Np.Source := "Browsers"
    if !RegExMatch(Np.Accent, "^[0-9A-Fa-f]{6}$")
        Np.Accent := ""
    if !RegExMatch(Np.OutlineColor, "^[0-9A-Fa-f]{6}$")
        Np.OutlineColor := ""
    try OcClamp()
    try AcClamp()
    try CtClamp()
    try BarClamp()
    ; once: settings from before step 11 move to the Crimson look the user picked.
    ; (Saved colours override class defaults, so the switch has to happen here.)
    if (Integer(Theme.StyleVer) < 12) {
        c := ThemePreset("Crimson")
        Theme.Panel := c[1], Theme.Header := c[2], Theme.Panel2 := c[3], Theme.Accent := c[4]
        Theme.Accent2 := c[5], Theme.Text := c[6], Theme.Dim := c[7], Theme.Line := c[8]
        Theme.Preset := "Crimson"
        if (Theme.HudBorderColor = "FF2836" || Theme.HudBorderColor = "FF2E63")
            Theme.HudBorderColor := c[4]
        if (Anim.Effect = "Rainbow")          ; it would paint over the gradient header line
            Anim.Effect := "Off"
        Theme.StyleVer := 12
        SaveIni()
    }
    ; once (step 14): the overlay goes back to the step 9 look by default - the classic
    ; renderer with its red outline. "Modern look" on the Overlay tab brings back step 13's.
    if (Theme.StreamerScope != "Overlays only" && Theme.StreamerScope != "Menu only")
        Theme.StreamerScope := "Menu + overlays"
    try IniDelete(Store.Ini, "Turn")         ; the 180 turn was removed in step 19
    if (Integer(Theme.StyleVer) < 14) {
        Theme.Renderer := "Classic"
        if (Theme.HudBorderColor = "EE2F5F")
            Theme.HudBorderColor := "FF2836"
        Theme.StyleVer := 14
        SaveIni()
    }
}

IniMap() => Map(
    "Theme",   [Theme,  "FontName Preset Panel Header Panel2 Accent Accent2 Text Dim Line HudTextColor "
                      . "HudBorderColor WallPath Renderer MenuEngine UserName StreamerScope Look Grade",
                        "StyleVer Opacity HudOn HudX HudY PillH PillGap PillVertical HudFontSize HudShowState HudShowMsg "
                      . "HudShowCounts HudShowDesmo HudShowBag HudShowMammoth HudShowOc "
                      . "HudShowStreamer HudBorderOn "
                      . "HudBgOn HudBgOpacity StreamerMode OverlayGameOnly WallOn Splash SelfCheck "
                      . "ShotStamp NeonEdges Spotlight LookSplash"],
    "Hotkeys", [Keys,   "Menu Toggle Fire Pick Kill Shot", ""],
    "Desmo",   [Desmo,  "Toggle", "DelayMs HoldOn HoldMs"],
    "Mammoth", [Mammoth, "Toggle Button", "IntervalMs HoldMs GameOnly ClickOnArm"],
    "Fps",     [Fps,    "ConsoleKey", "OpenDelayMs CloseDelayMs"],
    "Bag",     [Bag,    "Toggle TriggerKey", "X Y UseCurrent GameOnly"],
    "Audio",   [Audio,  "MusicPath ClickPath LogoPath", "MusicOn ClickOn LogoW LogoH LogoX"],
    "Stats",   [Stats,  "PingHost BarLogo BarLogoColor", "CardOn ShowClock ShowCpu ShowRam ShowGpu ShowPing ShowFps ShowPlayers PingAuto QueryPort IntervalSec "
                              . "Bar BarPing BarFps BarCpu BarGpu BarRam BarTag "
                              . "HudFontSize HudX HudY"],
    "Anim",    [Anim,   "Effect", "HoverOn TabOn PulseOn HoverSpeed TabSpeed PulseDepth "
                          . "RainbowOn RainbowSpeed GlowOn TitleOn FadeIn"],
    "Alerts",  [Alerts, "Pos", "On AntiFail LagMs LossPct Server Feedback Sound Secs"],
    "Filter",  [Filter, "Name Key NextKey Last", "Strength"],
    "NowPlaying", [Np,  "Source Accent OutlineColor", "On Cover Progress HidePaused Alpha Scale X Y Outline GameOnly"],
    "OcMacro", [Oc,     "Toggle Mode Keys", "GapMs HoldMs Shift GameOnly StopSec"],
    "AutoClick", [Ac,   "Toggle Mode Button", "Cps HoldMs Vary VaryPct GameOnly Limit"],
    "Clantag", [Ct,     "Text Style Where Font TextColor Accent BgColor OutlineColor Key",
                        "On Speed Bold Scale Alpha Outline Record X Y"])

LoadIni() {
    if !FileExist(Store.Ini) {
        Store.Profiles["Default"] := CfgToMap()
        Store.Active := "Default"
        SaveIni()
        return
    }

    Store.Active  := IniRead(Store.Ini, "Meta", "Active",   "Default")
    Log.TextColor := IniRead(Store.Ini, "Meta", "LogColor", Log.TextColor)
    Store.GameExe := IniRead(Store.Ini, "Meta", "GameExe",  "")
    RebuildGameTargets()

    defaults := CfgToMap()
    for name in StrSplit(IniRead(Store.Ini, "Meta", "Profiles", "Default"), "|") {
        if (name = "")
            continue
        m := Map()
        for k, dv in defaults
            m[k] := IniRead(Store.Ini, "Profile " . name, k, dv)
        Store.Profiles[name] := m
    }
    if (Store.Profiles.Count = 0)
        Store.Profiles["Default"] := defaults
    if !Store.Profiles.Has(Store.Active)
        Store.Active := ProfileNames()[1]
    MapToCfg(Store.Profiles[Store.Active])

    for sec, d in IniMap() {
        for k in Words(d[2])
            d[1].%k% := IniRead(Store.Ini, sec, k, d[1].%k%)
        for k in Words(d[3])
            d[1].%k% := Integer(IniRead(Store.Ini, sec, k, d[1].%k%))
    }

    ; [Pills] key=x,y,size - spots and sizes saved by the overlay's LOCK
    raw := ""
    try raw := IniRead(Store.Ini, "Pills")
    for line in StrSplit(raw, "`n", "`r") {
        if !InStr(line, "=")
            continue
        parts := StrSplit(line, "=", , 2)
        nums  := StrSplit(parts[2], ",")
        if (nums.Length = 3) {
            try Pill.Pos[Trim(parts[1])] := [Integer(nums[1]), Integer(nums[2]),
                                             Max(6, Min(48, Integer(nums[3])))]
        }
    }

    LayLoadIni()
    TuneLoadIni()

    raw := ""
    try raw := IniRead(Store.Ini, "Regions")
    for line in StrSplit(raw, "`n", "`r") {
        if !InStr(line, "=")
            continue
        parts := StrSplit(line, "=", , 2)
        nums  := StrSplit(parts[2], ",")
        if (nums.Length = 4)
            Store.Regions[Trim(parts[1])] :=
                [Integer(nums[1]), Integer(nums[2]), Integer(nums[3]), Integer(nums[4])]
    }
}

SaveIni() {
    Store.Profiles[Store.Active] := CfgToMap()

    IniWrite(Store.Active,  Store.Ini, "Meta", "Active")
    IniWrite(Log.TextColor, Store.Ini, "Meta", "LogColor")
    IniWrite(Store.GameExe, Store.Ini, "Meta", "GameExe")

    names := ""
    for name, _ in Store.Profiles
        names .= (names = "" ? "" : "|") . name
    IniWrite(names, Store.Ini, "Meta", "Profiles")

    for name, m in Store.Profiles
        for k, v in m
            IniWrite(v, Store.Ini, "Profile " . name, k)

    for sec, d in IniMap()
        for props in [d[2], d[3]]
            for k in Words(props)
                IniWrite(d[1].%k%, Store.Ini, sec, k)

    try IniDelete(Store.Ini, "Pills")
    for k, v in Pill.Pos
        IniWrite(v[1] . "," . v[2] . "," . v[3], Store.Ini, "Pills", k)

    LaySaveIni()
    TuneSaveIni()

    try IniDelete(Store.Ini, "Regions")
    for res, r in Store.Regions
        IniWrite(r[1] . "," . r[2] . "," . r[3] . "," . r[4], Store.Ini, "Regions", res)
}
