; ArkSense - lib\Clantag.ahk
; Clantag (step 23): an animated tag drawn on your own screen only. Nothing is typed into
; ARK and nobody else sees it - it is an overlay like the pills and the stats card.
; Part of ArkSense.ahk; run that file, not this one.
;
; Two animations, both worked out from the clock (CtFrame), so every place that draws the
; tag shows the same frame:
;   Build-up  types itself out letter by letter behind a blinking cursor, holds, deletes,
;             starts again (the CS clantag look)
;   Decode    random symbols lock into the tag one letter at a time, hold, scramble away
;
; Two places:
;   On its own         a small see-through box (one layered window, GDI+ per-pixel alpha,
;                      built like the Now playing card), movable with MOVE / LOCK or the
;                      overlay's EDIT LAYOUT
;   On the stats card  the card's top line. Classic look: the card without the tag is kept
;                      as a bitmap (Card.BaseDC) and each frame only copies it and draws the
;                      tag, so the graph isn't redrawn 15 times a second. Modern look: the
;                      helper gets a short "ctag" message per frame.
;
; One 40 ms timer (CtTick) runs while the clantag is on. It draws only when the frame
; changed: Build-up about 7 times a second, Decode about 16 while letters scramble and not
; at all while the tag holds.

CtStyles() => ["Build-up", "Decode"]
CtPlaces() => ["On its own", "On the stats card"]
CtFonts()  => ["Consolas", "Bahnschrift", "Segoe UI", "Menu font"]

CtFace() => (Ct.Font = "Menu font") ? Theme.FontName : Ct.Font

; no control characters, no tabs; up to 24 characters
CtClean(s) => SubStr(Trim(RegExReplace(String(s), "[\x00-\x1F\x7F]", " ")), 1, 24)

CtTag() {
    t := CtClean(Ct.Text)
    return (t = "") ? "ArkSense" : t
}

; drawn in the stats card's top line (rather than on its own)
; drawn in the stats card's top line or in the stats bar (rather than on its own). The bar's
; "Clantag" toggle (lib\Bar.ahk) also puts it there.
CtOnCard() => Ct.On && (Ct.Where = "On the stats card" || (Stats.Bar && Stats.BarTag))

CtClamp() {
    Ct.Text := CtClean(Ct.Text)
    if (Ct.Text = "")
        Ct.Text := "pseidonx"
    Ct.Style := (Ct.Style = "Decode") ? "Decode" : "Build-up"
    Ct.Where := (Ct.Where = "On the stats card") ? "On the stats card" : "On its own"
    Ct.Font  := ListPick(CtFonts(), Ct.Font)
    try Ct.Speed := Max(25, Min(300, Integer(Ct.Speed)))
    catch
        Ct.Speed := 100
    try Ct.Scale := Max(50, Min(300, Integer(Ct.Scale)))
    catch
        Ct.Scale := 100
    try Ct.Alpha := Max(0, Min(255, Integer(Ct.Alpha)))
    catch
        Ct.Alpha := 170
    try Ct.X := Max(-1, Min(20000, Integer(Ct.X)))
    catch
        Ct.X := -1
    try Ct.Y := Max(-1, Min(20000, Integer(Ct.Y)))
    catch
        Ct.Y := -1
    if (Ct.X < 0 || Ct.Y < 0)
        Ct.X := -1, Ct.Y := -1
    Ct.On := Ct.On ? 1 : 0
    Ct.Bold := Ct.Bold ? 1 : 0
    Ct.Outline := Ct.Outline ? 1 : 0
    Ct.Record := Ct.Record ? 1 : 0
    for pair in [["TextColor", "FFFFFF"], ["Accent", "FF2836"], ["BgColor", "1C1C24"], ["OutlineColor", "FF2836"]] {
        k := pair[1]
        Ct.%k% := RegExMatch(Ct.%k%, "^[0-9A-Fa-f]{6}$") ? StrUpper(Ct.%k%) : pair[2]
    }
    Ct.Key := Trim(Ct.Key)
}

; ---- the animation ----------------------------------------------------------------------
CtGlyphs() => "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*+=?<>/[]{}"

; a repeatable "random" number 0..1 for n (same n, same number)
CtRnd(n) {
    x := Sin(n * 12.9898 + 78.233) * 43758.5453
    return x - Floor(x)
}

CtGlyph(n) {
    gl := CtGlyphs()
    return SubStr(gl, Floor(CtRnd(n) * StrLen(gl)) + 1, 1)
}

; the frame at t ms after the start:
;   txt   what each letter shows (the tag's letter, or a symbol while scrambling)
;   mask  per letter: 0 hidden, 1 normal colour, 2 accent colour (scrambling)
;   cur   Build-up's cursor: the letter slot it sits in (0-based), -1 = not shown
CtFrame(t) {
    tag := CtTag()
    n := StrLen(tag)
    sp := Ct.Speed / 100
    bt := t * sp                                   ; time at the base speed
    if (Ct.Style = "Decode") {
        p := Mod(bt, 4400)                         ; one cycle: lock in 1.3 s, hold 2.2 s, scramble
        tick := Floor(bt / 60)                     ; symbols change ~16x a second
        txt := "", mask := ""
        Loop Parse tag {
            i := A_Index - 1
            if (p < 1300)
                real := p > 150 + i * (1050 / n)
            else if (p < 3500)
                real := true
            else
                real := p < 3500 + i * (650 / n)
            if (real || A_LoopField = " ") {
                txt .= A_LoopField
                mask .= "1"
            } else {
                txt .= CtGlyph(tick * 31 + i * 7)
                mask .= "2"
            }
        }
        return {txt: txt, mask: mask, cur: -1}
    }
    ; Build-up: 0..n letters (one step each), hold 9 steps, delete, 3 empty steps
    frames := 2 * n + 13
    f := Mod(Floor(bt / 220), frames)
    k := (f <= n) ? f : (f <= n + 9) ? n : (f <= 2 * n + 9) ? n - (f - n - 9) : 0
    mask := ""
    Loop n
        mask .= (A_Index <= k) ? "1" : "0"
    blink := Mod(Floor(bt / 380), 2) = 0
    return {txt: tag, mask: mask, cur: blink ? k : -1}
}

CtCurFrame() {
    if !IsObject(Ct.Fr)
        Ct.Fr := CtFrame(A_TickCount - Ct.T0)
    return Ct.Fr
}

; ---- start / stop -----------------------------------------------------------------------
CtBoot() {
    Ct.T0 := A_TickCount
    CtRestart()
}

; after a settings change (APPLY, the hotkey, a profile): start the animation over and
; redraw both places
CtRestart() {
    Ct.T0 := A_TickCount
    Ct.Fr := CtFrame(0)
    Ct.Sig := "", Ct.CardSig := ""
    Ct.Moving := Ct.Moving && Ct.On && !CtOnCard()
    if Ct.On {
        SetTimer(CtTick, 40)
    } else {
        SetTimer(CtTick, 0)
        Ct.Moving := false
    }
    if !(Ct.On && !CtOnCard())
        CtHide()
    CtAffinity()
    if !CtOnCard()
        CardBaseFree()
    Card.TagLay := ""
    try RefreshStatHud()                   ; the card gains or loses its tag line
    CtStatusTick()
}

CtTick() {
    if Anim.Busy
        return
    if !Ct.On {
        SetTimer(CtTick, 0)
        CtHide()
        return
    }
    fr := CtFrame(A_TickCount - Ct.T0)
    fs := fr.txt . "|" . fr.mask . "|" . fr.cur
    if CtOnCard() {
        CtHide()
        if (fs != Ct.CardSig) {
            Ct.CardSig := fs
            Ct.Fr := fr
            try CtCardFrame(fr)
        }
        return
    }
    Ct.Fr := fr
    editing := (Ct.Moving || UI.HudDragging) ? 1 : 0
    if (!editing && !OverlayAllowed()) {
        CtHide()
        return
    }
    sig := fs . "|" . editing
    if (sig = Ct.Sig)
        return
    Ct.Sig := sig
    try CtDraw(fr, editing)
}

; ---- on its own: the box ----------------------------------------------------------------
CtHide() {
    if (Ct.Win != "" && DllCall("user32\IsWindowVisible", "Ptr", Ct.Win.Hwnd))
        DllCall("user32\ShowWindow", "Ptr", Ct.Win.Hwnd, "Int", 0)
    Ct.Sig := ""
}

; streamer mode: hidden from capture like the other overlays, unless "Show in recordings"
CtStreamFlag() => Ct.Record ? 0 : StreamFlag("overlay")

CtAffinity() {
    if (Ct.Win != "")
        SetAffinity(Ct.Win.Hwnd, CtStreamFlag())
}

CtWindow() {
    if (Ct.Win != "")
        return Ct.Win
    ; layered (0x80000) + click-through (0x20); the picture comes from UpdateLayeredWindow
    w := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")
    w.MarginX := 0, w.MarginY := 0
    Ct.Win := w
    f := CtStreamFlag()
    if f
        try DllCall("user32\SetWindowDisplayAffinity", "Ptr", w.Hwnd, "UInt", f)
    return w
}

; the saved spot, else the top centre of the main screen
CtWhere(W, H, &x, &y) {
    if (Ct.X >= 0 && Ct.Y >= 0) {
        x := Ct.X, y := Ct.Y
        return
    }
    x := (A_ScreenWidth - W) // 2
    y := Round(12 * A_ScreenDPI / 96)
}

; where each letter starts at this font: xs[i] = left edge of letter i, xs[n+1] = the end.
; Measured once per tag / font / size (letters keep their places while the frame changes).
CtBoxLayout(face, px, bold) {
    static L := ""
    tag := CtTag()
    key := face . "|" . Round(px, 2) . "|" . bold . "|" . Ct.Style . "|" . tag
    if (IsObject(L) && L.key = key)
        return L
    n := StrLen(tag)
    xs := [0], cw := px * 0.6
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    g := mem ? GpGraphics(mem) : 0
    if g {
        ; "|" after each piece keeps trailing spaces in the measure (the typographic
        ; format drops them), its own width is taken off again
        bar := GpTextW(g, "|", face, px, bold)
        Loop n
            xs.Push(Max(xs[xs.Length], GpTextW(g, SubStr(tag, 1, A_Index) . "|", face, px, bold) - bar))
        cw := GpTextW(g, "_", face, px, bold)
    } else {
        Loop n
            xs.Push(A_Index * px * 0.6)
    }
    GpDone(g)
    if mem
        DllCall("gdi32\DeleteDC", "Ptr", mem)
    L := {key: key, xs: xs, n: n, cw: cw, w: xs[n + 1] + ((Ct.Style = "Build-up") ? cw : 0)}
    return L
}

CtDraw(fr, editing) {
    if !GdipReady()
        return
    win := CtWindow()
    s := Ct.Scale / 100 * A_ScreenDPI / 96
    face := CtFace(), px := 18 * s
    L := CtBoxLayout(face, px, Ct.Bold)
    padX := Round(12 * s), padY := Round(6 * s)
    th := Round(px * 1.32)
    W := Max(Round(40 * s), Round(2 * padX + L.w)), H := 2 * padY + th
    if !GpCanvas(W, H, &mem, &bmp, &old) {
        GpCanvasFree(mem, bmp, old)
        return
    }
    g := GpGraphics(mem)
    try {
        if !g
            return
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
        r := Min(H / 2, 8 * s)
        a := editing ? Max(170, Ct.Alpha) : Ct.Alpha
        if (a > 0)
            GpFillRound(g, 0.5, 0.5, W - 1, H - 1, r, Argb(Ct.BgColor, a))
        if editing
            GpStrokeRound(g, 0.75, 0.75, W - 1.5, H - 1.5, r, Argb(OvC("Accent"), 255), Max(1.5, 1.5 * s))
        else if Ct.Outline
            GpStrokeRound(g, 0.75, 0.75, W - 1.5, H - 1.5, r, Argb(Ct.OutlineColor, 230), Max(1.5, 1.5 * s))
        ; with little or no background the letters get a dark shadow, so they read on any scene
        CtDrawLetters(g, fr, L, face, px, (W - L.w) / 2, padY, th, a < 90)

        CtWhere(W, H, &x, &y)
        if (editing && !Ct.Jump && DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd)) {
            try WinGetPos(&x, &y, , , "ahk_id " . win.Hwnd)    ; being dragged: stay put
        }
        Ct.Jump := false
        GpPush(win.Hwnd, mem, x, y, W, H)
        ; click-through unless it is being placed
        ex := WinGetExStyle("ahk_id " . win.Hwnd)
        want := editing ? (ex & ~0x20) : (ex | 0x20)
        if (want != ex)
            WinSetExStyle(want, "ahk_id " . win.Hwnd)
        if !DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd) {
            DllCall("user32\ShowWindow", "Ptr", win.Hwnd, "Int", 4)      ; SW_SHOWNOACTIVATE
            DllCall("user32\SetWindowPos", "Ptr", win.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
                    "UInt", 0x13)                                        ; on top, no move / size / activate
        }
        Ct.W := W, Ct.H := H
    } finally {
        GpDone(g)
        GpCanvasFree(mem, bmp, old)
    }
}

; each letter in its own slot, so a symbol never pushes the others around
CtDrawLetters(g, fr, L, face, px, x0, y0, th, shadow) {
    tc := Argb(Ct.TextColor, 255), ac := Argb(Ct.Accent, 255), sc := Argb("000000", 160)
    off := Max(1, Round(px / 16))
    Loop L.n {
        i := A_Index
        m := SubStr(fr.mask, i, 1)
        ch := SubStr(fr.txt, i, 1)
        if (m = "0" || m = "" || ch = " " || ch = "")
            continue
        bx := x0 + L.xs[i] - px * 0.6
        bw := L.xs[i + 1] - L.xs[i] + px * 1.2
        if shadow
            GpText(g, ch, face, px, Ct.Bold, sc, bx + off, y0 + off, bw, th, 1)
        GpText(g, ch, face, px, Ct.Bold, (m = "2") ? ac : tc, bx, y0, bw, th, 1)
    }
    if (fr.cur >= 0 && fr.cur <= L.n) {
        cx := x0 + L.xs[fr.cur + 1] - px * 0.6
        if shadow
            GpText(g, "_", face, px, Ct.Bold, sc, cx + off, y0 + off, L.cw + px * 1.2, th, 1)
        GpText(g, "_", face, px, Ct.Bold, ac, cx, y0, L.cw + px * 1.2, th, 1)
    }
}

; MOVE: the box takes clicks and can be dragged
CtMove() {
    if !Ct.On {
        Flash("turn the clantag on first (and APPLY)")
        return
    }
    CtPosFromFields()                    ; typed X / Y: it goes there first
    if CtOnCard() {                      ; in the stats card / bar: that moves (step 25)
        CardMove()
        return
    }
    Ct.Moving := true
    Ct.Sig := ""
    CtTick()
    Flash("drag the clantag where you want it, then press LOCK")
}

; LOCK: remember where it is
CtLock() {
    if (CtOnCard() || Card.Moving) {
        CardLock()
        return
    }
    CtCapture()
    Ct.Moving := false
    Ct.Sig := ""
    SaveIni()
    CtTick()
    CtPosFields()
    CtStatusTick()
    Flash("clantag position saved")
}

CtCapture() {
    if (Ct.Win = "" || !DllCall("user32\IsWindowVisible", "Ptr", Ct.Win.Hwnd))
        return
    try {
        WinGetPos(&x, &y, , , "ahk_id " . Ct.Win.Hwnd)
        Ct.X := Max(0, x), Ct.Y := Max(0, y)
    }
}

CtReset() {
    if CtOnCard() {                      ; the card / bar back to its default spot
        if Pill.Pos.Has("stats")
            Pill.Pos.Delete("stats")
        SaveIni()
        RefreshStatHud()
        CardPosFields()
        CtPosFields()
        Flash((Stats.Bar ? "bar" : "stats card") . " back to its default spot")
        return
    }
    Ct.X := -1, Ct.Y := -1
    Ct.Jump := true
    Ct.Sig := ""
    SaveIni()
    CtTick()
    CtPosFields()
    CtStatusTick()
    Flash("clantag back to the top centre")
}

; X / Y on the page: the box's corner, or - while the tag sits in the stats card / bar -
; the card's corner (what you see move)
CtPosFields() {
    if CtOnCard()
        CardWant(&x, &y, &size)
    else
        x := Ct.X, y := Ct.Y
    if UI.Ctrl.Has("ctX")
        UI.Ctrl["ctX"].Value := x
    if UI.Ctrl.Has("ctY")
        UI.Ctrl["ctY"].Value := y
}

; typed X / Y -> where it goes now (also while MOVE is on); true when it changed.
; onCard: which one the fields belong to (the place before a Where change in APPLY)
CtPosFromFields(onCard := "") {
    if !(UI.Ctrl.Has("ctX") && UI.Ctrl.Has("ctY"))
        return false
    if (onCard = "")
        onCard := CtOnCard()
    x := Trim(UI.Ctrl["ctX"].Value), y := Trim(UI.Ctrl["ctY"].Value)
    if !(RegExMatch(x, "^-?\d+$") && RegExMatch(y, "^-?\d+$"))
        return false
    nx := Integer(x), ny := Integer(y)
    if onCard {
        CardWant(&cx, &cy, &size)
        if (nx = cx && ny = cy)
            return false
        CardPlace(Max(-5000, Min(20000, nx)), Max(-5000, Min(20000, ny)))
        CardPosFields()
        return true
    }
    nx := Max(-1, Min(20000, nx)), ny := Max(-1, Min(20000, ny))
    if (nx < 0 || ny < 0)
        nx := -1, ny := -1
    if (nx = Ct.X && ny = Ct.Y)
        return false
    Ct.X := nx, Ct.Y := ny
    Ct.Jump := true
    Ct.Sig := ""
    return true
}

; the show / hide hotkey
CtToggleKey(*) {
    Ct.On := Ct.On ? 0 : 1
    SetToggle("ctOn", Ct.On)
    SaveIni()
    CtRestart()
    Flash("clantag " . (Ct.On ? "on" : "off"))
}

; ---- on the stats card ------------------------------------------------------------------
; one tag frame: the modern card gets a short message, the classic one is redrawn from
; its saved bitmap
CtCardFrame(fr) {
    if !CardShown()
        return
    if OvlOn()
        OvlSend("ctag`t" . OvlClean(fr.txt) . "`t" . fr.mask . "`t" . fr.cur)
    else
        CardTagFrame()
}

; GDI fonts for the tag, kept between frames
CtGdiFont(pt, bold, face) {
    static cache := Map()
    k := face . "|" . pt . "|" . bold
    if cache.Has(k)
        return cache[k]
    if (cache.Count > 6) {
        for kk, fo in cache
            DllCall("gdi32\DeleteObject", "Ptr", fo)
        cache.Clear()
        Card.TagLay := ""
    }
    cache[k] := GdiFont(pt, bold, face)
    return cache[k]
}

; the tag's letter places at the classic card's size (cached in Card.TagLay)
CtCardLayout(hdc, size) {
    pt := Max(7, Round(size * 1.15 * Ct.Scale / 100))
    face := CtFace(), tag := CtTag()
    key := face . "|" . pt . "|" . Ct.Bold . "|" . Ct.Style . "|" . tag
    L := Card.TagLay
    if (IsObject(L) && L.key = key)
        return L
    font := CtGdiFont(pt, Ct.Bold, face)
    n := StrLen(tag)
    xs := [0]
    Loop n {
        GdiTextSize(hdc, font, SubStr(tag, 1, A_Index), &w, &h)
        xs.Push(Max(xs[xs.Length], w))
    }
    GdiTextSize(hdc, font, "_", &cw, &h)
    GdiTextSize(hdc, font, "Ag", &aw, &th)
    L := {key: key, pt: pt, face: face, xs: xs, n: n, cw: cw, h: th,
          w: xs[n + 1] + ((Ct.Style = "Build-up") ? cw : 0)}
    Card.TagLay := L
    return L
}

; draw the current frame at Card.TagX / TagY
CardTagDraw(hdc) {
    L := Card.TagLay
    if !IsObject(L)
        return
    fr := CtCurFrame()
    font := CtGdiFont(L.pt, Ct.Bold, L.face)
    x0 := Card.TagX, y0 := Card.TagY
    Loop L.n {
        i := A_Index
        m := SubStr(fr.mask, i, 1)
        ch := SubStr(fr.txt, i, 1)
        if (m = "0" || m = "" || ch = " " || ch = "")
            continue
        x := x0 + L.xs[i]
        if (m = "2") {                                   ; a symbol: centred in the letter's slot
            GdiTextSize(hdc, font, ch, &gw, &gh)
            x += (L.xs[i + 1] - L.xs[i] - gw) // 2
        }
        GdiText(hdc, font, ch, x, y0, (m = "2") ? Ct.Accent : Ct.TextColor)
    }
    if (fr.cur >= 0 && fr.cur <= L.n)
        GdiText(hdc, font, "_", x0 + L.xs[fr.cur + 1], y0, Ct.Accent)
}

; keep the card as drawn so far (everything but the tag) for the frames in between
CardBaseSave(src, W, H) {
    if (!Card.BaseDC || Card.BaseW != W || Card.BaseH != H) {
        scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
        dc  := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
        bmp := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", scr, "Int", W, "Int", H, "Ptr")
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
        if (!dc || !bmp) {
            if bmp
                DllCall("gdi32\DeleteObject", "Ptr", bmp)
            if dc
                DllCall("gdi32\DeleteDC", "Ptr", dc)
            CardBaseFree()
            return
        }
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bmp, "Ptr")
        CardBaseFree()
        Card.BaseDC := dc, Card.BaseBmp := bmp, Card.BaseOld := old, Card.BaseW := W, Card.BaseH := H
    }
    DllCall("gdi32\BitBlt", "Ptr", Card.BaseDC, "Int", 0, "Int", 0, "Int", W, "Int", H,
            "Ptr", src, "Int", 0, "Int", 0, "UInt", 0xCC0020)           ; SRCCOPY
}

; clear the handles first, then free (a timer can run in between)
CardBaseFree() {
    dc := Card.BaseDC, bmp := Card.BaseBmp, old := Card.BaseOld
    Card.BaseDC := 0, Card.BaseBmp := 0, Card.BaseOld := 0, Card.BaseW := 0, Card.BaseH := 0
    if (dc && old)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old, "Ptr")
    if bmp
        DllCall("gdi32\DeleteObject", "Ptr", bmp)
    if dc
        DllCall("gdi32\DeleteDC", "Ptr", dc)
}

; one tag frame on the classic card: saved card + tag, pushed in one call
CardTagFrame() {
    win := UI.StatHud
    if (OvlOn() || win = "" || Anim.Busy)
        return
    if !DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd)
        return
    if Stats.Bar {                                       ; the stats bar is small: redraw it whole
        BarDraw(Card.Size ? Card.Size : Stats.HudFontSize)
        return
    }
    if !Card.BaseDC
        return
    W := Card.BaseW, H := Card.BaseH, base := Card.BaseDC
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
    bmp := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", scr, "Int", W, "Int", H, "Ptr")
    old := bmp ? DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr") : 0
    try {
        if !bmp
            return
        DllCall("gdi32\BitBlt", "Ptr", mem, "Int", 0, "Int", 0, "Int", W, "Int", H,
                "Ptr", base, "Int", 0, "Int", 0, "UInt", 0xCC0020)
        DllCall("gdi32\SetBkMode", "Ptr", mem, "Int", 1)              ; TRANSPARENT text
        CardTagDraw(mem)
        CardPush(win, mem, W, H, Card.Alpha)
    } finally {
        if old
            DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old, "Ptr")
        if bmp
            DllCall("gdi32\DeleteObject", "Ptr", bmp)
        DllCall("gdi32\DeleteDC", "Ptr", mem)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    }
}

; the "ct" lines of the modern card message: the tag, its look and the current frame
OvlCardTag() {
    if !CtOnCard()
        return ""
    fr := CtCurFrame()
    return "`nct`t" . OvlClean(CtTag()) . "`t" . OvlClean(CtFace()) . "`t" . Ct.Bold . "`t" . Ct.Scale
         . "`t" . Ct.TextColor . "`t" . Ct.Accent . "`t" . ((Ct.Style = "Build-up") ? 1 : 0)
         . "`t" . Ct.Outline . "`t" . Ct.OutlineColor . "`t" . Ct.BgColor . "`t" . Ct.Alpha
         . "`nctf`t" . OvlClean(fr.txt) . "`t" . fr.mask . "`t" . fr.cur
}

; ---- page -------------------------------------------------------------------------------
CtStatusText() {
    if !Ct.On
        return "off" . ((Ct.Key != "") ? "   (" . HotDisp(Ct.Key) . " shows it)" : "")
    if CtOnCard() {
        where := Stats.Bar ? "in the stats bar" : "on the stats card"
        if !Stats.CardOn
            return where . " - but the card is off (Overlay > Stats card)"
        return where . "   " . Ct.Style
    }
    return "on its own   " . Ct.Style . "   " . ((Ct.X >= 0) ? Ct.X . ", " . Ct.Y : "top centre")
}

CtStatusTick() {
    if !UI.Ctrl.Has("ctStatus")
        return
    c := UI.Ctrl["ctStatus"]
    t := "now   " . CtStatusText()
    if (c.Text != t) {
        c.Text := t
        bad := CtOnCard() && !Stats.CardOn
        Paint(c, "", bad ? Theme.Bad : Ct.On ? Theme.Ok : Theme.Dim)
    }
    BarStatusTick()
}

BuildClantag(g) {
    p := "clantag"
    gr := GroupBegin(g, p, 0, Layout.TOP, "Clantag")
    GText(gr, GRow(gr), "ctStatus")
    GToggle(gr, GRow(gr), "ctOn", "Show the clantag", Ct.On,
            "An animated tag on your own screen. Nothing is typed into ARK - other players "
          . "never see it. Follows Overlay > Only in ARK.")
    y := GRow(gr)
    GLabel(gr, y, "Tag", "Up to 24 characters.", 60)
    GField(gr, y, "ctText", Ct.Text, false, 150)
    y := GRow(gr), GLabel(gr, y, "Animation", "Build-up: types itself out letter by letter behind a "
          . "cursor, holds, deletes (the CS clantag look). Decode: random symbols lock into the tag "
          . "one by one, hold, then scramble away.", 100),
        GDrop(gr, y, "ctStyle", CtStyles(), Ct.Style, 130)
    GSlider(gr, GRow(gr), "ctSpeed", "Speed", Ct.Speed, 25, 300, "%", 5,
            "100% = Build-up adds a letter every 0.22 s, Decode runs a 4.4 s cycle.")
    y := GRow(gr), GLabel(gr, y, "Where", "On its own: a small box you can move anywhere. On the "
          . "stats card: in the card's top line (it moves and resizes with the card, and uses the "
          . "card's own background and outline; with the stats card shown as a bar, it sits in "
          . "the bar).", 70),
        GDrop(gr, y, "ctWhere", CtPlaces(), Ct.Where, 150)
    y := GRow(gr)
    GLabel(gr, y, "Show / hide key", "Turns the clantag on and off. Empty = no key.")
    GHot(gr, y, "ctKey", Ct.Key)
    GToggle(gr, GRow(gr), "ctRecord", "Show in recordings", Ct.Record,
            "On: the clantag stays visible in OBS / Medal / Discord captures even while streamer "
          . "mode hides the other overlays. On the stats card it follows the card instead.")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, Layout.TOP, "Look")
    y := GRow(gr), GLabel(gr, y, "Font", "Consolas keeps every letter the same width (Decode "
          . "looks steadiest). Menu font = the font picked in Settings.", 60),
        GDrop(gr, y, "ctFont", CtFonts(), Ct.Font, 130)
    GToggle(gr, GRow(gr), "ctBold", "Bold", Ct.Bold)
    GSlider(gr, GRow(gr), "ctScale", "Size", Ct.Scale, 50, 300, "%", 5)
    GSlider(gr, GRow(gr), "ctAlpha", "Background", Ct.Alpha, 0, 255, "", 1,
            "How solid the box behind the tag is (also inside the stats bar / card). 0 = no box, "
          . "just the letters (they get a dark shadow so they stay readable).")
    GToggle(gr, GRow(gr), "ctOutline", "Outline", Ct.Outline, "A line around the tag - around its own box, "
          . "or around the tag inside the stats bar / card. Press APPLY to see it.")
    for r in [["Text", "ctTextColor", Ct.TextColor, "The tag's letters."],
              ["Accent", "ctAccent", Ct.Accent, "Build-up's cursor and Decode's scrambling symbols."],
              ["Background", "ctBgColor", Ct.BgColor, "The box behind the tag."],
              ["Outline colour", "ctOutlineColor", Ct.OutlineColor, "The line around the box."]] {
        y := GRow(gr)
        GLabel(gr, y, r[1], r[4])
        GSwatch(gr, y, r[2], r[2] . "Sw", r[3])
    }
    y := GRow(gr)
    GLabel(gr, y, "Presets", "Sets the accent and the outline colour.", 70)
    for i, col in ["FF2836", "18C8E6", "4CD07A", "A06BFF", "FFA23A", "FFFFFF"] {
        c := MkBtn(g, "x" . (GRight(gr) - 6 * 26 + 4 + (i - 1) * 26) . " y" . (y + 3) . " w20 h18", "",
                   CtPresetCb(col), col, col)
        Reg(p, c)
    }
    GroupEnd(gr)

    gr := GroupBegin(g, p, 2, Layout.TOP, "Position")
    y := GRow(gr)
    GLabel(gr, y, "X / Y", "Top-left corner in screen pixels. Type them and press MOVE or APPLY "
        . "to put it there. -1 / -1 = top centre of the main screen. While the tag sits in the "
        . "stats card or bar, these are the card's / bar's corner and MOVE moves that.")
    if CtOnCard()
        CardWant(&px, &py, &psz)
    else
        px := Ct.X, py := Ct.Y
    GField(gr, y, "ctX", px, false, 52, GRight(gr) - 110)
    GField(gr, y, "ctY", py, false, 52)
    GButtons(gr, GRow(gr), [["MOVE", (*) => CtMove(), "accent"], ["LOCK", (*) => CtLock()]],
             ["Goes to the X / Y above, then you can drag it (the stats card / bar when the tag "
            . "is in it - the pills stay locked).", "Saves where it is."])
    GButtons(gr, GRow(gr), [["RESET POSITION", (*) => CtReset()]],
             ["Back to the top centre of the main screen."])
    y2 := GroupEnd(gr)

    BarGroup(g, p, y2)                                   ; the stats bar (lib\Bar.ahk)

    FootButtons(g, p, [["APPLY", (*) => ApplyClantag(), "accent"]])
    CtStatusTick()
}

CtPresetCb(col) => (*) => CtSetPreset(col)

CtSetPreset(col) {
    Ct.Accent := col, Ct.OutlineColor := col
    for name in ["ctAccent", "ctOutlineColor"] {
        if UI.Ctrl.Has(name)
            UI.Ctrl[name].Value := col
        if UI.Ctrl.Has(name . "Sw")
            Paint(UI.Ctrl[name . "Sw"], col)
    }
    SaveIni()
    Ct.Sig := "", Ct.CardSig := ""
    Card.TagLay := ""
    try RefreshStatHud()
}

ApplyClantag() {
    wasCard := CtOnCard()                                ; what the X / Y fields were showing
    Ct.On := ChkVal(UI.Ctrl["ctOn"])
    t := CtClean(UI.Ctrl["ctText"].Value)
    if (t != "")
        Ct.Text := t
    Ct.Style := DropValue("ctStyle", Ct.Style)
    Ct.Speed := SliderValue("ctSpeed", 100)
    Ct.Where := DropValue("ctWhere", Ct.Where)
    Ct.Key := Trim(UI.Ctrl["ctKey"].Value)
    Ct.Record := ChkVal(UI.Ctrl["ctRecord"])
    Ct.Font := DropValue("ctFont", Ct.Font)
    Ct.Bold := ChkVal(UI.Ctrl["ctBold"])
    Ct.Scale := SliderValue("ctScale", 100)
    Ct.Alpha := SliderValue("ctAlpha", 170)
    Ct.Outline := ChkVal(UI.Ctrl["ctOutline"])
    Ct.TextColor := Hex("ctTextColor", Ct.TextColor)
    Ct.Accent := Hex("ctAccent", Ct.Accent)
    Ct.BgColor := Hex("ctBgColor", Ct.BgColor)
    Ct.OutlineColor := Hex("ctOutlineColor", Ct.OutlineColor)
    CtClamp()
    CtPosFromFields(wasCard)                             ; typed X / Y: moves it now
    barChanged := BarReadUI()
    UI.Ctrl["ctText"].Value := Ct.Text
    for name in ["ctTextColor", "ctAccent", "ctBgColor", "ctOutlineColor"] {
        k := SubStr(name, 3)
        UI.Ctrl[name].Value := Ct.%k%
        Paint(UI.Ctrl[name . "Sw"], Ct.%k%)
    }
    CtPosFields()
    ApplyHotkeys()
    SaveIni()
    if barChanged {
        RebuildStatHud()                                 ; graph card <-> bar
        SetTimer(StatsTick, -50)                         ; its numbers right away
    }
    CtRestart()
    warn := (CtOnCard() && !Stats.CardOn) ? " - turn the stats card on (Overlay) to see it" : ""
    Logg("clantag", (Ct.On ? "on: " . Ct.Style . ", " . StrLower(Ct.Where) : "off"))
    Flash("clantag and bar settings applied" . warn)
}
