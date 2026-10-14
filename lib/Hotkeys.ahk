; ArkSense - lib\Hotkeys.ahk
; Rebindable hotkeys and the tray menu.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Hotkeys / tray ---------------------------------------------------------
ApplyHotkeys() {
    static bound := []
    for hk in bound {
        try Hotkey(hk, "Off")
    }
    bound := []
    Keys.Bad := []                        ; the self-check reports these
    pairs := [[Keys.Menu,   (*) => ToggleMenu()],
              [Keys.Toggle, (*) => ToggleMacro()],
              [Keys.Fire,   (*) => FireNow()],
              [Keys.Pick,   (*) => Eyedrop()],
              [Keys.Kill,   (*) => KillAll()],
              [Desmo.Toggle, (*) => DesmoToggle()],
              [Mammoth.Toggle, (*) => MammothToggle()],
              [Bag.Toggle,    (*) => BagToggle()],
              [Keys.Shot,     (*) => ShotTake()],
              [Lay.Keys[1],   LayKeyCb(1)],
              [Lay.Keys[2],   LayKeyCb(2)],
              [Lay.Keys[3],   LayKeyCb(3)],
              [Lay.NextKey,   LayNext],
              [Filter.Key,    FilterToggleKey],
              [Filter.NextKey, FilterNextKey],
              [Ct.Key,        CtToggleKey]]
    for pair in pairs {
        if (Trim(pair[1]) = "")
            continue
        try {
            Hotkey(pair[1], pair[2], "On")
            bound.Push(pair[1])
        } catch {
            Keys.Bad.Push(pair[1])
        }
    }

    ; OC macro: "*" so the key still works while the macro holds Shift down
    if (Trim(Oc.Toggle) != "") {
        k := "*" . Trim(Oc.Toggle)
        try {
            if (Oc.Mode = "Hold") {
                Hotkey(k, OcHoldDown, "On")
                bound.Push(k)
                Hotkey(k . " up", OcHoldUp, "On")
                bound.Push(k . " up")
            } else {
                Hotkey(k, OcToggle, "On")
                bound.Push(k)
            }
        } catch {
            Keys.Bad.Push(Oc.Toggle)
        }
    }

    ; autoclicker: same "*" binding, so it works whatever modifiers are held
    if (Trim(Ac.Toggle) != "") {
        k := "*" . Trim(Ac.Toggle)
        try {
            if (Ac.Mode = "Hold") {
                Hotkey(k, AcHoldDown, "On")
                bound.Push(k)
                Hotkey(k . " up", AcHoldUp, "On")
                bound.Push(k . " up")
            } else {
                Hotkey(k, AcToggle, "On")
                bound.Push(k)
            }
        } catch {
            Keys.Bad.Push(Ac.Toggle)
        }
    }

    ; passthrough; BagFire no-ops unless armed
    if (Trim(Bag.TriggerKey) != "") {
        try {
            Hotkey("~" . Bag.TriggerKey, BagFire, "On")
            bound.Push("~" . Bag.TriggerKey)
        } catch {
            Keys.Bad.Push(Bag.TriggerKey)
        }
    }
}

BuildTray() {
    tm := A_TrayMenu
    tm.Delete()
    tm.Add("Show menu",    (*) => ShowMenu())
    tm.Add("Toggle macro", (*) => ToggleMacro())
    tm.Add()
    tm.Add("Reload", (*) => Reload())
    tm.Add("Exit",   (*) => ExitApp())
    tm.Default := "Show menu"
    tm.ClickCount := 1
    A_IconTip := "ark antidote"
}
