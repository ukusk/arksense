BuildMenu() {
    DropClose()                       ; a list left open would point at dead controls
    UI.Sliders      := Map()
    UI.SliderByName := Map()
    UI.SliderVal    := Map()
    UI.Drops        := Map()
    UI.DropVal      := Map()
    UI.Ctrl      := Map()
    UI.Pages     := Map("antidote", [], "macros", [], "oc", [], "fps", [], "overlay", [], "music", [], "clantag", [], "look", [], "settings", [],
                        "tune", [], "logs", [])
    UI.Tabs      := Map()
    UI.TabBars   := Map()
    UI.TabIcons  := Map()
    UI.CustomBg  := Map()
    UI.CustomFg  := Map()
    UI.Hover     := Map()
    UI.Tips      := Map()
    UI.Groups    := []
    SearchClose()
    Search.Idx   := []
    Search.Group := ""
    UI.Rings     := []
    UI.Borders   := []
    UI.Halos     := []
    UI.Strips    := []
    UI.HotChips  := Map()
    UI.TabBgs    := Map()
    Web.Model    := Map()             ; the web menu's copy of every page, rebuilt with it
    Web.Reg      := []
    Web.Last     := Map()
    Web.Group    := ""
    Web.Foot     := ""
    Web.Dirty    := true
    UI.AccentSegs := []
    UI.GlowSegs  := []
    UI.TabX      := Layout.TABX
    Anim.Heat    := Map()
    UI.Round     := []
    UI.LastHover := 0
    Anim.Fades := Map()
    UI.PagesReady := false            ; controls are rebuilt, so sweep once again
    if !UI.Pages.Has(UI.Page)         ; e.g. a page name from an older build
        UI.Page := "antidote"

    ; NOTE: do not add WS_EX_COMPOSITED (+E0x02000000) or WS_CLIPCHILDREN here. It
    ; leaves the hand-painted background bands unrendered. The bands and group
    ; panels get WS_CLIPSIBLINGS instead (on the controls, not the window).
    g := Gui("-Caption +ToolWindow +AlwaysOnTop", "ark antidote")
    g.BackColor := Theme.Panel
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s9", Theme.FontName)
    UI.Menu := g

    ; ---- frame: sidebar, content top bar, footer (step 12: tabs on the left) ------
    ; Sidebar band on the left (logo, page list, profile box); the content area has a
    ; slim top bar (page title, search, window buttons) and a footer (status, buttons).
    bands := []
    bands.Push(Paint(g.Add("Text", "x0 y0 w" . Layout.SIDE . " h" . Layout.HGT . " +0x04000000"),
                     Theme.Header))
    Paint(g.Add("Text", "x" . Layout.SIDE . " y0 w1 h" . Layout.HGT), Theme.Line)          ; sidebar edge
    Paint(g.Add("Text", "x" . (Layout.SIDE + 1) . " y" . Layout.HDR . " w" . (Layout.W - Layout.SIDE - 1)
              . " h1"), Theme.Line)                                                         ; under the top bar
    Paint(g.Add("Text", "x" . (Layout.SIDE + 1) . " y" . (Layout.HGT - Layout.FOOT) . " w"
              . (Layout.W - Layout.SIDE - 1) . " h1"), Theme.Line)                          ; over the footer
    ; accent line along the very top edge, in segments so an effect can flow along it.
    ; Resting look: primary -> second colour over the first 55%, then fading out; a
    ; dimmer row under it reads as a glow.
    segs := 24
    Loop segs {
        x1 := (A_Index - 1) * Layout.W // segs, x2 := A_Index * Layout.W // segs
        col := HeaderLineColour(A_Index - 1, segs)
        UI.AccentSegs.Push(Paint(g.Add("Text", "x" . x1 . " y0 w" . (x2 - x1) . " h2"), col))
        UI.GlowSegs.Push(Paint(g.Add("Text", "x" . x1 . " y2 w" . (x2 - x1) . " h2"),
                               MixHex(col, (x1 < Layout.SIDE) ? Theme.Header : Theme.Panel, 0.72)))
    }

    ; ---- sidebar: logo + wordmark ----------------------------------------------
    ; custom path if set, else logo.png beside the script; missing file shows an "A" badge
    logoY  := 16
    logoX  := Min(Audio.LogoX, 40)
    logoPath := (Trim(Audio.LogoPath) != "") ? Audio.LogoPath : A_ScriptDir . "\logo.png"
    lw := Min(Audio.LogoW, 40), lh := Min(Audio.LogoH, 40)
    shown := false
    if FileExist(logoPath) {
        try {
            g.Add("Picture", "x" . logoX . " y" . logoY . " w" . lw . " h" . lh, logoPath)
            shown := true
        }
    }
    if !shown {
        g.SetFont("s" . Max(8, Round(lh * 0.55)) . " Bold", Theme.FontName)
        Paint(g.Add("Text", "x" . logoX . " y" . logoY . " w" . lw . " h" . lh
                  . " Center +0x200", "A"), Theme.Header, Theme.Accent)
        g.SetFont("s9 Norm", Theme.FontName)
    }
    logoRight := logoX + lw + 9
    ; wordmark: "ARK" plain, "SENSE" one letter at a time from the primary to the
    ; second colour (GetPos measures every piece, no guessing)
    g.SetFont("s14 Bold")
    ac := g.Add("Text", "x" . logoRight . " y" . (logoY - 2) . " h24", "ARK")
    Paint(ac, Theme.Header, Theme.Text)
    UI.Ctrl["logoArk"] := ac               ; follows the effect when that is on
    ac.GetPos(&ax, &ay, &aw, &ah)
    cx := ax + aw
    for i, ch in StrSplit("SENSE") {
        lc := g.Add("Text", "x" . cx . " y" . (logoY - 2) . " h24", ch)
        Paint(lc, Theme.Header, MixHex(Theme.Accent, Theme.Accent2, (i - 1) / 4))
        lc.GetPos(&lx, , &lw2)
        cx := lx + lw2
    }
    ; credit line - plain text, only the handle itself is italic ("&&" = a plain "&").
    ; Beside the logo when it fits, else on its own line under it.
    g.SetFont("s7 Norm", Theme.FontName)
    vc := g.Add("Text", "x" . (logoRight + 1) . " y" . (logoY + 22), "Slopcoded && tested by ")
    Paint(vc, Theme.Header, Theme.Dim)
    vc.GetPos(&vx, &vy, &vw, &vh)
    g.SetFont("s7 Italic", Theme.FontName)
    pc := g.Add("Text", "x" . (vx + vw) . " y" . (logoY + 22), "pseidonx")
    Paint(pc, Theme.Header, Theme.Text)
    pc.GetPos(, , &pw)
    navY := 74
    if (vx + vw + pw > Layout.SIDE - 6) {
        navY := 80
        cy := logoY + lh + 4
        vc.Move(logoX + 2, cy)
        pc.Move(logoX + 2 + vw, cy)
    }
    g.SetFont("s9 Norm", Theme.FontName)

    ; ---- optional wallpaper behind the content area (pushed to the very bottom) ----
    wall := ""
    if (Theme.WallOn && FileExist(Theme.WallPath)) {
        try {
            wall := g.Add("Picture", "x" . (Layout.SIDE + 1) . " y" . (Layout.HDR + 1) . " +0x04000000", Theme.WallPath)
            wall.GetPos(, , &iw, &ih)
            bw := Layout.W - Layout.SIDE - 1, bh := Layout.HGT - Layout.HDR - Layout.FOOT - 1
            sc := Max(bw / Max(1, iw), bh / Max(1, ih))     ; cover: fill, crop the rest
            nw := Ceil(iw * sc), nh := Ceil(ih * sc)
            wall.Value := "*w" . nw . " *h" . nh . " " . Theme.WallPath
            wall.Move(Layout.SIDE + 1 + (bw - nw) // 2, Layout.HDR + 1 + (bh - nh) // 2, nw, nh)
        } catch {
            wall := ""
        }
    }

    ; ---- the page list down the sidebar, in sections ------------------------------
    y := navY
    ; 11 pages since step 23: rows a little closer so the list ends above the profile box
    count := 0
    for sec in NavList()
        count += sec[2].Length
    pitch := (count > 10) ? 34 : 36
    for sec in NavList() {
        g.SetFont("s8 Bold", Theme.FontName)
        Paint(g.Add("Text", "x22 y" . y . " w150 h16 +0x200", sec[1]), Theme.Header, MixHex(Theme.Dim, Theme.Header, 0.25))
        g.SetFont("s9 Norm", Theme.FontName)
        y += 20
        for it in sec[2] {
            MkNav(g, it[1], Chr(it[2]), it[3], y)
            y += pitch
        }
        y += 10
    }

    ; ---- profile box at the bottom of the sidebar: who, ARK state, session time ----
    by := Layout.HGT - 64
    box := Paint(g.Add("Text", "x12 y" . by . " w" . (Layout.SIDE - 24) . " h50 +0x04000000"),
                 MixHex(Theme.Header, Theme.Panel, 0.55))
    UI.Strips.Push(box)
    UI.Round.Push([box, 10, "LR"])
    av := Paint(g.Add("Text", "x22 y" . (by + 9) . " w32 h32"), Theme.Accent)
    UI.Round.Push([av, 32, "LR"])
    g.SetFont("s11 Bold", Theme.FontName)
    avl := Paint(g.Add("Text", "x22 y" . (by + 9) . " w32 h32 Center +0x200", StrUpper(SubStr(Theme.UserName, 1, 1))),
                 Theme.Accent, "FFFFFF")
    UI.Round.Push([avl, 32, "LR"])
    UI.Ctrl["userAvatar"] := avl
    g.SetFont("s9 Bold", Theme.FontName)
    bc := MixHex(Theme.Header, Theme.Panel, 0.55)
    un := Paint(g.Add("Text", "x62 y" . (by + 7) . " w70 h18 +0x200 +0x100", Theme.UserName), bc, Theme.Text)
    un.OnEvent("Click", (*) => SetTimer(AskUserName, -10))
    UI.Ctrl["userLabel"] := un
    UI.Tips[un.Hwnd] := "Click to change the name"
    g.SetFont("s8 Norm", Theme.FontName)
    UI.Ctrl["sessionTimer"] := Paint(g.Add("Text", "x" . (Layout.SIDE - 72) . " y" . (by + 7)
                                     . " w54 h18 Right +0x200"), bc, Theme.Dim)
    g.SetFont("s8 Bold", Theme.FontName)
    UI.Ctrl["arkStatus"] := Paint(g.Add("Text", "x62 y" . (by + 25) . " w110 h18 +0x200"), bc, Theme.Ok)
    g.SetFont("s9 Norm", Theme.FontName)

    ; ---- content top bar: where you are, search, window buttons ----------------------
    g.SetFont("s9 w600", Theme.FontName)
    UI.Ctrl["pageCrumb"] := Paint(g.Add("Text", "x" . Layout.LEFT . " y15 w74 h24 +0x200", ""),
                                  Theme.Panel, Theme.Dim)
    g.SetFont("s13 Bold", Theme.FontName)
    UI.Ctrl["pageTitle"] := Paint(g.Add("Text", "x" . (Layout.LEFT + 74) . " y12 w260 h28 +0x200", ""),
                                  Theme.Panel, Theme.Text)
    g.SetFont("s9 Norm", Theme.FontName)
    ; settings search box (results open under it)
    se := g.Add("Edit", "x" . (Layout.W - 86 - 230) . " y15 w230 h24 -E0x200", "")
    Paint(se, Theme.Panel2, Theme.Text)
    UI.Round.Push([se, 6, "LR"])
    DllCall("user32\SendMessageW", "Ptr", se.Hwnd, "UInt", 0x1501, "Ptr", 1,
            "Str", "Search settings  (Ctrl+F)")          ; EM_SETCUEBANNER placeholder
    se.OnEvent("Change", SearchChanged)
    UI.Ctrl["search"] := se
    g.SetFont("s9 Norm", Theme.FontName)
    MkBtn(g, "x" . (Layout.W - 70) . " y15 w26 h24 Center +0x200", "_", (*) => HideMenu(),
          Theme.Panel, Theme.Dim)
    MkBtn(g, "x" . (Layout.W - 40) . " y15 w26 h24 Center +0x200", Chr(0x00D7), (*) => ExitApp(),
          Theme.Panel, Theme.Dim)

    ; ---- live status line, footer left -----------------------------------------------
    g.SetFont("s8", "Consolas")
    UI.Ctrl["railStatus"] := Paint(g.Add("Text", "x" . Layout.LEFT . " y" . (Layout.BTNY + 5)
                                       . " w380 h18 +0x200"), Theme.Panel, Theme.Dim)
    g.SetFont("s9", Theme.FontName)

    BuildAntidote(g)
    BuildMacros(g)
    BuildOc(g)
    BuildFps(g)
    BuildOverlay(g)
    BuildMusic(g)
    BuildClantag(g)
    BuildLook(g)
    BuildSettings(g)
    BuildTune(g)
    BuildLogs(g)

    UI.Hwnd := g.Hwnd
    g.Show("w" . Layout.W . " h" . Layout.HGT . " Hide")
    ; Stacking: the group panels, then the two bands, go to the bottom of the
    ; z-order, so every control sits above its panel and every panel above its
    ; band (glow rings and halos go under their panels). With WS_CLIPSIBLINGS on
    ; all of these, a repaint of any of them is
    ; clipped by what sits on it. Same scheme as the overlay pills.
    ; bottom-up afterwards: wallpaper, bands, halos, borders, panels, title strips,
    ; then every other control on top
    for c in UI.Strips
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)   ; HWND_BOTTOM, NOSIZE|NOMOVE|NOACTIVATE
    for c in UI.Groups
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    for c in UI.Borders                   ; border ring under its panel, halo under the ring
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    for c in UI.Halos
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    for c in bands
        DllCall("user32\SetWindowPos", "Ptr", c.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    if (wall != "")                       ; the wallpaper sits under everything
        DllCall("user32\SetWindowPos", "Ptr", wall.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "UInt", 0x13)
    for r in UI.Round                     ; real sizes are known once the window exists
        RoundCtl(r[1], r[2], r[3])
    ; rounded window corners (real pixel size, so it holds at any DPI)
    WinGetPos(, , &ww, &wh, "ahk_id " . g.Hwnd)
    rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", ww + 1, "Int", wh + 1,
                   "Int", Round(14 * A_ScreenDPI / 96), "Int", Round(14 * A_ScreenDPI / 96), "Ptr")
    if (rgn && !DllCall("user32\SetWindowRgn", "Ptr", g.Hwnd, "Ptr", rgn, "Int", 1))
        DllCall("gdi32\DeleteObject", "Ptr", rgn)
    WinSetTransparent Theme.Opacity, "ahk_id " . g.Hwnd
    ApplyStreamerMode()
    ShowPage(UI.Page)
}

; ---- Page / window control -----------------------------------------------
ShowPage(page) {
    prev := UI.Page
    UI.Page := page
    g := UI.Menu
    ; WM_SETREDRAW TRUE makes a hidden window visible (that is how Windows implements
    ; it), which popped the menu up over the startup animation. Only pause redraw
    ; while the menu is actually on screen; a hidden window needs no anti-flicker.
    vis := DllCall("user32\IsWindowVisible", "Ptr", g.Hwnd)
    if vis
        DllCall("SendMessage", "Ptr", g.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)   ; WM_SETREDRAW off

    ; Touch only the outgoing and incoming pages. Re-hiding every already-hidden
    ; control (hundreds of them) is what made the switch visibly stutter. The
    ; first call still sweeps everything, since fresh controls start visible.
    if (!UI.PagesReady) {
        for name, arr in UI.Pages
            for c in arr
                c.Visible := (name = page)
        UI.PagesReady := true
    } else {
        if (prev != page && UI.Pages.Has(prev)) {
            for c in UI.Pages[prev]
                c.Visible := false
        }
        if UI.Pages.Has(page) {
            for c in UI.Pages[page]
                c.Visible := true
        }
    }

    ; sidebar: the open page's row gets a tinted background, a bright label, an
    ; accent icon and the accent bar on its left edge
    on := NavOnColour()
    for name, tab in UI.Tabs {
        active := (name = page)
        bg := active ? on : Theme.Header
        if UI.TabBgs.Has(name)
            Paint(UI.TabBgs[name], bg)
        Paint(tab, bg, active ? Theme.Text : Theme.Dim)
        if UI.TabBars.Has(name) {
            if Anim.TabOn
                FadeTo(UI.TabBars[name].Hwnd, active ? Theme.Accent : bg, Anim.TabSpeed)
            else
                Paint(UI.TabBars[name], active ? Theme.Accent : bg)
        }
        if UI.TabIcons.Has(name)
            Paint(UI.TabIcons[name], bg, active ? Theme.Accent : Theme.Dim)
    }
    meta := PageMeta(page)
    if UI.Ctrl.Has("pageTitle") {
        UI.Ctrl["pageCrumb"].Text := meta[1] . "  /"
        UI.Ctrl["pageTitle"].Text := StrReplace(meta[2], "&", "&&")   ; no mnemonic
    }
    if vis {
        DllCall("SendMessage", "Ptr", g.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)   ; WM_SETREDRAW on
        DllCall("RedrawWindow", "Ptr", g.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085)  ; one clean repaint
    }
    if (page = "antidote") {
        RefreshRegionInfo()
        RefreshGameInfo()
    }
}

ShowMenu(page := "") {
    if (page != "")
        ShowPage(page)
    if ((Web.State = "ready" || Web.State = "starting") && WebShow()) {
        UI.Visible := true                ; the web menu stands in for the native one
        return
    }
    fade := Anim.FadeIn && !UI.Visible
    if fade {
        Anim.FadeLevel := 0
        try WinSetTransparent(0, "ahk_id " . UI.Hwnd)
    }
    UI.Menu.Show()
    UI.Visible := true
    if fade
        SetTimer(MenuFadeStep, 15)
}

HideMenu() {
    WebHide()
    SetTimer(MenuFadeStep, 0)
    SearchClose()
    UI.Menu.Hide()
    UI.Visible := false
    ToolTip(, , , 2)                ; a hover tip must not outlive the menu
}

ToggleMenu() {
    if UI.Visible
        HideMenu()
    else
        ShowMenu()
}

ReadUI() {
    if UI.Ctrl.Has("gameExe") {
        Store.GameExe := Trim(UI.Ctrl["gameExe"].Value)
        RebuildGameTargets()
    }
    key := Trim(UI.Ctrl["antidoteKey"].Value)
    Cfg.AntidoteKey   := (key = "") ? "6" : key
    Cfg.IntervalSec   := Num("intervalSec", 600, 1, 86400)
    Cfg.KeyHoldMs     := Num("keyHold",      55, 10, 500)
    Cfg.AirborneMs    := Num("airborne",   1400, 0, 10000)
    Cfg.SkipIfActive  := ChkVal(UI.Ctrl["skipActive"])
    Cfg.BuffColor     := Hex("buffColor", Cfg.BuffColor)
    Cfg.Tolerance     := Num("tolerance",    30, 0, 255)
    Cfg.VerifyDelayMs := Num("verifyDelay", 450, 50, 5000)
    Cfg.RetryDelayMs  := Num("retryDelay",  300, 50, 5000)
    Cfg.MaxRetries    := Num("maxRetries",   15, 1, 200)
    Cfg.Relentless    := ChkVal(UI.Ctrl["relentless"])
    Cfg.RecheckMs     := Num("recheckMs",   500, 100, 10000)

    Theme.Accent  := Hex("cAccent",  Theme.Accent)
    Theme.Accent2 := Hex("cAccent2", Theme.Accent2)
    Theme.Panel   := Hex("cPanel",   Theme.Panel)
    Theme.Panel2  := Hex("cPanel2", Theme.Panel2)
    Theme.Text    := Hex("cText",   Theme.Text)
    Theme.Dim     := Hex("cDim",    Theme.Dim)
    Theme.Opacity := Num("opacity", 245, 120, 255)
    Theme.HudOn   := ChkVal(UI.Ctrl["hudOn"])
    Theme.HudX    := Num("hudX", 24, 0, 20000)
    Theme.HudY    := Num("hudY", 24, 0, 20000)
    Theme.PillH   := Num("hudPillH", 24, 16, 60)
    Theme.PillGap := Num("hudPillGap", 4, 0, 30)
    Theme.HudFontSize   := Num("hudFontSize", 9, 6, 24)
    Theme.HudShowState  := ChkVal(UI.Ctrl["hudShowState"])
    Theme.HudShowMsg    := ChkVal(UI.Ctrl["hudShowMsg"])
    Theme.HudShowCounts := ChkVal(UI.Ctrl["hudShowCounts"])
    Theme.HudShowDesmo  := ChkVal(UI.Ctrl["hudShowDesmo"])

    if UI.Ctrl.Has("bagToggle") {
        Bag.Toggle     := UI.Ctrl["bagToggle"].Value
        Bag.TriggerKey := UI.Ctrl["bagTrigger"].Value
        Bag.UseCurrent := ChkVal(UI.Ctrl["bagCurrent"])
        Bag.GameOnly   := ChkVal(UI.Ctrl["bagGameOnly"])
    }

    if UI.Ctrl.Has("hudBorderOn") {
        Theme.HudBorderOn  := ChkVal(UI.Ctrl["hudBorderOn"])
        Theme.HudBgOn      := ChkVal(UI.Ctrl["hudBgOn"])
        Theme.HudBgOpacity := Num("hudBgOpacity", 205, 0, 255)
        Theme.HudTextColor := Hex("hudTextColor", Theme.HudTextColor)
        Theme.HudBorderColor := Hex("hudBorderColor", Theme.HudBorderColor)
        Theme.HudShowBag      := ChkVal(UI.Ctrl["hudShowBag"])
        Theme.HudShowStreamer := ChkVal(UI.Ctrl["hudShowStreamer"])
        Theme.OverlayGameOnly := ChkVal(UI.Ctrl["hudGameOnly"])
        Theme.HudShowMammoth  := ChkVal(UI.Ctrl["hudShowMammoth"])
        if UI.Ctrl.Has("hudShowOcPill")
            Theme.HudShowOc   := ChkVal(UI.Ctrl["hudShowOcPill"])
        Theme.PillVertical    := ChkVal(UI.Ctrl["hudVertical"])
    }

    if UI.Ctrl.Has("statCpu") {
        Stats.ShowClock   := ChkVal(UI.Ctrl["statClock"])
        Stats.ShowCpu     := ChkVal(UI.Ctrl["statCpu"])
        Stats.ShowRam     := ChkVal(UI.Ctrl["statRam"])
        Stats.ShowGpu     := ChkVal(UI.Ctrl["statGpu"])
        Stats.CardOn      := ChkVal(UI.Ctrl["statCardOn"])
        Stats.ShowPing    := ChkVal(UI.Ctrl["statPing"])
        if UI.Ctrl.Has("statFps")
            Stats.ShowFps := ChkVal(UI.Ctrl["statFps"])
        if UI.Ctrl.Has("statPlayers")
            Stats.ShowPlayers := ChkVal(UI.Ctrl["statPlayers"])
        Stats.PingAuto    := ChkVal(UI.Ctrl["statPingAuto"])
        Stats.QueryPort   := Num("statQueryPort", 0, 0, 65535)
        h := Trim(UI.Ctrl["statPingHost"].Value)
        Stats.PingHost    := (h = "") ? "1.1.1.1" : h
        Stats.IntervalSec := Num("statInterval", 2, 1, 60)
    }

    if UI.Ctrl.Has("musicPath") {
        Audio.MusicOn   := ChkVal(UI.Ctrl["musicOn"])
        Audio.MusicPath := Trim(UI.Ctrl["musicPath"].Value)
        Audio.ClickOn   := ChkVal(UI.Ctrl["clickOn"])
        Audio.ClickPath := Trim(UI.Ctrl["clickPath"].Value)
        Audio.LogoPath  := Trim(UI.Ctrl["logoPath"].Value)
        Audio.LogoW     := Num("logoW", 34, 8, 200)
        Audio.LogoH     := Num("logoH", 34, 8, 200)
        Audio.LogoX     := Num("logoX", 14, 0, 560)
        Theme.WallOn    := ChkVal(UI.Ctrl["wallOn"])
        Theme.WallPath  := Trim(UI.Ctrl["wallPath"].Value)
        Theme.Splash    := ChkVal(UI.Ctrl["splashOn"])
        if UI.Ctrl.Has("menuEngine")
            Theme.MenuEngine := DropValue("menuEngine", Theme.MenuEngine)
        if UI.Ctrl.Has("userName") {
            n := UserNameClean(UI.Ctrl["userName"].Value)
            if (n != "")
                Theme.UserName := n
        }
    }
    if UI.Ctrl.Has("scOn")
        Theme.SelfCheck := ChkVal(UI.Ctrl["scOn"])
    if UI.Ctrl.Has("uiFont") {
        f := Trim(DropValue("uiFont", "Segoe UI"))
        Theme.FontName := (f != "") ? f : "Segoe UI"     ; blank falls back to default
    }

    m := UI.Ctrl["hkMenu"].Value
    t := UI.Ctrl["hkToggle"].Value
    f := UI.Ctrl["hkFire"].Value
    Keys.Menu   := (m = "") ? "Insert" : m
    Keys.Shot   := Trim(UI.Ctrl["hkShot"].Value)
    Theme.ShotStamp := ChkVal(UI.Ctrl["shotStamp"])
    Keys.Toggle := (t = "") ? "F8"     : t
    Keys.Fire   := (f = "") ? "F9"     : f
}

ApplyAll() {
    ReadUI()
    Paint(UI.Ctrl["buffSwatch"], Cfg.BuffColor)
    ApplyHotkeys()
    SaveIni()
    if S.enabled
        Schedule(A_TickCount)
    Flash("settings applied")
}

Rebuild(page) {
    Anim.Busy := true            ; block timers during the destroy/build window
    try {
        UI.Menu.Destroy()
        if UI.HudDragging              ; commit an open overlay layout edit first
            HudLockPosition()
        PillDestroyAll()
        CardDestroy()
        S.lastHud := ""
        UI.Page := page
        BuildMenu()
        BuildHud()
        BuildStatHud()
        ShowMenu(page)
    } finally {
        Anim.Busy := false
    }
}

ApplyTheme() {
    ReadUI()
    ApplyHotkeys()
    SyncMusic()
    SaveIni()
    WebEngineSync()                       ; Web <-> Native picked in Settings > Window
    Rebuild(UI.Page)
}

ResetTheme() {
    c := ThemePreset("Crimson")
    Theme.Panel   := c[1]
    Theme.Header  := c[2]
    Theme.Panel2  := c[3]
    Theme.Accent  := c[4]
    Theme.Accent2 := c[5]
    Theme.Text    := c[6]
    Theme.Dim     := c[7]
    Theme.Line    := c[8]
    Theme.Opacity := 248
    Theme.Preset  := "Crimson"
    SaveIni()
    Rebuild(UI.Page)
}

StatusTick() {
    static last := ""
    if (!UI.Visible || Anim.Busy || !UI.Ctrl.Has("railStatus"))
        return

    ; header: ARK running state + session timer text
    ; only touched when the text changes (each change repaints the control)
    if UI.Ctrl.Has("arkStatus") {
        running := GameActive() || WinExist("ahk_exe ShooterGame.exe") || WinExist("ahk_exe ArkAscended.exe")
        ac := UI.Ctrl["arkStatus"]
        t := Chr(0x25CF) . "  " . (running ? "ARK running" : "ARK closed")
        if (ac.Text != t) {
            ac.Text := t
            Paint(ac, "", running ? Theme.Ok : Theme.Bad)
        }
    }
    if UI.Ctrl.Has("sessionTimer") {
        secs := (A_TickCount - S.sessionStart) // 1000
        t := Format("{:02}:{:02}:{:02}", secs // 3600, Mod(secs // 60, 60), Mod(secs, 60))
        if (UI.Ctrl["sessionTimer"].Text != t)
            UI.Ctrl["sessionTimer"].Text := t
    }

    left := Max(0, S.nextFireAt - A_TickCount)
    txt := (S.enabled ? "RUNNING" : "stopped") . "  " . S.phase
         . "  next " . Round(left / 1000) . "s"
         . "  ok " . S.applied . " fail " . S.failed
         . "  " . (GameActive() ? "in ARK" : "ARK not focused")
    if (txt = last)
        return
    last := txt
    UI.Ctrl["railStatus"].Text := txt
    Paint(UI.Ctrl["railStatus"], "", S.enabled ? Theme.Ok : Theme.Dim)
    if UI.Ctrl.Has("antState") {
        c := UI.Ctrl["antState"]
        c.Text := "status   " . (S.enabled ? "RUNNING - phase " . S.phase : "stopped")
        Paint(c, "", S.enabled ? Theme.Ok : Theme.Dim)
    }
}

; ---- the sidebar's page list (the native and the web menu both use it) ------------------
NavList() => [["Main",     [["antidote", 0x2697, "Antidote"], ["macros", 0x21BB, "Macros"],
                            ["oc", 0x25C8, "OC macro"], ["fps", 0x26A1, "Game"]]],
              ["Visuals",  [["overlay", 0x25A3, "Overlay"], ["music", 0x266B, "Now playing"],
                            ["clantag", 0x2691, "Clantag & bar"], ["look", 0x2726, "Look"]]],
              ["System",   [["settings", 0x2699, "Settings"], ["tune", 0x2692, "Tune-up"],
                            ["logs", 0x2261, "Logs"]]]]

; ---- the name in the sidebar's profile box ------------------------------------------------
UserNameClean(s) => SubStr(Trim(RegExReplace(s, "[\r\n\t]", " ")), 1, 20)

SetUserName(name) {
    name := UserNameClean(name)
    if (name = "" || name = Theme.UserName)
        return
    Theme.UserName := name
    SaveIni()
    if UI.Ctrl.Has("userLabel")
        UI.Ctrl["userLabel"].Text := name
    if UI.Ctrl.Has("userAvatar")
        UI.Ctrl["userAvatar"].Text := StrUpper(SubStr(name, 1, 1))
    if UI.Ctrl.Has("userName")
        UI.Ctrl["userName"].Value := name
    WebUserName()
    Flash("name changed to " . name)
}

AskUserName() {
    r := InputBox("Name shown at the bottom left of the menu (up to 20 characters):",
                  "ArkSense - your name", "w340 h130", Theme.UserName)
    if (r.Result = "OK")
        SetUserName(r.Value)
}
