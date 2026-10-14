; ArkSense - lib\Paint.ahk
; Colour helpers, the WM_CTLCOLOR painter and the colour animation loop.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Painting helpers: WM_CTLCOLOR* recolours Edit/Static/Btn/ListBox ----
BGR(hex) {
    c := Integer("0x" . hex)
    return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
}

Brush(hex) {
    if !UI.Brushes.Has(hex)
        UI.Brushes[hex] := DllCall("gdi32\CreateSolidBrush", "UInt", BGR(hex), "Ptr")
    return UI.Brushes[hex]
}

CtlColor(wParam, lParam, msg, hwnd) {
    bg := UI.CustomBg.Has(lParam) ? UI.CustomBg[lParam] : Theme.Panel
    fg := UI.CustomFg.Has(lParam) ? UI.CustomFg[lParam] : Theme.Text
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", BGR(fg))
    DllCall("gdi32\SetBkColor",   "Ptr", wParam, "UInt", BGR(bg))
    return Brush(bg)
}

Paint(ctrl, bg := "", fg := "") {
    if (bg != "")
        UI.CustomBg[ctrl.Hwnd] := bg
    if (fg != "")
        UI.CustomFg[ctrl.Hwnd] := fg
    DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
    return ctrl
}

Lighten(hex) {
    c := Integer("0x" . hex)
    r := Min(255, ((c >> 16) & 0xFF) + 26)
    g := Min(255, ((c >>  8) & 0xFF) + 26)
    b := Min(255, ( c        & 0xFF) + 26)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

RGB3(hex) {
    c := Integer("0x" . hex)
    return [(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF]
}

Hex3(a) {
    return Format("{:02X}{:02X}{:02X}",
        Round(Max(0, Min(255, a[1]))), Round(Max(0, Min(255, a[2]))), Round(Max(0, Min(255, a[3]))))
}

Bright(hex, add) {
    a := RGB3(hex)
    return Hex3([a[1] + add, a[2] + add, a[3] + add])
}

; full-saturation hue (0-359) to hex - used by the rainbow border cycle
HsvHex(h) {
    h := Mod(h, 360) / 60
    x := 255 * (1 - Abs(Mod(h, 2) - 1))
    if (h < 1)
        r := 255, g := x, b := 0
    else if (h < 2)
        r := x, g := 255, b := 0
    else if (h < 3)
        r := 0, g := 255, b := x
    else if (h < 4)
        r := 0, g := x, b := 255
    else if (h < 5)
        r := x, g := 0, b := 255
    else
        r := 255, g := 0, b := x
    return Hex3([r, g, b])
}

; set a fade target for AnimTick to ease toward; paints immediately if anim is off
FadeTo(hwnd, targetHex, speed) {
    if (!Anim.HoverOn && !Anim.TabOn) {
        UI.CustomBg[hwnd] := targetHex
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
        return
    }
    startHex := UI.CustomBg.Has(hwnd) ? UI.CustomBg[hwnd] : targetHex
    Anim.Fades[hwnd] := {cur: RGB3(startHex), target: targetHex, speed: speed}
}

; single loop for every colour animation
AnimTick() {
    if (!UI.Visible || Anim.Busy || Web.Visible)       ; the web menu animates itself
        return

    for hwnd, f in (Anim.Fades.Count ? Anim.Fades.Clone() : Anim.Fades) {
        tgt := RGB3(f.target)
        cur := f.cur
        done := true
        Loop 3 {
            d := tgt[A_Index] - cur[A_Index]
            if (Abs(d) <= f.speed)
                cur[A_Index] := tgt[A_Index]
            else {
                cur[A_Index] += (d > 0 ? f.speed : -f.speed)
                done := false
            }
        }
        f.cur := cur
        UI.CustomBg[hwnd] := Hex3(cur)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
        if done
            Anim.Fades.Delete(hwnd)
    }

    if (Anim.Effect != "Off")
        FxTick()

    ; session timer: cycles the rainbow while an effect is on, else stays quiet
    if UI.Ctrl.Has("sessionTimer") {
        if (Anim.Effect != "Off") {
            Anim.TimerHue := Mod(Anim.TimerHue + 2, 360)
            Paint(UI.Ctrl["sessionTimer"], "", HsvHex(Anim.TimerHue))
        } else if (UI.CustomFg.Has(UI.Ctrl["sessionTimer"].Hwnd)
                   && UI.CustomFg[UI.Ctrl["sessionTimer"].Hwnd] != Theme.Dim) {
            Paint(UI.Ctrl["sessionTimer"], "", Theme.Dim)
        }
    }
}

; click-drag the frameless window via its title text (hit-test transparent)
GuiDrag(wParam, lParam, msg, hwnd) {
    if (hwnd != UI.Hwnd)
        return
    y := (lParam >> 16) & 0xFFFF
    if (y & 0x8000)
        y -= 0x10000
    if (y > Layout.HDR)               ; only the top bar drags the window
        return
    PostMessage 0xA1, 2, 0, , "ahk_id " . hwnd
}

HoverTick() {
    if (!UI.Visible || Anim.Busy || Web.Visible)
        return
    MouseGetPos , , , &ch, 2
    if (ch = UI.LastHover)
        return
    if UI.Hover.Has(UI.LastHover) {
        if Anim.HoverOn
            FadeTo(UI.LastHover, UI.Hover[UI.LastHover][1], Anim.HoverSpeed)
        else {
            UI.CustomBg[UI.LastHover] := UI.Hover[UI.LastHover][1]
            DllCall("InvalidateRect", "Ptr", UI.LastHover, "Ptr", 0, "Int", 1)
        }
    }
    UI.LastHover := ch
    if UI.Tips.Has(ch)                 ; hover tooltip, separate from Flash()'s #1
        StreamHide(ToolTip(UI.Tips[ch], , , 2))
    else
        ToolTip(, , , 2)
    if UI.Hover.Has(ch) {
        if Anim.HoverOn
            FadeTo(ch, UI.Hover[ch][2], Anim.HoverSpeed)
        else {
            UI.CustomBg[ch] := UI.Hover[ch][2]
            DllCall("InvalidateRect", "Ptr", ch, "Ptr", 0, "Int", 1)
        }
    }
}

Flash(msg) {
    StreamHide(ToolTip(msg, 20, 20))
    SetTimer(() => ToolTip(), -1500)
}

; ---- Effects: colour-only animation modes -----------------------------------------
; Every effect only recolours plain Statics (the segmented header line, the glow
; rings around group panels, the logo text, the overlay outlines), one colour per
; piece per frame from FxColour(). Nothing moves, so nothing can flicker or tear.
; FxColour must only ever return a bounded set of colours: Paint() keeps one GDI
; brush per distinct colour for the life of the script.

FxModes() => ["Off", "Pulse", "Rainbow", "Flame", "Neon", "Scanner"]

; mix two hex colours: t = 0 gives a, t = 1 gives b
MixHex(a, b, t) {
    x := RGB3(a), y := RGB3(b)
    return Hex3([x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t])
}

; heat 0..1 -> ember red -> orange -> yellow -> white-hot
FlameHex(v) {
    v := Max(0, Min(1, v))
    if (v < 0.35)
        return MixHex("4A0800", "C81E00", v / 0.35)
    if (v < 0.65)
        return MixHex("C81E00", "FF6A00", (v - 0.35) / 0.30)
    if (v < 0.90)
        return MixHex("FF6A00", "FFC23D", (v - 0.65) / 0.25)
    return MixHex("FFC23D", "FFF0B0", (v - 0.90) / 0.10)
}

; colour of piece i out of n for the current frame (Anim.Hue is the frame clock)
FxColour(i, n) {
    rad := Anim.Hue * 0.0174533
    switch Anim.Effect {
        case "Pulse":
            return Bright(Theme.Accent, Round(Anim.PulseDepth * (1 - Cos(rad)) / 2))
        case "Rainbow":
            return HsvHex(Anim.Hue + i * 360 / Max(n, 12))      ; flows along the line
        case "Flame":
            k := n . ":" . i                                    ; each piece flickers alone
            v := Anim.Heat.Has(k) ? Anim.Heat[k] : 0.5
            v := v * 0.55 + Random(0.0, 1.0) * 0.45
            Anim.Heat[k] := v
            return FlameHex(Round(v * 32) / 32)                 ; 33 colours at most
        case "Neon":
            t := Round((1 - Cos(rad)) * 12) / 24                ; 25 steps, bounded colours
            if (Random(1, 1500) = 1)                            ; the odd tube flicker
                t := 0
            return MixHex(MixHex(Theme.Accent, Theme.Panel, 0.45),
                          MixHex(Theme.Accent, "FFFFFF", Anim.PulseDepth / 400), t)
        case "Scanner":
            head := (Anim.Hue / 360) * (n + 6) - 3              ; sweeps past both ends
            lit  := Round(Max(0, 1 - Abs(i - head) / 3) * 16) / 16   ; 17 steps
            return MixHex(MixHex(Theme.Accent, Theme.Header, 0.75),
                          MixHex(Theme.Accent, "FFFFFF", 0.35), lit)
    }
    return Theme.Accent
}

; resting colour of header-line segment i of n: primary -> second colour over the
; first 55%, then fading into the bar
HeaderLineColour(i, n) {
    t := i / Max(1, n - 1)
    return (t < 0.55) ? MixHex(Theme.Accent, Theme.Accent2, t / 0.55)
                      : MixHex(Theme.Accent2, Theme.Header, Round((t - 0.55) / 0.45 * 8) / 8)
}

; one frame of the active effect
FxTick() {
    Anim.Hue := Mod(Anim.Hue + Anim.RainbowSpeed, 360)
    n := UI.AccentSegs.Length
    for i, c in UI.AccentSegs {
        col := FxColour(i - 1, n)
        Paint(c, col)
        if (UI.GlowSegs.Length >= i)
            Paint(UI.GlowSegs[i], MixHex(col, Theme.Panel, 0.72))
    }
    if Anim.GlowOn {
        rings := []
        for r in UI.Rings {
            if (r.page = UI.Page)
                rings.Push(r)
        }
        for j, r in rings {
            col := FxColour(j - 1, rings.Length)
            Paint(r.ring, col)
            Paint(r.halo, MixHex(col, Theme.Panel, 0.72))
        }
    }
    main := FxColour(0, 1)
    if (Anim.TitleOn && UI.Ctrl.Has("logoArk"))
        Paint(UI.Ctrl["logoArk"], Theme.Header, main)
    PillBorders(main)
}

; fade the menu in after ShowMenu (only when Anim.FadeIn is on)
MenuFadeStep() {
    if !UI.Visible {
        SetTimer(MenuFadeStep, 0)
        return
    }
    Anim.FadeLevel := Min(Theme.Opacity, Anim.FadeLevel + Max(8, Theme.Opacity // 7))
    try WinSetTransparent(Anim.FadeLevel, "ahk_id " . UI.Hwnd)
    if (Anim.FadeLevel >= Theme.Opacity)
        SetTimer(MenuFadeStep, 0)
}

; ---- Theme presets ----------------------------------------------------------------
; [Panel, Header, Panel2, Accent, Accent2, Text, Dim, Line]
ThemePresetNames() => ["Crimson", "ArkSense", "Midnight Rose", "Cyberpunk", "Synthwave", "Matrix",
                       "Inferno", "Arctic", "Toxic", "Royal", "Mono"]

ThemePreset(name) {
    switch name {
        case "Crimson":       return ["14101A", "1B1622", "110E16", "EE2F5F", "A06BFF", "E4DEEB", "736A85", "2A2334"]
        case "Midnight Rose": return ["0F0C1A", "18132A", "231C3A", "FF3D7F", "9D7BFF", "F2EEFF", "8A82A6", "2A2340"]
        case "Cyberpunk":     return ["0B0B0F", "15151B", "1F1F27", "FCEE0A", "00F0FF", "FFFFFF", "8A8A95", "2A2A33"]
        case "Synthwave":     return ["120621", "1D0B33", "2A1248", "FF2EC4", "00E5FF", "FCE8FF", "9A7BB5", "341A55"]
        case "Matrix":        return ["050A06", "0B140C", "112214", "00FF66", "7CFFB2", "D8FFE6", "4F8A5F", "163A1E"]
        case "Inferno":       return ["120806", "1E0E0A", "2B1610", "FF5A1F", "FFC23D", "FFF1E6", "A07A6A", "3A1E16"]
        case "Arctic":        return ["0A1016", "101A23", "172530", "3DD6FF", "A0F0FF", "EAF8FF", "7A93A6", "1E2F3C"]
        case "Toxic":         return ["0D0F07", "161A0C", "202511", "B6FF2E", "FFE14D", "F4FFE0", "8A9A6A", "2A3216"]
        case "Royal":         return ["0E0B14", "17121F", "221B2D", "D4AF37", "B48CFF", "F7F1E3", "8F8599", "2C2338"]
        case "Mono":          return ["0C0C0C", "161616", "212121", "FFFFFF", "9A9A9A", "FFFFFF", "7A7A7A", "2A2A2A"]
    }
    return ["0E0E12", "17171D", "1C1C24", "FF2836", "18C8E6", "FFFFFF", "7C7C8A", "26262F"]
}

; picked from the Style dropdown: swap the whole palette and rebuild
ApplyPreset(name) {
    known := false
    for n in ThemePresetNames()
        known := known || (n = name)
    if !known                                    ; "Auto" is not a stored palette: keep the colours
        return
    c := ThemePreset(name)
    Theme.Panel   := c[1]
    Theme.Header  := c[2]
    Theme.Panel2  := c[3]
    Theme.Accent  := c[4]
    Theme.Accent2 := c[5]
    Theme.Text    := c[6]
    Theme.Dim     := c[7]
    Theme.Line    := c[8]
    Theme.Preset  := name
    SaveIni()
    Rebuild(UI.Page)                          ; the Theme dropdown is on Visuals > Look
    Flash("theme: " . name)
}
