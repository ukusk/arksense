; ArkSense - lib\Stats.ahk
; System stats samplers (CPU/RAM/GPU helper) and the stats overlay window.
; Part of ArkSense.ahk; run that file, not this one.

; ---- System stats -----------------------------------------------------------
StatTxt(v, unit) => (v < 0) ? "n/a" : v . unit

; GetSystemTimes kernel time already includes idle, so busy = (k+u) - idle
CpuPct() {
    static pIdle := 0, pBusy := 0
    i := Buffer(8), k := Buffer(8), u := Buffer(8)
    if !DllCall("kernel32\GetSystemTimes", "Ptr", i, "Ptr", k, "Ptr", u)
        return -1
    idle := NumGet(i, 0, "Int64")
    busy := NumGet(k, 0, "Int64") + NumGet(u, 0, "Int64")
    dI := idle - pIdle, dB := busy - pBusy
    pIdle := idle, pBusy := busy
    if (dB <= 0)
        return -1
    return Max(0, Min(100, Round(100 * (dB - dI) / dB)))
}

RamPct() {
    m := Buffer(64, 0)
    NumPut("UInt", 64, m, 0)
    return DllCall("kernel32\GlobalMemoryStatusEx", "Ptr", m) ? NumGet(m, 4, "UInt") : -1
}

; system-wide GPU load = sum of the 3D-engine "Utilization Percentage" instances,
; the same data Task Manager shows. WMI (cooked, via a refresher) is tried first
; because it needs no struct marshaling or manual delta; PDH is the fallback for
; boxes where the WMI perf class is missing. -1 (n/a) only if BOTH are unavailable,
; which means this machine doesn't publish GPU counters at all.
; WMI only. The old PDH fallback walked a variable-size counter array with raw
; pointer arithmetic; a wrong offset there is an access violation, which kills the
; process outright - no error dialog, no log, nothing to diagnose. WMI is pure COM
; and cannot corrupt the process, so a machine that will not report GPU simply
; shows n/a instead of taking the app down.
; The WMI GPU query must NOT run on this thread. It returns one entry per GPU
; engine per process (often hundreds), each property read is a cross-process
; call, and the first connection can take seconds while Windows loads its perf
; libraries. Run every second on the GUI thread, it blocked the menu solid - the
; freeze on launch. So a tiny helper AutoHotkey process does the query and writes
; the number to a temp file; this side only reads that file, which cannot block.
GpuPct() {
    if (!Stats.GpuPid || !ProcessExist(Stats.GpuPid)) {
        Stats.GpuPid := 0
        GpuHelperStart()
        throw Error("GPU helper starting")
    }
    path := A_Temp . "\ArkSense-gpu.txt"
    if !FileExist(path)
        throw Error("waiting for the first GPU sample")
    age := DateDiff(A_Now, FileGetTime(path, "M"), "Seconds")
    if (age > 10)
        throw Error("GPU sample is " . age . " s old")
    v := Integer(Trim(FileRead(path)))
    if (v < 0)
        throw Error("this system publishes no WMI GPU engine counters")
    return v
}

GpuHelperStart() {
    if (A_TickCount < Stats.GpuRetryAt)          ; never respawn in a tight loop
        return
    Stats.GpuRetryAt := A_TickCount + 30000
    try {
        ex := ComObject("WScript.Shell").Exec('"' . A_AhkPath . '" /ErrorStdOut *')
        ex.StdIn.Write(GpuHelperScript(ProcessExist()))
        ex.StdIn.Close()
        Stats.GpuPid := ex.ProcessID
        Logg("stats", "GPU helper started (pid " . Stats.GpuPid . ")")
    } catch as e {
        Stats.GpuPid := 0
        Logg("stats", "GPU helper failed to start: " . e.Message)
    }
}

GpuHelperStop() {
    if Stats.GpuPid
        try ProcessClose(Stats.GpuPid)
    Stats.GpuPid := 0
}

; the helper's whole script, fed over stdin. It exits by itself once this
; process is gone, and swallows its own errors so it can never show a dialog.
GpuHelperScript(parentPid) {
    lines := [
        '#Requires AutoHotkey v2.0',
        '#NoTrayIcon',
        'OnError(Quiet)',
        'out := A_Temp . "\ArkSense-gpu.txt"',
        'pid := ' . parentPid,
        'ref := 0',
        'coll := 0',
        'while ProcessExist(pid) {',
        '    v := -1',
        '    try {',
        '        if !IsObject(ref) {',
        '            ref := ComObject("WbemScripting.SWbemRefresher")',
        '            svc := ComObjGet("winmgmts:\\.\root\cimv2")',
        '            coll := ref.AddEnum(svc, "Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine").ObjectSet',
        '        }',
        '        ref.Refresh()',
        '        t := 0.0',
        '        for o in coll {',
        '            if InStr(o.Name, "engtype_3D")',
        '                t += o.UtilizationPercentage',
        '        }',
        '        v := Min(100, Round(t))',
        '    } catch {',
        '        ref := 0',
        '        coll := 0',
        '    }',
        '    try {',
        '        f := FileOpen(out, "w")',
        '        f.Write(v)',
        '        f.Close()',
        '    }',
        '    Sleep 2000',
        '}',
        'ExitApp',
        'Quiet(*) {',
        '    return 1',
        '}'
    ]
    txt := ""
    for ln in lines
        txt .= ln . "`n"
    return txt
}

; keep a bounded rolling history for the sparkline; skip n/a samples
StatPush(hist, v) {
    if (v < 0)
        return
    hist.Push(v)
    while (hist.Length > 20)
        hist.RemoveAt(1)
}

; run a sampler and keep the reason it failed, rather than swallowing it - a bare
; try here is what turned every fault into a permanent, unexplained "n/a".
SafeSample(key, fn) {
    try {
        v := fn()
        Stats.Err[key] := ""
        return v
    } catch as e {
        Stats.Err[key] := Type(e) . ": " . e.Message
        return -1
    }
}

StatsTick() {
    try StatsTickCore()
}

StatsTickCore() {
    ; what is measured follows the shown style: the graph card's toggles, or the bar's
    if (!StatNeed("gpu") && Stats.GpuPid)        ; GPU turned off: stop the helper
        GpuHelperStop()
    if (!StatNeed("ping") && Stats.PingPid)      ; same for the ping helper
        PingHelperStop()
    if ((!StatNeed("ping") || !QueryActive()) && Stats.QueryPid)
        QueryHelperStop()
    if !(StatNeed("clock") || StatNeed("cpu") || StatNeed("ram") || StatNeed("gpu") || StatNeed("ping")
         || StatNeed("fps"))
        return
    if StatNeed("cpu") {
        Stats.Cpu := SafeSample("cpu", CpuPct)
        StatPush(Stats.HistCpu, Stats.Cpu)
    }
    if StatNeed("ram") {
        Stats.Ram := SafeSample("ram", RamPct)
        StatPush(Stats.HistRam, Stats.Ram)
    }
    if StatNeed("gpu") {
        Stats.Gpu := SafeSample("gpu", GpuPct)
        StatPush(Stats.HistGpu, Stats.Gpu)
    }
    if StatNeed("ping") {
        static lastTarget := ""
        if Stats.PingAuto
            try ServerDetectTick()
        if (PingTarget() != lastTarget) {
            if (lastTarget != "")
                PingRestart()
            lastTarget := PingTarget()
        }
        Stats.Ping := SafeSample("ping", PingRead)
        if QueryActive() {
            Stats.Query := SafeSample("query", QueryRead)
        } else {
            Stats.Query := -1
            Stats.HistQuery := []
            Stats.Err["query"] := "waiting for the server address"
        }
    }
    if StatNeed("fps") {
        try FpsTick()
    } else if Stats.FpsPid {
        FpsHelperStop()
    }
    try AlertNetTick()
    RefreshStatHud()
    RefreshStatInfo()
}

; sample all three right now, ignoring the toggles, and report what happened
StatSelfTest() {
    Stats.Cpu := SafeSample("cpu", CpuPct)
    Stats.Ram := SafeSample("ram", RamPct)
    Stats.Gpu := SafeSample("gpu", GpuPct)
    Stats.Ping := SafeSample("ping", PingRead)
    if QueryActive()
        Stats.Query := SafeSample("query", QueryRead)
    txt := "self-test  (a first CPU/GPU read can be -1 until a second sample)`r`n`r`n"
    for key in ["cpu", "ram", "gpu", "ping", "query"] {
        v := StatValue(key)
        txt .= Format("{:-6}", StrUpper(key)) . Format("{:-8}", StatTxt(v, (key = "ping" || key = "query") ? " ms" : "%"))
             . ((Stats.Err[key] != "") ? Stats.Err[key] : "ok") . "`r`n"
    }
    txt .= "`r`ntimer every " . Stats.IntervalSec . "s   card "
         . (OvlOn() ? "drawn by the smooth renderer" : (UI.StatHud != "") ? "built" : "not built")
    if UI.Ctrl.Has("statInfo")
        UI.Ctrl["statInfo"].Value := txt
}

; ---- Stats overlay: a separate click-through window, one coloured row per stat
ClockTxt() => FormatTime(, "HH:mm")

; threshold colour: n/a grey, <60 green, 60-89 amber, >=90 red
StatColour(v) => (v < 0) ? OvC("Dim") : (v >= 90) ? OvC("Bad") : (v >= 60) ? "E6B800" : OvC("Ok")










RefreshStatInfo() {
    if (Anim.Busy || !UI.Ctrl.Has("statInfo"))
        return
    txt := ""
    for key in ["cpu", "ram", "gpu", "ping", "query"] {
        v := StatValue(key)
        on := StatNeed((key = "query") ? "ping" : key)
        txt .= Format("{:-6}", StrUpper(key)) . Format("{:-8}", StatTxt(v, (key = "ping" || key = "query") ? " ms" : "%"))
             . ((Stats.Err[key] != "") ? Stats.Err[key] : (on ? "" : "(toggle off)")) . "`r`n"
    }
    nv := NetView()
    txt .= "CARD  " . Format("{:-8}", StatTxt(nv.ping, " ms"))
         . (nv.qOk ? (nv.fromQuery ? "fastest server reply (lower than icmp " . StatTxt(nv.icmp, "") . ")"
                                   : "icmp ping (query floor not lower)")
                   : "icmp ping only - no server query answer yet") . "`r`n"
    txt .= "PLAYERS " . ((Stats.Players >= 0) ? Stats.Players . " / " . Stats.MaxPlayers
           : (Stats.QueryHow = "other-server") ? "n/a - the query port found is another server on this machine (Logs)"
           : "n/a - needs the server query (see QUERY)") . "`r`n"
    txt .= "FPS   " . Format("{:-8}", StatTxt(Stats.Fps, ""))
         . (!StatNeed("fps") ? "(toggle off)" : (Stats.FpsInfo != "") ? Stats.FpsInfo : "") . "`r`n"
    txt .= "SERVER " . ServerTxt() . ((Stats.QueryInfo != "") ? "  " . Stats.QueryInfo : "")
    try UI.Ctrl["statInfo"].Value := txt
    if UI.Ctrl.Has("pingServer") {
        c := UI.Ctrl["pingServer"]
        c.Text := "server   " . ServerTxt()
        Paint(c, "", (Stats.PingAuto && Stats.Server != "") ? Theme.Ok : Theme.Dim)
    }
}

StatValue(key) => (key = "cpu") ? Stats.Cpu : (key = "ram") ? Stats.Ram
                : (key = "gpu") ? Stats.Gpu : (key = "query") ? Stats.Query : Stats.Ping

; ---- Network ping: a helper process, like the GPU sampler -----------------------
; Win32_PingStatus blocks for up to its timeout, so it runs in a separate tiny
; AutoHotkey process that pings once a second and writes its last 60 results to a
; temp file (comma list; -1 = no answer, -2 = query failed). This side only reads
; the file, which cannot block the menu. No raw memory, no struct marshaling.

; only plain host names / IPs reach the helper's source text
PingHostSafe() => (SafeHost(Stats.PingHost) != "") ? Stats.PingHost : "1.1.1.1"

PingHelperStart() {
    if (A_TickCount < Stats.PingRetryAt)         ; never respawn in a tight loop
        return
    Stats.PingRetryAt := A_TickCount + 30000
    try {
        ex := ComObject("WScript.Shell").Exec('"' . A_AhkPath . '" /ErrorStdOut *')
        ex.StdIn.Write(PingHelperScript(ProcessExist(), PingTarget()))
        ex.StdIn.Close()
        Stats.PingPid := ex.ProcessID
        Logg("stats", "ping helper started (pid " . Stats.PingPid . ", host " . PingTarget() . ")")
    } catch as e {
        Stats.PingPid := 0
        Logg("stats", "ping helper failed to start: " . e.Message)
    }
}

PingHelperStop() {
    if Stats.PingPid
        try ProcessClose(Stats.PingPid)
    Stats.PingPid := 0
}

; the helper's whole script, fed over stdin. It exits by itself once this
; process is gone, and swallows its own errors so it can never show a dialog.
PingHelperScript(parentPid, host) {
    lines := [
        '#Requires AutoHotkey v2.0',
        '#NoTrayIcon',
        'OnError(Quiet)',
        'out := A_Temp . "\ArkSense-ping.txt"',
        'pid := ' . parentPid,
        'host := "' . host . '"',
        'q := Chr(39)',
        'hist := []',
        'svc := 0',
        'while ProcessExist(pid) {',
        '    t0 := A_TickCount',
        '    v := -2',
        '    try {',
        '        if !IsObject(svc)',
        '            svc := ComObjGet("winmgmts:\\.\root\cimv2")',
        '        v := -1',
        '        for o in svc.ExecQuery("SELECT StatusCode, ResponseTime FROM Win32_PingStatus WHERE Address=" . q . host . q . " AND Timeout=1000") {',
        '            if (o.StatusCode = 0)',
        '                v := o.ResponseTime',
        '        }',
        '    } catch {',
        '        svc := 0',
        '        v := -2',
        '    }',
        '    hist.Push(v)',
        '    while (hist.Length > 60)',
        '        hist.RemoveAt(1)',
        '    txt := ""',
        '    for i, x in hist',
        '        txt .= ((i = 1) ? "" : ",") . x',
        '    try {',
        '        f := FileOpen(out, "w")',
        '        f.Write(txt)',
        '        f.Close()',
        '    }',
        '    left := 1000 - (A_TickCount - t0)',
        '    if (left > 0)',
        '        Sleep left',
        '}',
        'ExitApp',
        'Quiet(*) {',
        '    return 1',
        '}'
    ]
    txt := ""
    for ln in lines
        txt .= ln . "`n"
    return txt
}

; latest ping in ms; refreshes Stats.HistPing from the helper's file. Throws (with
; the reason) when there is no fresh answer, so SafeSample can show why.
PingRead() {
    if (!Stats.PingPid || !ProcessExist(Stats.PingPid)) {
        Stats.PingPid := 0
        PingHelperStart()
        throw Error("ping helper starting")
    }
    path := A_Temp . "\ArkSense-ping.txt"
    if !FileExist(path)
        throw Error("waiting for the first ping")
    age := DateDiff(A_Now, FileGetTime(path, "M"), "Seconds")
    if (age > 6)
        throw Error("ping sample is " . age . " s old")
    hist := []
    for s in StrSplit(Trim(FileRead(path)), ",") {
        if (s != "")
            hist.Push(Integer(s))
    }
    if (hist.Length = 0)
        throw Error("waiting for the first ping")
    Stats.HistPing := hist
    v := hist[hist.Length]
    if (v = -2)
        throw Error("ping query failed")
    if (v = -1)
        throw Error("no answer from " . PingTarget())
    return v
}


PingColour(ms) => (ms < 0) ? OvC("Bad") : (ms >= 150) ? OvC("Bad") : (ms >= 80) ? "E6B800" : OvC("Ok")

; ---- Stats card: one movable, resizable box ---------------------------------------
; Top row: CPU / RAM / GPU / clock. Below: the ping graph with the latest value at
; its right end, and a PING / JITTER / LOSS line under it.
;
; Why it is drawn, not built from controls: the first version moved ~120 Static
; controls every second and each repainted on its own, so the see-through window
; showed half-painted frames - the flash. Now every update is drawn off-screen into
; one bitmap and handed to Windows in a single UpdateLayeredWindow call, so the
; screen only ever shows a finished frame. All GDI calls take plain numbers or a
; handle; the only buffers are three tiny input-only ones for UpdateLayeredWindow
; (size, source point, blend) and the 8-byte text-size buffer.
;
; The card joins the overlay's EDIT LAYOUT (or MOVE / RESIZE on its own group):
; drag to move, the corner triangle to resize; LOCK saves it as Pill.Pos["stats"].

CardMetrics() {
    out := []
    if Stats.ShowCpu
        out.Push("cpu")
    if Stats.ShowRam
        out.Push("ram")
    if Stats.ShowGpu
        out.Push("gpu")
    if Stats.ShowClock
        out.Push("clock")
    return out
}

BuildStatHud() {
    try BuildStatHudCore()
    catch as e {
        CardDestroy()                 ; never leave a half-built window behind
        Flash("stats card error: " . e.Message)
    }
}

BuildStatHudCore() {
    if OvlOn() {                          ; smooth renderer draws it; nothing to build here
        Card.Order := CardMetrics()
        Card.Graph := Stats.ShowPing
        Card.Size  := 0
        RefreshStatHud()
        return
    }
    metrics := CardMetrics()
    if (metrics.Length = 0 && !Stats.ShowPing && !Stats.Bar)
        return                        ; nothing to show: no window at all
    ; WS_EX_LAYERED (0x80000) and never SetLayeredWindowAttributes: the window's
    ; whole picture comes from UpdateLayeredWindow. +E0x20 = click-through.
    h := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")
    h.MarginX := 0
    h.MarginY := 0
    Card.Order := metrics
    Card.Graph := Stats.ShowPing
    Card.Size  := 0
    UI.StatHud := h
    ApplyStreamerMode()
    RefreshStatHud()
}

; clear the handle FIRST, then destroy - StatsTick can fire in between
CardDestroy() {
    old := UI.StatHud
    UI.StatHud := ""
    CardBaseFree()                    ; the clantag's saved copy of the card
    if (old != "")
        try old.Destroy()
}

RebuildStatHud() {
    CardDestroy()
    BuildStatHud()
}

; card size + where it sits: saved by LOCK, else the defaults
CardWant(&x, &y, &size) {
    if Pill.Pos.Has("stats") {
        x := Pill.Pos["stats"][1], y := Pill.Pos["stats"][2], size := Pill.Pos["stats"][3]
    } else {
        x := Stats.HudX, y := Stats.HudY, size := Stats.HudFontSize
    }
}

; ---- small GDI helpers (plain numbers and handles only) ---------------------------
GdiFont(pt, bold, face) => DllCall("gdi32\CreateFontW", "Int", -Round(pt * A_ScreenDPI / 72),
    "Int", 0, "Int", 0, "Int", 0, "Int", bold ? 700 : 400, "UInt", 0, "UInt", 0, "UInt", 0,
    "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0, "Str", face, "Ptr")

GdiTextSize(hdc, font, s, &w, &h) {
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", font, "Ptr")
    sz := Buffer(8, 0)
    w := StrLen(s) * 8, h := 16
    if DllCall("gdi32\GetTextExtentPoint32W", "Ptr", hdc, "Str", s, "Int", StrLen(s), "Ptr", sz) {
        w := NumGet(sz, 0, "Int")
        h := NumGet(sz, 4, "Int")
    }
}

GdiText(hdc, font, s, x, y, col) {
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", font, "Ptr")
    DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", BGR(col))
    DllCall("gdi32\TextOutW", "Ptr", hdc, "Int", x, "Int", y, "Str", s, "Int", StrLen(s))
}

GdiFill(hdc, x, y, w, h, col) {
    if (w <= 0 || h <= 0)
        return
    br  := DllCall("gdi32\CreateSolidBrush", "UInt", BGR(col), "Ptr")
    old := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", br, "Ptr")
    DllCall("gdi32\PatBlt", "Ptr", hdc, "Int", x, "Int", y, "Int", w, "Int", h, "UInt", 0xF00021) ; PATCOPY
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    DllCall("gdi32\DeleteObject", "Ptr", br)
}

GdiLine(hdc, x1, y1, x2, y2, col, w) {
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", w, "UInt", BGR(col), "Ptr")
    old := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
    DllCall("gdi32\MoveToEx", "Ptr", hdc, "Int", x1, "Int", y1, "Ptr", 0)
    DllCall("gdi32\LineTo", "Ptr", hdc, "Int", x2, "Int", y2)
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    DllCall("gdi32\DeleteObject", "Ptr", pen)
}

; rounded box; fillCol "" = no fill, penW 0 = no outline (outline stays inside)
GdiRound(hdc, x1, y1, x2, y2, d, fillCol, penCol, penW) {
    br  := (fillCol = "") ? DllCall("gdi32\GetStockObject", "Int", 5, "Ptr")          ; NULL_BRUSH
                          : DllCall("gdi32\CreateSolidBrush", "UInt", BGR(fillCol), "Ptr")
    pen := (penW <= 0) ? DllCall("gdi32\GetStockObject", "Int", 8, "Ptr")              ; NULL_PEN
                       : DllCall("gdi32\CreatePen", "Int", 6, "Int", penW, "UInt", BGR(penCol), "Ptr") ; INSIDEFRAME
    ob := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", br, "Ptr")
    op := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
    ; a NULL pen leaves the right/bottom edge undrawn, so grow the box by one
    g  := (penW <= 0) ? 1 : 0
    DllCall("gdi32\RoundRect", "Ptr", hdc, "Int", x1, "Int", y1, "Int", x2 + g, "Int", y2 + g,
            "Int", d, "Int", d)
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", ob, "Ptr")
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", op, "Ptr")
    if (fillCol != "")
        DllCall("gdi32\DeleteObject", "Ptr", br)
    if (penW > 0)
        DllCall("gdi32\DeleteObject", "Ptr", pen)
}

; hand the finished bitmap to Windows in one call. The key colour turns
; see-through, alpha is the overlay opacity. Input-only buffers of fixed size.
CardPush(win, mem, w, h, alpha) {
    static warned := false
    sz := Buffer(8, 0), src := Buffer(8, 0), bl := Buffer(4, 0)
    NumPut("Int", w, sz, 0), NumPut("Int", h, sz, 4)
    NumPut("UChar", alpha, bl, 2)                   ; BLENDFUNCTION.SourceConstantAlpha
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    ok := DllCall("user32\UpdateLayeredWindow", "Ptr", win.Hwnd, "Ptr", scr, "Ptr", 0, "Ptr", sz,
                  "Ptr", mem, "Ptr", src, "UInt", BGR(Pill.KeyCol), "Ptr", bl, "UInt", 3) ; COLORKEY|ALPHA
    if !ok {                                        ; fall back to the key colour alone
        err := A_LastError
        ok := DllCall("user32\UpdateLayeredWindow", "Ptr", win.Hwnd, "Ptr", scr, "Ptr", 0, "Ptr", sz,
                      "Ptr", mem, "Ptr", src, "UInt", BGR(Pill.KeyCol), "Ptr", bl, "UInt", 1)
        if !warned {
            warned := true
            Logg("stats", "card: opacity not supported here (error " . err . "), drawing opaque"
                        . (ok ? "" : " - and that failed too"))
        }
    }
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    return ok
}

; the card's three fonts for one size, kept between draws (step 20: the card is redrawn
; every second and used to make and delete three fonts each time). Cleared on a font change
; or when more than 8 sizes pile up (resizing).
CardFonts(size, &fS, &fB, &fG) {
    static cache := Map(), face := ""
    if (face != Theme.FontName || cache.Count > 8) {
        for k, v in cache
            for fo in v
                DllCall("gdi32\DeleteObject", "Ptr", fo)
        cache.Clear()
        face := Theme.FontName
    }
    if !cache.Has(size)
        cache[size] := [GdiFont(Max(6, Round(size * 0.75)), true, Theme.FontName),
                        GdiFont(Max(7, Round(size * 1.3)), true, Theme.FontName),
                        GdiFont(Max(6, size), false, "Segoe UI Symbol")]
    fS := cache[size][1], fB := cache[size][2], fG := cache[size][3]
}

; Draw the whole card at font size `size` and push it to the window.
CardDraw(size) {
    if Stats.Bar
        return BarDraw(size)          ; the stats bar style (lib\Bar.ahk)
    win := UI.StatHud
    if (win = "")
        return false
    editing := CardEditing()
    f      := size / 10
    pad    := Round(10 * f), gap := Round(8 * f), corner := Max(6, Round(14 * f))
    W      := Round(240 * f)
    filled := Theme.HudBgOn || editing
    fill   := filled ? OvC("Panel2") : Pill.KeyCol
    b      := (Theme.HudBorderOn || editing) ? Max(1, Round(f)) : 0
    outline := editing ? OvC("Accent") : (Card.FxCol != "") ? Card.FxCol : Theme.HudBorderColor
    alpha  := editing ? Max(170, Theme.HudBgOpacity) : Theme.HudBgOpacity
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
    CardFonts(size, &fS, &fB, &fG)
    bmp := 0, oldBmp := 0
    oldFont := DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", fS, "Ptr")
    try {
        ; ---- measure and lay out
        GdiTextSize(mem, fS, "GPU", &lw, &lh)
        GdiTextSize(mem, fB, "100%", &vw, &vh)
        y := pad
        tagOn := CtOnCard()
        Card.Chip := ""
        if tagOn {                                   ; clantag: its own line at the top
            L := CtCardLayout(mem, size)
            ; its own box (step 25): the clantag's outline, and its background when solid
            ; enough to show on this card (the card's opacity applies to the whole card)
            cpx := (Ct.Outline || Ct.Alpha >= 128) ? Round(6 * f) : 0
            cpy := cpx ? Round(2 * f) : 0
            Card.TagX := pad + cpx, Card.TagY := y + cpy
            if cpx
                Card.Chip := [pad, y, pad + L.w + 2 * cpx, y + L.h + 2 * cpy]
            y += L.h + 2 * cpy + Round(6 * f)
            W := Max(W, Round(2 * pad + L.w + 2 * cpx))
        }
        cellY := y
        if (Card.Order.Length > 0)
            y += lh + vh + gap
        if Card.Graph {
            GdiTextSize(mem, fS, "999", &tw, &th)
            gx := pad, gy := y, gh := Round(56 * f)
            gw := W - 2 * pad - tw - Round(8 * f)
            y += gh + Round(6 * f)
            footY := y
            y += th * 2 + Round(2 * f)               ; PING/JITTER/LOSS, then SERVER
        }
        H := y + pad
        GdiTextSize(mem, fG, Chr(0x25E2), &grw, &grh)
        Card.GripX := W - grw - Round(5 * f), Card.GripY := H - grh - Round(3 * f)

        bmp := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", scr, "Int", W, "Int", H, "Ptr")
        oldBmp := DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr")
        DllCall("gdi32\SetBkMode", "Ptr", mem, "Int", 1)              ; TRANSPARENT text

        ; ---- body
        GdiFill(mem, 0, 0, W, H, Pill.KeyCol)
        if (filled || b > 0)
            GdiRound(mem, 0, 0, W, H, corner, filled ? fill : "", outline, b)

        ; ---- the clantag's box (the letters go on per frame, see CardTagDraw)
        if (tagOn && IsObject(Card.Chip)) {
            cr := Card.Chip
            GdiRound(mem, cr[1], cr[2], cr[3], cr[4], cr[4] - cr[2], (Ct.Alpha >= 128) ? Ct.BgColor : "",
                     Ct.OutlineColor, Ct.Outline ? Max(1, Round(f)) : 0)
        }

        ; ---- top row
        if (Card.Order.Length > 0) {
            cw := (W - 2 * pad) / Card.Order.Length
            for i, key in Card.Order {
                cx := pad + Round((i - 1) * cw)
                lbl := (key = "clock") ? "TIME" : StrUpper(key)
                if (key = "clock") {
                    val := ClockTxt(), col := Theme.HudTextColor
                } else {
                    v := StatValue(key)
                    val := StatTxt(v, "%"), col := StatColour(v)
                }
                GdiTextSize(mem, fS, lbl, &a, &bh)
                GdiText(mem, fS, lbl, cx + (Round(cw) - a) // 2, cellY, OvC("Dim"))
                GdiTextSize(mem, fB, val, &a, &bh)
                GdiText(mem, fB, val, cx + (Round(cw) - a) // 2, cellY + lh, col)
            }
        }

        ; ---- ping graph
        if Card.Graph
            CardGraph(mem, fS, gx, gy, gw, gh, tw, th, footY, W, pad, f, fill, filled)

        ; ---- resize grip while editing
        if editing
            GdiText(mem, fG, Chr(0x25E2), Card.GripX, Card.GripY, OvC("Accent"))

        ; ---- clantag: keep the card as it is now, then draw the tag's current frame
        if tagOn {
            CardBaseSave(mem, W, H)
            CardTagDraw(mem)
        } else if Card.BaseDC {
            CardBaseFree()
        }
        Card.Alpha := alpha

        Card.W := W, Card.H := H, Card.Size := size
        CardPush(win, mem, W, H, alpha)
    } finally {
        if oldBmp
            DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", oldBmp, "Ptr")
        DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", oldFont, "Ptr")
        if bmp
            DllCall("gdi32\DeleteObject", "Ptr", bmp)
        DllCall("gdi32\DeleteDC", "Ptr", mem)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    }
    return true
}

; jitter = average change between consecutive answers; loss = share of the last
; 30 samples without one. -1 when there is nothing to measure yet.
SeriesStats(h, &jit, &loss) {
    jit := -1, loss := -1
    if (h.Length = 0)
        return
    first := Max(1, h.Length - 29)
    n := 0, lost := 0, sum := 0, cnt := 0, prev := ""
    Loop h.Length - first + 1 {
        v := h[first + A_Index - 1]
        n += 1
        if (v < 0) {
            lost += 1
            continue
        }
        if (prev != "") {
            sum += Abs(v - prev)
            cnt += 1
        }
        prev := v
    }
    jit  := cnt ? Round(sum / cnt) : -1
    loss := Round(100 * lost / n)
}

; ---- What the graph and its numbers show (step 15) ---------------------------------
; PING should match the game's own ping. Two measurements exist:
;  - ICMP ping: answered by whatever sits at the server's address. On FusionPvP it reads
;    a flat 48 ms (jitter 0) while ARK shows 28 - those pings take a slow path that
;    game traffic doesn't, so on its own it can't be trusted.
;  - Steam query (UDP, the server-browser packet): travels like game traffic, but the
;    server only answers between its game frames, so each reply = round trip + 0..1
;    frame. The FASTEST reply of the last 5 s is the round trip (+ a few ms).
; So per second PING = the lower of the ICMP ping and that query floor; with no query
; it is the ICMP ping alone. The raw query reply stays on the graph as the faint SERVER
; line (it rises when the server lags) and the lag alert still watches it.
HasAnswer(h, last := 30) {
    first := Max(1, h.Length - last + 1)
    Loop h.Length - first + 1 {
        if (h[first + A_Index - 1] >= 0)
            return true
    }
    return false
}

LastOf(h) => (h.Length > 0) ? h[h.Length] : -1

; fastest query reply among samples i-4 .. i (newest last), -1 if none answered
QueryFloorAt(q, i) {
    best := -1
    Loop 5 {
        k := i - A_Index + 1
        if (k >= 1 && k <= q.Length && q[k] >= 0)
            best := (best < 0) ? q[k] : Min(best, q[k])
    }
    return best
}

; the PING series: per second the lower of the ICMP ping and the query floor (both
; histories end "now", so they are lined up from the right)
PingSeries(p, q, &fromQuery) {
    n := Max(p.Length, q.Length)
    out := [], fromQuery := false
    Loop n {
        i := A_Index
        icmp := (p.Length - n + i >= 1) ? p[p.Length - n + i] : -1
        fl := QueryFloorAt(q, q.Length - n + i)
        if (icmp >= 0 && fl >= 0)
            v := Min(icmp, fl)
        else
            v := (icmp >= 0) ? icmp : fl
        out.Push(v)
        if (i = n)
            fromQuery := (fl >= 0 && (icmp < 0 || fl < icmp))
    }
    return out
}

NetView() {
    p := Stats.HistPing, q := Stats.HistQuery
    qOk := HasAnswer(q)
    main := qOk ? PingSeries(p, q, &fromQuery) : p
    if !qOk
        fromQuery := false
    v := {main: main, faint: qOk ? q : [], ping: LastOf(main), server: LastOf(q), qOk: qOk,
          icmp: LastOf(p), fromQuery: fromQuery}
    SeriesStats(v.main, &jit, &loss)
    v.jit := jit, v.loss := loss
    v.tag := (v.ping >= 0) ? String(v.ping) : "--"
    v.foot := "PING " . MsTxt(v.ping)
            . (qOk ? "  SERVER " . ((v.server >= 0) ? v.server : "--") : "")
            . "  JIT " . ((jit >= 0) ? jit : "--") . "  LOSS " . ((loss >= 0) ? loss . "%" : "--")
    fps := (Stats.ShowFps && Stats.HistFps.Length > 0) ? Stats.Fps : ""
    pl := ""
    if (Stats.ShowPlayers && Stats.Players >= 0)
        pl := "PLAYERS " . Stats.Players . ((Stats.MaxPlayers > 0) ? "/" . Stats.MaxPlayers : "") . "   "
    v.host := pl . ((fps != "") ? "FPS " . ((fps >= 0) ? fps : "--") . "   " : "")
            . "HOST " . ServerTxt() . (Stats.QueryFound ? "  q" . Stats.QueryFound
                                     : (Stats.QueryInfo != "" ? "  no query: icmp only" : ""))
    return v
}

; median of each sample and its neighbours, for the drawn line only: single-sample
; blips flatten out and real changes keep their steep edges (flat line + plateaus,
; the shape the user asked for). The newest sample stays exact, so the line ends on
; the number in the tag.
Med3(h) {
    out := []
    for i, v in h {
        if (v < 0) {
            out.Push(v)
            continue
        }
        a := (i > 1 && h[i - 1] >= 0) ? h[i - 1] : v
        c := (i < h.Length && h[i + 1] >= 0) ? h[i + 1] : v
        out.Push(Max(Min(a, v), Min(Max(a, v), c)))
    }
    return out
}

; one series -> runs of [x, y] points across the whole width, newest at the right.
; A missing answer breaks the line; its x goes into `lost`.
GraphRuns(h, n, gx, gy, gw, gh, top, lt, &lost) {
    runs := [], cur := "", lost := []
    Loop n {
        i := A_Index
        k := h.Length - n + i
        x := gx + (i - 1) * gw / (n - 1)
        if (k < 1) {
            cur := ""
            continue
        }
        v := h[k]
        if (v < 0) {
            lost.Push(Round(x))
            cur := ""
            continue
        }
        y := gy + gh - lt - Min(v, top) / top * (gh - lt * 2)
        if (cur = "") {
            cur := []
            runs.Push(cur)
        }
        cur.Push([x, y])
    }
    for r in runs {
        if (r.Length = 1)
            r.Push([r[1][1] + 0.8, r[1][2]])
    }
    return runs
}

; graph scale for one series: the usual level sits about 1/rise of the way up (ping:
; a bit under half), with room above the highest value so plateaus stay inside
SeriesTop(h, floor, rise) {
    vals := []
    for v in h {
        if (v >= 0)
            vals.Push(v)
    }
    if (vals.Length = 0)
        return floor
    hi := 0
    for v in vals
        hi := Max(hi, v)
    ; median
    srt := ""
    for v in vals
        srt .= v . "`n"
    srt := Sort(RTrim(srt, "`n"), "N")
    arr := StrSplit(srt, "`n")
    med := Integer(arr[(arr.Length + 1) // 2])
    return Max(floor, hi * 1.2, med * rise)
}

; The graph (classic look). Main line: the ping; faint: the server reply; green: FPS
; on its own scale. Smooth (anti-aliased) lines with GDI+; plain GDI if that fails.
CardGraph(hdc, fS, gx, gy, gw, gh, tw, th, footY, W, pad, f, fill, filled) {
    nv  := NetView()
    n   := Card.N
    lt  := Max(1.6, 2 * f)
    col := OvC("Accent2")                               ; step 9: cyan
    dim := OvC("Dim")
    ; grid: faint verticals and a base line
    Loop 5 {
        x := gx + Round(A_Index * gw / 6)
        GdiLine(hdc, x, gy, x, gy + gh - 1, MixHex(dim, fill, 0.86), 1)
    }
    GdiLine(hdc, gx, gy + gh - 1, gx + gw, gy + gh - 1, MixHex(dim, fill, 0.55), 1)
    ; the usual ping level sits a bit under half way up; FPS has its own scale
    ; ping and server reply share a scale (the ping is never above the server line)
    top := SeriesTop(nv.main, 30, 2.2)
    for x in nv.faint
        top := Max(top, x * 1.1)
    mainR  := GraphRuns(Med3(nv.main), n, gx, gy, gw, gh, top, lt, &lost)
    faintR := GraphRuns(Med3(nv.faint), n, gx, gy, gw, gh, top, lt, &lost2)
    fpsR := []
    fh := (Stats.ShowFps && HasAnswer(Stats.HistFps)) ? Stats.HistFps : []
    if (fh.Length > 0)
        fpsR := GraphRuns(Med3(fh), n, gx, gy, gw, gh, SeriesTop(fh, 30, 1.12), lt, &lost3)
    fpsCol := OvC("Ok")

    g := GdipReady() ? GpGraphics(hdc) : 0
    if g {
        for r in faintR
            GpLines(g, r, Argb(dim, 170), Max(1, lt - 0.6))
        for r in fpsR
            GpLines(g, r, Argb(fpsCol, 210), Max(1.2, lt * 0.75))
        for r in mainR {
            if filled {
                GpArea(g, r, gy + gh - 1, Argb(col, 80), Argb(col, 0), gy)
                GpLines(g, r, Argb(col, 34), lt * 2.8)      ; soft glow
            }
            GpLines(g, r, Argb(col, 255), lt)
        }
        GpDone(g)
    } else {
        for set in [[faintR, MixHex(dim, fill, 0.2), Max(1, Round(lt) - 1)],
                    [fpsR, fpsCol, Max(1, Round(lt) - 1)], [mainR, col, Round(lt)]] {
            for r in set[1] {
                Loop r.Length - 1
                    GdiLine(hdc, Round(r[A_Index][1]), Round(r[A_Index][2]), Round(r[A_Index + 1][1]),
                            Round(r[A_Index + 1][2]), set[2], set[3])
            }
        }
    }
    for x in lost
        GdiLine(hdc, x, gy, x, gy + Round(8 * f), OvC("Bad"), 2)

    ; latest values, tagged at the right end: ping, and FPS in green
    tx := gx + gw + Round(6 * f)
    lastY := gy + gh // 2
    if (mainR.Length > 0 && mainR[mainR.Length][mainR[mainR.Length].Length][1] >= gx + gw - 1)
        lastY := Round(mainR[mainR.Length][mainR[mainR.Length].Length][2])
    ty := Max(gy, Min(gy + gh - th, lastY - th // 2))
    GdiText(hdc, fS, nv.tag, tx, ty, PingColour(nv.ping))
    if (fpsR.Length > 0) {
        fr := fpsR[fpsR.Length], fy := Round(fr[fr.Length][2]) - th // 2
        if (Abs(fy - ty) < th)                          ; keep the two tags apart
            fy := (fy <= ty) ? ty - th : ty + th
        fy := Max(gy - th // 2, Min(gy + gh - th // 2, fy))
        GdiText(hdc, fS, LastOf(fh), tx, fy, fpsCol)
    }
    GdiText(hdc, fS, nv.foot, pad, footY, (nv.main.Length = 0) ? dim : Theme.HudTextColor)
    GdiText(hdc, fS, nv.host, pad, footY + th + Round(2 * f), dim)
}

; "48 ms", or "--" when there is no value
MsTxt(v) => (v >= 0) ? v . " ms" : "--"

; redraw and place the card. While editing it stays where the user dragged it.
RefreshStatHud() {
    if Anim.Busy
        return
    if OvlOn() {
        OvlCard()
        return
    }
    if (UI.StatHud = "")
        return
    win := UI.StatHud
    if !CardShown() {
        win.Hide()
        return
    }
    CardWant(&x, &y, &size)
    inEdit := CardEditing() && DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd)
    if (inEdit && Card.Size)
        size := Card.Size                            ; keep the size being edited
    if !CardDraw(size)
        return
    if !inEdit                                       ; while editing: don't yank it back
        win.Show(Format("x{} y{} w{} h{} NoActivate", x, y, Card.W, Card.H))
}

; grip drag: the card scales with the pointer, live (like a pill)
CardResizeDrag() {
    win := UI.StatHud
    MouseGetPos(&mx0)
    s0 := Card.Size, w0 := Max(1, Card.W)
    Loop {
        if (!CardEditing() || UI.StatHud != win)          ; rebuilt mid-drag
            break
        MouseGetPos(&mx)
        size := Max(6, Min(48, Round(s0 * (w0 + mx - mx0) / w0)))
        if (size != Card.Size)
            CardDraw(size)
        if !GetKeyState("LButton", "P")
            break
        Sleep 15
    }
}

; ---- Finding the ARK server automatically -----------------------------------------
; ARK's game traffic is UDP, and Windows keeps no remote address for UDP in its
; connection tables. lib\ServerDetect.ps1 records ~3 s of the kernel's own network
; events (needs admin, which this script already has), keeps the packets ARK's
; process sent, and writes the busiest destination. Nothing inside the game is read.
; It runs as a hidden PowerShell process; this side only starts it and reads the
; result file, so it can never block the menu. Re-checked every 2 minutes, at once
; when ARK (re)starts, and every 30 s while nothing has been found.

; only plain host names / IPs ever reach a helper's source text or command line
SafeHost(h) => RegExMatch(h, "^[A-Za-z0-9.:\-]{1,253}$") ? h : ""

; what the ping helper pings: the detected server when auto is on and one was found
PingTarget() => (Stats.PingAuto && Stats.Server != "") ? Stats.Server
              : (Stats.PingAuto && Stats.Local) ? "127.0.0.1" : PingHostSafe()

; process id of the running ARK window, 0 when ARK isn't running
GamePid() {
    for target in Store.GameTargets {
        if WinExist(target)
            return WinGetPID(target)
    }
    return 0
}

; drop the ping and query history and restart both helpers on the current target
PingRestart() {
    PingHelperStop()
    Stats.PingRetryAt := 0
    Stats.HistPing := []
    try FileDelete(A_Temp . "\ArkSense-ping.txt")
    QueryHelperStop()
    Stats.QueryRetryAt := 0
    Stats.HistQuery := []
    Stats.QueryFound := 0
    Stats.QueryHow := "", Stats.QuerySeen := ""
    Stats.QueryInfo := ""
    try FileDelete(A_Temp . "\ArkSense-query.txt")
}

; one line for the card and the Overlay tab: which server is being pinged
ServerTxt() {
    if !Stats.PingAuto
        return "manual  " . PingHostSafe()
    if (Stats.Local && Stats.Server = "")
        return "local / singleplayer (0 ms)"
    if (Stats.Server != "")
        return Stats.Server . ":" . Stats.ServerPort
             . ((Stats.ServerNote != "") ? "  (" . Stats.ServerNote . ")" : "")
    return (Stats.ServerNote != "") ? Stats.ServerNote : "not found yet"
}

; called from StatsTickCore while the ping graph and auto-detect are on
ServerDetectTick() {
    out := A_Temp . "\ArkSense-server.txt"
    if Stats.DetectPid {                          ; a run is in progress
        if ProcessExist(Stats.DetectPid)
            return
        Stats.DetectPid := 0
        ServerDetectRead(out)
        return
    }
    gp := GamePid()
    if !gp {
        Stats.ServerNote := "waiting for ARK"
        if (Stats.Local && Stats.Server = "")
            Stats.Local := false                  ; ARK closed: no longer "local"
        return
    }
    if (gp = Stats.DetectGame && A_TickCount < Stats.DetectAt)
        return
    ServerDetectStart(gp, out)
}

ServerDetectStart(gp, out) {
    ps := A_ScriptDir . "\lib\ServerDetect.ps1"
    Stats.DetectGame := gp
    if !FileExist(ps) {
        Stats.ServerNote := "lib\ServerDetect.ps1 is missing"
        Stats.DetectAt := A_TickCount + 300000
        return
    }
    try FileDelete(out)
    try {
        Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' . ps
          . '" -GamePid ' . gp . ' -Out "' . out . '"', , "Hide", &pid)
        Stats.DetectPid := pid
        if (Stats.Server = "")
            Stats.ServerNote := "detecting..."
    } catch as e {
        Stats.ServerNote := "detect failed: " . e.Message
        Stats.DetectAt := A_TickCount + 300000
    }
}

ServerDetectRead(out) {
    txt := ""
    try txt := Trim(FileRead(out))
    if (txt = "") {
        Stats.ServerNote := "detector gave no result"
        Stats.DetectAt := A_TickCount + 30000
        Logg("stats", "server detect: no result file")
        return
    }
    first := Trim(StrSplit(txt, "`n", "`r")[1])
    if (SubStr(first, 1, 6) = "error ") {
        Stats.ServerNote := "detect error (see Logs)"
        Stats.DetectAt := A_TickCount + 120000
        Logg("stats", "server detect " . SubStr(first, 1, 200))
        return
    }
    if (SubStr(first, 1, 4) = "none") {
        Stats.DetectAt := A_TickCount + 30000
        if (Stats.Server = "" || Stats.Local) {
            ; no game traffic leaves this PC: singleplayer, or a server on this PC that
            ; Windows didn't log - the round trip is 0
            if !Stats.Local
                Logg("stats", "no ARK server traffic - local / singleplayer, ping 0 ms")
            Stats.Local := true, Stats.Server := "", Stats.ServerPort := ""
            Stats.ServerNote := "local / singleplayer"
        } else {
            Stats.ServerNote := "no ARK traffic - join a server"
            Logg("stats", "server detect: " . SubStr(first, 1, 200))
        }
        return
    }
    isLocal := (SubStr(first, 1, 6) = "local ")
    if isLocal
        first := SubStr(first, 7)                 ; "local 127.0.0.1 7777 120": a server on this PC
    parts := StrSplit(first, " ")
    if (parts.Length < 2 || SafeHost(parts[1]) = "") {
        Stats.ServerNote := "unreadable detect result (see Logs)"
        Stats.DetectAt := A_TickCount + 120000
        Logg("stats", "server detect gave: " . SubStr(first, 1, 200))
        return
    }
    changed := (parts[1] != Stats.Server)
    Stats.Server     := parts[1]
    Stats.ServerPort := parts[2]
    Stats.Local      := isLocal
    Stats.ServerNote := isLocal ? "server on this PC" : ""
    Stats.DetectAt   := A_TickCount + 120000
    if changed {
        Logg("stats", "ARK server detected: " . Stats.Server . ":" . Stats.ServerPort
                    . ((parts.Length >= 3) ? "  (" . parts[3] . " packets in 3 s)" : ""))
        PingRestart()
        Alerts.Silent := 0, Alerts.Down := false, Alerts.Lagging := false, Alerts.LagRun := 0
        AlertServerFound(Stats.Server . ":" . Stats.ServerPort)
    }
}

; ---- Server response time (Steam query) ---------------------------------------------
; A plain ping is answered by the server machine's OS, never by the game, so it
; can't see server lag: in-game ping spikes to 100+ while it stays flat. A Steam
; server query is answered by the ARK server program itself, so when the server
; is overloaded its reply slows down too. lib\ServerQuery.ps1 sends one per second
; to the server's query port (found automatically, or set by hand) and keeps the
; last 60 reply times in a temp file; this side only starts it and reads that file.

; only query a real game server: the detected one, or a manual host you entered
QueryActive() => Stats.PingAuto ? (Stats.Server != "") : (Stats.PingHost != "1.1.1.1")

QueryHelperStart() {
    if (A_TickCount < Stats.QueryRetryAt)         ; never respawn in a tight loop
        return
    Stats.QueryRetryAt := A_TickCount + 30000
    ps := A_ScriptDir . "\lib\ServerQuery.ps1"
    if !FileExist(ps) {
        Stats.QueryInfo := "lib\ServerQuery.ps1 is missing"
        return
    }
    gp  := (Stats.PingAuto && RegExMatch(Stats.ServerPort, "^\d{1,5}$")) ? Stats.ServerPort : 0
    out := A_Temp . "\ArkSense-query.txt"
    try FileDelete(out)
    try {
        Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' . ps
          . '" -Ip ' . PingTarget() . ' -GamePort ' . gp . ' -QueryPort ' . Stats.QueryPort
          . ' -Out "' . out . '" -Parent ' . ProcessExist(), , "Hide", &pid)
        Stats.QueryPid := pid
        Stats.QueryInfo := "finding the query port..."
        Logg("stats", "server query helper started (pid " . pid . ", " . PingTarget() . ")")
    } catch as e {
        Stats.QueryPid := 0
        Stats.QueryInfo := "query helper failed: " . e.Message
        Logg("stats", Stats.QueryInfo)
    }
}

QueryHelperStop() {
    if Stats.QueryPid
        try ProcessClose(Stats.QueryPid)
    Stats.QueryPid := 0
}

; latest server reply time in ms; refreshes Stats.HistQuery. Throws the reason
; when there is no fresh answer, so SafeSample can show why.
QueryRead() {
    Stats.Players := -1, Stats.MaxPlayers := -1      ; set again below from a fresh answer
    if (!Stats.QueryPid || !ProcessExist(Stats.QueryPid)) {
        Stats.QueryPid := 0
        QueryHelperStart()
        throw Error((Stats.QueryInfo != "") ? Stats.QueryInfo : "server query starting")
    }
    path := A_Temp . "\ArkSense-query.txt"
    if !FileExist(path)
        throw Error("finding the query port...")
    txt := ""
    try txt := FileRead(path)
    lines := StrSplit(txt, "`n", "`r")
    if (lines.Length < 1 || lines[1] = "")
        throw Error("reading the query result")
    head := StrSplit(Trim(lines[1]), " ", , 3)       ; "port 27015 battlemetrics"
    if (head.Length >= 2 && head[2] = "0") {
        Stats.QueryFound := 0
        Stats.HistQuery := []
        info := (head.Length >= 3) ? head[3] : "query port not found"
        if (info != Stats.QueryInfo)
            Logg("stats", "server query: " . info)
        Stats.QueryInfo := info
        throw Error(Stats.QueryInfo)
    }
    if (head.Length >= 2 && RegExMatch(head[2], "^\d+$")) {
        if (Integer(head[2]) != Stats.QueryFound)
            Logg("stats", "server query port " . head[2] . ((head.Length >= 3) ? " (" . head[3] . ")" : ""))
        Stats.QueryFound := Integer(head[2])
        Stats.QueryHow   := (head.Length >= 3) ? head[3] : ""
        Stats.QueryInfo  := "query port " . head[2] . ((head.Length >= 3) ? " (" . head[3] . ")" : "")
    }
    ; line 4: every server answering on this address - logged once, for checking
    if (lines.Length >= 4 && SubStr(lines[4], 1, 5) = "seen ") {
        seen := Trim(SubStr(lines[4], 6))
        if (seen != Stats.QuerySeen) {
            Stats.QuerySeen := seen
            if (seen != "")
                Logg("stats", "servers on this address (q=query port, g=game port): " . SubStr(seen, 1, 400))
        }
    }
    age := DateDiff(A_Now, FileGetTime(path, "M"), "Seconds")
    if (age > 6)
        throw Error("server query result is " . age . " s old")
    hist := []
    if (lines.Length >= 2) {
        for s in StrSplit(Trim(lines[2]), ",") {
            if RegExMatch(s, "^-?\d+$")
                hist.Push(Integer(s))
        }
    }
    ; line 3: "players <online> <max>" - the server's own count, refreshed every second
    if (lines.Length >= 3 && RegExMatch(Trim(lines[3]), "^players (-?\d+) (-?\d+)$", &pm))
        Stats.Players := Integer(pm[1]), Stats.MaxPlayers := Integer(pm[2])
    if (hist.Length = 0)
        throw Error("waiting for the first server reply")
    Stats.HistQuery := hist
    v := hist[hist.Length]
    if (v < 0)
        throw Error("server did not answer the query")
    return v
}

; show the card's current position in the Overlay tab's X / Y boxes
CardPosFields() {
    CardWant(&x, &y, &size)
    if UI.Ctrl.Has("statPosX")
        UI.Ctrl["statPosX"].Value := x
    if UI.Ctrl.Has("statPosY")
        UI.Ctrl["statPosY"].Value := y
}

; ---- moving the card / bar on its own (step 25) -------------------------------------------
; EDIT LAYOUT moves everything and shows every pill (empty ones as "status message"
; placeholders). The card's own MOVE / RESIZE (Overlay > Stats card, and the Clantag & bar
; page when the tag sits in the card) only unlocks the card; the pills stay as they are.
CardEditing() => UI.HudDragging || Card.Moving

; the card / bar is on screen: being edited, or switched on and allowed (Only in ARK)
CardShown() => CardEditing() || (Stats.CardOn && OverlayAllowed())

; the card takes clicks while it is being edited (classic window; the helper does its own)
CardSetThrough(through) {
    if (UI.StatHud = "")
        return
    hw := UI.StatHud.Hwnd
    try {
        ex := WinGetExStyle("ahk_id " . hw)
        WinSetExStyle(through ? ex | 0x20 : ex & ~0x20, "ahk_id " . hw)
    }
}

CardMove() {
    if UI.HudDragging {
        Flash("EDIT LAYOUT is on - drag the card, then LOCK")
        return
    }
    Card.Moving := true
    CardSetThrough(false)
    RefreshStatHud()
    Flash("drag the " . (Stats.Bar ? "bar" : "card") . " to move it, its triangle to resize it, then LOCK")
}

CardLock() {
    if !Card.Moving {
        if UI.HudDragging
            HudLockPosition()
        return
    }
    CardCapture()
    Card.Moving := false
    CardSetThrough(true)
    SaveIni()
    RefreshStatHud()
    CardPosFields()
    try CtPosFields()
    Flash((Stats.Bar ? "bar" : "stats card") . " position saved")
}

; where the card is now -> Pill.Pos["stats"] (the spot LOCK saves)
CardCapture() {
    if OvlOn() {
        live := OvlPositions()
        if live.Has("stats")
            Pill.Pos["stats"] := [live["stats"][1], live["stats"][2], live["stats"][3]]
        return
    }
    if (UI.StatHud != "" && DllCall("user32\IsWindowVisible", "Ptr", UI.StatHud.Hwnd)) {
        try {
            WinGetPos(&x, &y, , , "ahk_id " . UI.StatHud.Hwnd)
            Pill.Pos["stats"] := [x, y, Card.Size ? Card.Size : Stats.HudFontSize]
        }
    }
}

; put the card at x, y now (typed coordinates), keeping its size; also while it is being moved
CardPlace(x, y) {
    CardWant(&ox, &oy, &size)
    Pill.Pos["stats"] := [x, y, (CardEditing() && Card.Size) ? Card.Size : size]
    if OvlOn() {
        OvlCard(true)
    } else if (UI.StatHud != "" && DllCall("user32\IsWindowVisible", "Ptr", UI.StatHud.Hwnd)) {
        try WinMove(x, y, , , "ahk_id " . UI.StatHud.Hwnd)
    }
    RefreshStatHud()
}

; X / Y typed in the Overlay tab: becomes the card's saved spot (same as LOCK),
; keeping its current size
CardPosFromFields() {
    CardWant(&x, &y, &size)
    nx := Num("statPosX", x, -5000, 20000)
    ny := Num("statPosY", y, -5000, 20000)
    if (nx != x || ny != y)
        CardPlace(nx, ny)                 ; moves it now, also while MOVE / RESIZE is on
}

; ---- FPS (step 14) -----------------------------------------------------------------
; lib\ArkSenseFps.exe (compiled from lib\ArkSenseFps.cs like the overlay renderer)
; counts ARK's frames from Windows' own graphics event log (ETW, the DXGI "Present"
; events - the same source PresentMon and other FPS counters use). Nothing is
; injected into ARK, nothing of its memory is read; Windows reports each frame ARK
; hands to the screen. Needs admin, which ArkSense already has. Writes
; %TEMP%\ArkSense-fps.txt every second ("ok" + the last 60 values, or "error ...").
; It ends by itself when ARK or ArkSense close, or when the stop file appears.
FpsExe() => A_ScriptDir . "\lib\ArkSenseFps.exe"

FpsTick() {
    gp := GamePid()
    if !gp {
        if Stats.FpsPid
            FpsHelperStop()
        Stats.Fps := -1, Stats.HistFps := [], Stats.FpsInfo := "waiting for ARK"
        return
    }
    if (Stats.FpsPid && (!ProcessExist(Stats.FpsPid) || gp != Stats.FpsGame)) {
        FpsRead()                             ; keep its last word (an error, maybe)
        FpsHelperStop()
    }
    if !Stats.FpsPid {
        FpsHelperStart(gp)
        return
    }
    FpsRead()
}

FpsHelperStart(gp) {
    if (A_TickCount < Stats.FpsRetryAt)
        return
    Stats.FpsRetryAt := A_TickCount + 30000
    try {
        CsBuild("ArkSenseFps", "/target:winexe /platform:x64", "")
        out := A_Temp . "\ArkSense-fps.txt"
        try FileDelete(out)
        try FileDelete(A_Temp . "\ArkSense-fps.stop")
        Run('"' . FpsExe() . '" ' . ProcessExist() . ' ' . gp . ' "' . out . '"', , "Hide", &pid)
        Stats.FpsPid := pid, Stats.FpsGame := gp
        Stats.FpsInfo := "starting..."
        Logg("stats", "fps counter started (pid " . pid . ", ARK " . gp . ")")
    } catch as e {
        Stats.FpsPid := 0
        Stats.FpsInfo := "fps counter unavailable: " . e.Message
        Logg("stats", Stats.FpsInfo)
    }
}

; ask it to stop (it closes its Windows trace session itself), kill it if it doesn't
FpsHelperStop() {
    pid := Stats.FpsPid
    Stats.FpsPid := 0
    if !pid
        return
    try FileAppend("", A_Temp . "\ArkSense-fps.stop")
    if S.Killing                          ; closing at once: it sees the stop file (or
        return                            ; that ArkSense is gone) and ends its session itself
    t0 := A_TickCount
    while (ProcessExist(pid) && A_TickCount - t0 < 1500)
        Sleep 50
    if ProcessExist(pid)
        try ProcessClose(pid)
    Stats.Fps := -1
    Stats.HistFps := []
}

FpsRead() {
    path := A_Temp . "\ArkSense-fps.txt"
    if !FileExist(path)
        return
    txt := ""
    try txt := FileRead(path)
    lines := StrSplit(txt, "`n", "`r")
    if (lines.Length < 1)
        return
    head := Trim(lines[1])
    if (SubStr(head, 1, 5) = "error") {
        Stats.FpsInfo := SubStr(head, 7, 160)
        Stats.Fps := -1, Stats.HistFps := []
        Stats.FpsRetryAt := A_TickCount + 120000
        return
    }
    if (DateDiff(A_Now, FileGetTime(path, "M"), "Seconds") > 5) {
        Stats.FpsInfo := "fps counter stalled"
        Stats.Fps := -1
        return
    }
    hist := []
    if (lines.Length >= 2) {
        for x in StrSplit(Trim(lines[2]), ",") {
            if RegExMatch(x, "^-?\d+$")
                hist.Push(Integer(x))
        }
    }
    Stats.HistFps := hist
    Stats.Fps := LastOf(hist)
    Stats.FpsInfo := (Stats.Fps < 0) ? "no frames from ARK yet (minimised?)" : ""
}
