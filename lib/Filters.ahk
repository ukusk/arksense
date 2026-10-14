; ArkSense - lib\Filters.ahk
; Screen colour filters, applied only while ARK is the focused window.
; Part of ArkSense.ahk; run that file, not this one.
;
; Uses Windows' own full-screen colour transform (Magnification API,
; MagSetFullscreenColorEffect - the same mechanism as Windows' built-in colour
; filters). It recolours the finished desktop picture: nothing in ARK is read or
; changed. The colour change itself runs on the GPU inside Windows' compositor:
; a small cost, and while a filter is showing the game can't use Windows' direct
; "independent flip" path, which can add up to about one frame of display delay.
; Off (or ARK not focused) = no transform at all, no cost.
;
; Matrices are 5x5, row = input channel (R, G, B, A, 1), column = output channel;
; the last row is a constant added to every pixel (brightness lift).

FilterNames() => ["Off", "Vivid", "Cave bright", "Night", "Warm", "Cold", "Muted", "Protan aid", "Deutan aid"]

FilterIdentity() => [[1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 1, 0], [0, 0, 0, 0, 1]]

; saturation s, contrast c (around mid grey), per-channel gains g, brightness lift b
FilterBuild(s, c, g, b) {
    w := [0.2126, 0.7152, 0.0722]                         ; luminance weights
    m := FilterIdentity()
    Loop 3 {
        i := A_Index
        Loop 3 {
            j := A_Index
            m[i][j] := ((1 - s) * w[i] + ((i = j) ? s : 0)) * g[j] * c
        }
    }
    Loop 3
        m[5][A_Index] := 0.5 * (1 - c) + b
    return m
}

FilterMatrix(name) {
    switch name {
        case "Vivid":       return FilterBuild(1.35, 1.06, [1, 1, 1], 0)
        case "Cave bright": return FilterBuild(1.08, 0.92, [1.18, 1.18, 1.18], 0.06)
        case "Night":       return FilterBuild(0.90, 0.90, [1.30, 1.30, 1.30], 0.09)
        case "Warm":        return FilterBuild(1.05, 1.00, [1.06, 1.00, 0.86], 0)
        case "Cold":        return FilterBuild(1.00, 1.00, [0.88, 1.00, 1.08], 0)
        case "Muted":       return FilterBuild(0.75, 1.05, [1, 1, 1], 0)
        ; colour-vision aids (daltonize: the colours a red- / green-weak eye mixes
        ; up are pushed apart into blue-yellow differences)
        case "Protan aid":  return [[1, 0.5089, 0.6173, 0, 0], [0, 0.4911, -0.6173, 0, 0], [0, 0, 1, 0, 0],
                                    [0, 0, 0, 1, 0], [0, 0, 0, 0, 1]]
        case "Deutan aid":  return [[1, 0.2023, 0.5174, 0, 0], [0, 0.7977, -0.5174, 0, 0], [0, 0, 1, 0, 0],
                                    [0, 0, 0, 1, 0], [0, 0, 0, 0, 1]]
    }
    return FilterIdentity()
}

; strength 0..100 blends from no change to the full filter
FilterBlend(m, strength) {
    t := Max(0, Min(100, strength)) / 100
    id := FilterIdentity()
    out := FilterIdentity()
    Loop 5 {
        i := A_Index
        Loop 5
            out[i][A_Index] := id[i][A_Index] + (m[i][A_Index] - id[i][A_Index]) * t
    }
    return out
}

; start the magnifier runtime once; false (with Filter.Err) when it can't work here
FilterInit() {
    if (Filter.Ready = 1)
        return true
    if (Filter.Ready = -1)
        return false
    try {
        if (A_PtrSize != 8)
            Filter.Err := "needs 64-bit AutoHotkey (Windows' magnifier refuses 32-bit callers)"
        else if !DllCall("kernel32\LoadLibraryW", "Str", "Magnification.dll", "Ptr")
            Filter.Err := "Magnification.dll is missing"
        else if !DllCall("Magnification\MagInitialize")
            Filter.Err := "Windows refused to start the magnifier runtime"
        else {
            Filter.Ready := 1
            return true
        }
    } catch as e {
        Filter.Err := "the magnifier runtime failed (" . e.Message . ")"
    }
    Filter.Ready := -1
    Logg("filter", "screen filter unavailable: " . Filter.Err)
    return false
}

FilterSet(m) {
    buf := Buffer(100, 0)                               ; MAGCOLOREFFECT: float[5][5], row by row
    Loop 5 {
        i := A_Index
        Loop 5
            NumPut("Float", m[i][A_Index], buf, ((i - 1) * 5 + A_Index - 1) * 4)
    }
    try return DllCall("Magnification\MagSetFullscreenColorEffect", "Ptr", buf)
    return false
}

; from HudTick (200 ms): the filter shows while ARK is focused (or during a preview)
FilterTick() {
    want := ""
    if (Filter.Name != "Off" && (GameActive() || A_TickCount < Filter.PreviewTill))
        want := Filter.Name . "|" . Filter.Strength
    if (want = Filter.Applied)
        return
    if (want = "" && Filter.Ready != 1) {                ; nothing was ever applied
        Filter.Applied := ""
        return
    }
    if !FilterInit() {
        Filter.Applied := want                          ; don't retry every tick
        FilterStatus()
        return
    }
    m := (want = "") ? FilterIdentity() : FilterBlend(FilterMatrix(Filter.Name), Filter.Strength)
    if !FilterSet(m) {
        Filter.Err := "Windows refused the colour effect"
        Logg("filter", Filter.Err)
    } else {
        Filter.Err := ""
    }
    Filter.Applied := want
    FilterStatus()
}

; at exit: put the screen back and release the runtime
FilterShutdown() {
    if (Filter.Ready != 1)
        return
    try FilterSet(FilterIdentity())
    try DllCall("Magnification\MagUninitialize")
    Filter.Ready := 0
    Filter.Applied := ""
}

FilterStatus() {
    if !UI.Ctrl.Has("filterStatus")
        return
    c := UI.Ctrl["filterStatus"]
    if (Filter.Err != "")
        txt := "unavailable: " . Filter.Err, col := Theme.Bad
    else if (Filter.Name = "Off")
        txt := "off", col := Theme.Dim
    else if (Filter.Applied != "")
        txt := "showing now: " . Filter.Name, col := Theme.Ok
    else
        txt := Filter.Name . " - shows while ARK is focused", col := Theme.Dim
    c.Text := "status   " . txt
    Paint(c, "", col)
}

; PREVIEW: show the picked filter for 5 s even though the menu has focus
FilterPreview() {
    FilterReadUI()
    if (Filter.Name = "Off") {
        Flash("pick a filter first")
        return
    }
    Filter.PreviewTill := A_TickCount + 5000
    FilterTick()
    Flash("previewing " . Filter.Name . " for 5 s")
}

FilterReadUI() {
    if !UI.Ctrl.Has("filterName")
        return
    Filter.Name := DropValue("filterName", "Off")
    Filter.Strength := Num("filterStrength", 100, 0, 100)
    if (Filter.Name != "Off")
        Filter.Last := Filter.Name
    Filter.Key := Trim(UI.Ctrl["filterKey"].Value)
    Filter.NextKey := Trim(UI.Ctrl["filterNextKey"].Value)
}

; hotkey: off <-> the last filter used
FilterToggleKey(*) {
    if (Filter.Name = "Off") {
        Filter.Name := (Filter.Last != "Off") ? Filter.Last : "Vivid"
    } else {
        Filter.Last := Filter.Name
        Filter.Name := "Off"
    }
    FilterKeyDone()
}

; hotkey: the next filter in the list (skipping Off)
FilterNextKey(*) {
    names := FilterNames()
    idx := 1
    for i, n in names {
        if (n = Filter.Name)
            idx := i
    }
    idx := (idx >= names.Length) ? 2 : idx + 1
    Filter.Name := names[idx]
    Filter.Last := Filter.Name
    FilterKeyDone()
}

FilterKeyDone() {
    DropSet("filterName", Filter.Name)
    SaveIni()
    FilterTick()
    FilterStatus()
    if Alerts.Feedback
        Alert("filter", "info", "Screen filter: " . Filter.Name, "", 0)
}
