; ArkSense - lib\Pages.ahk
; One builder per menu page, plus the APPLY handler that reads that page back.
; Part of ArkSense.ahk; run that file, not this one.

; ---- ANTIDOTE ------------------------------------------------------------------
BuildAntidote(g) {
    p := "antidote"

    ; column 1
    gr := GroupBegin(g, p, 0, Layout.TOP, "General")
    y := GRow(gr)
    GLabel(gr, y, "Hotbar key")
    GField(gr, y, "antidoteKey", Cfg.AntidoteKey, false, 60)
    y := GRow(gr)
    GLabel(gr, y, "Interval (seconds)")
    GField(gr, y, "intervalSec", Cfg.IntervalSec)
    GSlider(gr, GRow(gr), "keyHold", "Key hold", Cfg.KeyHoldMs, 10, 500, " ms")
    GSlider(gr, GRow(gr), "airborne", "Air time", Cfg.AirborneMs, 0, 10000, " ms", 1,
            "How long after Space you count as airborne (no dose is fired then).")
    GToggle(gr, GRow(gr), "skipActive", "Skip while the buff is up", Cfg.SkipIfActive,
            "OFF (default): always reapply at your interval, even if the old buff hasn't "
          . "expired - a safety buffer. ON: skip reapplying while the buff icon is still lit.")
    GToggle(gr, GRow(gr), "relentless", "Never sit without the buff", Cfg.Relentless,
            "Watches the buff icon between doses and reapplies as soon as it is missing and "
          . "you are back on the ground - this covers a dose wasted in water or mid-air. "
          . "Needs a scan area. Costs some extra keypresses.")
    GSlider(gr, GRow(gr), "recheckMs", "Recheck", Cfg.RecheckMs, 100, 10000, " ms")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Hotkeys")
    y := GRow(gr)
    GLabel(gr, y, "Menu")
    GHot(gr, y, "hkMenu", Keys.Menu)
    y := GRow(gr)
    GLabel(gr, y, "Toggle macro")
    GHot(gr, y, "hkToggle", Keys.Toggle)
    y := GRow(gr)
    GLabel(gr, y, "Apply now")
    GHot(gr, y, "hkFire", Keys.Fire)
    y := GRow(gr)
    GLabel(gr, y, "Clean screenshot",
            "Saves ARK's screen without the pills, stats card or this menu, to the Screenshots "
          . "folder next to ArkSense.ahk.")
    GHot(gr, y, "hkShot", Keys.Shot)
    GToggle(gr, GRow(gr), "shotStamp", "Stamp time and server on shots", Theme.ShotStamp)
    GButtons(gr, GRow(gr), [["OPEN SCREENSHOTS FOLDER", (*) => ShotFolder()]])
    GroupEnd(gr)

    ; column 2
    gr := GroupBegin(g, p, 1, Layout.TOP, "Scan area  (per resolution)")
    GText(gr, GRow(gr), "regionInfo")
    GButtons(gr, GRow(gr), [["PICK AREA", (*) => SetTimer(PickRegion, -60), "accent"],
                            ["CLEAR", (*) => ClearRegion()]])
    y := GRow(gr)
    GLabel(gr, y, "Buff colour")
    GSwatch(gr, y, "buffColor", "buffSwatch", Cfg.BuffColor)
    y := GRow(gr)
    GLabel(gr, y, "Tolerance (0-255)")
    GField(gr, y, "tolerance", Cfg.Tolerance)
    GButtons(gr, GRow(gr), [["EYEDROPPER", (*) => EyeHint()], ["TEST", (*) => TestDetect()]],
             ["Hover the buff icon in game and press the eyedropper key (" . Keys.Pick . ").",
              "Checks the scan area for the buff colour right now."])
    GText(gr, GRow(gr), "testResult")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Verify / retry")
    GSlider(gr, GRow(gr), "verifyDelay", "Verify delay", Cfg.VerifyDelayMs, 50, 5000, " ms")
    GSlider(gr, GRow(gr), "retryDelay", "Retry delay", Cfg.RetryDelayMs, 50, 5000, " ms")
    GSlider(gr, GRow(gr), "maxRetries", "Max retries", Cfg.MaxRetries, 1, 200, "")
    GroupEnd(gr)

    ; column 3
    gr := GroupBegin(g, p, 2, Layout.TOP, "Macro")
    GText(gr, GRow(gr), "antState")
    GButtons(gr, GRow(gr), [["TOGGLE MACRO", (*) => ToggleMacro(), "accent"]])
    GButtons(gr, GRow(gr), [["APPLY NOW", (*) => FireNow()]])
    GNote(gr, GRow(gr, 2), "Fires the hotbar key only while the buff icon is missing, then "
        . "checks it landed and retries if not.")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, y2, "Game window  (blank = auto)")
    GText(gr, GRow(gr), "gameInfo")
    GPath(gr, GRow(gr), "gameExe", Store.GameExe)
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyAll(), "accent"]])
    RefreshGameInfo()
}

RefreshGameInfo() {
    if !UI.Ctrl.Has("gameInfo")
        return
    c := UI.Ctrl["gameInfo"]
    if GameActive() {
        c.Text := "ARK window is focused right now"
        Paint(c, "", Theme.Ok)
    } else {
        c.Text := "ARK not focused (auto-detects ARK)"
        Paint(c, "", Theme.Dim)
    }
}

; ---- MACROS ----------------------------------------------------------------------
BuildMacros(g) {
    p := "macros"

    ; column 1: remount + insta-bag
    gr := GroupBegin(g, p, 0, Layout.TOP, "Remount")
    GText(gr, GRow(gr), "desmoStatus")
    y := GRow(gr)
    GLabel(gr, y, "Toggle hotkey")
    GHot(gr, y, "desmoHotkey", Desmo.Toggle)
    GSlider(gr, GRow(gr), "desmoDelay", "Double-press", Desmo.DelayMs, 1, 2000, " ms", 1,
            "While active, every real E press is followed by a second E after this delay. "
          . "Works in any window, not just ARK.")
    GToggle(gr, GRow(gr), "desmoHoldOn", "Hold E to spam E", Desmo.HoldOn,
            "Replaces the double-press: while E is held, E is sent repeatedly until you let go.")
    GSlider(gr, GRow(gr), "desmoHoldMs", "Spam interval", Desmo.HoldMs, 1, 1000, " ms", 1,
            "Windows timers bottom out around 10-16 ms, so 10 is effectively the fastest.")
    GButtons(gr, GRow(gr), [["TOGGLE REMOUNT", (*) => DesmoToggle(), "accent"]])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Insta-Bag")
    GText(gr, GRow(gr), "bagStatus")
    y := GRow(gr)
    GLabel(gr, y, "Arm hotkey")
    GHot(gr, y, "bagToggle", Bag.Toggle)
    y := GRow(gr)
    GLabel(gr, y, "Trigger key", "Once armed, each press of this key sends one click.")
    GHot(gr, y, "bagTrigger", Bag.TriggerKey)
    GToggle(gr, GRow(gr), "bagCurrent", "Click at the cursor", Bag.UseCurrent)
    GToggle(gr, GRow(gr), "bagGameOnly", "Only while ARK is focused", Bag.GameOnly)
    GText(gr, GRow(gr), "bagCoordInfo")
    GButtons(gr, GRow(gr), [["PICK POINT", (*) => SetTimer(PickBagPoint, -60)],
                            ["ARM / DISARM", (*) => BagToggle(), "accent"]])
    GroupEnd(gr)

    ; column 2: mammoth
    gr := GroupBegin(g, p, 1, Layout.TOP, "Mammoth clicker")
    GText(gr, GRow(gr), "mamStatus")
    y := GRow(gr)
    GLabel(gr, y, "Arm hotkey")
    GHot(gr, y, "mamToggle", Mammoth.Toggle)
    GSlider(gr, GRow(gr), "mamInterval", "Interval", Mammoth.IntervalMs, 100, 3000, " ms")
    GSlider(gr, GRow(gr), "mamHold", "Click hold", Mammoth.HoldMs, 5, 150, " ms")
    y := GRow(gr)
    GLabel(gr, y, "Mouse button")
    GDrop(gr, y, "mamButton", ["Left", "Right", "Middle"], Mammoth.Button, 100)
    GToggle(gr, GRow(gr), "mamGameOnly", "Only while ARK is focused", Mammoth.GameOnly)
    GToggle(gr, GRow(gr), "mamClickOnArm", "Click as soon as armed", Mammoth.ClickOnArm)
    GButtons(gr, GRow(gr), [["ARM / DISARM", (*) => MammothToggle(), "accent"]])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Beat meter")
    gr.g.SetFont("s9 Bold", Theme.FontName)
    GText(gr, GRow(gr, 2), "mamResult", Mammoth.ResultText, Theme.Text, 40)
    gr.g.SetFont("s9 Norm", Theme.FontName)
    GButtons(gr, GRow(gr), [["MEASURE", (*) => MammothMeasureStart()],
                            ["USE RESULT", (*) => MammothUseResult()]],
             ["Press, then left-click in time with the drum for 8-16 beats. It stops on its "
            . "own 3 s after your last click. A wide spread means the beat varies and a fixed "
            . "timer cannot stay on it.", ""])
    GroupEnd(gr)

    ; column 3: autoclicker (lib\AutoClick.ahk)
    AcBuildGroup(g, p)

    FootButtons(g, p, [["APPLY", (*) => ApplyMacros(), "accent"]])
    DesmoRefreshStatus()
    MammothRefreshStatus()
    RefreshBagCoordInfo()
    BagRefreshStatus()
    AcRefreshStatus()
}

; one APPLY for the whole tab: remount, mammoth, insta-bag and the autoclicker
ApplyMacros() {
    ReadUI()                                     ; insta-bag fields are read here
    Desmo.DelayMs := Num("desmoDelay", 20, 1, 2000)
    hk := UI.Ctrl["desmoHotkey"].Value
    Desmo.Toggle := (hk = "") ? "F3" : hk
    Desmo.HoldOn := ChkVal(UI.Ctrl["desmoHoldOn"])
    Desmo.HoldMs := Num("desmoHoldMs", 10, 1, 1000)
    if !Desmo.HoldOn
        DesmoHoldStop()

    Mammoth.IntervalMs := SliderValue("mamInterval", 600)
    Mammoth.HoldMs     := SliderValue("mamHold", 30)
    Mammoth.Button     := DropValue("mamButton", "Left")
    Mammoth.GameOnly   := ChkVal(UI.Ctrl["mamGameOnly"])
    Mammoth.ClickOnArm := ChkVal(UI.Ctrl["mamClickOnArm"])
    hk := UI.Ctrl["mamToggle"].Value
    Mammoth.Toggle := (hk = "") ? "F6" : hk
    MammothClamp()
    if Mammoth.Active                          ; restart the grid on the new interval
        Mammoth.NextAt := NowMs() + Mammoth.IntervalMs

    AcReadUI()
    warn := AcHotkeyWarn()

    ApplyHotkeys()
    SaveIni()
    DesmoRefreshStatus()
    MammothRefreshStatus()
    BagRefreshStatus()
    Flash((warn != "") ? warn : "macro settings applied")
}

; ---- FPS -------------------------------------------------------------------------
BuildFps(g) {
    p := "fps"
    gr := GroupBegin(g, p, 0, Layout.TOP, "Console")
    y := GRow(gr)
    GLabel(gr, y, "Console key")
    GHot(gr, y, "fpsConsoleKey", Fps.ConsoleKey)
    GSlider(gr, GRow(gr), "fpsOpenDelay", "Open delay", Fps.OpenDelayMs, 0, 5000, " ms")
    GSlider(gr, GRow(gr), "fpsCloseDelay", "Close delay", Fps.CloseDelayMs, 0, 5000, " ms")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Screen filter")
    y := GRow(gr), GLabel(gr, y, "Filter",
            "Recolours the whole screen while ARK is focused (Windows' own colour transform, the "
          . "one its built-in colour filters use). Nothing in the game is read or changed. Small "
          . "GPU cost and up to ~1 frame of display delay while one shows; Off costs nothing.", 100),
        GDrop(gr, y, "filterName", FilterNames(), Filter.Name, 140)
    GSlider(gr, GRow(gr), "filterStrength", "Strength", Filter.Strength, 0, 100, "%")
    y := GRow(gr), GLabel(gr, y, "On/off  /  next key", "First box: turns the filter off and "
          . "back on. Second: steps to the next filter.", 104),
        GHot(gr, y, "filterKey", Filter.Key, 72, GRight(gr) - 72 - 6 - 72),
        GHot(gr, y, "filterNextKey", Filter.NextKey, 72)
    GText(gr, GRow(gr), "filterStatus")
    GButtons(gr, GRow(gr), [["PREVIEW 5 S", (*) => FilterPreview(), "accent"]],
             ["Shows the picked filter for 5 seconds right now, even over this menu."])
    GNote(gr, GRow(gr, 3), "Vivid, Cave bright and Night lift colour or dark areas. The Protan / "
        . "Deutan aids help red- or green-weak eyes. Check your server's rules on visual tweaks.", 3)
    GroupEnd(gr)

    gr := GroupBegin(g, p, 1, Layout.TOP, "Presets")
    GButtons(gr, GRow(gr), [["NORMAL FPS CMDS + WHITE GEN RANGE", (*) => RunFpsPreset("normal"), "accent"]])
    GButtons(gr, GRow(gr), [["HARD FPS CMDS (GAME LOOKS WORSE)", (*) => RunFpsPreset("hard")]])
    GButtons(gr, GRow(gr), [["DEBUGSTRUCTURES", (*) => RunFpsPreset("debug")]])
    GButtons(gr, GRow(gr), [["DRAW 6X AREA (SINGLEPLAYER)", (*) => RunFpsPreset("draw6x")]])
    b := GButtons(gr, GRow(gr), [["TOGGLE WHITE GEN RANGE (" . (Fps.GenRangeOn ? "ON" : "OFF") . ")",
                                  (*) => ToggleGenRange()]])
    UI.Ctrl["fpsGenBtn"] := b[1]
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, Layout.TOP, "Alerts")
    GToggle(gr, GRow(gr), "alertOn", "Show alerts", Alerts.On,
            "Slide-in notes in a screen corner. Every alert is also written to Logs.")
    y := GRow(gr), GLabel(gr, y, "Antidote gave up " . Chr(0x00D7), "Alert when the antidote gave up "
          . "(all its tries failed) this many times in a row. 0 = off.", 170),
        GField(gr, y, "alertAnti", Alerts.AntiFail, true, 52)
    y := GRow(gr), GLabel(gr, y, "Server lag over (ms)", "Alert when the server's own reply time "
          . "(SERVER, the faint graph line) stays above this for 3 samples. 0 = off.", 170),
        GField(gr, y, "alertLag", Alerts.LagMs, true, 52)
    y := GRow(gr), GLabel(gr, y, "Answers missing over (%)", "Alert when this share of the last 30 "
          . "samples got no answer (packet loss or a stalling server). 0 = off.", 170),
        GField(gr, y, "alertLoss", Alerts.LossPct, true, 52)
    GToggle(gr, GRow(gr), "alertServer", "Server found / stops answering", Alerts.Server)
    GToggle(gr, GRow(gr), "alertFeedback", "Layout / filter key switches", Alerts.Feedback,
            "A short note when a hotkey switches the overlay layout or the screen filter.")
    GToggle(gr, GRow(gr), "alertSound", "Sound on warnings", Alerts.Sound)
    y := GRow(gr), GLabel(gr, y, "Position", "", 100),
        GDrop(gr, y, "alertPos", AlertPosNames(), AlertPosName(Alerts.Pos), 120)
    GSlider(gr, GRow(gr), "alertSecs", "Show for", Alerts.Secs, 2, 10, " s")
    GButtons(gr, GRow(gr), [["TEST ALERT", (*) => AlertTest(), "accent"]])
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyFps(), "accent"]])
    FilterStatus()
}

BuildOverlay(g) {
    p := "overlay"

    ; column 1
    gr := GroupBegin(g, p, 0, Layout.TOP, "Status pills")
    GToggle(gr, GRow(gr), "hudOn", "Show the overlay", Theme.HudOn)
    GSlider(gr, GRow(gr), "hudFontSize", "Pill size", Theme.HudFontSize, 6, 24, "", 1,
            "Size of pills that haven't been resized by hand.")
    y := GRow(gr)
    GLabel(gr, y, "Height / gap (px)")
    GField(gr, y, "hudPillH", Theme.PillH, true, 44, GRight(gr) - 94)
    GField(gr, y, "hudPillGap", Theme.PillGap, true, 44)
    GToggle(gr, GRow(gr), "hudVertical", "Stack vertically", Theme.PillVertical,
            "How pills without a saved spot line up from the anchor.")
    y := GRow(gr)
    GLabel(gr, y, "Stack anchor X / Y", "Where the automatic stack starts.")
    GField(gr, y, "hudX", Theme.HudX, true, 52, GRight(gr) - 110)
    GField(gr, y, "hudY", Theme.HudY, true, 52)
    GButtons(gr, GRow(gr), [["EDIT LAYOUT", (*) => HudPreview(), "accent"],
                            ["LOCK", (*) => HudLockPosition()]],
             ["Drag a pill or the stats card to move it. Drag the triangle at its end to "
            . "resize it. Then press LOCK to save.",
              "Saves where every pill and the stats card are, and how big."])
    GButtons(gr, GRow(gr), [["RESET LAYOUT", (*) => PillResetLayout()]],
             ["Forget every saved spot and size; pills restack at the anchor and the card "
            . "goes back to its position below."])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Look")
    GToggle(gr, GRow(gr), "hudBorderOn", "Pill outline", Theme.HudBorderOn)
    GToggle(gr, GRow(gr), "hudBgOn", "Pill background", Theme.HudBgOn)
    GSlider(gr, GRow(gr), "hudBgOpacity", "Opacity", Theme.HudBgOpacity, 0, 255, "")
    y := GRow(gr)
    GLabel(gr, y, "Text colour")
    GSwatch(gr, y, "hudTextColor", "hudTextSwatch", Theme.HudTextColor)
    y := GRow(gr)
    GLabel(gr, y, "Outline colour")
    GSwatch(gr, y, "hudBorderColor", "hudBorderSwatch", Theme.HudBorderColor)
    y := GRow(gr)
    GLabel(gr, y, "Text presets", "", 90)
    for i, col in ["FF2836", "4CD07A", "18C8E6", "7A5CFF", "FFA23A", "FFFFFF"] {
        c := MkBtn(g, "x" . (GRight(gr) - 6 * 26 + 4 + (i - 1) * 26) . " y" . (y + 3) . " w20 h18", "",
                   HudTextPresetCb(col), col, col)
        Reg(p, c)
    }
    GroupEnd(gr)

    ; column 2 - pill toggles two per row
    gr := GroupBegin(g, p, 1, Layout.TOP, "Pills shown")
    hw := (gr.w - 24 - 12) // 2
    lx := gr.x + 12, rx := gr.x + 12 + hw + 12
    y := GRow(gr)
    GToggle(gr, y, "hudShowState",    "Antidote",   Theme.HudShowState, "Antidote on / off", lx, hw)
    GToggle(gr, y, "hudShowMsg",      "Status msg", Theme.HudShowMsg, "The antidote's status message", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "hudShowCounts",   "Counts",     Theme.HudShowCounts, "Antidote key presses: ok = the buff showed up after the press, fail = it didn't", lx, hw)
    GToggle(gr, y, "hudShowDesmo",    "Remount",    Theme.HudShowDesmo, "", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "hudShowMammoth",  "Mammoth",    Theme.HudShowMammoth, "", lx, hw)
    GToggle(gr, y, "hudShowBag",      "Insta-Bag",  Theme.HudShowBag, "", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "hudShowStreamer", "Streamer",   Theme.HudShowStreamer, "Streamer mode", lx, hw)
    GToggle(gr, y, "hudShowOcPill",   "OC / clicker", Theme.HudShowOc, "Pills that show while the OC macro or the autoclicker runs", rx, hw)
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Display")
    GToggle(gr, GRow(gr), "hudGameOnly", "Only in ARK (and in this menu)", Theme.OverlayGameOnly,
            "On: the pills, the stats card and alerts hide whenever another window (a browser, "
          . "Discord, the desktop) is in front, and come back when you click into ARK or open this "
          . "menu. Off: they always show.")
    GToggle(gr, GRow(gr), "hudModern", "Modern look (smooth renderer)", (Theme.Renderer = "Smooth"),
            "Off (default): the pills, stats card and graph look like they did in step 9 - red, "
          . "cyan and dark grey, whatever the menu theme. On: the step 13 look, drawn by a small "
          . "helper (lib\ArkSenseOverlay.cs, compiled on this PC the first time) with smooth edges, "
          . "gradients, glow and fades in the menu's colours. If it can't start, the classic look is "
          . "used by itself; the Self-check says why.")
    y := GRow(gr)
    GText(gr, y, "streamerStatus")
    UI.Ctrl["streamerStatus"].Move(, , 110)
    GDrop(gr, y, "streamScope", StreamerScopes(), Theme.StreamerScope, 150,
          (item) => SetTimer(SetStreamerScope.Bind(item), -10))
    UI.Tips[UI.Ctrl["streamerStatus"].Hwnd] := "What streamer mode hides from capture. If a recorder "
        . "(e.g. Medal) stops clipping while it's on, try 'Overlays only' or 'Menu only'."
    GButtons(gr, GRow(gr), [["TOGGLE STREAMER MODE", (*) => ToggleStreamerMode(), "accent"]],
             ["Hides the menu and / or the overlays (see the list above) from OBS/Medal-style "
            . "display capture (Windows Graphics Capture / DXGI). Needs Windows 10 2004+. A "
            . "recorder's GAME capture never sees ArkSense's windows anyway."])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Network")
    GToggle(gr, GRow(gr), "statPing", "Ping graph, jitter, loss", Stats.ShowPing,
            "The bright line is your ping to the ARK server: the lower of the plain ping and the "
          . "fastest Steam-query reply of the last 5 s (some servers answer plain pings slowly - "
          . "FusionPvP reads 48 that way while the game shows 28). The faint line, SERVER, is "
          . "every query reply; it reads higher (the server answers between its game frames) and "
          . "rises when the server lags. Both jump: your connection. Only SERVER: the server.")
    GToggle(gr, GRow(gr), "statPingAuto", "Find my ARK server automatically", Stats.PingAuto,
            "Watches which address ARK's own network traffic goes to (a 3-second Windows "
          . "network trace, every 2 minutes) and measures that. Nothing inside the game is read.")
    GText(gr, GRow(gr), "pingServer")
    y := GRow(gr)
    GLabel(gr, y, "Host / query",
            "Host: used when automatic is off. Query port: 0 finds it by itself (Steam server list, "
          . "BattleMetrics, then the usual ARK ports); set it if your server panel lists it.", 94)
    GField(gr, y, "statPingHost", Stats.PingHost, false, 104, GRight(gr) - 160)
    GField(gr, y, "statQueryPort", Stats.QueryPort, true, 52)
    GroupEnd(gr)

    ; column 3
    gr := GroupBegin(g, p, 2, Layout.TOP, "Stats card")
    hw := (gr.w - 24 - 12) // 2
    lx := gr.x + 12, rx := gr.x + 12 + hw + 12
    GToggle(gr, GRow(gr), "statCardOn", "Show the stats card", Stats.CardOn)
    y := GRow(gr)
    GToggle(gr, y, "statCpu", "CPU", Stats.ShowCpu, "", lx, hw)
    GToggle(gr, y, "statRam", "RAM", Stats.ShowRam, "", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "statGpu", "GPU", Stats.ShowGpu,
            "Uses the 3D-engine counter Windows exposes; a few systems don't publish it and "
          . "show n/a.", lx, hw)
    GToggle(gr, y, "statClock", "Clock", Stats.ShowClock, "24-hour clock", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "statFps", "FPS line", Stats.ShowFps,
            "ARK's frames per second as a green line (own scale) with its number. Counted from "
          . "Windows' own graphics event log (ETW DXGI Present events, like PresentMon) - "
          . "nothing is injected into ARK or read from it. Needs the ping graph on.", lx, hw)
    GToggle(gr, y, "statPlayers", "Players", Stats.ShowPlayers,
            "Players online right now, e.g. PLAYERS 54/70 - the server's own answer to the "
          . "Steam server query, read every second (the same packet BattleMetrics polls every "
          . "few minutes). Needs the server query to work (a q<port> on the HOST line). FusionPvP "
          . "runs several servers on one address: the count is only shown once the query port is "
          . "matched to YOUR server (its reply carries its game port). Logs lists every server found.", rx, hw)
    CardWant(&cx, &cy, &cs)
    y := GRow(gr)
    GLabel(gr, y, "Position X / Y",
            "Exact screen position of the card's top-left corner, in pixels. Type and press "
          . "APPLY, or drag it with MOVE / RESIZE.")
    GField(gr, y, "statPosX", cx, true, 52, GRight(gr) - 110)
    GField(gr, y, "statPosY", cy, true, 52)
    GSlider(gr, GRow(gr), "statInterval", "Update every", Stats.IntervalSec, 1, 60, " s")
    GButtons(gr, GRow(gr), [["MOVE / RESIZE", (*) => CardMove(), "accent"],
                            ["LOCK", (*) => CardLock()]],
             ["Drag the card (or the stats bar) to move it, drag its triangle to resize it, then "
            . "press LOCK. Only the card unlocks - the pills stay as they are (EDIT LAYOUT moves "
            . "everything).", "Saves where the card is."])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, y2, "Layouts")
    Loop 3 {
        i := A_Index
        y := GRow(gr)
        GField(gr, y, "layName" . i, Lay.Names[i], false, 112, gr.x + 12)
        UI.Tips[UI.Ctrl["layName" . i].Hwnd] := "Name of layout " . i
        GHot(gr, y, "layKey" . i, Lay.Keys[i], 84, gr.x + 12 + 112 + 8)
        UI.Tips[UI.Ctrl["layKey" . i].Hwnd] := "Hotkey that switches to this layout"
        b := MkBtn(g, "x" . (GRight(gr) - 46) . " y" . y . " w46 h24 Center +0x200", "LOAD", LayLoadCb(i))
        UI.Tips[b.Hwnd] := "Switch the overlay to this layout now"
        Reg(p, b)
    }
    y := GRow(gr), GLabel(gr, y, "Next layout key", "Steps 1 > 2 > 3 > 1 ...", 120),
        GHot(gr, y, "layNext", Lay.NextKey, 84, GRight(gr) - 46 - 8 - 84)
    GButtons(gr, GRow(gr), [["SAVE 1", LaySaveCb(1)], ["SAVE 2", LaySaveCb(2)], ["SAVE 3", LaySaveCb(3)]],
             ["Store the overlay as it is now (pills shown, card parts, every position and size) "
            . "as layout 1. Applies this tab first.", "Same, into layout 2.", "Same, into layout 3."])
    GText(gr, GRow(gr), "layStatus")
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyOverlayTab(), "accent"]])
    RefreshStreamerStatus()
    LayStatus()
}

; one APPLY for the whole tab: status pills and the stats overlay
ApplyOverlayTab(quiet := false) {
    oldTarget := PingTarget(), oldQuery := Stats.QueryPort
    ReadUI()
    LayReadUI()
    if UI.Ctrl.Has("hudModern")
        Theme.Renderer := ChkVal(UI.Ctrl["hudModern"]) ? "Smooth" : "Classic"
    CardPosFromFields()                    ; typed X / Y -> the card's saved spot
    if (PingTarget() != oldTarget || Stats.QueryPort != oldQuery)
        PingRestart()                      ; new target or port: restart both helpers
    if UI.Ctrl.Has("hudTextSwatch")
        Paint(UI.Ctrl["hudTextSwatch"], Theme.HudTextColor)
    if UI.Ctrl.Has("hudBorderSwatch")
        Paint(UI.Ctrl["hudBorderSwatch"], Theme.HudBorderColor)
    SetTimer(StatsTick, Stats.IntervalSec * 1000)
    ApplyHotkeys()                         ; layout keys
    SaveIni()
    OvlApplyMode()                         ; Smooth <-> Classic
    RebuildHud()
    RebuildStatHud()
    RefreshStatInfo()
    if !quiet
        Flash("overlay settings applied" . ((Theme.Renderer = "Smooth" && !OvlOn())
                                            ? " - modern look unavailable, see Self-check" : ""))
}

; ---- NOW PLAYING (music overlay) -------------------------------------------------------
BuildMusic(g) {
    p := "music"
    gr := GroupBegin(g, p, 0, Layout.TOP, "Now playing")
    GToggle(gr, GRow(gr), "npOn", "Show what's playing", Np.On,
            "A small see-through card with the song or video playing in YouTube - thumbnail, "
          . "title, artist and progress. It shows while something plays and follows "
          . "Overlay > Only in ARK.")
    y := GRow(gr), GLabel(gr, y, "Listen to",
            "Browsers: YouTube / YouTube Music (and anything else playing) in Chrome, Edge, "
          . "Firefox, Opera, Brave, Vivaldi. Any app: also Spotify, the Media Player and the rest.", 100),
        GDrop(gr, y, "npSource", ["Browsers", "Any app"], Np.Source, 130)
    hw := (gr.w - 24 - 12) // 2
    lx := gr.x + 12, rx := gr.x + 12 + hw + 12
    y := GRow(gr)
    GToggle(gr, y, "npCover", "Thumbnail", Np.Cover, "The video thumbnail / album art on the left.", lx, hw)
    GToggle(gr, y, "npProgress", "Progress bar", Np.Progress, "Position and length of the song.", rx, hw)
    GToggle(gr, GRow(gr), "npHidePaused", "Hide when paused (after 5 s)", Np.HidePaused)
    GToggle(gr, GRow(gr), "npGameOnly", "Only while ARK or this menu is focused", Np.GameOnly,
            "On: the card hides the moment anything else (a browser, Discord, the desktop) is "
          . "the focused window, and comes back when you click into ARK or open this menu. Off: "
          . "it follows Overlay > Only in ARK like the other overlays.")
    GText(gr, GRow(gr), "npNow")
    GText(gr, GRow(gr), "npVia")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, Layout.TOP, "Look")
    GSlider(gr, GRow(gr), "npAlpha", "Background", Np.Alpha, 0, 255, "", 1,
            "How solid the card's background is. Text and the picture always stay solid.")
    GSlider(gr, GRow(gr), "npScale", "Size", Np.Scale, 60, 250, "%")
    y := GRow(gr)
    GLabel(gr, y, "Bar colour", "Progress bar and play mark. Empty = the overlay's own colour.")
    GField(gr, y, "npAccent", Np.Accent, false, 76)
    GToggle(gr, GRow(gr), "npOutline", "Outline", Np.Outline, "A line around the card.")
    y := GRow(gr)
    GLabel(gr, y, "Outline colour", "Any hex colour (RRGGBB). Empty = the bar colour.")
    GSwatch(gr, y, "npOutlineColor", "npOutlineSw", NpOutlineShown())
    y := GRow(gr)
    GLabel(gr, y, "Presets", "", 70)
    for i, col in ["FF2836", "18C8E6", "4CD07A", "A06BFF", "FFA23A", "FFFFFF"] {
        c := MkBtn(g, "x" . (GRight(gr) - 6 * 26 + 4 + (i - 1) * 26) . " y" . (y + 3) . " w20 h18", "",
                   NpOutlineCb(col), col, col)
        Reg(p, c)
    }
    GroupEnd(gr)

    gr := GroupBegin(g, p, 2, Layout.TOP, "Position")
    y := GRow(gr)
    GLabel(gr, y, "X / Y", "Top-left corner in screen pixels. -1 / -1 = bottom left of the "
        . "main screen.")
    GField(gr, y, "npX", Np.X, false, 52, GRight(gr) - 110)
    GField(gr, y, "npY", Np.Y, false, 52)
    GButtons(gr, GRow(gr), [["MOVE", (*) => NpMove(), "accent"], ["LOCK", (*) => NpLock()]],
             ["Shows the card (a placeholder if nothing plays) at the X / Y above so you can drag it.",
              "Saves where it is."])
    GButtons(gr, GRow(gr), [["RESET POSITION", (*) => NpReset()]],
             ["Back to the bottom left of the main screen."])
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyMusic(), "accent"]])
}

; the outline colour in use (its own, else the bar colour)
NpOutlineShown() => (Np.OutlineColor != "") ? Np.OutlineColor : (Np.Accent != "") ? Np.Accent : OvC("Accent2")

NpOutlineCb(col) => (*) => NpSetOutline(col)

NpSetOutline(col) {
    Np.OutlineColor := col
    Np.Outline := 1
    if UI.Ctrl.Has("npOutlineColor")
        UI.Ctrl["npOutlineColor"].Value := col
    if UI.Ctrl.Has("npOutlineSw")
        Paint(UI.Ctrl["npOutlineSw"], col)
    SetToggle("npOutline", 1)
    SaveIni()
    Np.Sig := ""
    NpRefresh()
}

ApplyMusic() {
    Np.On := ChkVal(UI.Ctrl["npOn"])
    Np.Source := DropValue("npSource", Np.Source)
    Np.Cover := ChkVal(UI.Ctrl["npCover"])
    Np.Progress := ChkVal(UI.Ctrl["npProgress"])
    Np.HidePaused := ChkVal(UI.Ctrl["npHidePaused"])
    Np.GameOnly := ChkVal(UI.Ctrl["npGameOnly"])
    Np.Outline := ChkVal(UI.Ctrl["npOutline"])
    oc := Trim(UI.Ctrl["npOutlineColor"].Value)
    Np.OutlineColor := (oc = "") ? "" : Hex("npOutlineColor", Np.OutlineColor)
    Paint(UI.Ctrl["npOutlineSw"], NpOutlineShown())
    Np.Alpha := Num("npAlpha", 175, 0, 255)
    Np.Scale := Num("npScale", 100, 60, 250)
    a := Trim(UI.Ctrl["npAccent"].Value)
    a := RegExReplace(a, "^#")
    Np.Accent := RegExMatch(a, "^[0-9A-Fa-f]{6}$") ? StrUpper(a) : ""
    UI.Ctrl["npAccent"].Value := Np.Accent
    NpPosFromFields()                     ; typed X / Y: moves it, also while MOVE is on
    NpPosFields()
    SaveIni()
    NpApply()
    Flash("Now playing settings applied")
}

; ---- SETTINGS (appearance, animation, profiles) -----------------------------------
BuildSettings(g) {
    p := "settings"

    ; column 1
    gr := GroupBegin(g, p, 0, Layout.TOP, "Colours")
    rows := [["Primary",      "cAccent",  Theme.Accent],
             ["Gradient end", "cAccent2", Theme.Accent2],
             ["Background",   "cPanel",   Theme.Panel],
             ["Control fill", "cPanel2",  Theme.Panel2],
             ["Text",         "cText",    Theme.Text],
             ["Dim text",     "cDim",     Theme.Dim]]
    for r in rows {
        y := GRow(gr)
        GLabel(gr, y, r[1])
        GSwatch(gr, y, r[2], r[2] . "Sw", r[3])
    }
    y := GRow(gr)
    GLabel(gr, y, "Primary presets", "", 100)
    for i, col in ["FF2836", "18C8E6", "7A5CFF", "4CD07A", "FF00FF", "FFFFFF"] {
        c := MkBtn(g, "x" . (GRight(gr) - 6 * 26 + 4 + (i - 1) * 26) . " y" . (y + 3) . " w20 h18", "",
                   PresetCb(col), col, col)
        Reg(p, c)
    }
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Window")
    y := GRow(gr), GLabel(gr, y, "Menu", "Web: the menu drawn by Edge WebView2 (smooth fonts, gradients, "
          . "animations; ~150-250 MB while loaded). Native: the classic window. If Web can't start, "
          . "Native is used by itself; the Self-check says why.", 60),
        GDrop(gr, y, "menuEngine", ["Web", "Native"], Theme.MenuEngine, 110)
    GSlider(gr, GRow(gr), "opacity", "Opacity", Theme.Opacity, 120, 255, "",
            1, "Native menu only (Windows can't fade a WebView2 window).")
    y := GRow(gr)
    GLabel(gr, y, "Font", "Tab icons and the data panels keep their own faces so glyphs "
        . "and columns stay aligned.", 60)
    fonts := ["Segoe UI", "Arial", "Calibri", "Consolas", "Courier New", "Georgia",
              "Impact", "Lucida Console", "Segoe UI Semibold", "Tahoma", "Times New Roman",
              "Trebuchet MS", "Verdana"]
    have := false
    for f in fonts {
        if (f = Theme.FontName)
            have := true
    }
    if !have                                  ; keep a font picked in an older build
        fonts.InsertAt(1, Theme.FontName)
    GDrop(gr, y, "uiFont", fonts, Theme.FontName, 170)
    GToggle(gr, GRow(gr), "wallOn", "Wallpaper behind the panels", Theme.WallOn,
            "Any picture; it is scaled to fill the menu and cropped. Darker pictures read best.")
    y := GRow(gr)
    GPath(gr, y, "wallPath", Theme.WallPath, gr.w - 24 - 78)
    GBrowse(gr, y, (*) => BrowseWall())
    GroupEnd(gr)

    ; column 2
    gr := GroupBegin(g, p, 1, Layout.TOP, "Audio (mp3)")
    GToggle(gr, GRow(gr), "musicOn", "Background theme song", Audio.MusicOn)
    y := GRow(gr)
    GPath(gr, y, "musicPath", Audio.MusicPath, gr.w - 24 - 78)
    GBrowse(gr, y, (*) => BrowseAudio("musicPath"))
    GToggle(gr, GRow(gr), "clickOn", "Click sound on buttons", Audio.ClickOn)
    y := GRow(gr)
    GPath(gr, y, "clickPath", Audio.ClickPath, gr.w - 24 - 78)
    GBrowse(gr, y, (*) => BrowseAudio("clickPath"))
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Logo (png)")
    y := GRow(gr)
    GPath(gr, y, "logoPath", Audio.LogoPath, gr.w - 24 - 78)
    GBrowse(gr, y, (*) => BrowseLogo())
    y := GRow(gr)
    GLabel(gr, y, "Width / height (px)")
    GField(gr, y, "logoW", Audio.LogoW, true, 44, GRight(gr) - 94)
    GField(gr, y, "logoH", Audio.LogoH, true, 44)
    GSlider(gr, GRow(gr), "logoX", "Logo X", Audio.LogoX, 0, 560, " px")
    y := GRow(gr)
    GLabel(gr, y, "Your name", "The name in the box at the bottom left of the sidebar. You can "
        . "also click the name there to change it.", 90)
    GField(gr, y, "userName", Theme.UserName, false, 150)
    GroupEnd(gr)

    ; column 3
    gr := GroupBegin(g, p, 2, Layout.TOP, "Profiles")
    y := GRow(gr)
    GLabel(gr, y, "Profile", "", 80)
    GDrop(gr, y, "profList", ProfileNames(), Store.Active, 170)
    GButtons(gr, GRow(gr), [["LOAD", (*) => SetTimer(LoadProfile, -60), "accent"],
                            ["SAVE INTO", (*) => SaveIntoSelected()],
                            ["DELETE", (*) => DeleteProfile(), "bad"]],
             ["Load the picked profile.", "Save the current antidote settings into the picked profile.", ""])
    y := GRow(gr)
    GPath(gr, y, "newName", "", gr.w - 24 - 108)
    b := MkBtn(g, "x" . (GRight(gr) - 100) . " y" . (y + 1) . " w100 h22 Center +0x200", "CREATE",
               (*) => NewProfile())
    UI.Tips[b.Hwnd] := "Saves the current antidote settings as a new profile with the name on "
                     . "the left. Scan areas are kept per resolution, outside profiles."
    Reg(p, b)
    GText(gr, GRow(gr), "profStatus")
    GroupEnd(gr)

    FootButtons(g, p, [["RESET THEME", (*) => SetTimer(ResetTheme, -60)],
                       ["APPLY", (*) => SetTimer(ApplySettings, -60), "accent"]])
}

; BROWSE button at the right end of a path row
GBrowse(grp, y, cb) {
    b := MkBtn(grp.g, "x" . (GRight(grp) - 72) . " y" . (y + 1) . " w72 h22 Center +0x200", "BROWSE", cb)
    Reg(grp.page, b)
    return b
}

; colours, audio, logo, font, plus Style and Animation (on Visuals > Look since step 22);
; the theme needs a full rebuild
ApplySettings() {
    Anim.HoverOn    := ChkVal(UI.Ctrl["animHover"])
    Anim.TabOn      := ChkVal(UI.Ctrl["animTab"])
    Anim.HoverSpeed := Num("animHoverSpeed", 22, 4, 64)
    Anim.TabSpeed   := Num("animTabSpeed",   18, 4, 64)
    Anim.PulseDepth := Num("animPulseDepth", 40, 10, 120)
    Anim.RainbowSpeed := Num("animRainbowSpeed", 3, 1, 15)
    Anim.Effect     := DropValue("fxMode", "Off")
    Anim.RainbowOn  := (Anim.Effect = "Rainbow")    ; legacy flags kept in step
    Anim.PulseOn    := (Anim.Effect = "Pulse")
    Anim.GlowOn     := ChkVal(UI.Ctrl["fxGlow"])
    Anim.TitleOn    := ChkVal(UI.Ctrl["fxTitle"])
    Anim.FadeIn     := ChkVal(UI.Ctrl["fxFade"])
    Theme.Preset    := DropValue("themePreset", Theme.Preset)
    if (Anim.Effect = "Off")
        PillBorders(Theme.HudBorderColor)     ; restore the outlines once nothing animates them
    ApplyTheme()
}

; ---- TUNE-UP ---------------------------------------------------------------------
BuildTune(g) {
    p := "tune"
    gr := GroupBegin(g, p, 0, Layout.TOP, "Windows game settings")
    GToggle(gr, GRow(gr), "tuneGameMode", "Game Mode", TuneGameMode(),
            "Windows gives the focused game priority and holds back updates and background "
          . "work while you play. Recommended: on.")
    GToggle(gr, GRow(gr), "tuneDvr", "Game Bar recording", TuneDvr(),
            "Xbox Game Bar clip recording, including recording in the background, which costs "
          . "FPS all the time. Recommended: off, unless you use it for clips.")
    GToggle(gr, GRow(gr), "tuneHags", "Hardware GPU scheduling", TuneHags(),
            "Lets the graphics card manage its own memory queue. Needs Windows 10 2004+ and a "
          . "recent NVIDIA / AMD driver; results differ per PC (try both). Takes effect after a restart.")
    GText(gr, GRow(gr), "tuneWinStatus")
    GNote(gr, GRow(gr, 2), "APPLY writes what you ticked. The first value of everything ArkSense "
        . "changes is kept, so UNDO can put it back.")
    GButtons(gr, GRow(gr), [["UNDO MY CHANGES", (*) => TuneUndo()]],
             ["Puts back every Windows setting and the power plan as they were before ArkSense "
            . "first changed them."])
    GroupEnd(gr)

    gr := GroupBegin(g, p, 1, Layout.TOP, "Power plan")
    GText(gr, GRow(gr), "tunePlanNow")
    names := TunePlanNames()
    pick := TunePlanName(Tune.GamePlan)
    for n in names {                       ; default pick: a high-performance plan if there is one
        if (Tune.GamePlan = "" && InStr(n, "perform"))
            pick := n
    }
    y := GRow(gr), GLabel(gr, y, "Plan", "", 60),
        GDrop(gr, y, "tunePlan", names, pick, 180)
    GButtons(gr, GRow(gr), [["USE THIS PLAN NOW", (*) => TunePlanNow(), "accent"]])
    GToggle(gr, GRow(gr), "tuneAutoPlan", "Only while ARK runs", Tune.AutoPlan,
            "Switches to the plan above when ARK starts and back to your usual one when it "
          . "closes (or when ArkSense closes).")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "ARK priority")
    GText(gr, GRow(gr), "tunePrioNow")
    y := GRow(gr), GLabel(gr, y, "Priority", "", 80),
        GDrop(gr, y, "tunePrio", TunePrioNames(), TunePrioName(Tune.Prio), 140)
    GToggle(gr, GRow(gr), "tuneAutoPrio", "Set it whenever ARK starts", Tune.AutoPrio)
    GButtons(gr, GRow(gr), [["APPLY TO ARK NOW", (*) => TuneApplyPrio()]])
    GNote(gr, GRow(gr, 2), "Above normal is the safe pick. High can make voice chat or music "
        . "stutter on a busy CPU. Realtime is never offered.")
    GroupEnd(gr)

    gr := GroupBegin(g, p, 2, Layout.TOP, "Live readout")
    y := GRow(gr, 3.6)
    st := g.Add("Edit", "x" . (gr.x + 12) . " y" . y . " w" . (gr.w - 24) . " h104 +Multi +ReadOnly -E0x200")
    st.SetFont("s8", "Consolas")
    Paint(st, Theme.Panel2, Theme.Text)
    UI.Round.Push([st, 8, "LR"])
    UI.Ctrl["statInfo"] := st
    Reg(p, st)
    WebRec("edit", y, gr.x + 12, {c: st})
    GButtons(gr, GRow(gr), [["TEST SAMPLERS", (*) => StatSelfTest()]],
             ["Reads CPU, RAM, GPU, ping and the server query right now and shows what each one said."])
    GroupEnd(gr)

    FootButtons(g, p, [["REFRESH", (*) => TuneRefresh()], ["APPLY", (*) => TuneApply(), "accent"]])
    TuneRefresh()
    RefreshStatInfo()
}

; ---- LOGS ------------------------------------------------------------------------
BuildLogs(g) {
    p := "logs"
    gr := GroupBegin(g, p, 0, Layout.TOP, "Action history  (this script's own actions only)", 2)
    y := GRow(gr, 13)
    ; Own header row instead of the ListView's themed (white) one; the list itself
    ; gets the dark Explorer theme for its scrollbar and selection (Win10 1809+,
    ; silently ignored elsewhere).
    g.SetFont("s8 Bold", Theme.FontName)
    for i, h in [["TIME", 0], ["SOURCE", 70], ["ACTION", 150]] {
        hc := Paint(g.Add("Text", "x" . (gr.x + 18 + h[2]) . " y" . y . " w70 h16 +0x200", h[1]),
                    Theme.Header, Theme.Dim)
        Reg(p, hc)
    }
    g.SetFont("s9 Norm", Theme.FontName)
    lv := g.Add("ListView", "x" . (gr.x + 12) . " y" . (y + 20) . " w" . (gr.w - 24)
              . " h364 -Multi -Hdr -E0x200 Background" . Theme.Panel2, ["Time", "Source", "Action"])
    try DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    UI.Round.Push([lv, 10, "LR"])
    lv.SetFont("c" . Log.TextColor)
    lv.ModifyCol(1, 70)
    lv.ModifyCol(2, 80)
    lv.ModifyCol(3, gr.w - 24 - 70 - 80 - 24)
    UI.Ctrl["logView"] := lv
    Reg(p, lv)
    WebRec("list", y, gr.x + 12, {c: lv})
    GroupEnd(gr)

    gr := GroupBegin(g, p, 2, Layout.TOP, "Log colour")
    y := GRow(gr)
    GLabel(gr, y, "Text colour")
    GSwatch(gr, y, "logColor", "logSwatch", Log.TextColor)
    y := GRow(gr)
    GLabel(gr, y, "Presets", "", 90)
    for i, col in ["4CD07A", "FF2836", "18C8E6", "7A5CFF", "FFA23A", "FFFFFF"] {
        c := MkBtn(g, "x" . (GRight(gr) - 6 * 26 + 4 + (i - 1) * 26) . " y" . (y + 3) . " w20 h18", "",
                   LogPresetCb(col), col, col)
        Reg(p, c)
    }
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, y2, "Killswitch")
    GNote(gr, GRow(gr, 2), "Instantly stops every feature (antidote, remount, mammoth, bag, OC), "
        . "lets go of held keys, hides everything and closes ArkSense.")
    y := GRow(gr)
    GLabel(gr, y, "Panic key")
    GHot(gr, y, "killKey", Keys.Kill)
    GButtons(gr, GRow(gr), [["KILL + EXIT", (*) => KillAll(), "bad"]])
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, y2, "Self-check")
    GToggle(gr, GRow(gr), "scOn", "Check everything on start", Theme.SelfCheck,
            "After start: helper files, scan area, hotkey clashes, missing pictures, ARK in "
          . "borderless mode. A short report pops up; problems also go to this log.")
    GButtons(gr, GRow(gr), [["RUN SELF-CHECK NOW", (*) => SelfCheck(true), "accent"]])
    GroupEnd(gr)

    FootButtons(g, p, [["CLEAR", (*) => ClearLog()],
                       ["REFRESH", (*) => RefreshLogView()],
                       ["APPLY", (*) => ApplyLog(), "accent"]])
    RefreshLogView()
}


; ---- small handlers used by the pages above ------------------------------------
BrowseAudio(ctrlKey) {
    path := FileSelect(3, , "Select an MP3", "Audio (*.mp3)")
    if (path != "" && UI.Ctrl.Has(ctrlKey))
        UI.Ctrl[ctrlKey].Value := path
}

BrowseLogo() {
    path := FileSelect(3, , "Select a PNG", "Images (*.png; *.jpg; *.bmp; *.gif)")
    if (path != "" && UI.Ctrl.Has("logoPath"))
        UI.Ctrl["logoPath"].Value := path
}

PresetCb(col) => (*) => SetAccent(col)

SetAccent(col) {
    UI.Ctrl["cAccent"].Value := col
    Paint(UI.Ctrl["cAccentSw"], col)
    SetTimer(ApplyTheme, -60)
}

LogPresetCb(col) => (*) => SetLogColor(col)

SetLogColor(col) {
    Log.TextColor := col
    if UI.Ctrl.Has("logColor")
        UI.Ctrl["logColor"].Value := col
    if UI.Ctrl.Has("logSwatch")
        Paint(UI.Ctrl["logSwatch"], col)
    if UI.Ctrl.Has("logView")
        UI.Ctrl["logView"].SetFont("c" . col)
    SaveIni()
    RefreshLogView()
}

ApplyLog() {
    if UI.Ctrl.Has("logColor") {
        v := Trim(UI.Ctrl["logColor"].Value)
        v := StrReplace(StrReplace(v, "0x"), "#")
        if RegExMatch(v, "^[0-9a-fA-F]{6}$")
            Log.TextColor := StrUpper(v)
    }
    if UI.Ctrl.Has("scOn")
        Theme.SelfCheck := ChkVal(UI.Ctrl["scOn"])
    if UI.Ctrl.Has("killKey") {
        Keys.Kill := UI.Ctrl["killKey"].Value
        ApplyHotkeys()
    }
    if UI.Ctrl.Has("logSwatch")
        Paint(UI.Ctrl["logSwatch"], Log.TextColor)
    if UI.Ctrl.Has("logView")
        UI.Ctrl["logView"].SetFont("c" . Log.TextColor)
    SaveIni()
    RefreshLogView()
    Flash("log settings applied")
}

ApplyFps() {
    key := UI.Ctrl["fpsConsoleKey"].Value
    Fps.ConsoleKey   := (key = "") ? "Tab" : key
    Fps.OpenDelayMs  := Num("fpsOpenDelay",  200, 0, 5000)
    Fps.CloseDelayMs := Num("fpsCloseDelay", 150, 0, 5000)
    FilterReadUI()
    AlertReadUI()
    ApplyHotkeys()
    SaveIni()
    Filter.Applied := "?"                  ; re-apply the filter with the new settings
    FilterTick()
    FilterStatus()
    Flash("game settings applied")
}

BrowseWall() {
    path := FileSelect(3, , "Select a wallpaper", "Images (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
    if (path != "" && UI.Ctrl.Has("wallPath"))
        UI.Ctrl["wallPath"].Value := path
}
