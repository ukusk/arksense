; ArkSense - lib\Bar.ahk
; Stats bar (step 24): the stats card as one slim bar instead of the graph -
;   [bolt] ArkSense | clantag | [signal] 26 ms | [chart] 77 fps | CPU 31% | GPU 40% | RAM 52%
; Ping and FPS by default; CPU, GPU, RAM and the clantag are switched on separately. It is
; the same window as the stats card (UI.StatHud), so it moves and resizes with EDIT LAYOUT,
; follows "Show the stats card", "Only in ARK", streamer mode and the card's background,
; opacity, outline and text colour (Overlay > Look). Settings: Visuals > Clantag & bar.
; Part of ArkSense.ahk; run that file, not this one.
;
; Classic look: drawn with GDI+ into a 32-bit bitmap with real per-pixel alpha (the
; background is see-through by the card's opacity, text stays solid), redrawn once a
; second with the stats and on each clantag frame. Modern look: the C# helper draws it
; (Render.Bar) from the same numbers.

; what the samplers measure: the graph card's toggles, or the bar's when it is a bar
StatNeed(k) {
    if Stats.Bar {
        switch k {
            case "cpu":   return Stats.BarCpu
            case "ram":   return Stats.BarRam
            case "gpu":   return Stats.BarGpu
            case "ping":  return Stats.BarPing
            case "fps":   return Stats.BarFps
        }
        return 0
    }
    switch k {
        case "cpu":   return Stats.ShowCpu
        case "ram":   return Stats.ShowRam
        case "gpu":   return Stats.ShowGpu
        case "ping":  return Stats.ShowPing
        case "fps":   return Stats.ShowPing && Stats.ShowFps
        case "clock": return Stats.ShowClock
    }
    return 0
}

; the bar's parts after the brand (and the clantag), left to right:
; {k: ping|fps|cpu|gpu|ram, v: value text, u: unit or label, vc: value colour, ic: icon colour, lvl: signal 1-3}
BarItems() {
    out := []
    if Stats.BarPing {
        nv := NetView()
        ms := nv.ping
        out.Push({k: "ping", v: (ms >= 0) ? String(ms) : "--", u: "ms", vc: Theme.HudTextColor,
                  ic: PingColour(ms), lvl: (ms < 0) ? 0 : (ms < 80) ? 3 : (ms < 150) ? 2 : 1})
    }
    if Stats.BarFps
        out.Push({k: "fps", v: (Stats.Fps >= 0) ? String(Stats.Fps) : "--", u: "fps", vc: Theme.HudTextColor,
                  ic: OvC("Accent2"), lvl: 0})
    for k in ["cpu", "gpu", "ram"] {
        if !Stats.Bar%k%
            continue
        v := StatValue(k)
        out.Push({k: k, v: StatTxt(v, "%"), u: StrUpper(k), vc: StatColour(v), ic: "", lvl: 0})
    }
    return out
}

; ---- logos (step 25) -------------------------------------------------------------------------
; Each logo is a few shapes on a 16 x 16 grid, filled with the "alternate" rule, so a shape
; inside another one cuts a hole (the skull's eyes, the crosshair's ring). The same text goes
; to the C# helper (the "logo" line), so both looks draw exactly the same logos.
;   p x,y,x,y,...  polygon    e cx,cy,rx,ry  ellipse    r x,y,w,h  rectangle
BarLogos() => ["Lightning", "Flame", "Crown", "Skull", "Diamond", "Star", "Crosshair", "Shield", "None"]

BarLogoSpec(name) {
    switch name {
        case "Flame":
            return "p 8,0,11.5,4.5,13.5,8.5,13,12.5,10.5,15.5,8,16,5.5,15.5,3,12.5,2.6,9,4.4,5.6,5.6,8.4,6.6,5"
                 . ";p 8,7.4,10,10.6,9.8,13.2,8,14.4,6.2,13.2,6.2,10.6"
        case "Crown":
            return "p 1,4.5,4.6,8.4,8,2.4,11.4,8.4,15,4.5,13.6,12.4,2.4,12.4;r 2.4,13.4,11.2,2"
                 . ";e 1,3.1,1,1;e 8,1.1,1,1;e 15,3.1,1,1"
        case "Skull":
            return "p 2.27,11.02,1.42,9.39,1.03,7.61,1.11,5.78,1.66,4.04,2.64,2.5,3.98,1.27,5.61,0.42,"
                 . "7.39,0.03,9.22,0.11,10.96,0.66,12.5,1.64,13.73,2.98,14.58,4.61,14.97,6.39,14.89,8.22,"
                 . "14.34,9.96,11.6,15.6,4.4,15.6"
                 . ";e 5.2,7.6,1.9,2.2;e 10.8,7.6,1.9,2.2;p 8,10.2,9.1,12.4,6.9,12.4"
                 . ";r 6.3,13.4,0.8,2.2;r 8.9,13.4,0.8,2.2"
        case "Diamond":
            return "p 4,1.5,12,1.5,15.5,6,8,15.5,0.5,6;p 5.2,6.6,10.8,6.6,8,12.6"
        case "Star":
            return "p 8,0.6,9.94,5.93,15.61,6.13,11.14,9.62,12.7,15.07,8,11.9,3.3,15.07,4.86,9.62,0.39,6.13,6.06,5.93"
        case "Crosshair":
            return "e 8,8,6.4,6.4;e 8,8,4.8,4.8;e 8,8,1.1,1.1"
                 . ";r 7.25,0,1.5,1.6;r 7.25,14.4,1.5,1.6;r 0,7.25,1.6,1.5;r 14.4,7.25,1.6,1.5"
                 . ";r 7.25,3.2,1.5,2.4;r 7.25,10.4,1.5,2.4;r 3.2,7.25,2.4,1.5;r 10.4,7.25,2.4,1.5"
        case "Shield":
            return "p 8,0.4,14.6,2.8,14.2,8.8,8,15.8,1.8,8.8,1.4,2.8;p 8,2.9,12.2,4.5,11.9,8.4,8,12.9,4.1,8.4,3.8,4.5"
                 . ";p 8,5,10,6,9.8,8.2,8,10.4,6.2,8.2,6,6"
        case "None":
            return ""
    }
    return "p 9.2,0,3.4,9.2,7.6,9.2,6.4,16,12.6,6.4,8.4,6.4,10.4,0"         ; Lightning
}

BarLogoColour() => (Stats.BarLogoColor != "") ? Stats.BarLogoColor : OvC("Accent")

; draw a logo spec into a sz x sz box at x, y (GDI+, one path, alternate fill)
GpLogo(g, spec, x, y, sz, argb) {
    if (spec = "")
        return
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)          ; FillModeAlternate
    if !path
        return
    k := sz / 16
    for part in StrSplit(spec, ";") {
        part := Trim(part)
        kind := SubStr(part, 1, 1)
        nums := []
        for v in StrSplit(Trim(SubStr(part, 2)), ",")
            nums.Push(Float(v))
        if (kind = "p" && nums.Length >= 6) {
            pts := []
            i := 1
            while (i < nums.Length) {
                pts.Push([x + nums[i] * k, y + nums[i + 1] * k])
                i += 2
            }
            buf := GpPoints(pts)
            DllCall("gdiplus\GdipAddPathPolygon", "Ptr", path, "Ptr", buf, "Int", pts.Length)
        } else if (kind = "e" && nums.Length = 4) {
            DllCall("gdiplus\GdipAddPathEllipse", "Ptr", path, "Float", x + (nums[1] - nums[3]) * k,
                    "Float", y + (nums[2] - nums[4]) * k, "Float", 2 * nums[3] * k, "Float", 2 * nums[4] * k)
        } else if (kind = "r" && nums.Length = 4) {
            DllCall("gdiplus\GdipAddPathRectangle", "Ptr", path, "Float", x + nums[1] * k, "Float", y + nums[2] * k,
                    "Float", nums[3] * k, "Float", nums[4] * k)
        }
    }
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br)
    if br {
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; ---- classic look -------------------------------------------------------------------------
; a filled polygon from [[x, y], ...]
GpPoly(g, pts, argb) {
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    buf := GpPoints(pts)
    DllCall("gdiplus\GdipAddPathPolygon", "Ptr", path, "Ptr", buf, "Int", pts.Length)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br)
    if br {
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; one piece of text, measured with the typographic width and centred in a padded box so
; it lands exactly on x .. x + w
BarText(g, s, face, px, bold, argb, x, w, H, shadow := false) {
    if shadow
        GpText(g, s, face, px, bold, Argb("000000", 150), x - px * 0.5 + 1, 1, w + px, H, 1)
    GpText(g, s, face, px, bold, argb, x - px * 0.5, 0, w + px, H, 1)
}

; a hairline between two parts; returns where the next part starts
BarSep(g, x, gap, H, argb) {
    x += gap
    sb := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &sb)
    if sb {
        DllCall("gdiplus\GdipFillRectangle", "Ptr", g, "Ptr", sb, "Float", x, "Float", H * 0.27,
                "Float", 1, "Float", H * 0.46)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", sb)
    }
    return x + 1 + gap
}

; push a per-pixel-alpha bitmap to the card window without moving it
BarPush(win, mem, W, H) {
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    sz := Buffer(8, 0), src := Buffer(8, 0), bl := Buffer(4, 0)
    NumPut("Int", W, sz, 0), NumPut("Int", H, sz, 4)
    NumPut("UChar", 255, bl, 2), NumPut("UChar", 1, bl, 3)              ; AC_SRC_ALPHA
    ok := DllCall("user32\UpdateLayeredWindow", "Ptr", win.Hwnd, "Ptr", scr, "Ptr", 0, "Ptr", sz,
                  "Ptr", mem, "Ptr", src, "UInt", 0, "Ptr", bl, "UInt", 2)     ; ULW_ALPHA
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    return ok
}

; draw the whole bar at card size `size` and push it (classic look)
BarDraw(size) {
    win := UI.StatHud
    if (win = "" || !GdipReady())
        return false
    if Card.BaseDC
        CardBaseFree()                              ; the graph card's saved copy isn't used here
    editing := CardEditing()
    f := size / 11 * A_ScreenDPI / 96
    face := Theme.FontName
    px := 13.5 * f, upx := 11 * f
    H := Round(30 * f), pad := 13 * f, gap := 10 * f
    filled := Theme.HudBgOn || editing
    alpha := editing ? Max(200, Theme.HudBgOpacity) : Theme.HudBgOpacity
    shadow := !filled || alpha < 90
    text := Theme.HudTextColor, dim := MixHex(Theme.HudTextColor, OvC("Dim"), 0.6)
    items := BarItems()
    tagOn := CtOnCard()
    fr := tagOn ? CtCurFrame() : ""

    ; ---- measure (a throwaway surface)
    mdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    mg := mdc ? GpGraphics(mdc) : 0
    if !mg {
        if mdc
            DllCall("gdi32\DeleteDC", "Ptr", mdc)
        return false
    }
    try {
        logo := BarLogoSpec(Stats.BarLogo)
        boltW := (logo = "") ? 0 : 15 * f
        brandW := GpTextW(mg, "ArkSense", face, px, true)
        segs := [boltW + ((logo = "") ? 0 : 6 * f) + brandW]    ; widths of the parts, left to right
        chip := 0
        if tagOn {
            tpx := px * Ct.Scale / 100
            TL := CtBoxLayout(CtFace(), tpx, Ct.Bold)
            chip := (Ct.Outline || Ct.Alpha > 0) ? 7 * f : 0    ; the tag's own box (step 25)
            segs.Push(TL.w + 2 * chip)
        }
        for it in items {
            vw := GpTextW(mg, it.v, face, px, true)
            uw := GpTextW(mg, it.u, face, upx, false)
            it.vw := vw, it.uw := uw
            segs.Push((it.ic != "") ? 12 * f + 6 * f + vw + 4 * f + uw : uw + 5 * f + vw)
        }
    } finally {
        GpDone(mg)
        DllCall("gdi32\DeleteDC", "Ptr", mdc)
    }
    W := pad * 2
    for sw in segs                                               ; (not "w": that is W)
        W += sw
    W += (segs.Length - 1) * (2 * gap + 1)
    if editing
        W += 14 * f                                              ; room for the resize grip
    W := Round(W)

    if !GpCanvas(W, H, &mem, &bmp, &old) {
        GpCanvasFree(mem, bmp, old)
        return false
    }
    g := GpGraphics(mem)
    try {
        if !g
            return false
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
        r := H / 2
        if filled
            GpFillRound(g, 0.5, 0.5, W - 1, H - 1, r, Argb(OvC("Panel2"), alpha))
        if (Theme.HudBorderOn || editing) {
            oc := editing ? OvC("Accent") : (Card.FxCol != "") ? Card.FxCol : Theme.HudBorderColor
            GpStrokeRound(g, 0.75, 0.75, W - 1.5, H - 1.5, r, Argb(oc, 235), Max(1.2, 1.2 * f))
        }
        x := pad
        sepC := Argb(dim, 110)

        ; brand: logo + ArkSense
        if (logo != "") {
            GpLogo(g, logo, x, H / 2 - 7.5 * f, 15 * f, Argb(BarLogoColour(), 255))
            x += boltW + 6 * f
        }
        BarText(g, "ArkSense", face, px, true, Argb(text, 255), x, brandW, H, shadow)
        x += brandW

        ; clantag (its own font, colours, animation - and its own background and outline)
        if tagOn {
            x := BarSep(g, x, gap, H, sepC)
            if chip {
                ch := Round(tpx * 1.32) + 4 * f, cy0 := (H - ch) / 2
                if (Ct.Alpha > 0)
                    GpFillRound(g, x, cy0, TL.w + 2 * chip, ch, ch / 2, Argb(Ct.BgColor, Ct.Alpha))
                if Ct.Outline
                    GpStrokeRound(g, x + 0.5, cy0 + 0.5, TL.w + 2 * chip - 1, ch - 1, ch / 2,
                                  Argb(Ct.OutlineColor, 230), Max(1.2, 1.2 * f))
            }
            CtDrawLetters(g, fr, TL, CtFace(), tpx, x + chip, (H - Round(tpx * 1.32)) / 2, Round(tpx * 1.32),
                          shadow && !(chip && Ct.Alpha >= 90))
            x += TL.w + 2 * chip
        }

        ; ping / fps with an icon, cpu / gpu / ram with a label
        for it in items {
            x := BarSep(g, x, gap, H, sepC)
            if (it.k = "ping") {
                Loop 3 {                                         ; signal bars, lit by how good it is
                    bh := (2 + A_Index * 3) * f, bw := 2.6 * f
                    bx := x + (A_Index - 1) * (bw + 1.7 * f), by := H / 2 + 5 * f - bh
                    GpFillRound(g, bx, by, bw, bh, 0.8 * f, Argb(it.ic, (A_Index <= it.lvl) ? 255 : 70))
                }
            } else if (it.k = "fps") {                           ; a small line chart
                pts := []
                for p in [[0, 8], [3.2, 4.6], [6, 6.6], [10, 1.6]]
                    pts.Push([x + 1 * f + p[1] * f, H / 2 - 4.6 * f + p[2] * f])
                GpLines(g, pts, Argb(it.ic, 255), Max(1.4, 1.6 * f))
            }
            if (it.ic != "") {
                x += 12 * f + 6 * f
                BarText(g, it.v, face, px, true, Argb(it.vc, 255), x, it.vw, H, shadow)
                x += it.vw + 4 * f
                BarText(g, it.u, face, upx, false, Argb(dim, 255), x, it.uw, H, shadow)
                x += it.uw
            } else {
                BarText(g, it.u, face, upx, true, Argb(dim, 255), x, it.uw, H, shadow)
                x += it.uw + 5 * f
                BarText(g, it.v, face, px, true, Argb(it.vc, 255), x, it.vw, H, shadow)
                x += it.vw
            }
        }

        ; resize grip while editing (a small triangle at the right end)
        if editing {
            gx := W - pad * 0.6 - 9 * f, gy := H / 2 - 4.5 * f
            GpPoly(g, [[gx + 9 * f, gy], [gx + 9 * f, gy + 9 * f], [gx, gy + 9 * f]], Argb(OvC("Accent"), 255))
            Card.GripX := Round(gx), Card.GripY := 0
        }
        Card.W := W, Card.H := H, Card.Size := size
        BarPush(win, mem, W, H)
    } finally {
        GpDone(g)
        GpCanvasFree(mem, bmp, old)
    }
    return true
}

; ---- the settings group (on the Clantag & bar page) ---------------------------------------
BarGroup(g, p, y) {
    gr := GroupBegin(g, p, 2, y, "Stats bar")
    GToggle(gr, GRow(gr), "barOn", "Show the stats card as a bar", Stats.Bar,
            "One slim bar instead of the graph: ArkSense, then ping and FPS (and what you switch "
          . "on below). Same window as the stats card: Overlay > Show the stats card must be on, "
          . "EDIT LAYOUT moves and resizes it, and it uses the card's background, opacity, outline "
          . "and text colour (Overlay > Look).")
    hw := (gr.w - 24 - 12) // 2
    lx := gr.x + 12, rx := gr.x + 12 + hw + 12
    y := GRow(gr)
    GToggle(gr, y, "barPing", "Ping", Stats.BarPing, "Same number as the card's PING (needs the "
          . "server found, see Overlay > Network).", lx, hw)
    GToggle(gr, y, "barFps", "FPS", Stats.BarFps, "ARK's frames per second (Windows' own graphics "
          . "event log, nothing is read from ARK).", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "barCpu", "CPU", Stats.BarCpu, "", lx, hw)
    GToggle(gr, y, "barGpu", "GPU", Stats.BarGpu, "", rx, hw)
    y := GRow(gr)
    GToggle(gr, y, "barRam", "RAM", Stats.BarRam, "", lx, hw)
    GToggle(gr, y, "barTag", "Clantag", Stats.BarTag,
            "Shows the clantag (left column - its text, animation and colours) in the bar "
          . "instead of on its own. The clantag itself must be on.", rx, hw)
    y := GRow(gr), GLabel(gr, y, "Logo", "What sits in front of ArkSense in the bar.", 60),
        GDrop(gr, y, "barLogo", BarLogos(), Stats.BarLogo, 130)
    y := GRow(gr)
    GLabel(gr, y, "Logo colour", "Any hex colour (RRGGBB). Empty = the overlay's accent colour.")
    GSwatch(gr, y, "barLogoColor", "barLogoSw", BarLogoColour())
    GText(gr, GRow(gr), "barStatus")
    return GroupEnd(gr)
}

BarStatusText() {
    if !Stats.Bar
        return "off - the graph card is shown"
    if !Stats.CardOn
        return "on - but the stats card is off (Overlay)"
    return "on" . ((Stats.BarTag && !Ct.On) ? " - clantag needs the clantag on" : "")
}

BarStatusTick() {
    if !UI.Ctrl.Has("barStatus")
        return
    c := UI.Ctrl["barStatus"]
    t := "now   " . BarStatusText()
    if (c.Text != t) {
        c.Text := t
        Paint(c, "", (Stats.Bar && Stats.CardOn && !(Stats.BarTag && !Ct.On)) ? Theme.Ok
                   : Stats.Bar ? Theme.Bad : Theme.Dim)
    }
}

; read the group (from the page's APPLY); true when the bar's look or contents changed
BarReadUI() {
    before := Stats.Bar . Stats.BarPing . Stats.BarFps . Stats.BarCpu . Stats.BarGpu . Stats.BarRam . Stats.BarTag
            . Stats.BarLogo . Stats.BarLogoColor
    Stats.BarLogo := ListPick(BarLogos(), DropValue("barLogo", Stats.BarLogo))
    lc := Trim(UI.Ctrl["barLogoColor"].Value)
    ; the field shows the colour in use; typing the accent itself (or nothing) keeps "follow the accent"
    Stats.BarLogoColor := (lc = "" || Hex("barLogoColor", "") = OvC("Accent")) ? "" : Hex("barLogoColor", Stats.BarLogoColor)
    UI.Ctrl["barLogoColor"].Value := BarLogoColour()
    Paint(UI.Ctrl["barLogoSw"], BarLogoColour())
    Stats.Bar     := ChkVal(UI.Ctrl["barOn"])
    Stats.BarPing := ChkVal(UI.Ctrl["barPing"])
    Stats.BarFps  := ChkVal(UI.Ctrl["barFps"])
    Stats.BarCpu  := ChkVal(UI.Ctrl["barCpu"])
    Stats.BarGpu  := ChkVal(UI.Ctrl["barGpu"])
    Stats.BarRam  := ChkVal(UI.Ctrl["barRam"])
    Stats.BarTag  := ChkVal(UI.Ctrl["barTag"])
    return before != Stats.Bar . Stats.BarPing . Stats.BarFps . Stats.BarCpu . Stats.BarGpu . Stats.BarRam . Stats.BarTag
                   . Stats.BarLogo . Stats.BarLogoColor
}

BarClamp() {
    for k in ["Bar", "BarPing", "BarFps", "BarCpu", "BarGpu", "BarRam", "BarTag"]
        Stats.%k% := Stats.%k% ? 1 : 0
    Stats.BarLogo := ListPick(BarLogos(), Stats.BarLogo)
    if !RegExMatch(Stats.BarLogoColor, "^[0-9A-Fa-f]{6}$")
        Stats.BarLogoColor := ""
}
