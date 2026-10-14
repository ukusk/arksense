; ArkSense - lib\Look.ahk
; Visuals > Look (step 21): background looks, neon edges, spotlight and colour grades for
; the web menu, and the same look on the startup animation.
; The web menu draws them in CSS (lib\menu\menu.css, body classes set by applyTheme in
; menu.js). The startup animation draws them with GDI+ (SplashLook* below, called from
; SplashDraw in lib\Extras.ahk). The native menu keeps its plain look.
; Part of ArkSense.ahk; run that file, not this one.

LookNames()  => ["None", "Aurora", "Embers", "Frosted glass", "Holo"]
GradeNames() => ["None", "Cinematic", "Warm", "Cold", "Vivid", "Mono"]

; the code the web menu and the splash use: "Frosted glass" -> "glass", "Aurora" -> "aurora"
LookCode(name) => (name = "Frosted glass") ? "glass" : StrLower(name)

; name from a list, matched without case; the first one when it isn't in the list
ListPick(list, val) {
    for it in list {
        if (it = val)
            return it
    }
    return list[1]
}

; ---- colour grades as 3x4 colour matrices (rows r, g, b: [kr, kg, kb, offset], 0-1 units)
; Same numbers as the CSS filters the web menu uses, applied in the same order.
GradeMatrix(grade) {
    static cache := Map()
    grade := StrLower(grade)
    if cache.Has(grade)
        return cache[grade]
    switch grade {
        case "warm":      ops := [["sepia", 0.25], ["sat", 1.3], ["hue", -8]]
        case "cold":      ops := [["sat", 1.05], ["hue", -125]]
        case "vivid":     ops := [["sat", 1.6], ["con", 1.12]]
        case "mono":      ops := [["sat", 0], ["con", 1.1]]
        case "cinematic": ops := [["con", 1.08], ["sat", 1.18], ["sepia", 0.08]]
        default:          ops := []
    }
    m := [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
    for op in ops
        m := GradeMul(GradeOp(op[1], op[2]), m)
    cache[grade] := m
    return m
}

GradeOp(kind, a) {
    switch kind {
        case "sepia":
            k := 1 - a
            return [[0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k, 0],
                    [0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k, 0],
                    [0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k, 0]]
        case "sat":
            return [[0.213 + 0.787 * a, 0.715 - 0.715 * a, 0.072 - 0.072 * a, 0],
                    [0.213 - 0.213 * a, 0.715 + 0.285 * a, 0.072 - 0.072 * a, 0],
                    [0.213 - 0.213 * a, 0.715 - 0.715 * a, 0.072 + 0.928 * a, 0]]
        case "hue":
            c := Cos(a * 0.017453292519943), s := Sin(a * 0.017453292519943)
            return [[0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0],
                    [0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0],
                    [0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0]]
        case "con":
            o := 0.5 - 0.5 * a
            return [[a, 0, 0, o], [0, a, 0, o], [0, 0, a, o]]
    }
    return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
}

; a after b
GradeMul(a, b) {
    r := []
    Loop 3 {
        i := A_Index, row := []
        Loop 3 {
            j := A_Index
            row.Push(a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j])
        }
        row.Push(a[i][1] * b[1][4] + a[i][2] * b[2][4] + a[i][3] * b[3][4] + a[i][4])
        r.Push(row)
    }
    return r
}

; "RRGGBB" through a grade
GradeHex(hex, grade) {
    if (grade = "" || grade = "none")
        return hex
    m := GradeMatrix(grade)
    v := Integer("0x" . hex)
    c := [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255]
    out := ""
    Loop 3 {
        row := m[A_Index]
        x := row[1] * c[1] + row[2] * c[2] + row[3] * c[3] + row[4]
        out .= Format("{:02X}", Round(Max(0, Min(1, x)) * 255))
    }
    return out
}

; the grade as GDI+ image attributes (for pictures: the custom logo); 0 for none
GradeImageAttr(grade) {
    if (grade = "" || grade = "none")
        return 0
    m := GradeMatrix(grade)
    cm := Buffer(100, 0)                       ; 5x5 floats, row vector [r g b a 1] * M
    Loop 3 {
        j := A_Index                           ; output channel
        Loop 3
            NumPut("Float", m[j][A_Index], cm, ((A_Index - 1) * 5 + (j - 1)) * 4)
        NumPut("Float", m[j][4], cm, (4 * 5 + (j - 1)) * 4)
    }
    NumPut("Float", 1, cm, (3 * 5 + 3) * 4)    ; alpha unchanged
    NumPut("Float", 1, cm, (4 * 5 + 4) * 4)
    ia := 0
    DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &ia)
    if ia
        DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", ia, "Int", 0, "Int", 1, "Ptr", cm,
                "Ptr", 0, "Int", 0)
    return ia
}

; ---- Visuals > Look page: looks, colour grade, startup animation, Style, Animation --------
BuildLook(g) {
    p := "look"
    ; column 1: background look, then animation
    gr := GroupBegin(g, p, 0, Layout.TOP, "Background")
    y := GRow(gr), GLabel(gr, y, "Look", "The background of the web menu and the startup animation.", 70),
        GDrop(gr, y, "lookName", LookNames(), Theme.Look, 140)
    GNote(gr, GRow(gr, 5), "Aurora: soft clouds in your colours drifting behind the panels.`n"
        . "Embers: slow glowing sparks rising behind the panels.`n"
        . "Frosted glass: see-through blurred panels over the menu picture (Settings > Window).`n"
        . "Holo: ARK Tek style - cyan, square panels, scanlines.", 5)
    GToggle(gr, GRow(gr), "lookNeon", "Neon edges", Theme.NeonEdges,
            "A slowly turning gradient round every panel, with glowing buttons and title.")
    GToggle(gr, GRow(gr), "lookSpot", "Spotlight", Theme.Spotlight,
            "A soft light follows the mouse and the panel under it lifts a little.")
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 0, y2, "Animation")
    GToggle(gr, GRow(gr), "animHover", "Button hover fade", Anim.HoverOn)
    GToggle(gr, GRow(gr), "animTab",   "Tab accent ease",   Anim.TabOn,
            "Off also stops every moving look (aurora, embers, neon, grain) in the web menu.")
    GSlider(gr, GRow(gr), "animHoverSpeed", "Hover speed", Anim.HoverSpeed, 4, 64, "")
    GSlider(gr, GRow(gr), "animTabSpeed",   "Tab speed",   Anim.TabSpeed, 4, 64, "")
    GroupEnd(gr)

    ; column 2: colour grade, startup animation
    gr := GroupBegin(g, p, 1, Layout.TOP, "Colour grade")
    y := GRow(gr), GLabel(gr, y, "Grade", "A colour filter over the whole web menu.", 70),
        GDrop(gr, y, "lookGrade", GradeNames(), Theme.Grade, 140)
    GNote(gr, GRow(gr, 4), "Cinematic: more contrast, warm highlights, teal shadows, vignette and "
        . "film grain. Warm / Cold: shifts the colours warmer or cooler. Vivid: stronger colours. "
        . "Mono: black and white.", 4)
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 1, y2, "Startup animation")
    GToggle(gr, GRow(gr), "splashOn", "Show the startup animation", Theme.Splash,
            "Logo and a glowing loading bar while ArkSense starts (about 3.5 s).")
    GToggle(gr, GRow(gr), "lookSplash", "Use the look on it", Theme.LookSplash,
            "The loading card gets the same background, edges and grade as the menu. "
          . "With everything on None / off it looks as before.")
    GButtons(gr, GRow(gr), [["PREVIEW", (*) => LookPreview(), "accent"]],
             ["Plays the startup animation now with what is picked here (APPLY not needed)."])
    GroupEnd(gr)

    ; column 3: style (theme, effect, glow), then notes
    gr := GroupBegin(g, p, 2, Layout.TOP, "Style")
    y := GRow(gr)
    GLabel(gr, y, "Theme", "Swaps the whole palette at once. Fine-tune it in "
        . "Colours afterwards.", 90)
    names := ThemePresetNames()
    known := false
    for n in names
        known := known || (n = Theme.Preset)
    if !known                                    ; "Auto" (from the wallpaper) or a hand-made mix
        names.Push(Theme.Preset)
    GDrop(gr, y, "themePreset", names, Theme.Preset, 150,
              (item) => SetTimer(ApplyPreset.Bind(item), -60))
    y := GRow(gr)
    GLabel(gr, y, "Effect", "Animates the header line, the logo, glowing panel "
        . "edges and the overlay outlines. Pulse/Neon breathe, Rainbow flows, Flame flickers, "
        . "Scanner sweeps.", 90)
    GDrop(gr, y, "fxMode", FxModes(), Anim.Effect, 150)
    GSlider(gr, GRow(gr), "animRainbowSpeed", "Effect speed", Anim.RainbowSpeed, 1, 15, "")
    GSlider(gr, GRow(gr), "animPulseDepth",   "Glow strength", Anim.PulseDepth, 10, 120, "")
    GToggle(gr, GRow(gr), "fxGlow",  "Glowing panel edges", Anim.GlowOn)
    GToggle(gr, GRow(gr), "fxTitle", "Logo text follows the effect", Anim.TitleOn)
    GToggle(gr, GRow(gr), "fxFade",  "Fade in when opened", Anim.FadeIn)
    y2 := GroupEnd(gr)

    gr := GroupBegin(g, p, 2, y2, "Good to know")
    GNote(gr, GRow(gr, 5), "Background, edges, spotlight and grade are drawn by the web menu "
        . "(Settings > Window > Web) and the startup animation; the native menu keeps its plain "
        . "look. Frosted glass costs the most graphics work; Embers draws at about 20 frames a "
        . "second. Nothing animates while the menu is hidden.", 5)
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyLook(), "accent"]])
}

LookRead() {
    Theme.Look  := ListPick(LookNames(), DropValue("lookName", Theme.Look))
    Theme.Grade := ListPick(GradeNames(), DropValue("lookGrade", Theme.Grade))
    if UI.Ctrl.Has("lookNeon") {
        Theme.NeonEdges := ChkVal(UI.Ctrl["lookNeon"])
        Theme.Spotlight := ChkVal(UI.Ctrl["lookSpot"])
        Theme.LookSplash := ChkVal(UI.Ctrl["lookSplash"])
    }
}

; the looks, plus Style and Animation (moved here from Settings in step 22): those need
; the same full rebuild Settings > APPLY does, which also sends the web menu its new model
ApplyLook() {
    LookRead()
    SetTimer(ApplySettings, -60)
}

; play the startup animation now with the picks on the page (saved or not)
LookPreview() {
    if (Splash.Win != "")
        return
    keep := [Theme.Look, Theme.Grade, Theme.NeonEdges, Theme.Spotlight, Theme.LookSplash]
    LookRead()
    Theme.LookSplash := 1
    SplashShow(true)
    Theme.Look := keep[1], Theme.Grade := keep[2], Theme.NeonEdges := keep[3]
    Theme.Spotlight := keep[4], Theme.LookSplash := keep[5]
}

; ---- the startup animation in the look ----------------------------------------------------
; Fixed when the splash opens: which look, the palette (look + grade), the blurred
; background for Frosted glass and the logo's grade.
SplashLookInit(cardX, cardY, cardW, cardH) {
    on := Theme.LookSplash
    Splash.Look  := on ? LookCode(Theme.Look) : "none"
    Splash.Grade := on ? StrLower(Theme.Grade) : "none"
    Splash.Neon  := on && Theme.NeonEdges
    Splash.Spot  := on && Theme.Spotlight
    p := {acc: Theme.Accent, acc2: Theme.Accent2, panel: Theme.Panel, header: Theme.Header,
          text: Theme.Text, dim: Theme.Dim, white: "FFFFFF"}
    if (Splash.Look = "holo")
        p.acc := "3EF2FF", p.acc2 := "2A7BFF", p.panel := "06121A", p.header := "0B2430",
        p.text := "DDF8FF", p.dim := "6FA3B5"
    if (Splash.Grade != "none") {
        for k in ["acc", "acc2", "panel", "header", "text", "dim", "white"]
            p.%k% := GradeHex(p.%k%, Splash.Grade)
    }
    Splash.P := p
    Splash.Ia := GradeImageAttr(Splash.Grade)
    Splash.Bg := (Splash.Look = "glass") ? SplashGlassBg(cardX, cardY, cardW, cardH) : 0
}

SplashLookFree() {
    if Splash.Ia
        DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", Splash.Ia)
    GpFreeImage(Splash.Bg)
    Splash.Ia := 0, Splash.Bg := 0
}

; Frosted glass: the menu picture if one is set, else the screen behind the card (taken
; once, before the card shows), made small and stretched back = blurred. 0 if neither works.
SplashGlassBg(x, y, w, h) {
    w := Round(w), h := Round(h)
    src := 0, sx := 0, sy := 0, sw := 0, sh := 0, hbm := 0
    if (Theme.WallOn && FileExist(Theme.WallPath))
        src := GpLoadImage(Theme.WallPath)
    if src {
        iw := 0, ih := 0
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &iw)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &ih)
        sc := Min(iw / w, ih / h)                          ; cover: crop to the card's shape
        sw := Round(w * sc), sh := Round(h * sc), sx := (iw - sw) // 2, sy := (ih - sh) // 2
    } else {
        scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
        mdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
        hbm := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", scr, "Int", w, "Int", h, "Ptr")
        o := DllCall("gdi32\SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
        DllCall("gdi32\BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", scr,
                "Int", Round(x), "Int", Round(y), "UInt", 0x00CC0020)       ; SRCCOPY
        DllCall("gdi32\SelectObject", "Ptr", mdc, "Ptr", o, "Ptr")
        DllCall("gdi32\DeleteDC", "Ptr", mdc)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &src)
        sw := w, sh := h
    }
    out := 0
    if src {
        tw := Max(2, w // 14), th := Max(2, h // 14)
        mid := GpBitmap(Max(4, w // 4), Max(4, h // 4))    ; two steps down = smooth, no blocks
        tiny := GpBitmap(tw, th)
        out := GpBitmap(w, h)
        if (mid && tiny && out) {
            GpBitmapDraw(mid, src, Max(4, w // 4), Max(4, h // 4), sx, sy, sw, sh)
            GpBitmapDraw(tiny, mid, tw, th, 0, 0, Max(4, w // 4), Max(4, h // 4))
            GpBitmapDraw(out, tiny, w, h, 0.5, 0.5, tw - 1, th - 1)
        } else {
            GpFreeImage(out), out := 0
        }
        GpFreeImage(mid), GpFreeImage(tiny), GpFreeImage(src)
    }
    if hbm
        DllCall("gdi32\DeleteObject", "Ptr", hbm)
    return out
}

; under the card body: the glass picture
SplashLookUnder(g, cx, cy, cw, ch, r) {
    if (Splash.Look = "glass" && Splash.Bg) {
        GpClipRound(g, cx, cy, cw, ch, r)
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", g, "Ptr", Splash.Bg, "Int", Round(cx), "Int", Round(cy),
                "Int", Round(cw), "Int", Round(ch))
        DllCall("gdiplus\GdipResetClip", "Ptr", g)
    }
}

; how solid the card body is in this look
SplashBodyAlpha() => (Splash.Look = "glass") ? 178 : 250

; over the card body, under the badge and text: aurora clouds, embers, holo glow, spotlight
SplashLookOver(g, el, cx, cy, cw, ch, r) {
    lk := Splash.Look, pal := Splash.P, s := Splash.S
    if (lk = "none" && !Splash.Spot)
        return
    GpClipRound(g, cx, cy, cw, ch, r)
    try {
        if (lk = "aurora" || (lk = "glass" && !Splash.Bg)) {
            t := el / 1000
            a := (lk = "glass") ? 130 : 125
            GpRadial(g, cx + cw * (0.25 + 0.06 * Sin(t * 0.55)), cy + ch * (0.30 + 0.07 * Cos(t * 0.47)),
                     cw * 0.42, ch * 0.55, Argb(pal.acc, a))
            GpRadial(g, cx + cw * (0.72 + 0.05 * Cos(t * 0.41)), cy + ch * (0.25 + 0.06 * Sin(t * 0.63)),
                     cw * 0.36, ch * 0.50, Argb(pal.acc2, a))
            GpRadial(g, cx + cw * (0.58 + 0.07 * Sin(t * 0.37 + 1)), cy + ch * (0.88 + 0.05 * Cos(t * 0.52)),
                     cw * 0.45, ch * 0.45, Argb(MixHex(pal.acc, GradeHex("FF9D5C", Splash.Grade), 0.45), a * 0.8))
            if (lk = "glass")                           ; frost: a light sheen over the clouds
                GpFillRound(g, cx, cy, cw, ch, r, Argb(pal.white, 10))
        } else if (lk = "glass") {
            GpFillRound(g, cx, cy, cw, ch, r, Argb(pal.white, 12))
        }
        if (lk = "glass") {                             ; bright inner edge along the top
            hl := GpGrad(cx, cy, cw, ch * 0.35, Argb(pal.white, 34), Argb(pal.white, 0), 1)
            GpFillRoundB(g, cx, cy, cw, ch * 0.35, r, hl), GpFreeBrush(hl)
        }
        if (lk = "embers") {
            ember := GradeHex("FFA050", Splash.Grade), cols := [pal.acc, pal.acc2, ember]
            Loop 34 {
                i := A_Index
                fx := SplashHash(i * 3.1), fy := SplashHash(i * 7.7), sp := 0.035 + SplashHash(i * 1.9) * 0.07
                y := Mod(fy + el / 1000 * sp, 1.0)
                px := cx + cw * (fx + 0.012 * Sin(el / 700 + i))
                py := cy + ch * (1.05 - y * 1.1)
                rad := (2 + SplashHash(i * 5.3) * 5) * s
                tw := 0.65 + 0.35 * Sin(el / 260 + i * 1.7)
                fade := Min(1, y * 6, (1 - y) * 4)
                col := cols[Mod(i, 3) + 1]
                GpRadial(g, px, py, rad * 2.6, rad * 2.6, Argb(col, Round(150 * tw * fade)))
                GpFillRound(g, px - rad * 0.3, py - rad * 0.3, rad * 0.6, rad * 0.6, rad * 0.3,
                            Argb(MixHex(col, "FFFFFF", 0.5), Round(230 * tw * fade)))
            }
        }
        if (lk = "holo") {                              ; light from the top, a scan band moving down
            GpRadial(g, cx + cw / 2, cy, cw * 0.65, ch * 0.7, Argb(pal.acc, 40))
            bandH := 46 * s, by := cy - bandH + Mod(el * 0.11 * s, ch + bandH)
            bb := GpGrad(cx, by, cw, bandH, Argb(pal.acc, 0), Argb(pal.acc, 34), 1)
            DllCall("gdiplus\GdipSetLineSigmaBlend", "Ptr", bb, "Float", 0.5, "Float", 1.0)
            DllCall("gdiplus\GdipFillRectangle", "Ptr", g, "Ptr", bb, "Float", cx, "Float", by, "Float", cw, "Float", bandH)
            GpFreeBrush(bb)
        }
        if Splash.Spot {                                ; a soft light wandering over the card
            t := el / 1000
            GpRadial(g, cx + cw * (0.5 + 0.38 * Sin(t * 0.9)), cy + ch * (0.45 + 0.30 * Sin(t * 1.3 + 0.6)),
                     160 * s, 160 * s, Argb(MixHex(pal.acc, pal.white, 0.35), 85))
        }
    } finally {
        DllCall("gdiplus\GdipResetClip", "Ptr", g)
    }
}

; the card's edge: the usual gradient, or for Neon edges a turning gradient + bright line
SplashLookEdge(g, el, cx, cy, cw, ch, r) {
    pal := Splash.P, s := Splash.S
    if !Splash.Neon {
        eb := GpGrad(cx, cy, cw, ch, Argb(pal.acc, 200), Argb(pal.acc2, 150), 2)
        GpStrokeRoundB(g, cx + 0.5, cy + 0.5, cw - 1, ch - 1, r, eb, Max(1, 1.2 * s)), GpFreeBrush(eb)
        return
    }
    ang := Mod(el * 0.04, 360)                          ; one turn in 9 s, like the menu
    rc := GpRectF(cx, cy, cw / 2, ch / 2), br := 0
    DllCall("gdiplus\GdipCreateLineBrushFromRectWithAngle", "Ptr", rc, "UInt", Argb(pal.acc, 255),
            "UInt", Argb(pal.acc2, 255), "Float", ang, "Int", 0, "Int", 3, "Ptr*", &br)   ; tile-flip
    if br {
        GpStrokeRoundB(g, cx + 1, cy + 1, cw - 2, ch - 2, r, br, 2.2 * s)
        GpFreeBrush(br)
    }
    GpStrokeRound(g, cx + 3 * s, cy + 3 * s, cw - 6 * s, ch - 6 * s, Max(1, r - 3 * s), Argb(pal.acc, 40), s)
}

; on top of everything: holo scanlines, the cinematic tint, vignette and grain
SplashLookTop(g, el, cx, cy, cw, ch, r) {
    lk := Splash.Look, pal := Splash.P, s := Splash.S
    if (lk != "holo" && Splash.Grade != "cinematic")
        return
    GpClipRound(g, cx, cy, cw, ch, r)
    try {
        if (lk = "holo") {
            pen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", Argb(pal.acc, 16), "Float", 1, "Int", 2, "Ptr*", &pen)
            if pen {
                y := cy + 1
                while (y < cy + ch) {
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", cx, "Float", y,
                            "Float", cx + cw, "Float", y)
                    y += 3 * s
                }
                DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
            }
        }
        if (Splash.Grade = "cinematic") {
            tb := GpGrad(cx, cy, cw, ch, Argb("FF8C3C", 18), Argb("008CA0", 22), 2)
            DllCall("gdiplus\GdipFillRectangle", "Ptr", g, "Ptr", tb, "Float", cx, "Float", cy, "Float", cw, "Float", ch)
            GpFreeBrush(tb)
            GpVignette(g, cx, cy, cw, ch, Argb("000000", 100))
            ; film grain: a few hundred faint dots, new every frame
            n := 180, wb := Buffer(16 * n), kb := Buffer(16 * n)
            Loop n {
                o := (A_Index - 1) * 16, d := Random(1, 2) * s
                NumPut("Float", cx + Random(0.0, 1.0) * cw, "Float", cy + Random(0.0, 1.0) * ch, "Float", d, "Float", d, wb, o)
                NumPut("Float", cx + Random(0.0, 1.0) * cw, "Float", cy + Random(0.0, 1.0) * ch, "Float", d, "Float", d, kb, o)
            }
            for pair in [[wb, Argb("FFFFFF", 22)], [kb, Argb("000000", 34)]] {
                br := 0
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", pair[2], "Ptr*", &br)
                if br {
                    DllCall("gdiplus\GdipFillRectangles", "Ptr", g, "Ptr", br, "Ptr", pair[1], "Int", n)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
                }
            }
        }
    } finally {
        DllCall("gdiplus\GdipResetClip", "Ptr", g)
    }
}

; Holo: the wordmark gets a red / cyan split behind it
SplashLookSplit(g, txt, face, px, x, y, w, h) {
    if (Splash.Look != "holo")
        return
    s := Splash.S
    GpText(g, txt, face, px, true, Argb(GradeHex("FF2850", Splash.Grade), 120), x + 1.5 * s, y, w, h)
    GpText(g, txt, face, px, true, Argb(Splash.P.acc, 150), x - 1.5 * s, y, w, h)
}

; the card's corner radius in this look (Holo is square-ish)
SplashRadius() => ((Splash.Look = "holo") ? 4 : 18) * Splash.S

; repeatable 0..1 "random" number from a seed
SplashHash(x) {
    v := Sin(x * 12.9898 + 78.233) * 43758.5453
    return v - Floor(v)
}
