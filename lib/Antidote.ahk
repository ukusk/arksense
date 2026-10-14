; ArkSense - lib\Antidote.ahk
; Antidote state machine, buff detection and the scan-area picker.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Macro state machine ------------------------------------------------
Tick() {
    if !S.enabled
        return

    if !GameActive() {
        Hud("paused - ARK not focused", Theme.Dim)
        return
    }

    now := A_TickCount

    switch S.phase {
        case "idle":
            if (now >= S.nextFireAt) {
                S.attempts := 0
                S.readyAt  := now
                S.phase    := "armed"
            } else if (Cfg.Relentless && now >= S.recheckAt && CurrentRegion()) {
                ; The interval alone cannot keep the buff up: a dose swallowed in
                ; water or mid-air is simply lost, and waiting out the interval
                ; leaves you bare. So while idle, watch the buff icon and re-arm
                ; the instant it is missing and a dose could actually land.
                S.recheckAt := now + Cfg.RecheckMs
                if (!BuffPresent() && now >= S.airborneTill && !S.menuOpen) {
                    S.attempts := 0
                    S.readyAt  := now
                    S.phase    := "armed"
                    Hud("buff gone - reapplying", Theme.Accent)
                } else {
                    Hud("next in " . Round((S.nextFireAt - now) / 1000) . "s", Theme.Dim)
                }
            } else {
                Hud("next in " . Round((S.nextFireAt - now) / 1000) . "s", Theme.Dim)
            }
        case "armed":
            if (now >= S.readyAt)
                TryFire(now)
        case "verify":
            if (now >= S.verifyAt)
                Verify(now)
    }
}

TryFire(now) {
    ; airborne/menu checks are optimisations - the retry loop is the real safety net
    if (now < S.airborneTill) {
        Hud("airborne - holding", Theme.Dim)
        return
    }
    if (S.menuOpen) {
        Hud("inventory open - holding", Theme.Dim)
        return
    }

    ; only fire while the buff is down, so verification is unambiguous
    if (Cfg.SkipIfActive && BuffPresent()) {
        Schedule(now)
        Hud("buff already up - skipped", Theme.Dim)
        return
    }

    if (S.attempts >= Cfg.MaxRetries) {
        S.gaveUp += 1
        Schedule(now)
        ; back off briefly rather than for the whole interval - the idle re-check
        ; then keeps watching, so a long swim costs seconds, not the full cycle
        if Cfg.Relentless
            S.recheckAt := now + (Cfg.RetryDelayMs * 4)
        Hud("gave up after " . Cfg.MaxRetries . " tries", Theme.Bad)
        AlertAntidote(true)
        return
    }

    S.attempts += 1
    TapKey(Cfg.AntidoteKey)
    S.verifyAt := A_TickCount + Cfg.VerifyDelayMs
    S.phase    := "verify"
    Hud("applying (try " . S.attempts . ")", Theme.Accent)
}

Verify(now) {
    ; re-check airborne: a lit icon after a mid-verify jump could be the OLD buff
    if (now < S.airborneTill) {
        S.readyAt := now + Cfg.RetryDelayMs
        S.phase   := "armed"
        Hud("jumped mid-verify - retrying", Theme.Bad)
        return
    }
    ; step 25: ok / fail count presses - ok = the buff showed up after this press, fail = it
    ; didn't (before, fail only went up when a whole cycle of MaxRetries presses gave up)
    if BuffPresent() {
        S.applied += 1
        AlertAntidote(false)
        Schedule(now)
        Hud("applied ok (try " . S.attempts . ")", Theme.Ok)
    } else {
        S.failed += 1
        S.readyAt := now + Cfg.RetryDelayMs
        S.phase   := "armed"
        Hud("no buff - retrying", Theme.Bad)
    }
}

Schedule(now) {
    S.phase      := "idle"
    S.attempts   := 0
    S.nextFireAt := now + (Cfg.IntervalSec * 1000)
    S.recheckAt  := now + Cfg.RecheckMs
}

GameActive() {
    ; match any configured window; default list covers ARK SE + Ascended
    for target in Store.GameTargets {
        if WinActive(target)
            return true
    }
    return false
}

RebuildGameTargets() {
    Store.GameTargets := ["ahk_exe ShooterGame.exe", "ahk_exe ArkAscended.exe"]
    if (Trim(Store.GameExe) != "")
        Store.GameTargets.InsertAt(1, Trim(Store.GameExe))
}

TapKey(key) {
    ; explicit hold - UE4 can miss a zero-length synthetic tap
    SendEvent "{" . key . " down}"
    Sleep Cfg.KeyHoldMs
    SendEvent "{" . key . " up}"
    Logg("antidote", "tap '" . key . "'")
}

CurrentRegion() {
    k := A_ScreenWidth . "x" . A_ScreenHeight
    return Store.Regions.Has(k) ? Store.Regions[k] : ""
}

BuffPresent() {
    r := CurrentRegion()
    if !r
        return false
    try {
        if PixelSearch(&fx, &fy, r[1], r[2], r[3], r[4],
                       Integer("0x" . Cfg.BuffColor), Cfg.Tolerance)
            return true
    }
    return false
}

; bring the ARK window to the foreground; returns false if it isn't running
ActivateGame() {
    for target in Store.GameTargets {
        if WinExist(target) {
            if !WinActive(target) {
                WinActivate(target)
                if !WinWaitActive(target, , 1)   ; up to 1s for it to come forward
                    return false
            }
            return true
        }
    }
    return false
}

; ---- Region picker ---------------------------------------------------------
PickRegion() {
    HideMenu()
    Sleep 150

    shade := Gui("+AlwaysOnTop -Caption +ToolWindow")

    StreamHide(shade.Hwnd)
    shade.BackColor := "000000"
    shade.SetFont("s11 Bold", Theme.FontName)
    Paint(shade.Add("Text", "x24 y24 w900 h64",
        "Drag a box around the whole buff tray. Leave margin - ARK slides buff "
      . "icons sideways`nas other buffs come and go.    Esc cancels."),
        "000000", Theme.Accent)
    shade.Show(Format("x0 y0 w{} h{} NoActivate", A_ScreenWidth, A_ScreenHeight))
    WinSetTransparent 110, "ahk_id " . shade.Hwnd

    sel := Gui("+AlwaysOnTop -Caption +ToolWindow")

    StreamHide(sel.Hwnd)
    sel.BackColor := Theme.Accent

    while true {
        if GetKeyState("Escape", "P") {
            shade.Destroy()
            sel.Destroy()
            ShowMenu("antidote")
            return
        }
        if GetKeyState("LButton", "P")
            break
        Sleep 20
    }

    MouseGetPos &ax, &ay
    sel.Show("x" . ax . " y" . ay . " w1 h1 NoActivate")
    WinSetTransparent 130, "ahk_id " . sel.Hwnd

    while GetKeyState("LButton", "P") {
        MouseGetPos &cx, &cy
        sel.Move(Min(ax, cx), Min(ay, cy), Max(1, Abs(cx - ax)), Max(1, Abs(cy - ay)))
        Sleep 16
    }
    MouseGetPos &bx, &by

    shade.Destroy()
    sel.Destroy()

    x1 := Min(ax, bx), y1 := Min(ay, by)
    x2 := Max(ax, bx), y2 := Max(ay, by)

    if ((x2 - x1) < 8 || (y2 - y1) < 8) {
        ShowMenu("antidote")
        Flash("selection too small - try again")
        return
    }

    Store.Regions[A_ScreenWidth . "x" . A_ScreenHeight] := [x1, y1, x2, y2]
    SaveIni()
    ShowMenu("antidote")
}

ClearRegion() {
    k := A_ScreenWidth . "x" . A_ScreenHeight
    if Store.Regions.Has(k)
        Store.Regions.Delete(k)
    SaveIni()
    RefreshRegionInfo()
}

RefreshRegionInfo() {
    if !UI.Ctrl.Has("regionInfo")
        return
    r := CurrentRegion()
    c := UI.Ctrl["regionInfo"]
    if r {
        c.Text := Format("{},{} to {},{}   ({} x {} px)",
            r[1], r[2], r[3], r[4], r[3] - r[1], r[4] - r[2])
        Paint(c, "", Theme.Ok)
    } else {
        c.Text := "none for " . A_ScreenWidth . "x" . A_ScreenHeight . " - pick one first"
        Paint(c, "", Theme.Bad)
    }
}

TestDetect() {
    ReadUI()
    Paint(UI.Ctrl["buffSwatch"], Cfg.BuffColor)
    c := UI.Ctrl["testResult"]
    if !CurrentRegion() {
        c.Text := "no area set"
        Paint(c, "", Theme.Bad)
        return
    }
    found := BuffPresent()
    c.Text := found ? "buff FOUND" : "buff not found"
    Paint(c, "", found ? Theme.Ok : Theme.Bad)
}

EyeHint() {
    Flash("Hover the buff icon and press " . Keys.Pick)
}

ToggleMacro() {
    if (!S.enabled && !CurrentRegion()) {
        ShowMenu("antidote")
        Flash("set a scan area for this resolution first")
        return
    }
    S.enabled := !S.enabled
    if S.enabled {
        S.phase      := "idle"
        S.attempts   := 0
        S.menuOpen   := false
        S.nextFireAt := A_TickCount
    }
    S.lastHud := ""
    Hud(S.enabled ? "starting" : "stopped", Theme.Dim)
    TrayTip(S.enabled ? "Macro enabled" : "Macro disabled", "ark antidote")
}

FireNow() {
    if !CurrentRegion() {
        ShowMenu("antidote")
        return
    }
    S.enabled    := true
    S.phase      := "idle"
    S.attempts   := 0
    S.nextFireAt := A_TickCount
    S.lastHud    := ""
}

Eyedrop() {
    MouseGetPos &mx, &my
    hex := Format("{:06X}", PixelGetColor(mx, my, "RGB"))
    Cfg.BuffColor := hex
    if UI.Ctrl.Has("buffColor") {
        UI.Ctrl["buffColor"].Value := hex
        Paint(UI.Ctrl["buffSwatch"], hex)
    }
    A_Clipboard := hex
    Flash("colour " . hex . " captured at " . mx . "," . my)
}
