; ArkSense - lib\Extras.ahk
; Startup animation, settings search, clean screenshots
; and the self-check. Everything here is plain Static controls and plain GDI calls.
; Part of ArkSense.ahk; run that file, not this one.

; ==== Startup animation ===========================================================
; Step 16: drawn like the menu - a dark rounded card with a gradient edge and the
; accent line along its top, the gradient "A" badge (or the custom logo), the ARK /
; SENSE wordmark, the credit, a status line and a gradient loading bar. Glow: a soft
; halo around the card and the badge breathes, the bar glows and a shine sweeps along
; it. Drawn with GDI+ into one per-pixel-alpha layered window, ~30 frames a second,
; only while it shows (about 4 s). Boot calls SplashStep() as it really progresses; the
; bar never runs ahead of the real work, and never finishes faster than Splash.Dur.

SplashShow(preview := false) {
    if (!Theme.Splash && !preview)
        return
    if !GdipReady()
        return                                    ; no GDI+: start without the animation
    s := A_ScreenDPI / 96
    Splash.S := s
    Splash.W := Round(500 * s), Splash.H := Round(330 * s)
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x80000 +E0x20 -DPIScale")
    g.MarginX := 0, g.MarginY := 0
    Splash.Win := g
    StreamHide(g.Hwnd)
    logoPath := (Trim(Audio.LogoPath) != "") ? Audio.LogoPath : A_ScriptDir . "\logo.png"
    Splash.Logo := GpLoadImage(logoPath)
    Splash.Text := "starting"
    Splash.T0 := A_TickCount, Splash.Cur := 0, Splash.Target := 5, Splash.Done := false
    Splash.EndAt := 0
    ; centred on the screen ARK (or the mouse) is on: the main screen is fine here
    Splash.X := (A_ScreenWidth - Splash.W) // 2, Splash.Y := (A_ScreenHeight - Splash.H) // 2
    Splash.Preview := preview
    m := 34 * s                                   ; the card inside the glow margin (as SplashDraw)
    SplashLookInit(Splash.X + m, Splash.Y + m, Splash.W - 2 * m, Splash.H - 2 * m)
    SplashDraw(0, 0, 0)
    DllCall("user32\ShowWindow", "Ptr", g.Hwnd, "Int", 4)          ; SW_SHOWNOACTIVATE
    SetTimer(SplashTick, 33)
}

; boot reports real progress (0-100) with a short status message
SplashStep(pctNow, text) {
    if (Splash.Win = "")
        return
    Splash.Target := Max(Splash.Target, pctNow)
    Splash.Text := text
}

SplashTick() {
    g := Splash.Win
    if (g = "") {
        SetTimer(SplashTick, 0)
        return
    }
    el := A_TickCount - Splash.T0
    if Splash.Preview                              ; Visuals > Look > PREVIEW: fake a boot
        SplashStep(Min(100, el / 32), (el < 1200) ? "loading settings" : (el < 2600) ? "building the menu" : "ready")
    ; never ahead of the real work, never faster than the set duration
    want := Min(Splash.Target, el / Splash.Dur * 100)
    if (el > 12000)                                ; boot stalled (an error?) - finish anyway
        want := 100, Splash.Target := 100
    Splash.Cur := Min(100, Splash.Cur + (want - Splash.Cur) * 0.25 + 0.2 * (want > Splash.Cur))
    p := Min(100, Splash.Cur)
    if (p >= 99.5 && Splash.Target >= 100 && Splash.EndAt = 0)
        Splash.EndAt := A_TickCount + 420           ; hold at 100% a moment, then fade
    fade := Min(1, el / 280)                        ; fade in
    if Splash.EndAt {
        left := Splash.EndAt - A_TickCount
        if (left <= 0) {
            SplashClose()
            return
        }
        fade := Min(fade, left / 300)
    }
    try SplashDraw(el, p, fade)
}

; one frame. el = ms since start, p = 0-100, fade = 0-1
SplashDraw(el, p, fade) {
    s := Splash.S, W := Splash.W, H := Splash.H
    if !GpCanvas(W, H, &mem, &bmp, &old)
        return
    g := GpGraphics(mem)
    try {
        if !g
            return
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
        ; colours after Visuals > Look (the theme's own when the look is None)
        pal := Splash.P, acc := pal.acc, acc2 := pal.acc2
        breathe := (1 - Cos(el * 0.0042)) / 2         ; 0..1, ~1.5 s per breath
        m := 34 * s                                   ; room for the outer glow
        cx := m, cy := m, cw := W - 2 * m, ch := H - 2 * m, r := SplashRadius()

        ; outer glow, breathing (Neon edges: brighter, wider, drifting between both colours)
        if Splash.Neon
            GpGlow(g, cx, cy, cw, ch, r, MixHex(acc, acc2, (1 - Cos(el * 0.0011)) / 2), 190 + 65 * breathe, m, 12)
        else
            GpGlow(g, cx, cy, cw, ch, r, acc, 120 + 100 * breathe, m * 0.9, 10)
        ; Frosted glass: the blurred picture under a see-through body
        SplashLookUnder(g, cx, cy, cw, ch, r)
        ; card body: panel, slightly lighter towards the top
        ba := SplashBodyAlpha()
        br := GpGrad(cx, cy, cw, ch, Argb(MixHex(pal.header, pal.panel, 0.3), ba), Argb(pal.panel, ba), 1)
        GpFillRoundB(g, cx, cy, cw, ch, r, br), GpFreeBrush(br)
        ; the look's background: aurora clouds, embers, holo light, spotlight
        SplashLookOver(g, el, cx, cy, cw, ch, r)
        ; a soft accent wash behind the badge
        wash := GpGrad(cx, cy, cw, ch * 0.6, Argb(acc, Round(26 + 18 * breathe)), Argb(acc, 0), 1)
        GpFillRoundB(g, cx, cy, cw, ch * 0.6, r, wash), GpFreeBrush(wash)
        ; gradient edge (Neon edges: a turning one)
        SplashLookEdge(g, el, cx, cy, cw, ch, r)
        ; the accent line along the top edge (like the menu), fading out to the right
        tl := GpGrad(cx + r, cy, cw - 2 * r, 2 * s, Argb(acc, 255), Argb(acc2, 0), 0)
        GpFillRoundB(g, cx + r, cy + 0.5, cw - 2 * r, 2.2 * s, s, tl), GpFreeBrush(tl)

        ; badge: the custom logo, else the gradient "A" (glow breathes)
        bs := 74 * s, bx := (W - bs) / 2, by := cy + 30 * s, br2 := (Splash.Look = "holo") ? 6 * s : 18 * s
        GpGlow(g, bx, by, bs, bs, br2, acc, 170 + 85 * breathe, 24 * s, 8)
        if Splash.Logo {
            GpFillRoundB(g, bx, by, bs, bs, br2, 0)
            GpCoverSquare(g, Splash.Logo, bx, by, bs, br2, Splash.Ia)
        } else {
            bb := GpGrad(bx, by, bs, bs, Argb(acc, 255), Argb(acc2, 255), 2)
            GpFillRoundB(g, bx, by, bs, bs, br2, bb), GpFreeBrush(bb)
            hl := GpGrad(bx, by, bs, bs * 0.5, Argb(pal.white, 60), Argb(pal.white, 0), 1)
            GpFillRoundB(g, bx, by, bs, bs * 0.5, br2, hl), GpFreeBrush(hl)
            GpText(g, "A", Theme.FontName, 40 * s, true, Argb(pal.white, 255), bx, by, bs, bs, 1)
        }

        ; wordmark: ARK in the text colour, SENSE in the accent gradient. Each box is a full
        ; font size wider than the measured text: GDI+ pads both sides of a string, and a
        ; box that is too tight cuts the word with "..." (step 25: "ARKSEN...")
        fp := 30 * s, wy := by + bs + 14 * s
        w1 := GpTextW(g, "ARK", Theme.FontName, fp, true)
        w2 := GpTextW(g, "SENSE", Theme.FontName, fp, true)
        wx := (W - w1 - w2) / 2
        SplashLookSplit(g, "ARK", Theme.FontName, fp, wx, wy, w1 + fp, fp * 1.4)
        SplashLookSplit(g, "SENSE", Theme.FontName, fp, wx + w1, wy, w2 + fp, fp * 1.4)
        GpText(g, "ARK", Theme.FontName, fp, true, Argb(pal.text, 255), wx, wy, w1 + fp, fp * 1.4)
        sb := GpGrad(wx + w1, wy, w2, fp, Argb(acc, 255), Argb(acc2, 255), 0)
        GpTextB(g, "SENSE", Theme.FontName, fp, true, sb, wx + w1, wy, w2 + fp, fp * 1.4)
        GpFreeBrush(sb)
        GpText(g, "Slopcoded & tested by pseidonx", Theme.FontName, 11 * s, false, Argb(pal.dim, 255),
               cx, wy + fp * 1.35, cw, 16 * s, 1)

        ; status line + percentage
        pad := 38 * s
        bx2 := cx + pad, bw := cw - 2 * pad, bh := 7 * s, by2 := cy + ch - 34 * s
        GpText(g, Splash.Text, Theme.FontName, 11.5 * s, false, Argb(pal.dim, 255), bx2, by2 - 24 * s, bw * 0.75, 18 * s)
        GpText(g, Round(p) . "%", Theme.FontName, 12 * s, true, Argb(acc, 255), bx2 + bw * 0.5, by2 - 24 * s, bw * 0.5, 18 * s, 2)
        ; the bar: track, glowing gradient fill, a shine sweeping along it
        GpFillRound(g, bx2, by2, bw, bh, bh / 2, Argb(pal.white, 22))
        fw := Max(bh, bw * p / 100)
        GpGlow(g, bx2, by2, fw, bh, bh / 2, acc, 190 + 65 * breathe, 13 * s, 6)
        fb := GpGrad(bx2, by2, bw, bh, Argb(acc, 255), Argb(acc2, 255), 0)
        GpFillRoundB(g, bx2, by2, fw, bh, bh / 2, fb), GpFreeBrush(fb)
        sw := Max(20 * s, bw * 0.12)
        sx := Mod(el * 0.32 * s, fw + sw) - sw
        if (fw > sw) {
            x1 := Max(bx2, bx2 + sx), x2 := Min(bx2 + fw, bx2 + sx + sw)
            if (x2 > x1) {
                sh := GpGrad(bx2 + sx, by2, sw, bh, Argb(pal.white, 0), Argb(pal.white, 150), 0)
                DllCall("gdiplus\GdipSetLineSigmaBlend", "Ptr", sh, "Float", 0.5, "Float", 1.0)
                GpFillRoundB(g, x1, by2, x2 - x1, bh, bh / 2, sh), GpFreeBrush(sh)
            }
        }
        ; a bright dot riding the end of the fill
        GpFillRound(g, bx2 + fw - bh * 0.8, by2 - bh * 0.3, bh * 1.6, bh * 1.6, bh * 0.8, Argb(pal.white, 230))
        ; on top: holo scanlines, the cinematic tint / vignette / grain
        SplashLookTop(g, el, cx, cy, cw, ch, r)

        GpPush(Splash.Win.Hwnd, mem, Splash.X, Splash.Y, W, H, 255 * fade)
    } finally {
        GpDone(g)
        GpCanvasFree(mem, bmp, old)
    }
}

SplashClose() {
    SetTimer(SplashTick, 0)
    g := Splash.Win
    Splash.Win := ""                                ; clear first, then destroy
    if (g != "")
        try g.Destroy()
    GpFreeImage(Splash.Logo)
    Splash.Logo := 0
    SplashLookFree()
    Splash.Preview := false
    if Splash.Done {
        Splash.Done := false
        BootShow()
    }
}

; end of boot: show the menu now, or once the splash has finished
BootDone() {
    if (Splash.Win != "")
        Splash.Done := true
    else
        BootShow()
}

BootShow() {
    ShowMenu(CurrentRegion() ? "" : "antidote")
    if Theme.SelfCheck
        SetTimer(SelfCheckStartup, -700)
}

SelfCheckStartup() => SelfCheck(false)

; ==== Settings search =============================================================
; Every label, toggle, button and group title on every page is indexed with its
; page, its group and its tooltip. Typing in the footer box lists the matches;
; picking one opens that page and flashes the setting.

SearchAdd(page, ctrl, text, tip := "") {
    Search.Idx.Push({page: page, ctrl: ctrl, text: text, group: Search.Group,
                     hay: StrLower(text . " " . tip . " " . Search.Group . " " . page)})
}

; ranked matches for the box's text: every word must appear somewhere; a match in
; the setting's own name ranks above one found only in its tooltip or group
SearchFind(q) {
    words := StrSplit(StrLower(Trim(q)), " ")
    best := [], rest := []
    for it in Search.Idx {
        ok := true
        for w in words {
            if (w != "" && !InStr(it.hay, w)) {
                ok := false
                break
            }
        }
        if !ok
            continue
        if InStr(StrLower(it.text), words[1])
            best.Push(it)
        else
            rest.Push(it)
    }
    for it in rest
        best.Push(it)
    while (best.Length > 8)
        best.Pop()
    return best
}

SearchChanged(*) {
    if !UI.Ctrl.Has("search")
        return
    q := Trim(UI.Ctrl["search"].Value)
    SearchClose()
    if (StrLen(q) < 2)
        return
    hits := SearchFind(q)
    Search.Hits := hits
    e := UI.Ctrl["search"]
    ControlGetPos(&ex, &ey, &ew, &eh, e)
    WinGetClientPos(&cx, &cy, , , "ahk_id " . UI.Hwnd)
    rowH := Round(24 * A_ScreenDPI / 96)
    wPx  := Round(330 * A_ScreenDPI / 96)
    n := Max(1, hits.Length)
    p := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +Owner" . UI.Hwnd)
    StreamHide(p.Hwnd)
    p.BackColor := Theme.Panel2
    p.MarginX := 0, p.MarginY := 0
    if (hits.Length = 0) {
        p.SetFont("s9 Norm", Theme.FontName)
        Paint(p.Add("Text", "x0 y0 w" . wPx . " h" . rowH . " +0x200", "  nothing found"), Theme.Panel2, Theme.Dim)
    }
    for i, it in hits {
        p.SetFont("s8 Bold", Theme.FontName)
        pg := Paint(p.Add("Text", "x0 y" . ((i - 1) * rowH) . " w" . Round(wPx * 0.27) . " h" . rowH
                        . " +0x200 +0x100", "  " . StrUpper(it.page)), Theme.Panel2, Theme.Accent)
        p.SetFont("s9 Norm", Theme.FontName)
        tx := Paint(p.Add("Text", "x" . Round(wPx * 0.27) . " y" . ((i - 1) * rowH) . " w" . (wPx - Round(wPx * 0.27))
                        . " h" . rowH . " +0x200 +0x100", it.text), Theme.Panel2, Theme.Text)
        pg.OnEvent("Click", SearchPickCb(i))
        tx.OnEvent("Click", SearchPickCb(i))
    }
    Search.Popup := p
    p.Show("x" . (cx + ex + ew - wPx) . " y" . (cy + ey + eh + 4) . " w" . wPx . " h" . (n * rowH) . " NoActivate")
}

SearchPickCb(i) => (*) => SearchPickLater(i)

; deferred, like the dropdowns: never destroy a window from its own click event
SearchPickLater(i) {
    if (Search.Popup != "")
        try Search.Popup.Hide()
    SetTimer(SearchGo.Bind(i), -10)
}

SearchGo(i) {
    SearchClose()
    if (i > Search.Hits.Length)
        return
    it := Search.Hits[i]
    if (UI.Page != it.page)
        ShowPage(it.page)
    SearchFlash(it.ctrl)
}

; Enter in the box: go to the first match
SearchEnter() {
    if (Search.Hits.Length >= 1)
        SearchGo(1)
}

SearchClose() {
    p := Search.Popup
    Search.Popup := ""                              ; clear first, then destroy
    if (p = "")
        return
    try {
        for hwnd, ctl in p {
            if UI.CustomBg.Has(ctl.Hwnd)
                UI.CustomBg.Delete(ctl.Hwnd)
            if UI.CustomFg.Has(ctl.Hwnd)
                UI.CustomFg.Delete(ctl.Hwnd)
        }
    }
    try p.Destroy()
}

; light the found setting up for a moment so the eye lands on it
SearchFlash(ctrl) {
    try {
        h := ctrl.Hwnd
        old := UI.CustomBg.Has(h) ? UI.CustomBg[h] : Theme.Header
        Paint(ctrl, MixHex(Theme.Accent, old, 0.45))
        SetTimer(SearchUnflash.Bind(ctrl, old), -1600)
    }
}

SearchUnflash(ctrl, old) {
    try Paint(ctrl, old)
}

; Ctrl+F while the menu is in front
SearchFocus() {
    if UI.Ctrl.Has("search")
        try UI.Ctrl["search"].Focus()
}

SearchHasFocus() => UI.Visible && UI.Ctrl.Has("search")
                    && DllCall("user32\GetFocus", "Ptr") = UI.Ctrl["search"].Hwnd

SearchClear() {
    SearchClose()
    if UI.Ctrl.Has("search")
        UI.Ctrl["search"].Value := ""
}

; ==== Clean screenshot ============================================================
; Copies ARK's window (or the main screen) straight from the screen. BitBlt
; without the CAPTUREBLT flag leaves out layered windows - this script's pills,
; stats card and menu all are - so the shot is clean without hiding anything.
; Saved as a BMP via GetDIBits into our own fixed-size buffers, then converted to
; PNG in the background by PowerShell (System.Drawing). If that conversion fails,
; the BMP simply stays.

ShotTake(*) {
    static busy := false
    if busy
        return
    busy := true
    try {
        name := ShotCapture()
        Flash("screenshot saved: " . name)
        Logg("shot", "saved " . name)
    } catch as e {
        Flash("screenshot failed: " . e.Message)
        Logg("shot", "failed: " . e.Message)
    }
    busy := false
}

ShotCapture() {
    x := 0, y := 0, w := A_ScreenWidth, h := A_ScreenHeight
    for target in Store.GameTargets {
        if WinExist(target) {
            WinGetPos(&x, &y, &w, &h, target)
            break
        }
    }
    if (w < 16 || h < 16)
        throw Error("nothing to capture")
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
    bmp := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", scr, "Int", w, "Int", h, "Ptr")
    old := DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr")
    selected := true
    try {
        if !DllCall("gdi32\BitBlt", "Ptr", mem, "Int", 0, "Int", 0, "Int", w, "Int", h,
                    "Ptr", scr, "Int", x, "Int", y, "UInt", 0x00CC0020)       ; SRCCOPY only
            throw Error("could not copy the screen")
        if Theme.ShotStamp
            ShotStamp(mem, w, h)
        DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old, "Ptr")         ; GetDIBits needs it free
        selected := false
        return ShotSave(scr, bmp, w, h)
    } finally {
        if selected
            DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old, "Ptr")
        DllCall("gdi32\DeleteObject", "Ptr", bmp)
        DllCall("gdi32\DeleteDC", "Ptr", mem)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    }
}

; time, server and server response in the bottom-right corner, with a shadow
ShotStamp(hdc, w, h) {
    txt := FormatTime(, "yyyy-MM-dd  HH:mm:ss")
    if (Stats.Server != "")
        txt .= "   " . Stats.Server . ":" . Stats.ServerPort
    if (Stats.Query >= 0)
        txt .= "   server " . Stats.Query . " ms"
    else if (Stats.Ping >= 0)
        txt .= "   ping " . Stats.Ping . " ms"
    txt .= "   ArkSense"
    f := GdiFont(10, true, Theme.FontName)
    try {
        DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)
        GdiTextSize(hdc, f, txt, &tw, &th)
        x := w - tw - 14, y := h - th - 12
        GdiText(hdc, f, txt, x + 1, y + 1, "000000")
        GdiText(hdc, f, txt, x, y, "FFFFFF")
    } finally {
        DllCall("gdi32\DeleteObject", "Ptr", f)
    }
}

; 32-bit top-down BMP: 14-byte file header + 40-byte info header + pixels.
; Both buffers are allocated here at exactly the size Windows is told about.
ShotSave(scr, bmp, w, h) {
    dir := A_ScriptDir . "\Screenshots"
    DirCreate(dir)
    name := "ArkSense_" . FormatTime(, "yyyyMMdd_HHmmss")
    bmpPath := dir . "\" . name . ".bmp"
    size := w * h * 4
    bmi := Buffer(44, 0)                                ; BITMAPINFOHEADER + 1 spare RGBQUAD
    NumPut("UInt", 40, bmi, 0), NumPut("Int", w, bmi, 4), NumPut("Int", -h, bmi, 8)
    NumPut("UShort", 1, bmi, 12), NumPut("UShort", 32, bmi, 14)   ; planes, bits; BI_RGB = 0
    bits := Buffer(size, 0)
    got := DllCall("gdi32\GetDIBits", "Ptr", scr, "Ptr", bmp, "UInt", 0, "UInt", h,
                   "Ptr", bits, "Ptr", bmi, "UInt", 0)
    if (got != h)
        throw Error("copied " . got . " of " . h . " lines")
    hdr := Buffer(54, 0)
    NumPut("UShort", 0x4D42, hdr, 0)                    ; "BM"
    NumPut("UInt", 54 + size, hdr, 2)
    NumPut("UInt", 54, hdr, 10)                         ; pixels start after both headers
    NumPut("UInt", 40, hdr, 14), NumPut("Int", w, hdr, 18), NumPut("Int", -h, hdr, 22)
    NumPut("UShort", 1, hdr, 26), NumPut("UShort", 32, hdr, 28)
    NumPut("UInt", size, hdr, 34)
    f := FileOpen(bmpPath, "w")
    f.RawWrite(hdr, 54)
    f.RawWrite(bits, size)
    f.Close()
    ; PNG in the background; a path with a quote in it just keeps the BMP
    if !InStr(dir, "'") {
        png := dir . "\" . name . ".png"
        cmd := "Add-Type -AssemblyName System.Drawing; "
             . "$b = New-Object System.Drawing.Bitmap '" . bmpPath . "'; "
             . "$b.Save('" . png . "', [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); "
             . "Remove-Item -LiteralPath '" . bmpPath . "'"
        try Run('powershell.exe -NoProfile -NonInteractive -Command "' . cmd . '"', , "Hide")
        return name . ".png"
    }
    return name . ".bmp"
}

ShotFolder(*) {
    dir := A_ScriptDir . "\Screenshots"
    DirCreate(dir)
    try Run('explorer.exe "' . dir . '"')
}

; ==== Self-check ==================================================================
; Looks for the things that most often make ArkSense "not work": missing helper
; files, no scan area, hotkeys that clash or failed to bind, missing pictures,
; ARK not in borderless mode. Shows a short report; every problem also goes to Logs.

SelfCheck(fromButton := true) {
    res := []                                           ; [state, text]: 1 ok, 0 problem, 2 info
    res.Push([A_IsAdmin ? 1 : 0, A_IsAdmin ? "running as admin" : "not running as admin - hotkeys may not reach ARK"])
    miss := []
    for f in ["ServerDetect.ps1", "ServerQuery.ps1", "ArkSenseOverlay.cs", "ArkSenseFps.cs", "NowPlaying.ps1"] {
        if !FileExist(A_ScriptDir . "\lib\" . f)
            miss.Push(f)
    }
    if miss.Length
        res.Push([0, "missing in lib: " . SelfJoin(miss)])
    else
        res.Push([1, "helper scripts present"])
    if OvlOn()
        res.Push([1, "smooth overlay renderer running"])
    else if (Theme.Renderer = "Classic")
        res.Push([2, "classic overlay look (step 9) - Modern look is off in Overlay > Display"])
    else
        res.Push([0, "modern look unavailable (classic in use): " . SubStr(Ovl.Why, 1, 120)])
    if Theme.StreamerMode {
        ApplyStreamerMode()
        if Stream.Failed
            res.Push([0, "streamer mode: " . Stream.Failed . " window(s) not hidden (Logs says why)"])
        else
            res.Push([1, "streamer mode: " . Stream.Hidden . " windows hidden from capture ("
                        . Theme.StreamerScope . ")"])
    }
    if StatNeed("fps") {
        if (Stats.Fps >= 0)
            res.Push([1, "FPS counter running (" . Stats.Fps . " fps)"])
        else if (Stats.FpsInfo != "")
            res.Push([(InStr(Stats.FpsInfo, "unavailable") || InStr(Stats.FpsInfo, "could not")
                       || InStr(Stats.FpsInfo, "needs")) ? 0 : 2, "FPS: " . SubStr(Stats.FpsInfo, 1, 120)])
    }
    if Np.On {
        if (Np.Via = "media session" || (Np.Pid && Np.Note = ""))
            res.Push([1, "Now playing reads Windows' media sessions"])
        else if (Np.Note != "" && Np.Note != "starting...")
            res.Push([2, "Now playing: " . SubStr(Np.Note, 1, 110) . " - using window titles"])
    }
    if (Stats.Bar && Stats.CardOn)
        res.Push([2, "stats card shown as a bar"])
    if Ct.On {
        if (CtOnCard() && !Stats.CardOn)
            res.Push([0, "clantag is set to the stats card, but the card is off (Overlay)"])
        else
            res.Push([1, "clantag on: " . Ct.Style . ", " . StrLower(Ct.Where)
                        . ((Theme.StreamerMode && Ct.Record && !CtOnCard()) ? " (shows in recordings)" : "")])
    }
    if WebOn()
        res.Push([1, "web menu running (Edge WebView2)"])
    else if (Theme.MenuEngine = "Native")
        res.Push([2, "native menu (picked in Settings > Window)"])
    else
        res.Push([0, "web menu unavailable (native in use): " . SubStr(Web.Why, 1, 120)])
    if (Filter.Name != "Off" && Filter.Ready = -1)
        res.Push([0, "screen filter can't work here: " . Filter.Err])
    if !FileExist(A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe")
        res.Push([0, "PowerShell not found - ping, server detect and PNG shots need it"])
    if CurrentRegion()
        res.Push([1, "scan area set for " . A_ScreenWidth . "x" . A_ScreenHeight])
    else
        res.Push([0, "no scan area for " . A_ScreenWidth . "x" . A_ScreenHeight . " - Antidote tab"])
    if !RegExMatch(Cfg.BuffColor, "^[0-9a-fA-F]{6}$")
        res.Push([0, "buff colour '" . Cfg.BuffColor . "' is not a hex colour"])
    if Keys.Bad.Length
        res.Push([0, "hotkeys that failed to bind: " . SelfJoin(Keys.Bad)])
    dup := SelfDupKeys()
    if dup.Length
        res.Push([0, "keys used twice: " . SelfJoin(dup)])
    if (!Keys.Bad.Length && !dup.Length)
        res.Push([1, "hotkeys bound, no clashes"])
    if (Trim(Audio.LogoPath) != "" && !FileExist(Audio.LogoPath))
        res.Push([0, "logo file not found"])
    if (Theme.WallOn && !FileExist(Theme.WallPath))
        res.Push([0, "wallpaper file not found"])
    if (Audio.MusicOn && !FileExist(Audio.MusicPath))
        res.Push([0, "music file not found"])
    try {
        IniWrite(A_Now, Store.Ini, "Meta", "LastStart")
    } catch {
        res.Push([0, "can't write ArkSense.ini - settings won't save"])
    }
    ark := ""
    for target in Store.GameTargets {
        if WinExist(target) {
            ark := target
            break
        }
    }
    if (ark = "") {
        res.Push([2, "ARK isn't running (not a problem)"])
    } else {
        WinGetPos(&ax, &ay, &aw, &ah, ark)
        if (WinGetStyle(ark) & 0xC00000)
            res.Push([0, "ARK has a title bar - use Borderless Window mode"])
        else if (aw >= A_ScreenWidth && ah >= A_ScreenHeight)
            res.Push([1, "ARK in borderless window"])
        else
            res.Push([2, "ARK window is " . aw . "x" . ah . " (screen " . A_ScreenWidth . "x" . A_ScreenHeight . ")"])
    }
    bad := 0
    for r in res {
        if (r[1] = 0) {
            bad += 1
            Logg("check", r[2])
        }
    }
    Logg("check", bad ? bad . " problem(s) found" : "all good")
    if (fromButton || bad || Theme.SelfCheck)
        SelfCheckShow(res, bad)
}

SelfJoin(arr) {
    out := ""
    for i, v in arr
        out .= ((i = 1) ? "" : ", ") . v
    return out
}

; every key ArkSense binds, listed once each; keys that appear twice
SelfDupKeys() {
    seen := Map(), dup := []
    seen.CaseSense := false
    for k in [Keys.Menu, Keys.Toggle, Keys.Fire, Keys.Pick, Keys.Kill, Keys.Shot, Desmo.Toggle,
              Mammoth.Toggle, Oc.Toggle, Ac.Toggle, Bag.Toggle, Bag.TriggerKey,
              Lay.Keys[1], Lay.Keys[2], Lay.Keys[3], Lay.NextKey, Filter.Key, Filter.NextKey, Ct.Key] {
        k := Trim(k)
        if (k = "")
            continue
        if seen.Has(k) {
            if (seen[k] = 1)
                dup.Push(k)
            seen[k] += 1
        } else {
            seen[k] := 1
        }
    }
    return dup
}

SelfCheckShow(res, bad) {
    SelfCheckClose()
    s := A_ScreenDPI / 96
    W := Round(360 * s), rowH := Round(22 * s), pad := Round(14 * s)
    H := pad * 2 + Round(30 * s) + res.Length * rowH + Round(30 * s)
    g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    StreamHide(g.Hwnd)
    g.BackColor := Theme.Header
    g.MarginX := 0, g.MarginY := 0
    g.SetFont("s10 Bold", Theme.FontName)
    Paint(g.Add("Text", "x" . pad . " y" . pad . " w" . Round(W * 0.5) . " h" . Round(22 * s) . " +0x200",
                "SELF-CHECK"), Theme.Header, Theme.Text)
    Paint(g.Add("Text", "x" . Round(W * 0.5) . " y" . pad . " w" . (Round(W * 0.5) - pad) . " h" . Round(22 * s)
                . " Right +0x200", bad ? bad . " to fix" : "all good"), Theme.Header, bad ? Theme.Bad : Theme.Ok)
    y := pad + Round(30 * s)
    for r in res {
        g.SetFont("s9 Norm", "Segoe UI Symbol")
        glyph := (r[1] = 1) ? Chr(0x2713) : (r[1] = 0) ? Chr(0x2717) : Chr(0x2022)
        col   := (r[1] = 1) ? Theme.Ok : (r[1] = 0) ? Theme.Bad : Theme.Dim
        Paint(g.Add("Text", "x" . pad . " y" . y . " w" . Round(18 * s) . " h" . rowH . " +0x200", glyph),
              Theme.Header, col)
        g.SetFont("s9 Norm", Theme.FontName)
        Paint(g.Add("Text", "x" . (pad + Round(22 * s)) . " y" . y . " w" . (W - 2 * pad - Round(22 * s))
                    . " h" . rowH . " +0x200", r[2]), Theme.Header, (r[1] = 0) ? Theme.Text : Theme.Dim)
        y += rowH
    }
    g.SetFont("s8 Bold", Theme.FontName)
    c := Paint(g.Add("Text", "x" . (W - pad - Round(70 * s)) . " y" . (y + Round(6 * s)) . " w" . Round(70 * s)
                     . " h" . Round(20 * s) . " Center +0x200 +0x100", "CLOSE"), Theme.Panel2, Theme.Text)
    c.OnEvent("Click", (*) => SetTimer(SelfCheckClose, -10))
    Check.Win := g
    g.Show(Format("x{} y{} w{} h{} NoActivate Hide", A_ScreenWidth - W - Round(20 * s), Round(20 * s), W, H))
    r := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", W + 1, "Int", H + 1,
                 "Int", Round(18 * s), "Int", Round(18 * s), "Ptr")
    if (r && !DllCall("user32\SetWindowRgn", "Ptr", g.Hwnd, "Ptr", r, "Int", 1))
        DllCall("gdi32\DeleteObject", "Ptr", r)
    SetAffinity(g.Hwnd, StreamFlag("menu"))
    g.Show("NoActivate")
    ; all good: a few seconds; problems: long enough to read
    SetTimer(SelfCheckClose, bad ? -20000 : -6000)
}

SelfCheckClose() {
    SetTimer(SelfCheckClose, 0)
    g := Check.Win
    Check.Win := ""                           ; clear first, then destroy
    if (g != "")
        try g.Destroy()
}
