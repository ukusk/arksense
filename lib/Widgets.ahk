; ArkSense - lib\Widgets.ahk
; Menu layout constants and the widget kit (labels, fields, checkboxes, sliders, dropdowns).
; Part of ArkSense.ahk; run that file, not this one.

; ---- Menu layout ------------------------------------------------------------
; Top bar (logo, tabs, status), three columns of rounded group panels, and a
; footer with the live status line and the page's buttons.
; Class, not loose globals: statics init before auto-exec, so Boot always sees values.
class Layout {
    static W    := 1090      ; sidebar + three columns (step 12)
    static HGT  := 620
    static SIDE := 190       ; sidebar width (page list)
    static LEFT := 204       ; left edge of the first column (SIDE + 14)
    static HDR  := 52        ; content top bar height (also the drag area)
    static FOOT := 44        ; footer bar height
    static PAD  := 16        ; right margin
    static GAP  := 12        ; space between columns and between groups
    static COLW := 282       ; one of three columns
    static TOP  := 66        ; top edge of the first group in a column
    static ROW  := 30        ; row pitch inside a group
    static TABX := 168       ; (old top-tab layout, unused)
    static BTNY := 620 - 36  ; footer button row
}

ColX(col) => Layout.LEFT + col * (Layout.COLW + Layout.GAP)

; [section, title] shown in the content top bar
PageMeta(page) {
    switch page {
        case "macros":   return ["Main", "Macros"]
        case "oc":       return ["Main", "OC macro"]
        case "fps":      return ["Main", "Game"]
        case "overlay":  return ["Visuals", "Overlay"]
        case "music":    return ["Visuals", "Now playing"]
        case "clantag":  return ["Visuals", "Clantag & bar"]
        case "look":     return ["Visuals", "Look"]
        case "settings": return ["System", "Settings"]
        case "tune":     return ["System", "Tune-up"]
        case "logs":     return ["System", "Logs"]
    }
    return ["Main", "Antidote"]
}

NavOnColour() => MixHex(Theme.Accent, Theme.Header, 0.84)

; Round a control's corners with a window region (d = corner diameter at 96 DPI).
; sides "L" or "R" leaves the other side square - the two halves of a dropdown.
; Uses the control's real pixel size, so it holds at any DPI.
RoundCtl(ctrl, d, sides := "LR") {
    try ControlGetPos(, , &w, &h, ctrl)
    catch
        return
    d  := Max(2, Round(d * A_ScreenDPI / 96))
    x1 := InStr(sides, "L") ? 0 : -d
    x2 := InStr(sides, "R") ? w + 1 : w + d
    y2 := InStr(sides, "T") ? h + d : h + 1             ; "T": round the top corners only
    rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", x1, "Int", 0, "Int", x2, "Int", y2,
                   "Int", d, "Int", d, "Ptr")
    if (rgn && !DllCall("user32\SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", rgn, "Int", 0))
        DllCall("gdi32\DeleteObject", "Ptr", rgn)
}

; Group panel. The panel is a plain Static pushed to the bottom of the z-order
; after the build (see BuildMenu) and given WS_CLIPSIBLINGS - the same scheme the
; overlay pills use - so repainting the panel can never paint over a control on
; it. Rows are added top-down with GRow(); GroupEnd() sizes the panel to fit.
; Look (step 12, Fatality-style): a flat box a shade lighter than the window, a 1px
; border (the ring, Theme.Line) and a small bold title in capitals. Rows start at
; y + 30. (Step 11's tinted title strip is gone; UI.Strips now only holds the
; sidebar rows and the profile box.)
GroupBegin(g, page, col, y, title, span := 1) {
    x := ColX(col)
    w := Layout.COLW * span + Layout.GAP * (span - 1)
    bg := Paint(g.Add("Text", "x" . x . " y" . y . " w" . w . " h40 +0x04000000"), Theme.Header)
    g.SetFont("s8 Bold", Theme.FontName)
    cap := Paint(g.Add("Text", "x" . (x + 12) . " y" . (y + 8) . " h16 +0x200", StrUpper(title)),
                 Theme.Header, Theme.Text)
    g.SetFont("s9 Norm", Theme.FontName)
    UI.Groups.Push(bg)
    UI.Round.Push([bg, 6, "LR"])
    Reg(page, bg, cap)
    WebGroupBegin(page, col, y, title, span)
    Search.Group := title                   ; settings search: rows remember their group
    SearchAdd(page, cap, title)
    ; border: a 1px ring behind the panel (pushed under it after the build). With
    ; "glowing panel edges" it takes the effect colour and gets a soft halo too.
    halo := ""
    if Anim.GlowOn {
        halo := Paint(g.Add("Text", "x" . (x - 3) . " y" . (y - 3) . " w" . (w + 6) . " h46 +0x04000000"),
                      MixHex(Theme.Accent, Theme.Panel, 0.72))
        UI.Round.Push([halo, 14, "LR"])
        UI.Halos.Push(halo)
        Reg(page, halo)
    }
    ring := Paint(g.Add("Text", "x" . (x - 1) . " y" . (y - 1) . " w" . (w + 2) . " h42 +0x04000000"),
                  Anim.GlowOn ? Theme.Accent : Theme.Line)
    UI.Round.Push([ring, 8, "LR"])
    UI.Borders.Push(ring)
    Reg(page, ring)
    if Anim.GlowOn
        UI.Rings.Push({ring: ring, halo: halo, page: page})
    return {g: g, page: page, x: x, y: y, w: w, next: y + 30, bg: bg, ring: ring, halo: halo}
}

; top of the next row; the cursor then moves down n rows
GRow(grp, n := 1) {
    y := grp.next
    grp.next += Round(n * Layout.ROW)
    return y
}

; size the panel to its rows; returns where the next group in this column starts
GroupEnd(grp) {
    h := grp.next - grp.y + 6
    grp.bg.Move(, , , h)
    grp.ring.Move(, , , h + 2)
    if (grp.halo != "")
        grp.halo.Move(, , , h + 6)
    return grp.y + h + Layout.GAP
}

; right edge of a group's content
GRight(grp) => grp.x + grp.w - 12

; label at the left of a row; tip (optional) shows as a hover tooltip
GLabel(grp, y, txt, tip := "", w := 0) {
    w := w ? w : Round(grp.w * 0.5)
    c := Paint(grp.g.Add("Text", "x" . (grp.x + 12) . " y" . (y + 2) . " w" . w . " h20 +0x200", txt),
               Theme.Header, Theme.Text)
    if (tip != "")
        UI.Tips[c.Hwnd] := tip
    Reg(grp.page, c)
    SearchAdd(grp.page, c, txt, tip)
    WebRec("label", y, grp.x + 12, {text: txt, c: c})
    return c
}

; status / info line across the whole row (name optional, for live updates)
GText(grp, y, name := "", txt := "", col := "", h := 20) {
    c := Paint(grp.g.Add("Text", "x" . (grp.x + 12) . " y" . (y + 2) . " w" . (grp.w - 24)
                       . " h" . h . (h <= 20 ? " +0x200" : ""), txt),
               Theme.Header, (col = "") ? Theme.Dim : col)
    if (name != "")
        UI.Ctrl[name] := c
    Reg(grp.page, c)
    WebRec("text", y, grp.x + 12, {c: c})
    return c
}

; small dimmed note, n rows tall
GNote(grp, y, txt, n := 2) {
    grp.g.SetFont("s8 Norm", Theme.FontName)
    c := Paint(grp.g.Add("Text", "x" . (grp.x + 12) . " y" . (y + 2) . " w" . (grp.w - 24)
                       . " h" . (Round(n * Layout.ROW) - 4), txt), Theme.Header, Theme.Dim)
    grp.g.SetFont("s9 Norm", Theme.FontName)
    Reg(grp.page, c)
    WebRec("note", y, grp.x + 12, {text: txt})
    return c
}

; short value box, right-aligned (or at x when given)
GField(grp, y, name, val, numeric := true, w := 70, x := "") {
    x := (x = "") ? GRight(grp) - w : x
    e := grp.g.Add("Edit", "x" . x . " y" . (y + 1) . " w" . w . " h22 -E0x200 Center"
                 . (numeric ? " Number" : ""), val)
    grp.g.SetFont("s9 Norm", Theme.FontName)
    Paint(e, Theme.Panel2, Theme.Text)
    UI.Round.Push([e, 6, "LR"])
    UI.Ctrl[name] := e
    Reg(grp.page, e)
    WebRec("field", y, x, {c: e, num: numeric, w: w})
    return e
}

; left-aligned text box (paths, names); w = 0 fills the row
GPath(grp, y, name, val, w := 0) {
    w := w ? w : grp.w - 24
    e := grp.g.Add("Edit", "x" . (grp.x + 12) . " y" . (y + 1) . " w" . w . " h22 -E0x200", val)
    Paint(e, Theme.Panel2, Theme.Text)
    UI.Round.Push([e, 6, "LR"])
    UI.Ctrl[name] := e
    Reg(grp.page, e)
    WebRec("path", y, grp.x + 12, {c: e})
    return e
}

; key-capture box, right-aligned (or at x)
; Windows' key-capture box can't be recoloured (it stays white), so it sits off-window
; (still focusable) and a dark chip shows its value: click the chip, press the keys,
; the chip follows. UI.Ctrl[name] is still the real box, so .Value works as before.
GHot(grp, y, name, val, w := 100, x := "") {
    x := (x = "") ? GRight(grp) - w : x
    h := grp.g.Add("Hotkey", "x-40 y" . (y + 1) . " w20 h20", val)
    grp.g.SetFont("s9 Bold", Theme.FontName)
    chip := grp.g.Add("Text", "x" . x . " y" . (y + 1) . " w" . w . " h22 Center +0x200 +0x100", HotDisp(val))
    grp.g.SetFont("s9 Norm", Theme.FontName)
    Paint(chip, Theme.Panel2, (val = "") ? Theme.Dim : Theme.Text)
    UI.Round.Push([chip, 6, "LR"])
    UI.Tips[chip.Hwnd] := "Click, then press the key or combination. Backspace clears it."
    chip.OnEvent("Click", (*) => HotEdit(name))
    h.OnEvent("Change", (*) => HotSync(name, true))   ; (key boxes have no focus events)
    UI.HotChips[name] := chip
    UI.Ctrl[name] := h
    Reg(grp.page, h, chip)
    WebRec("hot", y, x, {c: h, name: name, w: w, tc: chip})
    return h
}

; "^+F7" -> "Ctrl+Shift+F7"; empty -> "Not set"
HotDisp(v) {
    if (Trim(v) = "")
        return "Not set"
    out := ""
    while (StrLen(v) > 1 && InStr("^!+#", SubStr(v, 1, 1))) {
        out .= Map("^", "Ctrl+", "!", "Alt+", "+", "Shift+", "#", "Win+")[SubStr(v, 1, 1)]
        v := SubStr(v, 2)
    }
    return out . ((StrLen(v) = 1) ? StrUpper(v) : v)
}

; chip clicked: focus the real key box, show that it is listening, and watch for
; the focus leaving it (a 100 ms check, only while one is being edited)
HotEdit(name) {
    if !(UI.HotChips.Has(name) && UI.Ctrl.Has(name))
        return
    UI.Ctrl[name].Focus()
    chip := UI.HotChips[name]
    chip.Text := "press a key..."
    Paint(chip, MixHex(Theme.Accent, Theme.Panel2, 0.8), Theme.Accent)
    UI.HotEditing := name
    SetTimer(HotWatch, 100)
}

HotWatch() {
    name := UI.HotEditing
    done := (name = "" || !UI.Ctrl.Has(name) || !UI.Visible)
    if !done {
        try done := (DllCall("user32\GetFocus", "Ptr") != UI.Ctrl[name].Hwnd)
        catch
            done := true
    }
    if (!done && GetKeyState("LButton", "P")) {          ; a click anywhere else ends it
        MouseGetPos(, , , &over, 2)
        if (UI.HotChips.Has(name) && over != UI.HotChips[name].Hwnd) {
            DllCall("user32\SetFocus", "Ptr", UI.Hwnd)
            done := true
        }
    }
    if !done
        return
    SetTimer(HotWatch, 0)
    UI.HotEditing := ""
    if (name != "")
        HotSync(name)
}

; show the key box's value on its chip (editing = still focused, keep the accent)
HotSync(name, editing := false) {
    if !(UI.HotChips.Has(name) && UI.Ctrl.Has(name))
        return
    chip := UI.HotChips[name], v := UI.Ctrl[name].Value
    chip.Text := HotDisp(v)
    if editing
        Paint(chip, MixHex(Theme.Accent, Theme.Panel2, 0.8), Theme.Accent)
    else
        Paint(chip, Theme.Panel2, (v = "") ? Theme.Dim : Theme.Text)
}

; On/off row (or part of one, with x/w): label on the left, a small rounded box on
; the right. Clicking
; either toggles it. State lives in UI.ChkState (v2 controls reject ad-hoc props).
GToggle(grp, y, name, txt, val, tip := "", x := "", w := 0) {
    left  := (x = "") ? grp.x + 12 : x              ; x/w: put it in part of the row
    right := (x = "") ? GRight(grp) : x + w
    box := grp.g.Add("Text", "x" . (right - 13) . " y" . (y + 6) . " w13 h13 +0x100")
    lbl := grp.g.Add("Text", "x" . left . " y" . (y + 2) . " w" . (right - left - 22)
                    . " h20 +0x200 +0x100", txt)
    Paint(lbl, Theme.Header)                ; PaintChk keeps this background
    UI.ChkState[box.Hwnd] := val ? 1 : 0
    UI.ChkLbl[box.Hwnd]   := lbl
    PaintChk(box)
    box.OnEvent("Click", (*) => ToggleChk(box))
    lbl.OnEvent("Click", (*) => ToggleChk(box))
    if (tip != "")
        UI.Tips[lbl.Hwnd] := tip
    SearchAdd(grp.page, lbl, txt, tip)
    UI.Round.Push([box, 4, "LR"])
    UI.Ctrl[name] := box
    Reg(grp.page, box, lbl)
    WebRec("toggle", y, left, {c: box, tc: lbl, text: txt, half: (x != "")})
    return box
}

; Slider on one row: label | track | value. The hit area is created first and is
; the only SS_NOTIFY piece; the track halves on top of it are hit-test
; transparent, so a press anywhere on the track reaches WidgetMouseDown.
GSlider(grp, y, name, label, val, lo, hi, unit := "", step := 1, tip := "") {
    g   := grp.g
    val := Max(lo, Min(hi, val))
    lw  := Round(grp.w * 0.40)               ; label column
    tx  := grp.x + 12 + lw + 6               ; bar left
    tw  := GRight(grp) - tx                  ; bar width (the value is written inside it)
    hit := Paint(g.Add("Text", "x" . tx . " y" . y . " w" . tw . " h26 +0x100 +0x04000000"), Theme.Header)
    GLabel(grp, y, label, tip, lw)
    fw   := SliderFillW(val, lo, hi, tw)
    fill := Paint(g.Add("Text", "x" . tx . " y" . (y + 6) . " w" . fw . " h14 +0x04000000"), Theme.Accent)
    rest := Paint(g.Add("Text", "x" . (tx + fw) . " y" . (y + 6) . " w" . (tw - fw) . " h14 +0x04000000"), Theme.Panel2)
    ; the value sits in the middle of the bar; its background follows whichever half
    ; is under it (SliderPaintVal)
    g.SetFont("s8 Bold", Theme.FontName)
    vt  := g.Add("Text", "x" . (tx + tw // 2 - 30) . " y" . (y + 6) . " w60 h14 Center +0x200", val . unit)
    g.SetFont("s9 Norm", Theme.FontName)
    ; the bar halves and the value go above the hit area, which is clipped by them
    ; (CLIPSIBLINGS); none of them takes clicks, so a press reaches the hit area
    for c in [fill, rest, vt]
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)   ; HWND_TOP, NOSIZE|NOMOVE|NOACTIVATE
    sl := {name: name, page: grp.page, x: tx, w: tw, lo: lo, hi: hi, step: Max(1, step), unit: unit,
           hit: hit, val: vt, fill: fill, rest: rest, y: y}
    UI.Sliders[hit.Hwnd]  := sl
    UI.SliderByName[name] := sl
    UI.SliderVal[name]    := val
    UI.Ctrl[name]         := vt
    SliderPaintVal(sl, fw)
    Reg(grp.page, hit, vt, fill, rest)
    WebRec("slider", y, tx, {sl: sl})
    return sl
}

; value text colours: on the filled part white on the primary colour, else normal text
SliderPaintVal(sl, fw) {
    over := (fw >= sl.w // 2)
    Paint(sl.val, over ? Theme.Accent : Theme.Panel2, over ? "FFFFFF" : Theme.Text)
}

; dropdown, right-aligned (or at x); outer corners rounded only
GDrop(grp, y, name, items, val, w := 110, onChange := "", x := "") {
    x := (x = "") ? GRight(grp) - w : x
    d := DropAt(grp.g, grp.page, x, y, w, name, items, val, onChange)
    UI.Round.Push([d.body, 8, "L"], [d.chev, 8, "R"])
    WebRec("drop", y, x, {name: name, w: w, tc: d.body})
    return d
}

; colour swatch + hex box, right-aligned. swName is the swatch's UI.Ctrl key.
GSwatch(grp, y, name, swName, val, w := 76) {
    Web.Mute := true                        ; recorded once, as a swatch, below
    e  := GField(grp, y, name, val, false, w)
    Web.Mute := false
    WebRec("swatch", y, GRight(grp) - w - 24, {c: e, sw: swName, w: w})
    sw := Paint(grp.g.Add("Text", "x" . (GRight(grp) - w - 24) . " y" . (y + 4) . " w16 h16"), val)
    UI.Round.Push([sw, 6, "LR"])
    UI.Ctrl[swName] := sw
    Reg(grp.page, sw)
    return e
}

; one row of buttons sharing the row width: specs = [[text, callback, style], ...]
; style: "" plain, "accent" primary colour, "bad" danger colour. Returns the buttons.
GButtons(grp, y, specs, tips := "") {
    n  := specs.Length
    bw := (grp.w - 24 - (n - 1) * 8) / n
    out := []
    for i, s in specs {
        style := (s.Length >= 3) ? s[3] : ""
        bg := (style = "accent") ? Theme.Accent : (style = "bad") ? Theme.Bad : BtnBg()
        fg := (style = "") ? Theme.Text : "FFFFFF"
        b := MkBtn(grp.g, "x" . Round(grp.x + 12 + (i - 1) * (bw + 8)) . " y" . y
                  . " w" . Round(bw) . " h24 Center +0x200", s[1], s[2], bg, fg)
        tip := (IsObject(tips) && tips.Length >= i) ? tips[i] : ""
        if (tip != "")
            UI.Tips[b.Hwnd] := tip
        Reg(grp.page, b)
        SearchAdd(grp.page, b, s[1], tip)
        out.Push(b)
    }
    return out
}

; footer buttons, laid out right to left from the window edge: [[text, cb, style], ...]
FootButtons(g, page, specs) {
    WebFootBegin(page)
    x := Layout.W - Layout.PAD
    i := specs.Length
    while (i >= 1) {
        s := specs[i]
        w := (s.Length >= 4) ? s[4] : 110
        x -= w
        style := (s.Length >= 3) ? s[3] : ""
        bg := (style = "accent") ? Theme.Accent : (style = "bad") ? Theme.Bad : BtnBg()
        fg := (style = "") ? Theme.Text : "FFFFFF"
        b := MkBtn(g, "x" . x . " y" . Layout.BTNY . " w" . w . " h28 Center +0x200", s[1], s[2], bg, fg)
        Reg(page, b)
        x -= 8
        i -= 1
    }
    Web.Foot := ""
}

; Sidebar page row: tinted background (open page), accent bar on its left edge, icon
; (Segoe UI Symbol) and label. The background is pushed under everything with the
; title strips (UI.Strips), so the bar, icon and label always sit above it.
MkNav(g, page, glyph, label, y) {
    w := Layout.SIDE - 24
    bg := Paint(g.Add("Text", "x12 y" . y . " w" . w . " h32 +0x100 +0x04000000"), Theme.Header)
    bg.OnEvent("Click", (*) => ShowPage(page))
    UI.Strips.Push(bg)
    UI.Round.Push([bg, 8, "LR"])
    UI.TabBgs[page] := bg
    bar := Paint(g.Add("Text", "x12 y" . (y + 8) . " w3 h16"), Theme.Header)
    UI.Round.Push([bar, 3, "LR"])
    UI.TabBars[page] := bar
    g.SetFont("s11", "Segoe UI Symbol")
    ic := g.Add("Text", "x26 y" . y . " w22 h32 Center +0x200 +0x100", glyph)
    ic.OnEvent("Click", (*) => ShowPage(page))
    Paint(ic, Theme.Header, Theme.Dim)
    UI.TabIcons[page] := ic
    g.SetFont("s9 w600", Theme.FontName)
    c := g.Add("Text", "x56 y" . y . " w" . (w - 50) . " h32 +0x200 +0x100", StrReplace(label, "&", "&&"))
    c.OnEvent("Click", (*) => ShowPage(page))
    Paint(c, Theme.Header, Theme.Dim)
    g.SetFont("s9 Norm", Theme.FontName)
    UI.Tabs[page] := c
    return c
}


; Button captions are written in capitals in the pages; the step-11 look shows them
; in sentence case. Words that must stay capitals (names, units) are restored.
BtnCase(txt) {
    if (txt = "" || txt != StrUpper(txt))
        return txt                                    ; already mixed case: leave it
    out := StrUpper(SubStr(txt, 1, 1)) . StrLower(SubStr(txt, 2))
    for w in ["FPS", "ARK", "GPU", "CPU", "RAM", "PNG", "F7", "F9"]
        out := RegExReplace(out, "i)\b" . w . "\b", w)
    return out
}

; plain (secondary) button colour: a step lighter than the panels
BtnBg() => MixHex(Theme.Header, "FFFFFF", 0.05)

MkBtn(g, opts, txt, cb, bg := "", fg := "") {
    bg := (bg = "") ? BtnBg() : bg
    fg := (fg = "") ? Theme.Text   : fg
    c := g.Add("Text", opts . " +0x100", BtnCase(txt))
    wrapped := ClickWrap(cb)
    c.OnEvent("Click", wrapped)
    Paint(c, bg, fg)
    bx := RegExMatch(opts, "\bx(-?\d+)", &mx) ? Integer(mx[1]) : 0
    by := RegExMatch(opts, "\by(-?\d+)", &my) ? Integer(my[1]) : 0
    if (txt = "" && bg != BtnBg())                  ; a colour preset square
        WebRec("color", by, bx, {c: c, cb: wrapped, col: bg})
    else
        WebRec("button", by, bx, {c: c, cb: wrapped,
               style: (bg = Theme.Accent) ? "accent" : (bg = Theme.Bad) ? "bad" : ""})
    UI.Hover[c.Hwnd] := [bg, Lighten(bg)]
    UI.Round.Push([c, 6, "LR"])
    return c
}

; plays the click sound (if enabled) then runs the button's real callback
ClickWrap(cb) {
    return (*) => (PlayClick(), cb())
}

Reg(page, ctrls*) {
    for c in ctrls
        UI.Pages[page].Push(c)
}

ChkVal(box) {
    return UI.ChkState.Has(box.Hwnd) ? UI.ChkState[box.Hwnd] : 0
}

; accent box + white tick when on; dark box and a dimmed label when off
PaintChk(box) {
    on := ChkVal(box)
    Paint(box, on ? Theme.Accent : Theme.Line)        ; filled square = on
    if UI.ChkLbl.Has(box.Hwnd)                        ; label a little softer while off
        Paint(UI.ChkLbl[box.Hwnd], "", on ? Theme.Text : MixHex(Theme.Text, Theme.Dim, 0.55))
}

ToggleChk(box) {
    UI.ChkState[box.Hwnd] := ChkVal(box) ? 0 : 1
    PaintChk(box)
}

; set a toggle from code (layouts, tune-up refresh); no-op when it isn't built
SetToggle(name, val) {
    if !UI.Ctrl.Has(name)
        return
    box := UI.Ctrl[name]
    UI.ChkState[box.Hwnd] := val ? 1 : 0
    PaintChk(box)
}

; logical fill width; 2px floor keeps both halves valid controls, like a min nub
SliderFillW(val, lo, hi, w) {
    frac := (hi > lo) ? (val - lo) / (hi - lo) : 0
    return Max(2, Min(w - 2, Round(frac * w)))
}

SliderValue(name, def) => UI.SliderVal.Has(name) ? UI.SliderVal[name] : def

SliderSet(sl, v) {
    v := Max(sl.lo, Min(sl.hi, Round(v)))
    if (UI.SliderVal.Has(sl.name) && UI.SliderVal[sl.name] = v)
        return
    UI.SliderVal[sl.name] := v
    fw := SliderFillW(v, sl.lo, sl.hi, sl.w)
    sl.fill.Move(, , fw)
    sl.rest.Move(sl.x + fw, , sl.w - fw)
    SliderPaintVal(sl, fw)
    sl.val.Text := v . sl.unit
}

; Positions come from ControlGetPos (real pixels), so the maths holds at any DPI;
; Move() takes the logical numbers the control was created with.
SliderFromMouse(sl) {
    MouseGetPos(&mx)
    WinGetClientPos(&cx, , , , "ahk_id " . UI.Hwnd)
    ControlGetPos(&fx, , , , sl.fill)
    ControlGetPos(&rx, , &rw, , sl.rest)
    span := Max(1, rx + rw - fx)
    frac := Max(0, Min(1, (mx - cx - fx) / span))
    SliderSet(sl, sl.lo + Round(frac * (sl.hi - sl.lo) / sl.step) * sl.step)
}

WidgetMouseDown(wParam, lParam, msg, hwnd) {
    ; any press in one of our windows that is not inside the open list closes it;
    ; catches quick clicks the 50 ms DropWatch poll can miss
    if (UI.DropPopup != "") {
        root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")   ; GA_ROOT
        if (root != UI.DropPopup.Hwnd)
            DropClose()
    }
    ; same for the settings-search results (but not a click in the search box)
    if (Search.Popup != "") {
        root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        if (root != Search.Popup.Hwnd && !(UI.Ctrl.Has("search") && hwnd = UI.Ctrl["search"].Hwnd))
            SearchClose()
    }
    if (Anim.Busy || !UI.Sliders.Has(hwnd))
        return
    Loop {
        if (Anim.Busy || !UI.Sliders.Has(hwnd))   ; menu rebuilt mid-drag
            break
        try SliderFromMouse(UI.Sliders[hwnd])
        if !GetKeyState("LButton", "P")
            break
        Sleep 15
    }
    return 0
}

; wheel over a slider = one step (Shift = ten). Hit-tested by position because
; the wheel message goes to the focused control, not the one under the cursor.
SliderWheel(wParam, lParam, msg, hwnd) {
    if (!UI.Visible || Anim.Busy || UI.Sliders.Count = 0)
        return
    MouseGetPos(&mx, &my, &win)
    if (win != UI.Hwnd)
        return
    WinGetClientPos(&cx, &cy, , , "ahk_id " . UI.Hwnd)
    for h, sl in UI.Sliders {
        if (sl.page != UI.Page)
            continue
        try ControlGetPos(&hx, &hy, &hw, &hh, sl.hit)
        catch
            continue
        if (mx - cx >= hx && mx - cx < hx + hw && my - cy >= hy && my - cy < hy + hh) {
            d := (wParam >> 16) & 0xFFFF
            if (d & 0x8000)
                d -= 0x10000
            n := GetKeyState("Shift") ? 10 : 1
            SliderSet(sl, UI.SliderVal[sl.name] + ((d > 0) ? n : -n) * sl.step)
            return 0
        }
    }
}

; Dropdown: a dark body plus a chevron cell; clicking either opens a borderless
; owned list window underneath. onChange (optional) is called with the new item.
DropAt(g, page, x, y, w, name, items, val, onChange := "") {
    found := false
    for it in items {
        if (it = val)
            found := true
    }
    if !found
        val := items[1]
    body := Paint(g.Add("Text", "x" . x . " y" . y . " w" . (w - 22) . " h24 +0x200 +0x100", "  " . val),
                  Theme.Panel2, Theme.Text)
    g.SetFont("s7 Norm", "Segoe UI Symbol")
    chev := Paint(g.Add("Text", "x" . (x + w - 22) . " y" . y . " w22 h24 Center +0x200 +0x100", Chr(0x25BC)),
                  Theme.Panel2, Theme.Text)
    g.SetFont("s9 Norm", Theme.FontName)
    d := {name: name, items: items, body: body, chev: chev, onChange: onChange}
    UI.Drops[name]  := d
    UI.DropVal[name] := val
    body.OnEvent("Click", (*) => DropOpen(name))
    chev.OnEvent("Click", (*) => DropOpen(name))
    UI.Ctrl[name] := body
    Reg(page, body, chev)
    return d
}

DropValue(name, def) => UI.DropVal.Has(name) ? UI.DropVal[name] : def

DropOpen(name) {
    ; the watcher already closed this same list on the mouse-down of this click
    if (name = UI.DropLastName && A_TickCount - UI.DropLastClose < 350)
        return
    DropClose()
    if (Anim.Busy || !UI.Drops.Has(name))
        return
    d := UI.Drops[name]
    ControlGetPos(&bx, &by, , &bh, d.body)
    ControlGetPos(&kx, , &kw, , d.chev)
    WinGetClientPos(&cx, &cy, , , "ahk_id " . UI.Hwnd)
    rowH := Round(24 * A_ScreenDPI / 96)
    wPx  := kx + kw - bx

    ; -DPIScale: sized in the real pixels measured above
    p := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +Owner" . UI.Hwnd)
    StreamHide(p.Hwnd)
    p.BackColor := Theme.Panel2
    p.MarginX := 0, p.MarginY := 0
    p.SetFont("s9 Bold", Theme.FontName)
    cur := DropValue(name, "")
    for i, item in d.items {
        r := p.Add("Text", "x0 y" . ((i - 1) * rowH) . " w" . wPx . " h" . rowH . " +0x200 +0x100", "  " . item)
        Paint(r, Theme.Panel2, (item = cur) ? Theme.Accent : Theme.Text)
        r.OnEvent("Click", DropPickCb(name, item))
    }
    UI.DropPopup := p
    UI.DropLastName := name
    p.Show("x" . (cx + bx) . " y" . (cy + by + bh + 2) . " w" . wPx . " h" . (rowH * d.items.Length) . " NoActivate")
    UI.DropWatchOn := true
    SetTimer(DropWatch, 50)
}

; deferred: destroying a window from inside its own control's click event is the
; pattern the rest of this file avoids (every menu rebuild goes through SetTimer)
DropPickCb(name, item) => (*) => DropPickLater(name, item)

DropPickLater(name, item) {
    if (UI.DropPopup != "")
        try UI.DropPopup.Hide()
    SetTimer(DropPick.Bind(name, item), -10)
}

DropPick(name, item) {
    DropClose()
    if !UI.Drops.Has(name)
        return
    d := UI.Drops[name]
    UI.DropVal[name] := item
    d.body.Text := "  " . item
    if (d.onChange != "")
        d.onChange.Call(item)
}

; set a dropdown from code, without its onChange
DropSet(name, item) {
    if !UI.Drops.Has(name)
        return
    UI.DropVal[name] := item
    UI.Drops[name].body.Text := "  " . item
}

DropClose() {
    if UI.DropWatchOn {
        UI.DropWatchOn := false
        SetTimer(DropWatch, 0)
    }
    p := UI.DropPopup
    UI.DropPopup := ""                ; clear first: DropWatch may already be queued
    if (p = "")
        return
    UI.DropLastClose := A_TickCount
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

; closes the list on any press outside it, or when the menu goes away
DropWatch() {
    p := UI.DropPopup
    if (p = "")
        return
    if (!UI.Visible || Anim.Busy) {
        DropClose()
        return
    }
    if GetKeyState("LButton", "P") {
        MouseGetPos(, , &win)
        if (win != p.Hwnd)
            DropClose()
    }
}

; ---- Reading the UI back into config --------------------------------------
Num(name, def, lo, hi) {
    v := def
    if UI.SliderVal.Has(name)             ; converted fields: the slider holds the value
        v := UI.SliderVal[name]
    else
        try v := Integer(UI.Ctrl[name].Value)
    return Max(lo, Min(hi, v))
}

Hex(name, def) {
    v := Trim(UI.Ctrl[name].Value)
    v := StrReplace(StrReplace(v, "0x"), "#")
    return RegExMatch(v, "^[0-9a-fA-F]{6}$") ? StrUpper(v) : def
}
