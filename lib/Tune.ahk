; ArkSense - lib\Tune.ahk
; PC tune-up: Windows Game Mode, Game Bar background recording, hardware GPU
; scheduling, the power plan (now, or only while ARK runs) and ARK's process
; priority. Everything here is a normal Windows setting - the same switches as in
; Settings / Control Panel - and every change can be put back with UNDO.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Windows settings (registry) ------------------------------------------------
; Game Mode is per user; GPU scheduling is machine-wide and needs a restart.
TuneKeyGameMode() => "HKCU\Software\Microsoft\GameBar"
TuneKeyDvr1()     => "HKCU\System\GameConfigStore"
TuneKeyDvr2()     => "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR"
TuneKeyHags()     => "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

TuneRead(key, name, def) {
    try return RegRead(key, name)
    return def
}

TuneGameMode() => TuneRead(TuneKeyGameMode(), "AutoGameModeEnabled", 1) ? 1 : 0     ; missing = on
TuneDvr()      => (TuneRead(TuneKeyDvr1(), "GameDVR_Enabled", 1) || TuneRead(TuneKeyDvr2(), "AppCaptureEnabled", 0)) ? 1 : 0
TuneHags()     => (TuneRead(TuneKeyHags(), "HwSchMode", 1) = 2) ? 1 : 0
TuneHagsOk()   => (StrSplit(A_OSVersion, ".").Length >= 3 && Integer(StrSplit(A_OSVersion, ".")[3]) >= 19041)

; remember the value before the first change (UNDO puts it back); "-" = it wasn't set
TuneRemember(id, key, name) {
    if Tune.Undo.Has(id)
        return
    v := "-"
    try v := RegRead(key, name)
    Tune.Undo[id] := v
}

TuneWrite(id, key, name, val) {
    TuneRemember(id, key, name)
    RegWrite(val, "REG_DWORD", key, name)
}

TuneApplyWindows() {
    msgs := []
    gm := ChkVal(UI.Ctrl["tuneGameMode"])
    if (gm != TuneGameMode()) {
        TuneWrite("GameMode", TuneKeyGameMode(), "AutoGameModeEnabled", gm)
        msgs.Push("Game Mode " . (gm ? "on" : "off"))
    }
    dv := ChkVal(UI.Ctrl["tuneDvr"])
    if (dv != TuneDvr()) {
        TuneWrite("Dvr1", TuneKeyDvr1(), "GameDVR_Enabled", dv)
        TuneWrite("Dvr2", TuneKeyDvr2(), "AppCaptureEnabled", dv)
        msgs.Push("background recording " . (dv ? "on" : "off"))
    }
    hg := ChkVal(UI.Ctrl["tuneHags"])
    if (hg != TuneHags()) {
        if !TuneHagsOk()
            throw Error("GPU scheduling needs Windows 10 version 2004 or newer")
        TuneWrite("Hags", TuneKeyHags(), "HwSchMode", hg ? 2 : 1)
        msgs.Push("GPU scheduling " . (hg ? "on" : "off") . " (after a restart)")
    }
    return msgs
}

TuneUndo(*) {
    if (Tune.Undo.Count = 0) {
        Flash("nothing to undo - ArkSense hasn't changed any Windows setting")
        return
    }
    regs := Map("GameMode", [TuneKeyGameMode(), "AutoGameModeEnabled"], "Dvr1", [TuneKeyDvr1(), "GameDVR_Enabled"],
               "Dvr2", [TuneKeyDvr2(), "AppCaptureEnabled"], "Hags", [TuneKeyHags(), "HwSchMode"])
    bad := 0
    for id, v in Tune.Undo {
        if (id = "Plan") {
            if (v != "" && !TuneSetPlan(v))
                bad += 1
            continue
        }
        if !regs.Has(id)
            continue
        try {
            if (v = "-")
                RegDelete(regs[id][1], regs[id][2])
            else
                RegWrite(v, "REG_DWORD", regs[id][1], regs[id][2])
        } catch {
            bad += 1
        }
    }
    Tune.Undo := Map()
    SaveIni()
    Logg("tune", "undo: Windows settings put back" . (bad ? " (" . bad . " failed)" : ""))
    Flash("put back what you had" . (bad ? " - " . bad . " item(s) failed, see Logs" : ""))
    TuneRefresh()
}

; ---- power plans ------------------------------------------------------------------
TuneGuidStr(ptr) {
    s := Buffer(80, 0)
    DllCall("ole32\StringFromGUID2", "Ptr", ptr, "Ptr", s, "Int", 40)
    return StrGet(s, "UTF-16")
}

; every plan on this PC with its real name
TunePlans() {
    out := []
    g := Buffer(16, 0)
    Loop 32 {
        size := 16
        if (DllCall("powrprof\PowerEnumerate", "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 16,   ; ACCESS_SCHEME
                    "UInt", A_Index - 1, "Ptr", g, "UInt*", &size, "UInt") != 0)
            break
        name := "plan " . A_Index
        need := 0
        DllCall("powrprof\PowerReadFriendlyName", "Ptr", 0, "Ptr", g, "Ptr", 0, "Ptr", 0, "Ptr", 0,
                "UInt*", &need, "UInt")
        if (need > 0 && need < 4096) {
            nb := Buffer(need, 0)
            if (DllCall("powrprof\PowerReadFriendlyName", "Ptr", 0, "Ptr", g, "Ptr", 0, "Ptr", 0,
                        "Ptr", nb, "UInt*", &need, "UInt") = 0)
                name := StrGet(nb, "UTF-16")
        }
        out.Push({guid: TuneGuidStr(g), name: name})
    }
    return out
}

TuneActivePlan() {
    p := 0
    if (DllCall("powrprof\PowerGetActiveScheme", "Ptr", 0, "Ptr*", &p, "UInt") != 0 || !p)
        return ""
    s := TuneGuidStr(p)
    DllCall("kernel32\LocalFree", "Ptr", p)
    return s
}

TuneSetPlan(guid) {
    g := Buffer(16, 0)
    if (DllCall("ole32\CLSIDFromString", "Str", guid, "Ptr", g, "Int") != 0)
        return false
    return DllCall("powrprof\PowerSetActiveScheme", "Ptr", 0, "Ptr", g, "UInt") = 0
}

TunePlanName(guid) {
    for p in Tune.Plans {
        if (p.guid = guid)
            return p.name
    }
    return (guid = "") ? "unknown" : "other plan"
}

TunePlanGuid(name) {
    for p in Tune.Plans {
        if (p.name = name)
            return p.guid
    }
    return ""
}

TunePlanNames() {
    if (Tune.Plans.Length = 0)
        try Tune.Plans := TunePlans()
    out := []
    for p in Tune.Plans
        out.Push(p.name)
    if (out.Length = 0)
        out.Push("(no plans found)")
    return out
}

; USE THIS PLAN NOW
TunePlanNow(*) {
    guid := TunePlanGuid(DropValue("tunePlan", ""))
    if (guid = "") {
        Flash("pick a plan first")
        return
    }
    cur := TuneActivePlan()
    if !Tune.Undo.Has("Plan")
        Tune.Undo["Plan"] := cur
    if TuneSetPlan(guid) {
        Logg("tune", "power plan: " . TunePlanName(guid))
        Flash("power plan: " . TunePlanName(guid))
    } else {
        Flash("Windows refused that power plan")
    }
    SaveIni()
    TuneRefresh()
}

; ---- ARK's priority -----------------------------------------------------------------
TunePrioNames() => ["Normal", "Above normal", "High"]
TunePrioWord(name) => (name = "High") ? "High" : (name = "Normal") ? "Normal" : "AboveNormal"
TunePrioName(word) => (word = "High") ? "High" : (word = "Normal") ? "Normal" : "Above normal"

TunePrioNow(pid) {
    h := DllCall("kernel32\OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")   ; QUERY_LIMITED_INFORMATION
    if !h
        return "?"
    c := DllCall("kernel32\GetPriorityClass", "Ptr", h, "UInt")
    DllCall("kernel32\CloseHandle", "Ptr", h)
    return (c = 0x80) ? "High" : (c = 0x8000) ? "Above normal" : (c = 0x20) ? "Normal"
         : (c = 0x4000) ? "Below normal" : (c = 0x40) ? "Low" : (c = 0x100) ? "Realtime" : "?"
}

TuneApplyPrio(*) {
    TuneReadUI()
    pid := GamePid()
    if !pid {
        Flash("ARK isn't running")
        return
    }
    try {
        ProcessSetPriority(Tune.Prio, pid)
        Logg("tune", "ARK priority: " . TunePrioName(Tune.Prio))
        Flash("ARK priority: " . TunePrioName(Tune.Prio))
    } catch as e {
        Flash("couldn't set ARK's priority: " . e.Message)
    }
    TuneRefresh()
}

; ---- while ARK runs (from HudTick; does work only every 2 s) -------------------------
TuneTick() {
    static nextAt := 0
    if (A_TickCount < nextAt)
        return
    nextAt := A_TickCount + 2000
    pid := GamePid()
    if (pid = Tune.LastPid)
        return
    Tune.LastPid := pid
    if !pid {                                           ; ARK closed: back to the usual plan
        TunePlanRestore()
        return
    }
    if Tune.AutoPrio {
        try {
            ProcessSetPriority(Tune.Prio, pid)
            Logg("tune", "ARK started: priority " . TunePrioName(Tune.Prio))
        }
    }
    if (Tune.AutoPlan && Tune.GamePlan != "") {
        cur := TuneActivePlan()
        if (cur != Tune.GamePlan && TuneSetPlan(Tune.GamePlan)) {
            if (Tune.SavedPlan = "")
                Tune.SavedPlan := cur
            SaveIni()
            Logg("tune", "ARK started: power plan " . TunePlanName(Tune.GamePlan))
        }
    }
}

; ARK closed, ArkSense closing, or found at start after a crash
TunePlanRestore() {
    if (Tune.SavedPlan = "")
        return
    if TuneSetPlan(Tune.SavedPlan)
        Logg("tune", "power plan back to " . TunePlanName(Tune.SavedPlan))
    Tune.SavedPlan := ""
    SaveIni()
}

; ---- the tab ---------------------------------------------------------------------
TuneReadUI() {
    if !UI.Ctrl.Has("tunePrio")
        return
    Tune.Prio     := TunePrioWord(DropValue("tunePrio", "Above normal"))
    Tune.AutoPrio := ChkVal(UI.Ctrl["tuneAutoPrio"])
    Tune.AutoPlan := ChkVal(UI.Ctrl["tuneAutoPlan"])
    g := TunePlanGuid(DropValue("tunePlan", ""))
    if (g != "")
        Tune.GamePlan := g
}

; APPLY (footer)
TuneApply(*) {
    TuneReadUI()
    msgs := []
    try msgs := TuneApplyWindows()
    catch as e {
        Flash(e.Message)
        Logg("tune", e.Message)
    }
    if (!Tune.AutoPlan)
        TunePlanRestore()                               ; turned off while ARK runs: undo the switch
    else
        Tune.LastPid := -1                              ; re-check ARK on the next tick
    SaveIni()
    for m in msgs
        Logg("tune", m)
    Flash((msgs.Length > 0) ? "applied: " . SelfJoin(msgs) : "tune-up settings saved")
    TuneRefresh()
}

TuneRefresh(*) {
    if !UI.Ctrl.Has("tuneGameMode")
        return
    SetToggle("tuneGameMode", TuneGameMode())
    SetToggle("tuneDvr", TuneDvr())
    SetToggle("tuneHags", TuneHags())
    c := UI.Ctrl["tuneWinStatus"]
    hs := TuneRead(TuneKeyHags(), "HwSchMode", "")
    c.Text := !TuneHagsOk() ? "GPU scheduling: needs Windows 10 2004+"
            : (hs = "") ? "GPU scheduling: driver default (off)" : "GPU scheduling takes effect after a restart"
    Paint(c, "", Theme.Dim)
    Tune.Plans := []
    try Tune.Plans := TunePlans()
    cur := TuneActivePlan()
    c := UI.Ctrl["tunePlanNow"]
    c.Text := "now   " . TunePlanName(cur) . (Tune.SavedPlan != "" ? "   (switched for ARK)" : "")
    Paint(c, "", Theme.Ok)
    pid := GamePid()
    c := UI.Ctrl["tunePrioNow"]
    c.Text := pid ? "ARK now   " . TunePrioNow(pid) : "ARK isn't running"
    Paint(c, "", pid ? Theme.Ok : Theme.Dim)
}

; at start: a plan left switched by a crash goes back if ARK isn't running
TuneBoot() {
    if (Tune.SavedPlan != "" && !GamePid())
        TunePlanRestore()
}

; INI [Tune] keeps the settings plus the undo values ([TuneUndo])
TuneLoadIni() {
    Tune.AutoPlan  := Integer(IniRead(Store.Ini, "Tune", "AutoPlan", Tune.AutoPlan)) ? 1 : 0
    Tune.GamePlan  := IniRead(Store.Ini, "Tune", "GamePlan", Tune.GamePlan)
    Tune.Prio      := TunePrioWord(TunePrioName(IniRead(Store.Ini, "Tune", "Prio", Tune.Prio)))
    Tune.AutoPrio  := Integer(IniRead(Store.Ini, "Tune", "AutoPrio", Tune.AutoPrio)) ? 1 : 0
    Tune.SavedPlan := IniRead(Store.Ini, "Tune", "SavedPlan", "")
    raw := ""
    try raw := IniRead(Store.Ini, "TuneUndo")
    for line in StrSplit(raw, "`n", "`r") {
        kv := StrSplit(line, "=", , 2)
        if (kv.Length = 2 && kv[1] != "")
            Tune.Undo[kv[1]] := RegExMatch(kv[2], "^\d+$") ? Integer(kv[2]) : kv[2]
    }
}

TuneSaveIni() {
    IniWrite(Tune.AutoPlan, Store.Ini, "Tune", "AutoPlan")
    IniWrite(Tune.GamePlan, Store.Ini, "Tune", "GamePlan")
    IniWrite(Tune.Prio, Store.Ini, "Tune", "Prio")
    IniWrite(Tune.AutoPrio, Store.Ini, "Tune", "AutoPrio")
    IniWrite(Tune.SavedPlan, Store.Ini, "Tune", "SavedPlan")
    try IniDelete(Store.Ini, "TuneUndo")
    for k, v in Tune.Undo
        IniWrite(v, Store.Ini, "TuneUndo", k)
}
