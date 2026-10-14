; ArkSense - lib\Overlay.ahk
; In-game status overlay (pills) and streamer mode.
; Part of ArkSense.ahk; run that file, not this one.
;
; Two renderers share everything here: the smooth one (lib\Ovl.ahk drives
; lib\ArkSenseOverlay.exe) and the classic one below (one AutoHotkey window per
; pill). Each entry point starts with "if OvlOn()" and hands the work over; the
; classic code runs when the smooth renderer is off or couldn't start.

HudTextPresetCb(col) => (*) => SetHudTextColor(col)

; Overlay colours. The classic look (the default) is step 9's: red, cyan and dark grey,
; whatever the menu theme is. The modern look ("Modern look" on the Overlay tab, the
; smooth renderer) follows the menu theme. Pill text / outline colours are the user's own.
OvC(k) {
    static step9 := Map("Accent", "FF2836", "Accent2", "18C8E6", "Panel", "0E0E12", "Panel2", "1C1C24",
                        "Dim", "7C7C8A", "Ok", "4CD07A", "Bad", "FF5C7A", "Text", "FFFFFF", "Line", "26262F")
    return (Theme.Renderer = "Smooth") ? Theme.%k% : step9[k]
}

SetHudTextColor(col) {
    Theme.HudTextColor := col
    if UI.Ctrl.Has("hudTextColor")
        UI.Ctrl["hudTextColor"].Value := col
    if UI.Ctrl.Has("hudTextSwatch")
        Paint(UI.Ctrl["hudTextSwatch"], col)
    SaveIni()
    RebuildHud()
}

SetStreamerScope(item) {
    Theme.StreamerScope := item
    ApplyStreamerMode()
    SaveIni()
    Flash("streamer mode hides: " . item)
}

ToggleStreamerMode(*) {
    Theme.StreamerMode := !Theme.StreamerMode
    ApplyStreamerMode()
    SaveIni()
    RefreshStreamerStatus()
}

RefreshStreamerStatus() {
    if !UI.Ctrl.Has("streamerStatus")
        return
    c := UI.Ctrl["streamerStatus"]
    c.Text := "streamer   " . (Theme.StreamerMode ? "ON" : "off")
    Paint(c, "", Theme.StreamerMode ? Theme.Ok : Theme.Dim)
}

; independent of the antidote loop, so add-on status still updates even
; while antidote is off or ARK isn't focused. Also notices when the overlays
; should appear or hide ("Only in ARK") - the pills via Hud()'s change key, the
; stats card here, since its own refresh runs only every few seconds.
HudTick() {
    static lastAllowed := -1
    if Anim.Busy
        return
    OvlCheck()                        ; smooth renderer still running? (every 2 s)
    try NpFocusTick()                 ; Now playing: hide at once when focus leaves ARK
    try StreamReassert()              ; streamer mode stays on every window (every 2 s)
    FilterTick()                      ; screen filter follows ARK's focus
    TuneTick()                        ; power plan / priority while ARK runs (every 2 s)
    a := OverlayAllowed()
    if (a != lastAllowed) {
        lastAllowed := a
        RefreshStatHud()
    }
    Hud(S.hudMsg, S.hudCol)
}

; ---- In-game status overlay: free-floating pills -------------------------------
; Every pill is its own small click-through window, so each one can sit anywhere
; on screen at its own size. A pill is plain Static controls - outline, fill,
; icon, text, and a resize grip shown only while editing - painted through the
; same CtlColor handler as the menu: no GDI+, no owner draw. Rounded corners come
; from SetWindowRgn (plain numbers only). The window background is a key colour
; knocked out with WinSetTransColor, so only the pill itself is visible.
;
; Pill windows are -DPIScale, so every number here is a real pixel: measured
; text widths, Move() and the regions all use the same units.
;
; Layout: a pill with a saved spot (Pill.Pos, from EDIT LAYOUT + LOCK) sits
; there at its saved size. A pill without one goes into an automatic stack that
; starts at the anchor Theme.HudX/HudY, at the default size Theme.HudFontSize.

; Pills in on-screen order: [key, icon glyph]. Each one is behind its own toggle.
PillDefs() {
    defs := []
    if Theme.HudShowState
        defs.Push(["state",   0x2699])
    if Theme.HudShowMsg
        defs.Push(["msg",     0x2261])
    if Theme.HudShowCounts
        defs.Push(["counts",  0x2263])
    if Theme.HudShowDesmo
        defs.Push(["desmo",   0x21BB])
    if Theme.HudShowMammoth
        defs.Push(["mammoth", 0x25B2])
    if Theme.HudShowBag
        defs.Push(["bag",     0x2318])
    if Theme.HudShowStreamer
        defs.Push(["stream",  0x25C9])
    if Theme.HudShowOc {                 ; one switch for both macro pills (shown only while running)
        defs.Push(["oc",      0x25C8])
        defs.Push(["clicker", 0x25CE])
    }
    if (defs.Length = 0)                 ; nothing ticked: keep one pill to drag
        defs.Push(["none",    0x25C9])
    return defs
}

; On/off pill. Colours follow the reference: a feature that is OFF is drawn in the
; primary colour so it stands out, one that is ON in the normal text colour.
PillState(name, active) => active ? [name . ": On",  Theme.HudTextColor, OvC("Dim")]
                                  : [name . ": Off", OvC("Accent"), OvC("Accent")]

; [text, text colour, icon colour] for one pill, or "" to hide it right now
PillContent(k, msg, col) {
    switch k {
        case "state":
            return PillState("Antidote", S.enabled)
        case "msg":
            if (msg = "")
                return ""
            return [msg, (col = "") ? Theme.HudTextColor : col, OvC("Dim")]
        case "counts":
            return ["ok " . S.applied . "   fail " . S.failed, Theme.HudTextColor, OvC("Dim")]
        case "desmo":
            return PillState("Remount", Desmo.Active)
        case "mammoth":
            return PillState("Mammoth", Mammoth.Active)
        case "bag":
            return PillState("Bag", Bag.Active)
        case "stream":
            return PillState("Stream", Theme.StreamerMode)
        case "oc":                                      ; only while it runs
            return Oc.Active ? ["OC: On", Theme.HudTextColor, OvC("Accent")] : ""
        case "clicker":
            return Ac.Active ? ["Clicker: " . Ac.Cps . "/s", Theme.HudTextColor, OvC("Accent")] : ""
    }
    return ["ArkSense", Theme.HudTextColor, OvC("Accent")]
}

BuildHud() {
    if OvlOn() {                          ; smooth renderer: no windows on this side
        order := []
        for d in PillDefs()
            order.Push(d[1])
        Pill.Items  := Map()
        Pill.ByHwnd := Map()
        Pill.Order  := order
        OvlTheme()
        return
    }
    items := Map(), order := [], byHwnd := Map()
    for d in PillDefs() {
        w := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")   ; click-through
        w.BackColor := Pill.KeyCol
        w.MarginX := 0
        w.MarginY := 0
        ; WS_CLIPSIBLINGS (0x04000000) on every piece: they overlap, and each must
        ; paint only the part of itself left uncovered, or a repaint of the outline
        ; would wipe the text above it.
        bd := w.Add("Text", "x0 y0 w10 h10 +0x04000000")
        fl := w.Add("Text", "x0 y0 w10 h10 +0x04000000")
        w.SetFont("s" . Theme.HudFontSize . " Norm", "Segoe UI Symbol")
        ic := w.Add("Text", "x0 y0 w10 h10 Center +0x200 +0x04000000", Chr(d[2]))
        gr := w.Add("Text", "x0 y0 w10 h10 Center +0x200 +0x04000000 Hidden", Chr(0x25E2))
        w.SetFont("s" . Theme.HudFontSize . " Bold", Theme.FontName)
        tx := w.Add("Text", "x0 y0 w10 h10 +0x200 +0x04000000", "")
        ; explicit stacking: raise each piece to the top in turn, so text ends on top
        for c in [bd, fl, ic, gr, tx]
            DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
                    "Int", 0, "Int", 0, "UInt", 0x13)   ; HWND_TOP, NOSIZE|NOMOVE|NOACTIVATE
        w.Show("x0 y0 w1 h1 NoActivate Hide")
        ; 0x prefix: a bare hex string can be read as an ambiguous number
        WinSetTransColor("0x" . Pill.KeyCol . " " . Theme.HudBgOpacity, "ahk_id " . w.Hwnd)
        items[d[1]] := {win: w, border: bd, fill: fl, icon: ic, grip: gr, text: tx,
                        size: Theme.HudFontSize, w: 1, h: 1, gx: 0}
        order.Push(d[1])
        byHwnd[w.Hwnd] := d[1]
    }
    ; publish only once complete: Hud() reads an empty Order as "mid-rebuild"
    Pill.Items  := items
    Pill.ByHwnd := byHwnd
    Pill.Order  := order
    ApplyStreamerMode()
}

; Clear the shared state FIRST, then destroy - a timer can call Hud() in between
; (the same rule as every other overlay rebuild in this script).
PillDestroyAll() {
    old := Pill.Items
    Pill.Order  := []
    Pill.Items  := Map()
    Pill.ByHwnd := Map()
    for k, p in old
        try p.win.Destroy()
}

; text size in pixels with the control's own font; plain GDI calls on our own
; fixed 8-byte SIZE buffer (two Ints), so there is no struct layout to get wrong
PillTextSize(ctrl, txt, &tw, &th) {
    tw := StrLen(txt) * 8, th := 16       ; fallback if the DC can't be had
    hdc := DllCall("user32\GetDC", "Ptr", ctrl.Hwnd, "Ptr")
    if !hdc
        return
    hf  := DllCall("user32\SendMessageW", "Ptr", ctrl.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    old := hf ? DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", hf, "Ptr") : 0
    sz  := Buffer(8, 0)
    if DllCall("gdi32\GetTextExtentPoint32W", "Ptr", hdc, "Str", txt, "Int", StrLen(txt), "Ptr", sz) {
        tw := NumGet(sz, 0, "Int")
        th := NumGet(sz, 4, "Int")
    }
    if old
        DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    DllCall("user32\ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)
}

; move a piece and round its corners (d = corner diameter). The system owns the
; region once SetWindowRgn accepts it; it is freed here only if it was refused.
PillPlace(ctrl, x, y, w, h, d) {
    ctrl.Move(x, y, w, h)
    rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w + 1, "Int", h + 1,
                   "Int", d, "Int", d, "Ptr")
    if (rgn && !DllCall("user32\SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", rgn, "Int", 1))
        DllCall("gdi32\DeleteObject", "Ptr", rgn)
}

; Size, colour and lay out one pill's pieces at font size `size`. Sets p.w/p.h;
; returns false when the pill has nothing to show right now. While editing, an
; empty pill shows a placeholder so it can still be placed, the outline is drawn
; in the primary colour and the resize grip appears at the right end.
PillRender(p, k, msg, col, size) {
    editing := UI.HudDragging
    c := PillContent(k, msg, col)
    if (c = "") {
        if !editing
            return false
        c := ["status message", OvC("Dim"), OvC("Dim")]
    }
    if (p.size != size) {
        p.icon.SetFont("s" . size)
        p.grip.SetFont("s" . size)
        p.text.SetFont("s" . size)
        p.size := size
    }
    f      := size / 9                       ; everything scales with the font
    b      := (Theme.HudBorderOn || editing) ? Max(1, Round(f)) : 0
    pad    := Round(9 * f), gap := Round(5 * f), corner := Max(6, Round(12 * f))
    filled := Theme.HudBgOn || editing       ; a see-through pill can't be grabbed
    fill   := filled ? OvC("Panel2") : Pill.KeyCol
    p.text.Text := c[1]
    PillTextSize(p.text, c[1], &tw, &th)
    PillTextSize(p.icon, p.icon.Text, &iw, &ih)
    tw += 2                                  ; bold/ClearType overhang
    gw := 0
    if editing
        PillTextSize(p.grip, p.grip.Text, &gw, &gh)
    h := Max(Round(Theme.PillH * f), th + Round(6 * f), ih + Round(6 * f))
    w := pad + iw + gap + tw + pad + (editing ? gw + gap : 0)
    win := p.win
    ; only while visible: WM_SETREDRAW TRUE would make a hidden pill visible at 0,0
    vis := DllCall("user32\IsWindowVisible", "Ptr", win.Hwnd)
    if vis
        DllCall("user32\SendMessageW", "Ptr", win.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)   ; WM_SETREDRAW off
    try {
        PillPlace(p.border, 0, 0, w, h, corner)
        PillPlace(p.fill, b, b, w - 2 * b, h - 2 * b, corner - 2 * b)
        p.icon.Move(pad, b, iw, h - 2 * b)
        p.text.Move(pad + iw + gap, b, tw, h - 2 * b)
        p.gx := w - pad - gw
        if editing
            p.grip.Move(p.gx, b, gw, h - 2 * b)
        Paint(p.border, editing ? OvC("Accent") : Theme.HudBorderColor)
        Paint(p.fill, fill)
        Paint(p.icon, fill, c[3])
        Paint(p.text, fill, c[2])
        Paint(p.grip, fill, OvC("Accent"))
        p.border.Visible := (b > 0)
        p.fill.Visible   := filled
        p.grip.Visible   := editing
    } finally {
        if vis {
            DllCall("user32\SendMessageW", "Ptr", win.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)   ; WM_SETREDRAW on
            DllCall("user32\RedrawWindow", "Ptr", win.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085)
        }
    }
    p.w := w
    p.h := h
    return true
}

; Render and place every pill. A rebuild swaps Pill.Items/Order, so work from a
; snapshot taken once at the start.
PillRefresh(msg, col) {
    if OvlOn() {
        OvlPills(msg, col)
        return
    }
    items := Pill.Items, order := Pill.Order
    show  := (Theme.HudOn || UI.HudDragging) && OverlayAllowed()
    ax := Theme.HudX, ay := Theme.HudY
    for k in order {
        if !items.Has(k)
            continue
        p := items[k]
        saved := Pill.Pos.Has(k)
        size  := saved ? Pill.Pos[k][3] : Theme.HudFontSize
        if (!show || !PillRender(p, k, msg, col, size)) {
            p.win.Hide()
            continue
        }
        if saved {
            x := Pill.Pos[k][1], y := Pill.Pos[k][2]
        } else {
            x := ax, y := ay
            if Theme.PillVertical
                ay += p.h + Theme.PillGap
            else
                ax += p.w + Theme.PillGap
        }
        p.win.Show(Format("x{} y{} w{} h{} NoActivate", x, y, p.w, p.h))
    }
}

; recolour every pill outline and the card outline (effects, or restoring the set colour)
PillBorders(col) {
    if OvlOn() {
        OvlFx(col)
        return
    }
    if (Pill.Order.Length = 0 || !Theme.HudBorderOn || UI.HudDragging)
        return
    for k, p in Pill.Items
        try Paint(p.border, col)
    Card.FxCol := col                     ; the card picks it up on its next draw
}

; Edit mode: pills take clicks (WS_EX_TRANSPARENT off) and are kept readable even
; if the overlay opacity is set very low; both are restored on the way out.
PillSetEditing(on) {
    if OvlOn() {                          ; the helper's windows take clicks while editing
        OvlSend("edit`t" . (on ? 1 : 0))
        return
    }
    alpha := on ? Max(170, Theme.HudBgOpacity) : Theme.HudBgOpacity
    for k, p in Pill.Items {
        hw := p.win.Hwnd
        try {
            ex := WinGetExStyle("ahk_id " . hw)
            WinSetExStyle(on ? ex & ~0x20 : ex | 0x20, "ahk_id " . hw)
            WinSetTransColor("0x" . Pill.KeyCol . " " . alpha, "ahk_id " . hw)
        }
    }
    if (UI.StatHud != "") {               ; the card: click-through only; its opacity is
        hw := UI.StatHud.Hwnd               ; drawn (never WinSetTransColor on that window)
        try {
            ex := WinGetExStyle("ahk_id " . hw)
            WinSetExStyle(on ? ex & ~0x20 : ex | 0x20, "ahk_id " . hw)
        }
    }
}

; remember where every visible pill (and the stats card) is now, and at what size
PillCapture() {
    if OvlOn() {                          ; where the helper has every piece right now
        for k, v in OvlPositions()
            Pill.Pos[k] := [v[1], v[2], v[3]]
        return
    }
    for k, p in Pill.Items {
        if !DllCall("user32\IsWindowVisible", "Ptr", p.win.Hwnd)
            continue
        try {
            WinGetPos(&x, &y, , , "ahk_id " . p.win.Hwnd)
            Pill.Pos[k] := [x, y, p.size]
        }
    }
    if (UI.StatHud != "" && DllCall("user32\IsWindowVisible", "Ptr", UI.StatHud.Hwnd)) {
        try {
            WinGetPos(&x, &y, , , "ahk_id " . UI.StatHud.Hwnd)
            Pill.Pos["stats"] := [x, y, Card.Size]
        }
    }
}

; Drag on the grip: the pill scales with the pointer, live. Runs inside the
; WM_LBUTTONDOWN handler until the button is released, like a slider drag.
PillResizeDrag(k) {
    p := Pill.Items[k]
    hw := p.win.Hwnd
    MouseGetPos(&mx0)
    WinGetPos(&wx, &wy, , , "ahk_id " . hw)
    s0 := p.size, w0 := Max(1, p.w)
    Loop {
        if (!UI.HudDragging || !Pill.Items.Has(k) || Pill.Items[k] != p)   ; rebuilt mid-drag
            break
        MouseGetPos(&mx)
        size := Max(6, Min(48, Round(s0 * (w0 + mx - mx0) / w0)))
        if (size != p.size) {
            PillRender(p, k, S.hudMsg, S.hudCol, size)
            p.win.Show(Format("x{} y{} w{} h{} NoActivate", wx, wy, p.w, p.h))
        }
        if !GetKeyState("LButton", "P")
            break
        Sleep 15
    }
}

; "Only in ARK": the overlays show while ARK is focused, while this menu is open,
; or while their layout is being edited; otherwise they hide (browser, desktop...)
OverlayAllowed() => !Theme.OverlayGameOnly || UI.HudDragging || UI.Visible || GameActive()

; records the latest message so HudTick() can redraw when only an add-on changed
Hud(msg, col := "") {
    S.hudMsg := msg
    S.hudCol := col
    if (Anim.Busy || UI.HudDragging)
        return
    key := msg . "|" . col . "|" . S.enabled . "|" . S.applied . "|" . S.failed
         . "|" . Desmo.Active . "|" . Mammoth.Active . "|" . Bag.Active
         . "|" . Theme.StreamerMode . "|" . OverlayAllowed() . "|" . Oc.Active . "|" . Ac.Active
    if (key = S.lastHud)
        return
    if (Pill.Order.Length = 0)            ; overlay mid-rebuild
        return
    S.lastHud := key
    PillRefresh(msg, col)
}

RebuildHud() {
    if UI.HudDragging                     ; commit an open layout edit first
        HudLockPosition()
    PillDestroyAll()
    BuildHud()
    S.lastHud := ""
}

; Edit mode only: press on a pill or the stats card to move it, on its grip
; (the triangle) to resize it.
HudDrag(wParam, lParam, msg, hwnd) {
    if (Np.Win != "" && hwnd = Np.Win.Hwnd && (Np.Moving || UI.HudDragging)) {
        PostMessage 0xA1, 2, 0, , "ahk_id " . hwnd       ; the Now playing card: just move it
        return 0
    }
    if (Ct.Win != "" && hwnd = Ct.Win.Hwnd && (Ct.Moving || UI.HudDragging)) {
        PostMessage 0xA1, 2, 0, , "ahk_id " . hwnd       ; the clantag box: same
        return 0
    }
    if (UI.HudDragging && Pill.ByHwnd.Has(hwnd)) {
        k := Pill.ByHwnd[hwnd]
        if !Pill.Items.Has(k)
            return
        if ((lParam & 0xFFFF) >= Pill.Items[k].gx - 2) {
            PillResizeDrag(k)
            return 0
        }
        PostMessage 0xA1, 2, 0, , "ahk_id " . hwnd       ; WM_NCLBUTTONDOWN / HTCAPTION
    } else if (CardEditing() && UI.StatHud != "" && hwnd = UI.StatHud.Hwnd) {
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        if (x >= Card.GripX - 3 && y >= Card.GripY - 3) {
            CardResizeDrag()
            return 0
        }
        PostMessage 0xA1, 2, 0, , "ahk_id " . hwnd
    }
}

; EDIT LAYOUT: every pill shows (even ones with nothing to say yet) and takes clicks
HudPreview() {
    if (Pill.Order.Length = 0)
        return
    UI.HudDragging := true
    PillSetEditing(true)
    PillRefresh(S.hudMsg, S.hudCol)
    RefreshStatHud()
    Np.Sig := ""
    try NpRefresh()
    Ct.Sig := ""
    try CtTick()
    Flash("drag a pill or the stats card to move it, its corner to resize it, then LOCK")
}

; LOCK: save every visible pill's spot and size, and go back to click-through
HudLockPosition() {
    PillCapture()
    if Np.On
        NpCapture()                           ; the Now playing card moves with the layout too
    if (Ct.On && !CtOnCard())
        CtCapture()                           ; and the clantag box
    UI.HudDragging := false
    Card.Moving := false                  ; a card-only move ends with it
    PillSetEditing(false)
    SaveIni()
    S.lastHud := ""
    Hud(S.hudMsg, S.hudCol)               ; redraw without grips (hides all if overlay is off)
    RefreshStatHud()
    CardPosFields()
    Np.Sig := ""
    try NpRefresh()
    NpPosFields()
    Ct.Sig := ""
    try CtTick()
    CtPosFields()
    Flash("overlay layout saved")
}

; RESET LAYOUT: forget every saved spot and size; pills restack at the anchor
PillResetLayout() {
    Pill.Pos := Map()
    SaveIni()
    S.lastHud := ""
    if UI.HudDragging
        PillRefresh(S.hudMsg, S.hudCol)
    else
        Hud(S.hudMsg, S.hudCol)
    RefreshStatHud()
    CardPosFields()
    Flash("pills restacked at the anchor")
}

; What streamer mode hides (step 19: Overlay > Display > "Hides"): "Menu + overlays",
; "Overlays only" or "Menu only". kind = "menu" (menu, its popups, tooltips, self-check,
; startup animation) or "overlay" (pills, stats card, Now playing, alerts).
StreamerScopes() => ["Menu + overlays", "Overlays only", "Menu only"]

StreamFlag(kind) {
    if !Theme.StreamerMode
        return 0
    sc := Theme.StreamerScope
    if (kind = "menu")
        return (sc = "Overlays only") ? 0 : 0x11
    return (sc = "Menu only") ? 0 : 0x11
}

; one window, right after it is made: hidden from capture if streamer mode covers it
StreamHide(hwnd, kind := "menu") {
    f := StreamFlag(kind)
    if (hwnd && f)
        try DllCall("user32\SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", f)
}

; set and read back; failures are counted for the self-check and logged once each
SetAffinity(hwnd, f) {
    static logged := Map()
    if !hwnd
        return true
    ok := false
    try ok := DllCall("user32\SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", f)
    if (!ok && f) {
        Stream.Failed += 1
        err := A_LastError
        if !logged.Has(hwnd) {
            logged[hwnd] := 1
            cls := ""
            try cls := WinGetClass("ahk_id " . hwnd)
            Logg("stream", "couldn't hide a window from capture (" . cls . ", error " . err
                         . ((err = 8) ? " - needs Windows 10 2004 or newer" : "") . ")")
        }
    } else if (ok && f) {
        Stream.Hidden += 1
    }
    return ok
}

; every 2 s while streamer mode is on (HudTick): set it again on every window, so a
; window that was rebuilt, re-shown or re-created by its helper is never left visible
StreamReassert() {
    static at := 0
    if (!Theme.StreamerMode || A_TickCount < at)
        return
    at := A_TickCount + 2000
    ApplyStreamerMode()
}

; hides windows from Windows Graphics Capture / DXGI (OBS, Medal display capture ...)
; while they stay visible on the real display - Windows 10 2004+/11 only.
ApplyStreamerMode() {
    Stream.Hidden := 0, Stream.Failed := 0
    fm := StreamFlag("menu"), fo := StreamFlag("overlay")
    for w in [Check.Win, Search.Popup, UI.DropPopup, Splash.Win] {
        if (w != "")
            SetAffinity(w.Hwnd, fm)
    }
    SetAffinity(UI.Hwnd, fm)
    if (Web.Gui != "")
        SetAffinity(Web.Gui.Hwnd, fm)
    for t in Alerts.Classic
        SetAffinity(t.g.Hwnd, fo)
    static lastOvl := -1
    if (OvlOn() && fo != lastOvl) {       ; the helper applies it to its own windows
        lastOvl := fo
        OvlTheme()
    }
    for k, p in Pill.Items
        SetAffinity(p.win.Hwnd, fo)
    if (UI.StatHud != "")
        SetAffinity(UI.StatHud.Hwnd, fo)
    if (Np.Win != "")
        SetAffinity(Np.Win.Hwnd, fo)
    CtAffinity()                          ; the clantag box (unless "Show in recordings")
}
