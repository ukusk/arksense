; ArkSense - lib\Ovl.ahk
; Smooth overlay renderer: starts and feeds lib\ArkSenseOverlay.exe.
; Part of ArkSense.ahk; run that file, not this one.
;
; The helper is compiled from lib\ArkSenseOverlay.cs on this PC the first time
; (and again whenever that file changes) with the C# compiler that is part of
; Windows' own .NET Framework 4 - nothing is downloaded. It draws the pills, the
; stats card and the alert toasts with smooth edges, gradients and real
; per-pixel transparency, and only when this side sends new content.
;
; This side never waits on it: every message is one SendMessageTimeout with
; WM_COPYDATA (plain text, tab-separated), answered at once. If the helper can't
; be compiled or started, or stops later, the classic renderer (the old pill
; windows and GDI card in Overlay.ahk / Stats.ahk) takes over by itself.

OvlOn() => Ovl.State = "ready"

OvlExe() => A_ScriptDir . "\lib\ArkSenseOverlay.exe"

; compile if needed, start, wait for its hello. Called once at boot.
OvlStart() {
    Ovl.Hwnd := 0
    Ovl.Live := Map()
    Ovl.Fails := 0
    Ovl.LastFx := ""
    if (Theme.Renderer != "Smooth") {
        Ovl.State := "off"
        Ovl.Why := "Classic picked in Overlay > Display"
        return false
    }
    try {
        OvlStopAll()
        OvlCompile()
        Run('"' . OvlExe() . '" ' . A_ScriptHwnd . ' ' . ProcessExist(), , "Hide", &pid)
        Ovl.Pid := pid
        t0 := A_TickCount
        while (!Ovl.Hwnd && A_TickCount - t0 < 5000 && ProcessExist(pid))
            Sleep 30                      ; the hello arrives in OvlReceive meanwhile
        if !Ovl.Hwnd
            throw Error(ProcessExist(pid) ? "the renderer didn't answer within 5 s"
                                          : "the renderer closed right after starting")
        Ovl.State := "ready"
        Ovl.Why := ""
        OvlTheme()
        Logg("overlay", "smooth renderer running (pid " . pid . ")")
        return true
    } catch as e {
        Ovl.State := "failed"
        Ovl.Why := e.Message
        Ovl.Hwnd := 0
        if Ovl.Pid
            try ProcessClose(Ovl.Pid)
        Ovl.Pid := 0
        Logg("overlay", "smooth renderer unavailable, using classic: " . e.Message)
        return false
    }
}

; a copy left from an earlier run (it quits by itself within 2 s, but it would
; lock the .exe during a recompile)
OvlStopAll() {
    Loop 6 {
        pid := ProcessExist("ArkSenseOverlay.exe")
        if !pid
            break
        try ProcessClose(pid)
        Sleep 60
    }
}

; Compile lib\ArkSenseOverlay.cs -> .exe when there is no .exe yet or the source
; changed since (size + time stamp of the source, kept in a small .src file).
OvlCompile() {
    CsBuild("ArkSenseOverlay", "/target:winexe", "/r:System.Drawing.dll /r:System.Windows.Forms.dll",
            "preparing the overlay renderer (first start only)")
}

; lib\<name>.cs -> lib\<name>.exe with Windows' own C# compiler (.NET Framework 4, part
; of Windows - nothing is downloaded). Skipped while the .exe matches the source.
CsBuild(name, opts, refs, splash := "") {
    src := A_ScriptDir . "\lib\" . name . ".cs"
    exe := A_ScriptDir . "\lib\" . name . ".exe"
    if !FileExist(src)
        throw Error("lib\" . name . ".cs is missing")
    stamp := FileGetSize(src) . "-" . FileGetTime(src, "M")
    mark := exe . ".src"
    old := ""
    try old := Trim(FileRead(mark))
    if (FileExist(exe) && old = stamp)
        return
    csc := ""
    for rel in ["\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "\Microsoft.NET\Framework\v4.0.30319\csc.exe"] {
        if FileExist(A_WinDir . rel) {
            csc := A_WinDir . rel
            break
        }
    }
    if (csc = "")
        throw Error("Windows' C# compiler (.NET Framework 4) was not found")
    if (splash != "")
        SplashStep(45, splash)
    out := A_Temp . "\ArkSense-csc-" . name . ".txt"
    try FileDelete(out)
    try FileDelete(exe)
    RunWait(A_ComSpec . ' /c ""' . csc . '" /nologo ' . opts . ' /optimize+ /out:"' . exe
          . '" ' . refs . ' "' . src . '" > "' . out . '" 2>&1"', , "Hide")
    if !FileExist(exe) {
        msg := ""
        try msg := FileRead(out)
        throw Error("compiling " . name . " failed: " . SubStr(RegExReplace(msg, "\s+", " "), 1, 240))
    }
    try FileDelete(mark)
    FileAppend(stamp, mark)
    Logg("overlay", "compiled lib\" . name . ".cs")
}

; replies from the helper: hello, positions after a drag / layout, errors
OvlReceive(wParam, lParam, msg, hwnd) {
    if (NumGet(lParam, 0, "UPtr") != 0x41534F56)       ; 'ASOV': not ours
        return
    n := NumGet(lParam, A_PtrSize, "UInt") // 2
    p := NumGet(lParam, A_PtrSize * 2, "Ptr")
    if (!p || n < 2)
        return 1
    txt := StrGet(p, n - 1, "UTF-16")
    lines := StrSplit(txt, "`n", "`r")
    head := StrSplit(lines[1], "`t")
    switch head[1] {
        case "hello":
            if (head.Length >= 2 && RegExMatch(head[2], "^\d+$"))
                Ovl.Hwnd := Integer(head[2])
            Ovl.Ver := (head.Length >= 3) ? head[3] : ""
        case "pos":
            live := OvlParsePos(lines)
            Ovl.Live := live
            if (CardEditing() && live.Has("stats"))
                Card.Size := live["stats"][3]
        case "log":
            if (head.Length >= 2)
                Logg("overlay", SubStr(head[2], 1, 200))
    }
    return 1
}

; "pos" lines: key, x, y, size
OvlParsePos(lines) {
    live := Map()
    for i, ln in lines {
        if (i = 1)
            continue
        a := StrSplit(ln, "`t")
        if (a.Length >= 4 && RegExMatch(a[2] . a[3] . a[4], "^[\d-]+$"))
            live[a[1]] := [Integer(a[2]), Integer(a[3]), Integer(a[4])]
    }
    return live
}

; LOCK: ask for every position right now (written to a temp file before the call
; returns), falling back to the last report if that fails
OvlPositions() {
    path := A_Temp . "\ArkSense-overlay-pos.txt"
    try FileDelete(path)
    if OvlSend("report") {
        txt := ""
        try txt := FileRead(path, "UTF-8")
        if (SubStr(txt, 1, 3) = "pos")
            Ovl.Live := OvlParsePos(StrSplit(txt, "`n", "`r"))
    }
    return Ovl.Live
}

; one message to the helper; false when it isn't there
OvlSend(txt) {
    if (!OvlOn() || !Ovl.Hwnd)
        return false
    cds := Buffer(A_PtrSize * 3, 0)                      ; COPYDATASTRUCT
    NumPut("UPtr", 1, cds, 0)
    NumPut("UInt", (StrLen(txt) + 1) * 2, cds, A_PtrSize)
    NumPut("Ptr", StrPtr(txt), cds, A_PtrSize * 2)
    res := 0
    ok := DllCall("user32\SendMessageTimeoutW", "Ptr", Ovl.Hwnd, "UInt", 0x4A, "Ptr", A_ScriptHwnd,
                  "Ptr", cds, "UInt", 0x2, "UInt", 800, "Ptr*", &res, "Ptr")   ; SMTO_ABORTIFHUNG
    if ok {
        Ovl.Fails := 0
        return true
    }
    Ovl.Fails += 1
    if (!ProcessExist(Ovl.Pid) || Ovl.Fails >= 5)
        OvlLost(ProcessExist(Ovl.Pid) ? "the renderer stopped answering" : "the renderer closed")
    return false
}

; every 2 s from HudTick: is the helper still there?
OvlCheck() {
    if (!OvlOn() || A_TickCount < Ovl.CheckAt)
        return
    Ovl.CheckAt := A_TickCount + 2000
    if !ProcessExist(Ovl.Pid) {
        OvlLost("the renderer closed")
        return
    }
    if Ovl.ThemeDirty                     ; a theme update that didn't get through
        OvlTheme()
}

; the helper is gone: try one restart, else hand the overlay to the classic renderer.
; Deferred: this can be reached from inside a pill or card refresh.
OvlLost(why) {
    if (Ovl.State != "ready")
        return
    Ovl.State := "failed"
    Ovl.Why := why
    Ovl.Hwnd := 0
    if Ovl.Pid
        try ProcessClose(Ovl.Pid)
    Logg("overlay", "smooth renderer: " . why)
    SetTimer(OvlRecover, -100)
}

OvlRecover() {
    if (Ovl.Restarts < 2) {
        Ovl.Restarts += 1
        if OvlStart() {
            OvlResync()
            return
        }
    }
    Logg("overlay", "switched to the classic renderer")
    RebuildHud()
    RebuildStatHud()
}

; send everything again (after a (re)start or a renderer switch)
OvlResync() {
    OvlTheme()
    S.lastHud := ""
    Hud(S.hudMsg, S.hudCol)
    RefreshStatHud()
}

OvlStop() {
    if !Ovl.Pid
        return
    OvlSend("quit")
    try ProcessClose(Ovl.Pid)
    Ovl.Pid := 0
    Ovl.Hwnd := 0
    if (Ovl.State = "ready")
        Ovl.State := "off"
}

; no tabs or line breaks inside one field
OvlClean(s) => StrReplace(StrReplace(StrReplace(String(s), "`t", " "), "`n", " "), "`r", "")

OvlCsv(arr) {
    out := ""
    for v in arr
        out .= (A_Index = 1 ? "" : ",") . v
    return out
}

; colours, fonts and pill look
OvlTheme() {
    t := "theme"
       . "`nfont=" . Theme.FontName . "`ntext=" . Theme.Text . "`ndim=" . Theme.Dim
       . "`naccent=" . Theme.Accent . "`naccent2=" . Theme.Accent2 . "`npanel=" . Theme.Panel
       . "`npanel2=" . Theme.Panel2 . "`nline=" . Theme.Line . "`nok=" . Theme.Ok . "`nbad=" . Theme.Bad . "`nwarn=E6B800"
       . "`nhudtext=" . Theme.HudTextColor . "`nhudborder=" . Theme.HudBorderColor
       . "`nborder=" . (Theme.HudBorderOn ? 1 : 0) . "`nbg=" . (Theme.HudBgOn ? 1 : 0)
       . "`nopacity=" . Theme.HudBgOpacity . "`nstreamer=" . (StreamFlag("overlay") ? 1 : 0)
       . "`ntoastpos=" . Alerts.Pos . "`npillh=" . Theme.PillH . "`nglow=1"
    Ovl.ThemeDirty := !OvlSend(t)
}

; every pill: what it says and where it goes (the helper lays out the auto stack)
OvlPills(msg, col) {
    editing := UI.HudDragging ? 1 : 0
    show := ((Theme.HudOn || editing) && OverlayAllowed()) ? 1 : 0
    out := "pills`t" . show . "`t" . editing . "`t" . Theme.HudX . "`t" . Theme.HudY
         . "`t" . (Theme.PillVertical ? 1 : 0) . "`t" . Theme.PillGap . "`t" . Theme.PillH
         . "`t" . Theme.HudFontSize
    for d in PillDefs() {
        k := d[1]
        c := PillContent(k, msg, col)
        hide := 0
        if (c = "") {
            if editing
                c := ["status message", Theme.Dim, Theme.Dim]
            else {
                c := ["", Theme.Dim, Theme.Dim]
                hide := 1
            }
        }
        saved := Pill.Pos.Has(k)
        pos := saved ? Pill.Pos[k] : [0, 0, Theme.HudFontSize]
        out .= "`n" . k . "`t" . d[2] . "`t" . OvlClean(c[1]) . "`t" . c[2] . "`t" . c[3]
             . "`t" . (saved ? 1 : 0) . "`t" . pos[1] . "`t" . pos[2] . "`t" . pos[3] . "`t" . hide
             . "`t" . OvlPillMark(k, col)
    }
    if !OvlSend(out)
        S.lastHud := ""                   ; didn't get through: HudTick sends it again
}

; colour of a pill's bottom bar: green while a feature is on, the primary colour
; while it is off; the message pill takes its message colour; others have none
OvlPillMark(k, col) {
    switch k {
        case "state":   on := S.enabled
        case "desmo":   on := Desmo.Active
        case "mammoth": on := Mammoth.Active
        case "bag":     on := Bag.Active
        case "stream":  on := Theme.StreamerMode
        case "oc":      on := Oc.Active
        case "clicker": on := Ac.Active
        case "msg":     return (col != "") ? col : ""
        default:        return ""
    }
    return on ? Theme.Ok : Theme.Accent
}

; the stats card: values, both graph series and the footer, all as text
OvlCard(jump := false) {
    editing := UI.HudDragging ? 1 : 0
    ; head: card show editing x y size graph cardonly jump - cardonly = the card alone is
    ; being moved (step 25), jump = place it at x y even while it is being edited
    tail := "`t" . ((Card.Moving && !UI.HudDragging) ? 1 : 0) . "`t" . (jump ? 1 : 0)
    show := CardShown() && (Stats.Bar || Card.Order.Length > 0 || Card.Graph)
    if !show {
        OvlSend("card`t0`t" . editing . "`t0`t0`t0`t0" . tail)
        return
    }
    CardWant(&x, &y, &size)
    if Stats.Bar {                        ; the stats bar (lib\Bar.ahk): its parts as text
        out := "card`t1`t" . editing . "`t" . x . "`t" . y . "`t" . size . "`t0" . tail . "`nbar`t1`t" . Theme.HudTextColor
             . "`nlogo`t" . BarLogoSpec(Stats.BarLogo) . "`t" . BarLogoColour()
        for it in BarItems()
            out .= "`nbi`t" . it.k . "`t" . OvlClean(it.v) . "`t" . it.u . "`t" . it.vc . "`t" . it.ic . "`t" . it.lvl
        OvlSend(out . OvlCardTag())
        return
    }
    out := "card`t1`t" . editing . "`t" . x . "`t" . y . "`t" . size . "`t" . (Card.Graph ? 1 : 0) . tail
    for key in Card.Order {
        if (key = "clock") {
            out .= "`nm`tTIME`t" . ClockTxt() . "`t" . Theme.HudTextColor . "`t-1"
        } else {
            v := StatValue(key)
            out .= "`nm`t" . StrUpper(key) . "`t" . StatTxt(v, "%") . "`t" . StatColour(v) . "`t" . v
        }
    }
    if Card.Graph {
        nv := NetView()
        fh := (Stats.ShowFps && HasAnswer(Stats.HistFps)) ? Stats.HistFps : []
        out .= "`nmain`t" . OvlCsv(nv.main) . "`nfaint`t" . OvlCsv(nv.faint)
             . "`nfps`t" . OvlCsv(fh) . "`t" . Theme.Ok
             . "`ntag`t" . nv.tag . "`t" . PingColour(nv.ping)
             . "`nfoot`t" . nv.foot . "`t" . ((nv.main.Length = 0) ? Theme.Dim : Theme.HudTextColor)
             . "`nhost`t" . OvlClean(nv.host)
    }
    out .= OvlCardTag()                   ; the clantag in the card's top line (step 23)
    OvlSend(out)
}

; menu effects recolour the pill outlines: at most ~15 changes a second
OvlFx(col) {
    if (!Theme.HudBorderOn || UI.HudDragging)
        return
    if (col = Theme.HudBorderColor)
        col := ""                                        ; back to the set colours
    if (col = Ovl.LastFx || (col != "" && A_TickCount - Ovl.FxAt < 66))
        return
    Ovl.FxAt := A_TickCount
    Ovl.LastFx := col
    OvlSend("fx`t" . col)
}

; the monitor ARK is on (else the main one) - where toasts slide in
OvlToastArea(&l, &t, &r, &b) {
    l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
    for target in Store.GameTargets {
        if !WinExist(target)
            continue
        try {
            WinGetPos(&wx, &wy, &ww, &wh, target)
            cx := wx + ww // 2, cy := wy + wh // 2
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &ml, &mt, &mr, &mb)
                if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                    l := ml, t := mt, r := mr, b := mb
                    return
                }
            }
        }
        return
    }
}

OvlToast(kind, title, body) {
    OvlToastArea(&l, &t, &r, &b)
    return OvlSend("toast`t" . kind . "`t" . OvlClean(title) . "`t" . OvlClean(body) . "`t"
                 . (Alerts.Secs * 1000) . "`t" . l . "`t" . t . "`t" . r . "`t" . b)
}

; Overlay tab APPLY: start or stop the helper when the Renderer choice changed
OvlApplyMode() {
    want := (Theme.Renderer = "Smooth")
    if (want && !OvlOn()) {
        PillDestroyAll()                  ; the classic windows go first
        CardDestroy()
        Ovl.Restarts := 0
        if !OvlStart()
            Flash("smooth renderer couldn't start: " . Ovl.Why)
    } else if (!want && OvlOn()) {
        OvlStop()
        Ovl.Why := "Classic picked in Overlay > Display"
    }
}

; closing ArkSense: music off, screen colours back, power plan back, helper closed
AppExit(*) {
    try MusicStop()
    try NpStop()                          ; Now playing reader + card
    try FpsHelperStop()                   ; FPS counter (it closes its trace session)
    try FilterShutdown()
    try TunePlanRestore()
    try OvlStop()
    if S.Killing                          ; killswitch: no slow teardown, the process just ends
        DllCall("kernel32\ExitProcess", "UInt", 0)
}
