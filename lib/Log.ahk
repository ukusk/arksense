; ArkSense - lib\Log.ahk
; Action history, error capture and the killswitch.
; Part of ArkSense.ahk; run that file, not this one.

; record one of the script's own actions into the bounded history
GlobalError(err, mode) {
    ; A fault inside a timer or paint handler repeats on every tick. Logging each
    ; one (disk write + tooltip + log repaint, up to 30x a second) locks the app,
    ; so cap it at 20 per 5 s and never re-enter while already handling one.
    static inside := false, winStart := 0, count := 0
    if inside
        return 1
    inside := true
    try {
        if (A_TickCount - winStart > 5000) {
            winStart := A_TickCount
            count := 0
        }
        count += 1
        if (count <= 20)
            GlobalErrorReport(err)
        else if (count = 21)
            try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  (further errors suppressed for 5 s)`r`n",
                           A_ScriptDir . "\ArkSense-errors.log")
    } finally {
        inside := false
    }
    return 1                      ; handled: drop this thread, keep the script alive
}

GlobalErrorReport(err) {
    msg  := "unknown error"
    line := 0
    file := ""
    try SplitPath(err.File, &file)             ; which lib\ file the line is in
    try msg  := Type(err) . ": " . err.Message
    try line := err.Line
    try {
        if (err.HasProp("What") && err.What != "")
            msg .= "  in " . err.What
    }
    where := file . " line " . line
    try Logg("error", msg . "  (" . where . ")")
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  " . msg
                 . "  " . where . "`r`n", A_ScriptDir . "\ArkSense-errors.log")
    try Flash("error logged (" . where . "): " . SubStr(msg, 1, 60))
}

Logg(src, msg) {
    Log.Items.Push({t: FormatTime(, "HH:mm:ss"), src: src, msg: msg})
    if (Log.Items.Length > Log.Max)
        Log.Items.RemoveAt(1, Log.Items.Length - Log.Max)
    if (UI.Visible && UI.Page = "logs")
        RefreshLogView()
}

RefreshLogView() {
    if !UI.Ctrl.Has("logView")
        return
    lv := UI.Ctrl["logView"]
    lv.Opt("-Redraw")
    lv.Delete()
    for it in Log.Items
        lv.Add(, it.t, it.src, it.msg)
    lv.Opt("+Redraw")
    if (Log.Items.Length > 0)
        lv.Modify(Log.Items.Length, "Vis")   ; scroll newest into view
}

ClearLog() {
    Log.Items := []
    RefreshLogView()
}

; killswitch (step 19): stop every macro, let go of every key one may be holding, and
; close ArkSense at once. Closing the process removes every window it owns (menu,
; pills, card, Now playing) in one go; AppExit puts the screen filter and the power
; plan back and ends the helpers.
KillAll(*) {
    S.Killing := true
    S.enabled := false
    Desmo.Active := false
    Mammoth.Active := false
    Mammoth.Measuring := false
    Bag.Active := false
    Oc.Active := false
    Ac.Active := false
    SetTimer(MammothTick, 0)
    ; keys a macro may be holding down right now (the OC macro holds Shift)
    for k in ["Shift", "LButton", "RButton", "MButton", "e", "1", "2", "3"] {
        try {
            if (GetKeyState(k) && !GetKeyState(k, "P"))
                SendEvent("{Blind}{" . k . " up}")
        }
    }
    Logg("system", "KILLSWITCH - everything stopped, ArkSense closed")
    ExitApp()
}

