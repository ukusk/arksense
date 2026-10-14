; ArkSense - lib\Alerts.ahk
; Slide-in alert toasts: antidote giving up, server lag / loss / not answering,
; server found, layout and filter switches.
; Part of ArkSense.ahk; run that file, not this one.
;
; The smooth renderer draws and animates them (lib\ArkSenseOverlay.cs); with the
; classic renderer a plain fading window is used instead. Every alert also goes
; to the Logs tab. Alerts follow "Only in ARK": with it on, none pop up over
; other windows (they are still logged).

AlertColour(kind) => (kind = "ok") ? Theme.Ok : (kind = "bad") ? Theme.Bad
                   : (kind = "warn") ? "E6B800" : Theme.Accent

AlertPosNames() => ["Top right", "Bottom right", "Top left", "Bottom left", "Top centre"]
AlertPosCodes() => ["tr", "br", "tl", "bl", "tc"]

AlertPosName(code) {
    for i, c in AlertPosCodes() {
        if (c = code)
            return AlertPosNames()[i]
    }
    return "Top right"
}

AlertPosCode(name) {
    for i, n in AlertPosNames() {
        if (n = name)
            return AlertPosCodes()[i]
    }
    return "tr"
}

; id groups repeats for the cooldown (ms): the same alert can't pop up again sooner
Alert(id, kind, title, body := "", cooldown := 60000) {
    if (cooldown > 0 && Alerts.Last.Has(id) && A_TickCount - Alerts.Last[id] < cooldown)
        return
    Alerts.Last[id] := A_TickCount
    Logg("alert", title . ((body != "") ? " - " . body : ""))
    if !Alerts.On
        return
    if (Alerts.Sound && (kind = "bad" || kind = "warn"))
        try SoundPlay("*48")                            ; Windows' own warning sound
    if !OverlayAllowed()
        return
    if OvlOn() && OvlToast(kind, title, body)
        return
    ToastClassic(kind, title, body)
}

AlertTest(*) {
    AlertReadUI()
    Alert("test", "warn", "Test alert", "This is how alerts look and where they appear.", 0)
}

; ---- triggers ------------------------------------------------------------------
; Antidote.ahk: TryFire gave up after the maximum tries / Verify saw the buff land
AlertAntidote(gaveUp) {
    if !gaveUp {
        Alerts.Streak := 0
        return
    }
    Alerts.Streak += 1
    n := Alerts.AntiFail
    if (n > 0 && Alerts.Streak >= n && Mod(Alerts.Streak - n, n) = 0)
        Alert("anti", "bad", "Antidote failed " . Alerts.Streak . Chr(0x00D7),
              "Gave up after " . Cfg.MaxRetries . " tries, " . Alerts.Streak . " times in a row. "
            . "Check the scan area and the antidote key.", 0)
}

; Stats.ahk: a server was found / changed
AlertServerFound(addr) {
    if Alerts.Server
        Alert("found", "info", "ARK server found", addr, 20000)
}

; StatsTickCore, after every sample: lag, loss and "server not answering"
AlertNetTick() {
    if !StatNeed("ping")
        return
    q := Stats.Query
    ; lag: the server's own reply time over the limit for 3 samples in a row
    if (Alerts.LagMs > 0 && q >= 0) {
        if (q >= Alerts.LagMs) {
            Alerts.LagRun += 1
            if (Alerts.LagRun >= 3 && !Alerts.Lagging) {
                Alerts.Lagging := true
                Alert("lag", "warn", "Server lag " . q . " ms",
                      "The server has answered slower than " . Alerts.LagMs . " ms for 3 samples.", 45000)
            }
        } else {
            Alerts.LagRun := 0
            if (Alerts.Lagging && q < Alerts.LagMs * 0.8) {
                Alerts.Lagging := false
                Alert("lagok", "ok", "Server back to " . q . " ms", "", 45000)
            }
        }
    }
    ; loss: share of the last 30 samples with no answer
    h := (Stats.HistQuery.Length > 0) ? Stats.HistQuery : Stats.HistPing
    if (Alerts.LossPct > 0 && h.Length >= 10) {
        SeriesStats(h, &jit, &loss)
        if (loss >= Alerts.LossPct && !Alerts.Lossy) {
            Alerts.Lossy := true
            Alert("loss", "warn", "Packet loss " . loss . "%",
                  "Answers are missing over the last " . Min(30, h.Length) . " samples.", 60000)
        } else if (Alerts.Lossy && loss < Alerts.LossPct / 2) {
            Alerts.Lossy := false
        }
    }
    ; not answering: the query worked before, now 10 misses in a row
    if (Alerts.Server && Stats.QueryFound) {
        last := (Stats.HistQuery.Length > 0) ? Stats.HistQuery[Stats.HistQuery.Length] : -1
        if (last < 0) {
            Alerts.Silent += 1
            if (Alerts.Silent >= 10 && !Alerts.Down) {
                Alerts.Down := true
                Alert("down", "bad", "Server not answering",
                      "No reply to the server query for 10 samples - it may be frozen or restarting.", 120000)
            }
        } else {
            Alerts.Silent := 0
            if Alerts.Down {
                Alerts.Down := false
                Alert("up", "ok", "Server answering again", "", 30000)
            }
        }
    }
}

; ---- settings (Game tab) ---------------------------------------------------------
AlertReadUI() {
    if !UI.Ctrl.Has("alertOn")
        return
    Alerts.On       := ChkVal(UI.Ctrl["alertOn"])
    Alerts.AntiFail := Num("alertAnti", 2, 0, 50)
    Alerts.LagMs    := Num("alertLag", 150, 0, 5000)
    Alerts.LossPct  := Num("alertLoss", 20, 0, 100)
    Alerts.Server   := ChkVal(UI.Ctrl["alertServer"])
    Alerts.Feedback := ChkVal(UI.Ctrl["alertFeedback"])
    Alerts.Sound    := ChkVal(UI.Ctrl["alertSound"])
    Alerts.Pos      := AlertPosCode(DropValue("alertPos", "Top right"))
    Alerts.Secs     := Num("alertSecs", 4, 2, 10)
    OvlTheme()                                          ; the helper needs the new corner
}

; ---- classic renderer: a simple fading window ------------------------------------
ToastClassic(kind, title, body) {
    OvlToastArea(&l, &t, &r, &b)
    w := 320, h := (body = "") ? 44 : 66
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000 -DPIScale")   ; click-through, no focus
    StreamHide(g.Hwnd, "overlay")
    g.BackColor := Theme.Panel2
    g.MarginX := 0
    g.MarginY := 0
    Paint(g.Add("Text", "x0 y0 w5 h" . h), AlertColour(kind))
    g.SetFont("s10 Bold", Theme.FontName)
    Paint(g.Add("Text", "x18 y" . ((body = "") ? 12 : 9) . " w292 h20 +0x200", title), Theme.Panel2, Theme.Text)
    if (body != "") {
        g.SetFont("s8 Norm", Theme.FontName)
        Paint(g.Add("Text", "x18 y31 w292 h32", body), Theme.Panel2, Theme.Dim)
    }
    g.Show("x" . (r - w - 24) . " y" . (t + 24) . " w" . w . " h" . h . " NoActivate Hide")
    rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w + 1, "Int", h + 1,
                   "Int", 14, "Int", 14, "Ptr")
    if (rgn && !DllCall("user32\SetWindowRgn", "Ptr", g.Hwnd, "Ptr", rgn, "Int", 1))
        DllCall("gdi32\DeleteObject", "Ptr", rgn)
    WinSetTransparent(0, "ahk_id " . g.Hwnd)
    Alerts.Classic.InsertAt(1, {g: g, h: h, w: w, a: 0, till: A_TickCount + Alerts.Secs * 1000,
                                l: l, t: t, r: r, b: b})
    Loop Max(0, Alerts.Classic.Length - 4)          ; more than 4: the oldest fade out
        Alerts.Classic[4 + A_Index].till := 0
    ToastClassicPlace()
    SetTimer(ToastClassicTick, 30)
}

ToastClassicPlace() {
    acc := 0
    for x in Alerts.Classic {
        pos := Alerts.Pos
        tx := (pos = "tl" || pos = "bl") ? x.l + 24 : (pos = "tc") ? (x.l + x.r - x.w) // 2 : x.r - x.w - 24
        ty := (pos = "br" || pos = "bl") ? x.b - 24 - x.h - acc : x.t + 24 + acc
        try x.g.Show("x" . tx . " y" . ty . " NoActivate")
        acc += x.h + 10
    }
}

ToastClassicTick() {
    keep := []
    gone := false
    for x in Alerts.Classic {
        target := (A_TickCount < x.till) ? 235 : 0
        x.a := (x.a < target) ? Min(target, x.a + 45) : Max(target, x.a - 30)
        try WinSetTransparent(x.a, "ahk_id " . x.g.Hwnd)
        if (x.a = 0 && target = 0) {
            try {
                for hwnd, ctl in x.g {                  ; forget their paint entries
                    if UI.CustomBg.Has(ctl.Hwnd)
                        UI.CustomBg.Delete(ctl.Hwnd)
                    if UI.CustomFg.Has(ctl.Hwnd)
                        UI.CustomFg.Delete(ctl.Hwnd)
                }
            }
            try x.g.Destroy()
            gone := true
            continue
        }
        keep.Push(x)
    }
    Alerts.Classic := keep
    if gone
        ToastClassicPlace()
    if (keep.Length = 0)
        SetTimer(ToastClassicTick, 0)
}
