; ArkSense - lib\NowPlaying.ahk
; "Now playing" overlay: a small see-through card with the song / video playing in
; YouTube (any browser) - thumbnail, title, artist, progress.
; Part of ArkSense.ahk; run that file, not this one.
;
; Where the song comes from: lib\NowPlaying.ps1 (hidden PowerShell) asks Windows'
; own media-session list - the one the volume flyout shows - once a second and
; writes it to %TEMP%\ArkSense-media.txt. If Windows can't give that list, the
; browser window titles are read instead ("<video> - YouTube - Google Chrome"; only
; the active tab shows there). Nothing inside a browser or ARK is read.
;
; The card is one layered window drawn with GDI+ (lib\Draw.ahk) into a 32-bit bitmap
; with real per-pixel transparency: the background is see-through (Np.Alpha), text
; and picture stay solid. It is redrawn only when what it shows changes (about once
; a second while a song plays, for the progress bar).

NpMediaFile() => A_Temp . "\ArkSense-media.txt"

NpBoot() {
    SetTimer(NpTick, 1000)
}

; settings changed (Now playing page APPLY)
NpApply() {
    NpHelperStop()                        ; source may have changed: start again
    Np.RetryAt := 0
    Np.Sig := ""
    if !Np.On
        NpHide()
    NpTick()
}

NpTick() {
    if Anim.Busy
        return
    if !Np.On {
        if Np.Pid
            NpHelperStop()
        NpHide()
        try NpStatusTick()
        return
    }
    try NpReadState()
    try NpRefresh()
    try NpStatusTick()
}

; ---- the helper ----------------------------------------------------------------------
NpHelperStart() {
    if (A_TickCount < Np.RetryAt)
        return
    Np.RetryAt := A_TickCount + 30000
    ps := A_ScriptDir . "\lib\NowPlaying.ps1"
    if !FileExist(ps) {
        Np.Note := "lib\NowPlaying.ps1 is missing"
        return
    }
    try FileDelete(NpMediaFile())
    try {
        Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'
          . ps . '" -Out "' . NpMediaFile() . '" -Parent ' . ProcessExist()
          . ' -Any ' . ((Np.Source = "Any app") ? 1 : 0), , "Hide", &pid)
        Np.Pid := pid
        Np.Note := "starting..."
        Logg("music", "now-playing reader started (pid " . pid . ")")
    } catch as e {
        Np.Pid := 0
        Np.Note := "reader failed: " . e.Message
        Logg("music", Np.Note)
    }
}

NpHelperStop() {
    if Np.Pid
        try ProcessClose(Np.Pid)
    Np.Pid := 0
}

; everything off: closing ArkSense, or the overlay switched off
NpStop() {
    NpHelperStop()
    NpHide()
    GpFreeImage(Np.Img)
    Np.Img := 0, Np.ImgPath := ""
}

; read what's playing into Np.*
NpReadState() {
    if (!Np.Pid || !ProcessExist(Np.Pid)) {
        Np.Pid := 0
        NpHelperStart()
    }
    path := NpMediaFile()
    m := Map()
    fresh := false
    if FileExist(path) {
        fresh := DateDiff(A_Now, FileGetTime(path, "M"), "Seconds") <= 5
        txt := ""
        try txt := FileRead(path, "UTF-8")
        for ln in StrSplit(txt, "`n", "`r") {
            p := InStr(ln, "`t")
            if p
                m[SubStr(ln, 1, p - 1)] := SubStr(ln, p + 1)
        }
    }
    state := m.Get("state", "")
    if (fresh && state = "ok") {
        Np.Via := "media session"
        Np.Note := m.Get("note", "")
        st := m.Get("status", "none")
        if (st = "none" || st = "Closed" || st = "Stopped") {
            NpSet("", "", "", "", -1, -1, "")
            return
        }
        NpSet(st, m.Get("title", ""), m.Get("artist", ""), m.Get("app", ""),
              NpNum(m.Get("pos", "-1")), NpNum(m.Get("len", "-1")), m.Get("cover", ""))
        return
    }
    ; no media-session answer: fall back to the browsers' window titles
    if (SubStr(state, 1, 5) = "error")
        Np.Note := SubStr(state, 7, 160)
    t := NpTitleScan()
    Np.Via := (t != "") ? "window title" : ""
    if (t = "")
        NpSet("", "", "", "", -1, -1, "")
    else
        NpSet("Playing", t, "", "browser", -1, -1, "")
}

NpNum(s) => RegExMatch(s, "^-?\d+(\.\d+)?$") ? Float(s) : -1

; YouTube in a browser's window title: "<video> - YouTube - Google Chrome"
NpTitleScan() {
    for exe in ["chrome.exe", "msedge.exe", "firefox.exe", "opera.exe", "brave.exe", "vivaldi.exe"] {
        try {
            for hwnd in WinGetList("ahk_exe " . exe) {
                t := WinGetTitle("ahk_id " . hwnd)
                if RegExMatch(t, "i)^(?:\(\d+\)\s*)?(.+?) - YouTube(?: Music)?(?:\s|$)", &mm)
                    return mm[1]
            }
        }
    }
    return ""
}

NpSet(status, title, artist, app, pos, len, cover) {
    NpTidy(&title, &artist)
    if (status = "Paused" && Np.Status != "Paused")
        Np.PausedAt := A_TickCount
    Np.Status := status, Np.Title := title, Np.Artist := artist, Np.App := app
    Np.PosSec := pos, Np.LenSec := len, Np.PosAt := A_TickCount
    if (cover != Np.CoverPath) {
        Np.CoverPath := cover
        GpFreeImage(Np.Img)
        Np.Img := 0, Np.ImgPath := ""
        if (cover != "" && GdipReady()) {
            Np.Img := GpLoadImage(cover)
            Np.ImgPath := Np.Img ? cover : ""
        }
    }
}

; YouTube titles -> song + artist: drop "(Official Video)"-style tags, split
; "Artist - Song", and tidy channel names ("Artist - Topic", "ArtistVEVO")
NpTidy(&title, &artist) {
    t := Trim(title), a := Trim(artist)
    t := RegExReplace(t, "i)\s*[\(\[][^\)\]]*\b(official|lyrics?|audio|video|visuali[sz]er|hd|hq|4k|mv|m/v|remaster(ed)?|explicit)\b[^\)\]]*[\)\]]")
    t := RegExReplace(t, "i)\s*\|\s*official.*$")
    channel := RegExMatch(a, "i)(\s-\stopic|vevo|records|music|official)$")
    a := RegExReplace(a, "i)\s*-\s*topic$")
    a := RegExReplace(a, "(?<=[a-z0-9])VEVO$")
    a := Trim(RegExReplace(a, "i)\s*(official)$"))
    ; "Artist - Song": split when the uploader is the artist (or a label / auto channel)
    if RegExMatch(t, "^(.+?)\s+[-" . Chr(0x2013) . Chr(0x2014) . "]\s+(.+)$", &m) {
        left := Trim(m[1])
        if (a = "" || channel || InStr(left, a) || InStr(a, left))
            a := left, t := Trim(m[2])
    }
    title := Trim(t), artist := Trim(a)
}

; m:ss / h:mm:ss
NpTime(sec) {
    sec := Max(0, Floor(sec))
    h := sec // 3600, mi := Mod(sec, 3600) // 60, s := Mod(sec, 60)
    return (h > 0) ? h . ":" . Format("{:02}:{:02}", mi, s) : mi . ":" . Format("{:02}", s)
}

; ---- the card -----------------------------------------------------------------------
; "Only while ARK or the menu is focused" (its own switch): the card hides as soon as
; anything else - a browser, Discord, the desktop - is in front. Off: the overlay-wide
; "Only in ARK" rule applies instead.
NpAllowed() {
    if !Np.GameOnly
        return OverlayAllowed()
    return GameActive() || OwnWindowActive()
}

; the foreground window is one of ArkSense's (the native or web menu, a dropdown, a dialog)
OwnWindowActive() {
    try return WinGetPID("A") = ProcessExist()
    return false
}

; from HudTick (5x a second): hide / show right away when the focus changes
NpFocusTick() {
    static last := -1
    if !Np.On
        return
    a := NpAllowed()
    if (a != last) {
        last := a
        Np.Sig := ""
        NpRefresh()
    }
}

NpWanted() {
    editing := Np.Moving || UI.HudDragging
    if editing
        return true
    if (!NpAllowed() || Np.Status = "" || Np.Title = "")
        return false
    if (Np.Status = "Paused" && Np.HidePaused && A_TickCount - Np.PausedAt > 5000)
        return false
    return true
}

NpRefresh() {
    if !NpWanted() {
        NpHide()
        return
    }
    pos := Np.PosSec
    if (Np.Status = "Playing" && pos >= 0)
        pos += (A_TickCount - Np.PosAt) / 1000
    if (Np.LenSec > 0)
        pos := Min(pos, Np.LenSec)
    editing := (Np.Moving || UI.HudDragging) ? 1 : 0
    sig := Np.Status . "|" . Np.Title . "|" . Np.Artist . "|" . Floor(pos) . "|" . Np.LenSec . "|" . Np.ImgPath
         . "|" . editing . "|" . Np.Alpha . "|" . Np.Scale . "|" . Np.Cover . "|" . Np.Progress . "|" . Np.Accent
         . "|" . Theme.Renderer . "|" . Theme.HudTextColor . "|" . Np.X . "|" . Np.Y
         . "|" . Np.Outline . "|" . Np.OutlineColor
    vis := (Np.Win != "") && DllCall("user32\IsWindowVisible", "Ptr", Np.Win.Hwnd)
    if (sig = Np.Sig && vis)
        return
    Np.Sig := sig
    NpDraw(pos, editing)
}

NpHide() {
    if (Np.Win != "")
        DllCall("user32\ShowWindow", "Ptr", Np.Win.Hwnd, "Int", 0)
    Np.Sig := ""
}

NpWindow() {
    if (Np.Win != "")
        return Np.Win
    ; layered (0x80000) + click-through (0x20); the picture comes from UpdateLayeredWindow
    w := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")
    w.MarginX := 0, w.MarginY := 0
    Np.Win := w
    StreamHide(w.Hwnd, "overlay")
    return w
}

; where the card goes: the saved spot, else the bottom-left of the main screen
NpWhere(W, H, &x, &y) {
    if (Np.X >= 0 && Np.Y >= 0) {
        x := Np.X, y := Np.Y
        return
    }
    x := 20, y := A_ScreenHeight - H - 140
}

NpDraw(pos, editing) {
    if !GdipReady()
        return
    win := NpWindow()
    s := Np.Scale / 100 * A_ScreenDPI / 96
    accent := (Np.Accent != "") ? Np.Accent : OvC("Accent2")
    title  := Np.Title, artist := Np.Artist
    if (title = "") {
        title := "Now playing"
        artist := "drag me, then LOCK"
    }
    hasBar := Np.Progress && (Np.LenSec > 0 || editing)
    pad  := 10 * s
    H    := Round((hasBar ? 80 : 58) * s)
    side := H - 2 * pad                                      ; the picture square
    showPic := Np.Cover
    W    := Round((showPic ? 340 : 290) * s)

    ; a 32-bit top-down bitmap with an alpha channel
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", W, bi, 4), NumPut("Int", -H, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
    bits := 0
    bmp := DllCall("gdi32\CreateDIBSection", "Ptr", mem, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    old := bmp ? DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr") : 0
    g := bmp ? GpGraphics(mem) : 0
    try {
        if !g
            return
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
        r := 12 * s
        GpFillRound(g, 0.5, 0.5, W - 1, H - 1, r, Argb(OvC("Panel"), Np.Alpha))
        if editing
            GpStrokeRound(g, 0.75, 0.75, W - 1.5, H - 1.5, r, Argb(OvC("Accent"), 255), Max(1.5, 1.5 * s))
        else if Np.Outline
            GpStrokeRound(g, 0.75, 0.75, W - 1.5, H - 1.5, r,
                          Argb((Np.OutlineColor != "") ? Np.OutlineColor : accent, 230), Max(1.5, 1.5 * s))

        tx := pad
        if showPic {
            py := pad
            if Np.Img {
                GpCoverSquare(g, Np.Img, pad, py, side, 8 * s)
            } else {
                GpFillRound(g, pad, py, side, side, 8 * s, Argb(accent, 46))
                GpText(g, Chr(0x266B), "Segoe UI Symbol", side * 0.5, false, Argb(accent, 230),
                       pad, py, side, side, 1)
            }
            tx := pad + side + 11 * s
        }
        tw := W - tx - pad
        ; play / pause mark at the top right
        mark := (Np.Status = "Paused") ? Chr(0x275A) . Chr(0x275A) : Chr(0x25B6)
        GpText(g, mark, "Segoe UI Symbol", 10 * s, false, Argb(accent, 230), W - pad - 22 * s, pad - 2 * s,
               22 * s, 18 * s, 2)
        GpText(g, title, Theme.FontName, 14.5 * s, true, Argb(Theme.HudTextColor, 255),
               tx, pad - 3 * s, tw - 24 * s, 21 * s)
        GpText(g, artist, Theme.FontName, 12 * s, false, Argb(MixHex(Theme.HudTextColor, OvC("Dim"), 0.45), 235),
               tx, pad + 18 * s, tw, 18 * s)
        if hasBar {
            len := (Np.LenSec > 0) ? Np.LenSec : 200
            p   := (Np.LenSec > 0) ? Max(0, pos) : 70
            by  := H - pad - 18 * s, bh := 4 * s
            GpFillRound(g, tx, by, tw, bh, bh / 2, Argb("FFFFFF", 42))
            fw := Max(bh, tw * Min(1, p / len))
            GpFillRound(g, tx, by, fw, bh, bh / 2, Argb(accent, 255))
            GpFillRound(g, tx + fw - bh * 0.9, by - bh * 0.4, bh * 1.8, bh * 1.8, bh * 0.9, Argb("FFFFFF", 235))
            tcol := Argb(MixHex(Theme.HudTextColor, OvC("Dim"), 0.55), 230)
            GpText(g, NpTime(p), Theme.FontName, 10.5 * s, false, tcol, tx, by + bh + 1 * s, tw / 2, 15 * s, 0)
            GpText(g, NpTime(len), Theme.FontName, 10.5 * s, false, tcol, tx + tw / 2, by + bh + 1 * s, tw / 2, 15 * s, 2)
        }

        NpWhere(W, H, &x, &y)
        if (editing && !Np.Jump && DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd)) {
            try WinGetPos(&x, &y, , , "ahk_id " . win.Hwnd)    ; being dragged: stay put
        }
        Np.Jump := false
        pt := Buffer(8, 0), sz := Buffer(8, 0), src := Buffer(8, 0), bl := Buffer(4, 0)
        NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
        NumPut("Int", W, sz, 0), NumPut("Int", H, sz, 4)
        NumPut("UChar", 255, bl, 2), NumPut("UChar", 1, bl, 3)       ; per-pixel alpha (AC_SRC_ALPHA)
        DllCall("user32\UpdateLayeredWindow", "Ptr", win.Hwnd, "Ptr", scr, "Ptr", pt, "Ptr", sz,
                "Ptr", mem, "Ptr", src, "UInt", 0, "Ptr", bl, "UInt", 2)         ; ULW_ALPHA
        ; click-through unless it is being placed
        ex := WinGetExStyle("ahk_id " . win.Hwnd)
        want := editing ? (ex & ~0x20) : (ex | 0x20)
        if (want != ex)
            WinSetExStyle(want, "ahk_id " . win.Hwnd)
        DllCall("user32\ShowWindow", "Ptr", win.Hwnd, "Int", 4)      ; SW_SHOWNOACTIVATE
        DllCall("user32\SetWindowPos", "Ptr", win.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
                "UInt", 0x13)                                        ; stay on top, no move / size / activate
        Np.W := W, Np.H := H
    } finally {
        GpDone(g)
        if old
            DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old, "Ptr")
        if bmp
            DllCall("gdi32\DeleteObject", "Ptr", bmp)
        DllCall("gdi32\DeleteDC", "Ptr", mem)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    }
}

; X / Y typed on the page -> Np.X / Np.Y; true when they changed. The next draw goes
; there even while MOVE is on (step 25: typed coordinates did nothing before)
NpPosFromFields() {
    if !(UI.Ctrl.Has("npX") && UI.Ctrl.Has("npY"))
        return false
    x := Trim(UI.Ctrl["npX"].Value), y := Trim(UI.Ctrl["npY"].Value)
    if !(RegExMatch(x, "^-?\d+$") && RegExMatch(y, "^-?\d+$"))
        return false
    nx := Max(-1, Min(20000, Integer(x))), ny := Max(-1, Min(20000, Integer(y)))
    if (nx < 0 || ny < 0)
        nx := -1, ny := -1
    if (nx = Np.X && ny = Np.Y)
        return false
    Np.X := nx, Np.Y := ny
    Np.Jump := true
    Np.Sig := ""
    return true
}

; MOVE: the card shows (a placeholder if nothing plays) at the typed X / Y and can be dragged
NpMove() {
    NpPosFromFields()
    Np.Moving := true
    Np.Sig := ""
    NpRefresh()
    Flash("drag the Now playing card where you want it, then press LOCK")
}

; LOCK: remember where it is
NpLock() {
    NpCapture()
    Np.Moving := false
    Np.Sig := ""
    SaveIni()
    NpRefresh()
    NpPosFields()
    Flash("Now playing position saved")
}

NpCapture() {
    if (Np.Win = "" || !DllCall("user32\IsWindowVisible", "Ptr", Np.Win.Hwnd))
        return
    try {
        WinGetPos(&x, &y, , , "ahk_id " . Np.Win.Hwnd)
        Np.X := Max(0, x), Np.Y := Max(0, y)
    }
}

NpReset() {
    Np.X := -1, Np.Y := -1
    Np.Jump := true
    Np.Sig := ""
    SaveIni()
    NpRefresh()
    NpPosFields()
    Flash("Now playing card back to its default spot")
}

NpPosFields() {
    if UI.Ctrl.Has("npX")
        UI.Ctrl["npX"].Value := Np.X
    if UI.Ctrl.Has("npY")
        UI.Ctrl["npY"].Value := Np.Y
}

; the live line on the Now playing page
NpStatusText() {
    if !Np.On
        return "off"
    if (Np.Title = "")
        return "nothing playing" . ((Np.Note != "" && Np.Note != "starting...") ? "   (" . Np.Note . ")" : "")
    return Np.Status . "   " . Np.Title . ((Np.Artist != "") ? "  -  " . Np.Artist : "")
}

NpStatusTick() {
    if !UI.Ctrl.Has("npNow")
        return
    c := UI.Ctrl["npNow"]
    t := "now   " . NpStatusText()
    if (c.Text != t) {
        c.Text := t
        Paint(c, "", (Np.Title != "") ? Theme.Ok : Theme.Dim)
    }
    if UI.Ctrl.Has("npVia") {
        v := "source   " . ((Np.Via != "") ? Np.Via : (Np.Pid ? "media sessions" : "-"))
           . (Np.App != "" && Np.Title != "" ? "   (" . Np.App . ")" : "")
        if (UI.Ctrl["npVia"].Text != v)
            UI.Ctrl["npVia"].Text := v
    }
}
