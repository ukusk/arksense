; ArkSense - lib\Oc.ahk
; OC macro: holds Shift and presses the hotbar keys 1 2 3 in turn, as fast as set,
; while the cursor rests on the 4th item (see the steps on its page). Only key presses
; are sent - nothing in the game is read.
; Part of ArkSense.ahk; run that file, not this one.

OcClamp() {
    Oc.GapMs   := Max(1, Min(1000, Integer(Oc.GapMs)))
    Oc.HoldMs  := Max(1, Min(200, Integer(Oc.HoldMs)))
    Oc.StopSec := Max(0, Min(3600, Integer(Oc.StopSec)))
    if (Oc.Mode != "Hold")
        Oc.Mode := "Toggle"
    if (OcKeyList().Length = 0)
        Oc.Keys := "1 2 3"
}

; "1 2 3" -> ["1", "2", "3"]; only plain key names (letters, digits, F-keys, Numpad...)
OcKeyList() {
    out := []
    for k in StrSplit(RegExReplace(Trim(Oc.Keys), "[,;]", " "), " ") {
        k := Trim(k)
        if (k != "" && RegExMatch(k, "^[A-Za-z0-9]{1,10}$"))
            out.Push(k)
    }
    return out
}

OcToggle(*) {
    if Oc.Active
        OcStop("stopped")
    else
        OcStart()
}

; Hold mode: the hotkey's own down / up
OcHoldDown(*) {
    if !Oc.Active
        OcStart()
}

OcHoldUp(*) {
    if Oc.Active
        OcStop("key released")
}

OcStart() {
    if Oc.Active
        return
    OcClamp()
    if (Oc.GameOnly && !GameActive()) {
        Flash("OC macro: click into ARK first (or turn off 'Only while ARK is focused')")
        return
    }
    Oc.Active := true
    Oc.StartAt := A_TickCount
    Oc.Sent := 0
    Oc.Why := ""
    S.lastHud := ""
    OcRefreshStatus()
    Logg("oc", "started (" . Oc.Keys . ", every " . (Oc.GapMs + Oc.HoldMs) . " ms"
              . (Oc.Shift ? ", Shift held" : "") . ")")
    SetTimer(OcRun, -1)                    ; the loop runs on its own thread
}

OcStop(why := "stopped") {
    if !Oc.Active
        return
    Oc.Active := false                     ; the loop sees this and lets go of Shift
    Oc.Why := why
    S.lastHud := ""
    OcRefreshStatus()
    Logg("oc", why . " after " . Oc.Sent . " key presses")
}

OcRun() {
    SetKeyDelay(-1, -1)                    ; this thread only: no built-in delays
    keys := OcKeyList()
    hires := false
    if (Oc.GapMs < 16 || Oc.HoldMs < 16) {
        DllCall("winmm\timeBeginPeriod", "UInt", 1)
        hires := true
    }
    i := 0
    try {
        while Oc.Active {
            if (Oc.GameOnly && !GameActive()) {
                OcStop("ARK lost focus")
                break
            }
            if (Oc.StopSec > 0 && A_TickCount - Oc.StartAt >= Oc.StopSec * 1000) {
                OcStop("time limit reached")
                break
            }
            if (Oc.Shift && !GetKeyState("Shift")) {
                SendEvent("{Blind}{Shift down}")
                Oc.Pressed := true
            }
            k := keys[Mod(i, keys.Length) + 1]
            i += 1
            SendEvent("{Blind}{" . k . " down}")
            Sleep Oc.HoldMs
            SendEvent("{Blind}{" . k . " up}")
            Oc.Sent += 1
            Sleep Oc.GapMs
        }
    } finally {
        if Oc.Pressed {
            Oc.Pressed := false
            if !GetKeyState("Shift", "P")      ; you're holding it yourself: leave it
                SendEvent("{Blind}{Shift up}")
        }
        if hires
            DllCall("winmm\timeEndPeriod", "UInt", 1)
        Oc.Active := false
        OcRefreshStatus()
        S.lastHud := ""
    }
}

OcRefreshStatus() {
    if !UI.Ctrl.Has("ocStatus")
        return
    c := UI.Ctrl["ocStatus"]
    if Oc.Active
        c.Text := "status   RUNNING - " . Oc.Keys . (Oc.Shift ? " with Shift" : "")
    else
        c.Text := "status   off" . ((Oc.Why != "") ? "  (" . Oc.Why . ", " . Oc.Sent . " presses)" : "")
                . ((Trim(Oc.Toggle) = "") ? "   - set a hotkey below" : "")
    Paint(c, "", Oc.Active ? Theme.Ok : Theme.Dim)
}

; ---- page -----------------------------------------------------------------------------
BuildOc(g) {
    p := "oc"
    gr := GroupBegin(g, p, 0, Layout.TOP, "OC macro")
    GText(gr, GRow(gr), "ocStatus")
    y := GRow(gr)
    GLabel(gr, y, "Hotkey", "Starts / stops the macro. Pick a key you don't use in ARK.")
    GHot(gr, y, "ocToggle", Oc.Toggle)
    y := GRow(gr), GLabel(gr, y, "Mode", "Toggle: press once to start, again to stop. Hold: runs only "
          . "while you hold the hotkey down.", 100),
        GDrop(gr, y, "ocMode", ["Toggle", "Hold"], Oc.Mode, 110)
    y := GRow(gr)
    GLabel(gr, y, "Keys", "Pressed in turn, separated by spaces. Default 1 2 3 = your first three "
        . "hotbar slots.")
    GField(gr, y, "ocKeys", Oc.Keys, false, 110)
    GToggle(gr, GRow(gr), "ocShift", "Hold Shift while it runs", Oc.Shift)
    GSlider(gr, GRow(gr), "ocGap", "Gap", Oc.GapMs, 1, 300, " ms", 1,
            "Pause after each key. Windows timers bottom out around 1-2 ms here (high-resolution "
          . "timing is on while it runs).")
    GSlider(gr, GRow(gr), "ocHold", "Key hold", Oc.HoldMs, 1, 100, " ms", 1,
            "How long each key is held down. Too short and ARK may miss presses.")
    GToggle(gr, GRow(gr), "ocGameOnly", "Only while ARK is focused", Oc.GameOnly,
            "Stops by itself the moment another window comes to the front.")
    y := GRow(gr)
    GLabel(gr, y, "Stop after (s)", "Stops by itself after this many seconds. 0 = never.")
    GField(gr, y, "ocStopSec", Oc.StopSec, true, 60)
    GButtons(gr, GRow(gr), [["START / STOP", (*) => OcToggle(), "accent"]],
             ["Starts it now (click into ARK within the first moment if 'Only while ARK is "
            . "focused' is on - better: use the hotkey in game)."])
    GroupEnd(gr)

    gr := GroupBegin(g, p, 1, Layout.TOP, "How to use")
    GNote(gr, GRow(gr, 2), "1.  Put 3 random blueprints in your first 3 hotbar slots - drag them "
        . "from the crafting tab.", 2)
    GNote(gr, GRow(gr, 1), "2.  Put a random item in the 4th slot.", 1)
    GNote(gr, GRow(gr, 2), "3.  Right-click the 4th item and leave your cursor resting on it.", 2)
    GNote(gr, GRow(gr, 2), "4.  Press the hotkey: it holds Shift and spams 1 2 3 until you press it "
        . "again (or let go, in Hold mode).", 2)
    GNote(gr, GRow(gr, 2), "Don't move the mouse while it runs. The killswitch (Logs tab) stops it too.", 2)
    GroupEnd(gr)

    FootButtons(g, p, [["APPLY", (*) => ApplyOc(), "accent"]])
    OcRefreshStatus()
}

ApplyOc() {
    Oc.Toggle := Trim(UI.Ctrl["ocToggle"].Value)
    Oc.Mode := DropValue("ocMode", "Toggle")
    Oc.Keys := Trim(UI.Ctrl["ocKeys"].Value)
    Oc.Shift := ChkVal(UI.Ctrl["ocShift"])
    Oc.GapMs := SliderValue("ocGap", 20)
    Oc.HoldMs := SliderValue("ocHold", 12)
    Oc.GameOnly := ChkVal(UI.Ctrl["ocGameOnly"])
    Oc.StopSec := Num("ocStopSec", 0, 0, 3600)
    OcClamp()
    UI.Ctrl["ocKeys"].Value := Oc.Keys
    warn := ""
    for k in OcKeyList() {
        if (Oc.Toggle != "" && k = Oc.Toggle)
            warn := "the hotkey is also one of the keys it presses - pick another"
    }
    if Oc.Active
        OcStop("settings changed")
    ApplyHotkeys()
    SaveIni()
    RebuildHud()
    OcRefreshStatus()
    Flash((warn != "") ? "OC macro: " . warn : "OC macro settings applied")
}
