; ArkSense - lib\Layouts.ahk
; Overlay layouts: three named slots ("PvP minimal", "PvE full", "Clean" to start
; with), each a snapshot of which pills and card parts show and where everything
; sits. A hotkey per slot, plus one that steps to the next slot.
; Part of ArkSense.ahk; run that file, not this one.

; [class letter, setting, Overlay-tab control]
LayProps() => [["T", "HudOn", "hudOn"], ["T", "HudShowState", "hudShowState"], ["T", "HudShowMsg", "hudShowMsg"],
               ["T", "HudShowCounts", "hudShowCounts"], ["T", "HudShowDesmo", "hudShowDesmo"],
               ["T", "HudShowMammoth", "hudShowMammoth"], ["T", "HudShowBag", "hudShowBag"],
               ["T", "HudShowStreamer", "hudShowStreamer"],
               ["S", "CardOn", "statCardOn"], ["S", "ShowCpu", "statCpu"], ["S", "ShowRam", "statRam"],
               ["S", "ShowGpu", "statGpu"], ["S", "ShowClock", "statClock"], ["S", "ShowPing", "statPing"]]

LayObj(letter) => (letter = "T") ? Theme : Stats

; what a slot holds before it is first saved over
LayDefaults(slot) {
    m := Map("Pos", Map())
    for a in LayProps()
        m[a[2]] := 1
    if (slot = 1) {                         ; PvP minimal: on/off states that matter + server line
        for k in ["HudShowMsg", "HudShowCounts", "HudShowMammoth", "HudShowStreamer",
                  "ShowCpu", "ShowRam", "ShowGpu", "ShowClock"]
            m[k] := 0
    } else if (slot = 3) {                  ; Clean: nothing on screen
        m["HudOn"] := 0
        m["CardOn"] := 0
    }
    return m
}

LayGet(slot) {
    if !Lay.Data.Has(slot)
        Lay.Data[slot] := LayDefaults(slot)
    return Lay.Data[slot]
}

; SAVE n: what the Overlay tab shows now (applied first) goes into slot n
LaySave(slot) {
    if UI.Ctrl.Has("hudOn")
        ApplyOverlayTab(true)
    if UI.HudDragging
        HudLockPosition()
    m := Map()
    for a in LayProps()
        m[a[2]] := LayObj(a[1]).%a[2]%
    pos := Map()
    for k, v in Pill.Pos
        pos[k] := [v[1], v[2], v[3]]
    m["Pos"] := pos
    Lay.Data[slot] := m
    Lay.Cur := slot
    SaveIni()
    LayStatus()
    Flash("saved the overlay as '" . Lay.Names[slot] . "'")
}

; LOAD n (button or hotkey)
LayLoad(slot, byKey := false) {
    m := LayGet(slot)
    if UI.HudDragging
        HudLockPosition()
    for a in LayProps() {
        if m.Has(a[2])
            LayObj(a[1]).%a[2]% := m[a[2]] ? 1 : 0
    }
    if (m.Has("Pos") && m["Pos"].Count > 0) {           ; a slot never saved keeps the current spots
        pos := Map()
        for k, v in m["Pos"]
            pos[k] := [v[1], v[2], v[3]]
        Pill.Pos := pos
    }
    Lay.Cur := slot
    SaveIni()
    RebuildHud()
    RebuildStatHud()
    LaySyncUI()
    LayStatus()
    if (byKey && Alerts.Feedback)
        Alert("layout", "info", "Layout: " . Lay.Names[slot], "", 0)
    else
        Flash("layout: " . Lay.Names[slot])
}

LayNext(*) => LayLoad(Mod(Lay.Cur, 3) + 1, true)

LayKeyCb(slot) => (*) => LayLoad(slot, true)
LayLoadCb(slot) => (*) => LayLoad(slot)
LaySaveCb(slot) => (*) => LaySave(slot)

; the Overlay tab's toggles follow a loaded layout, so a later APPLY keeps it
LaySyncUI() {
    for a in LayProps()
        SetToggle(a[3], LayObj(a[1]).%a[2]%)
    CardPosFields()
}

LayStatus() {
    if !UI.Ctrl.Has("layStatus")
        return
    c := UI.Ctrl["layStatus"]
    c.Text := "active   " . (Lay.Cur ? Lay.Names[Lay.Cur] : "none loaded yet")
    Paint(c, "", Lay.Cur ? Theme.Ok : Theme.Dim)
}

; names and keys typed in the Overlay tab
LayReadUI() {
    if !UI.Ctrl.Has("layName1")
        return
    Loop 3 {
        n := Trim(UI.Ctrl["layName" . A_Index].Value)
        Lay.Names[A_Index] := (n != "") ? SubStr(n, 1, 24) : "Layout " . A_Index
        Lay.Keys[A_Index] := Trim(UI.Ctrl["layKey" . A_Index].Value)
    }
    Lay.NextKey := Trim(UI.Ctrl["layNext"].Value)
}

; ---- INI: [Layouts] names / keys, [Layout n] one snapshot each --------------------
LayLoadIni() {
    Loop 3 {
        i := A_Index
        Lay.Names[i] := IniRead(Store.Ini, "Layouts", "Name" . i, Lay.Names[i])
        Lay.Keys[i]  := IniRead(Store.Ini, "Layouts", "Key" . i, Lay.Keys[i])
        sec := "Layout " . i
        if (IniRead(Store.Ini, sec, "HudOn", "") = "")
            continue                                    ; never saved: defaults
        m := LayDefaults(i)
        for a in LayProps() {
            try m[a[2]] := Integer(IniRead(Store.Ini, sec, a[2], m[a[2]])) ? 1 : 0
        }
        pos := Map()
        for part in StrSplit(IniRead(Store.Ini, sec, "Pos", ""), "|") {
            kv := StrSplit(part, ":", , 2)
            if (kv.Length < 2)
                continue
            n := StrSplit(kv[2], ",")
            if (n.Length = 3)
                try pos[kv[1]] := [Integer(n[1]), Integer(n[2]), Max(6, Min(48, Integer(n[3])))]
        }
        m["Pos"] := pos
        Lay.Data[i] := m
    }
    Lay.NextKey := IniRead(Store.Ini, "Layouts", "Next", Lay.NextKey)
    try Lay.Cur := Max(0, Min(3, Integer(IniRead(Store.Ini, "Layouts", "Cur", 0))))
}

LaySaveIni() {
    Loop 3 {
        i := A_Index
        IniWrite(Lay.Names[i], Store.Ini, "Layouts", "Name" . i)
        IniWrite(Lay.Keys[i], Store.Ini, "Layouts", "Key" . i)
        if !Lay.Data.Has(i)
            continue
        m := Lay.Data[i]
        sec := "Layout " . i
        for a in LayProps()
            IniWrite(m.Has(a[2]) ? m[a[2]] : 1, Store.Ini, sec, a[2])
        s := ""
        for k, v in m["Pos"]
            s .= ((s = "") ? "" : "|") . k . ":" . v[1] . "," . v[2] . "," . v[3]
        IniWrite(s, Store.Ini, sec, "Pos")
    }
    IniWrite(Lay.NextKey, Store.Ini, "Layouts", "Next")
    IniWrite(Lay.Cur, Store.Ini, "Layouts", "Cur")
}
