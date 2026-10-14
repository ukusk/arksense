; ArkSense - lib\Web.ahk
; The web menu: an Edge WebView2 window that shows lib\menu\index.html.
; Part of ArkSense.ahk; run that file, not this one.
;
; How it fits: the native menu is still built exactly as before, just never shown
; while the web menu is in use. Every widget records itself while it is built
; (WebGroupBegin / WebRec, called from lib\Widgets.ahk), so the web page gets a
; complete model of every page, group and row. A change on the page is written into
; the same native control (field text, toggle state, slider, dropdown), and a
; button press runs the same callback - so APPLY, validation and every side effect
; are the existing code, unchanged. While the web menu is open, WebTick sends
; what changed (status lines, values set by code) a few times a second.
;
; WebView2 comes with Windows 10/11 (the Edge WebView2 Runtime). The binding is
; thqby's WebView2.ahk (MIT licence, lib\vendor). If the runtime or the files are
; missing, or anything fails, the native menu is used - nothing else changes.
;
; Cost: about 150-250 MB of memory while it is loaded, ~0% CPU when idle. When the
; menu is hidden the page is made invisible and asked to use little memory.

WebOn() => (Web.State = "ready")

WebLoaderPath() => A_ScriptDir . "\lib\vendor\WebView2\" . (A_PtrSize * 8) . "bit\WebView2Loader.dll"

; "C:\a b\x.html" -> "file:///C:/a%20b/x.html"
WebUrl(path) {
    if (path = "")
        return ""
    p := StrReplace(StrReplace(StrReplace(path, "%", "%25"), " ", "%20"), "#", "%23")
    return "file:///" . StrReplace(p, "\", "/")
}

; ---- start / stop ------------------------------------------------------------------
; Called once at boot (and when Settings > Window switches the engine). Creating
; the WebView2 control is asynchronous; WebCreated finishes the job.
WebStart() {
    Web.Loaded := false
    if (Theme.MenuEngine != "Web") {
        Web.State := "off"
        Web.Why := "Native picked in Settings > Window"
        return false
    }
    html := A_ScriptDir . "\lib\menu\index.html"
    if !FileExist(html)
        return WebFail("lib\menu\index.html is missing")
    if !FileExist(WebLoaderPath())
        return WebFail("lib\vendor\WebView2 is missing")
    Web.State := "starting"
    try {
        g := Gui("-Caption +ToolWindow +AlwaysOnTop", "ArkSense")
        g.BackColor := Theme.Panel
        g.MarginX := 0, g.MarginY := 0
        g.Show("w" . Layout.W . " h" . Layout.HGT . " Hide")
        WinGetPos(, , &ww, &wh, "ahk_id " . g.Hwnd)
        d := Round(14 * A_ScreenDPI / 96)
        rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", ww + 1, "Int", wh + 1,
                       "Int", d, "Int", d, "Ptr")
        if (rgn && !DllCall("user32\SetWindowRgn", "Ptr", g.Hwnd, "Ptr", rgn, "Int", 1))
            DllCall("gdi32\DeleteObject", "Ptr", rgn)
        Web.Gui := g
        dataDir := EnvGet("LOCALAPPDATA") . "\ArkSense\WebView2"   ; our own profile, not Edge's
        DirCreate(dataDir)
        WebView2.CreateControllerAsync(g.Hwnd, 0, dataDir, "", WebLoaderPath()).then(WebCreated, WebCreateFailed)
    } catch as e {
        return WebFail(e.Message)
    }
    return true
}

WebCreateFailed(err) {
    msg := ""
    try msg := err.Message
    WebFail((msg != "") ? msg : "WebView2 could not start")
}

WebFail(why) {
    Web.State := "failed"
    if InStr(why, "0x80070002") || InStr(why, "not found")
        why .= " (the Edge WebView2 Runtime seems missing - install it from Microsoft's WebView2 page)"
    Web.Why := why
    Web.Ctl := "", Web.Core := ""
    if (Web.Gui != "")
        try Web.Gui.Destroy()
    Web.Gui := ""
    Logg("web", "web menu unavailable, using the native menu: " . why)
    return false
}

WebCreated(ctl) {
    try {
        Web.Ctl := ctl
        core := ctl.CoreWebView2
        Web.Core := core
        s := core.Settings
        try s.AreDevToolsEnabled := false
        try s.AreDefaultContextMenusEnabled := false
        try s.IsZoomControlEnabled := false
        try s.IsStatusBarEnabled := false
        try s.AreBrowserAcceleratorKeysEnabled := false        ; no F5 / Ctrl+F browser bar
        c := Integer("0x" . Theme.Panel)                         ; no white flash while loading
        try ctl.DefaultBackgroundColor := 0xFF | (((c >> 16) & 0xFF) << 8) | (((c >> 8) & 0xFF) << 16) | ((c & 0xFF) << 24)
        core.add_WebMessageReceived(WebOnMessage)
        core.Navigate(WebUrl(A_ScriptDir . "\lib\menu\index.html"))
        try ctl.IsVisible := false
        Web.State := "ready"
        Web.Why := ""
        ApplyStreamerMode()
        Logg("web", "web menu ready")
    } catch as e {
        WebFail("setup failed: " . e.Message)
    }
}

; Settings > Window changed the engine: start or stop the web menu to match
WebEngineSync() {
    want := (Theme.MenuEngine = "Web")
    if (want && (Web.State = "off" || Web.State = "failed")) {
        WebStart()
    } else if (!want && Web.State != "off") {
        WebStop()
        Web.Why := "Native picked in Settings > Window"
    }
}

WebStop() {
    WebHide()
    if (Web.Ctl != "")
        try Web.Ctl.Close()
    Web.Ctl := "", Web.Core := ""
    if (Web.Gui != "")
        try Web.Gui.Destroy()
    Web.Gui := ""
    Web.State := "off"
    Web.Loaded := false
}

; ---- show / hide (from ShowMenu / HideMenu) -------------------------------------------
; false = the web menu can't show right now; the caller shows the native one instead
WebShow() {
    if (Web.State = "starting" || (WebOn() && !Web.Loaded)) {    ; still loading: give it 3 s
        t0 := A_TickCount
        while ((Web.State = "starting" || (WebOn() && !Web.Loaded)) && A_TickCount - t0 < 3000)
            Sleep 30
    }
    if !(WebOn() && Web.Loaded)
        return false
    if Web.Dirty
        WebPushModel()
    Web.Gui.Show()
    Web.Visible := true
    try Web.Ctl.IsVisible := true
    WebMemory(0)
    try WinActivate("ahk_id " . Web.Gui.Hwnd)
    try Web.Ctl.MoveFocus(0)                                     ; keys go to the page
    SetTimer(WebTick, 250)
    return true
}

WebHide() {
    SetTimer(WebTick, 0)
    if Web.Capture
        WebCapture(false)
    if !Web.Visible
        return
    Web.Visible := false
    if (Web.Gui != "")
        try Web.Gui.Hide()
    try Web.Ctl.IsVisible := false
    WebMemory(1)
}

; 1 = hidden: ask the page to keep little memory; 0 = normal (needs a 2022+ runtime)
WebMemory(low) {
    if (Web.Core = "")
        return
    try {
        q := ComObjQuery(Web.Core, WebView2.Core.IID_19)
        ComCall(120, q, "int", low)
    }
}

; ---- talking to the page ------------------------------------------------------------
WebPost(json) {
    if (Web.Core != "") {
        try Web.Core.PostWebMessageAsJson(json)
        return
    }
    if Web.Test                                                  ; test harness: record it
        try FileAppend(json . "`n", A_Temp . "\ArkSense-webout.txt", "UTF-8")
}

; messages from the page arrive inside a WebView2 callback; handle them a moment
; later on their own thread so long actions (rebuilds, area picking) can't stall it
WebOnMessage(sender, args) {
    msg := ""
    try msg := args.TryGetWebMessageAsString()
    if (msg = "")
        return
    Web.Queue.Push(msg)
    SetTimer(WebDrain, -1)
}

WebDrain() {
    while (Web.Queue.Length > 0)
        try WebHandle(Web.Queue.RemoveAt(1))
}

WebHandle(msg) {
    a := StrSplit(msg, "`t")
    switch a[1] {
        case "ready":
            Web.Loaded := true
            Web.Dirty := true
            if Web.Visible
                WebPushModel()
        case "page":
            if (a.Length >= 2 && UI.Pages.Has(a[2])) {
                ShowPage(a[2])
                Web.SentPage := a[2]
                WebTick(true)
            }
        case "set":
            if Web.Dirty                                         ; the menu was just rebuilt: old ids
                return
            if (a.Length >= 3 && RegExMatch(a[2], "^\d+$"))
                WebSet(Integer(a[2]), a[3])
        case "click":
            if Web.Dirty
                return
            if (a.Length >= 2 && RegExMatch(a[2], "^\d+$") && Web.Reg.Length >= Integer(a[2])) {
                e := Web.Reg[Integer(a[2])]
                if e.HasOwnProp("cb")
                    e.cb.Call()
                WebTick(true)
            }
        case "drag":
            if (Web.Gui != "") {
                DllCall("user32\ReleaseCapture")
                PostMessage(0xA1, 2, 0, , "ahk_id " . Web.Gui.Hwnd)     ; WM_NCLBUTTONDOWN, HTCAPTION
            }
        case "min":
            HideMenu()
        case "close":
            ExitApp()
        case "name":
            if (a.Length >= 2)
                SetUserName(a[2])
        case "capture":
            WebCapture(a.Length >= 2 && a[2] = "1")
        case "wall":
            WebSendWall()
        case "autotheme":
            if (a.Length >= 9)
                WebAutoTheme(a)
        case "err":
            Logg("web", "page error: " . SubStr((a.Length >= 2) ? a[2] : "", 1, 200))
    }
}

; a key chip is listening: pause ArkSense's own hotkeys so the key isn't also run
; (WebTick lets go after 15 s in case the page never says it's done)
WebCapture(on) {
    Web.Capture := on
    Web.CapAt := A_TickCount
    try Suspend(on ? 1 : 0)
}

; ---- the model ------------------------------------------------------------------------
; Called from the widget kit while the native menu is built.
WebGroupBegin(page, col, y, title, span) {
    if !Web.Model.Has(page)
        Web.Model[page] := {groups: [], foot: []}
    Web.Group := {page: page, col: col, y: y, title: title, span: span, items: []}
    Web.Model[page].groups.Push(Web.Group)
}

WebFootBegin(page) {
    if !Web.Model.Has(page)
        Web.Model[page] := {groups: [], foot: []}
    Web.Foot := page
}

; one widget; y groups it into a row, x orders it inside the row
WebRec(kind, y, x, props) {
    if Web.Mute
        return
    props.k := kind, props.y := y, props.x := x
    if (Web.Foot != "") {
        Web.Reg.Push(props)
        props.id := Web.Reg.Length
        props.page := Web.Foot
        Web.Model[Web.Foot].foot.Push(props)
        return
    }
    if (Web.Group = "")
        return                                                   ; header buttons etc.
    Web.Reg.Push(props)
    props.id := Web.Reg.Length
    props.page := Web.Group.page
    Web.Group.items.Push(props)
}

; a widget's current state as one string (to notice changes)
WebLive(e) {
    try {
        switch e.k {
            case "text":
                return e.c.Text . "|" . (UI.CustomFg.Has(e.c.Hwnd) ? UI.CustomFg[e.c.Hwnd] : "")
            case "field", "path", "hot", "swatch", "edit":
                return e.c.Value
            case "toggle":
                return ChkVal(e.c)
            case "slider":
                return UI.SliderVal.Has(e.sl.name) ? UI.SliderVal[e.sl.name] : ""
            case "drop":
                d := UI.Drops.Has(e.name) ? UI.Drops[e.name] : ""
                return DropValue(e.name, "") . "|" . ((d != "") ? d.items.Length . WebJoin(d.items) : "")
            case "button":
                return e.c.Text
            case "list":
                return Log.Items.Length . "|" . ((Log.Items.Length > 0) ? Log.Items[Log.Items.Length].msg : "") . "|" . Log.TextColor
        }
    }
    return ""
}

WebJoin(arr) {
    s := ""
    for v in arr
        s .= "|" . v
    return s
}

; JSON for one widget: all = everything (model), else only what changes
WebItemJson(e, all) {
    j := '{"id":' . e.id
    if all
        j .= ',"k":' . Json(e.k) . ',"y":' . e.y . ',"x":' . e.x
    tipCtl := e.HasOwnProp("tc") ? e.tc : e.HasOwnProp("c") ? e.c : ""
    if (all && tipCtl != "" && UI.Tips.Has(tipCtl.Hwnd))
        j .= ',"tip":' . Json(UI.Tips[tipCtl.Hwnd])
    try {
        switch e.k {
            case "label", "note":
                if all
                    j .= ',"text":' . Json(e.text)
            case "text":
                j .= ',"text":' . Json(e.c.Text) . ',"col":' . Json(UI.CustomFg.Has(e.c.Hwnd) ? UI.CustomFg[e.c.Hwnd] : "")
            case "field", "path", "edit":
                j .= ',"v":' . Json(e.c.Value)
                if all && e.HasOwnProp("num")
                    j .= ',"num":' . (e.num ? 1 : 0) . ',"w":' . e.w
            case "hot":
                j .= ',"v":' . Json(e.c.Value) . (all ? ',"w":' . e.w : "")
            case "swatch":
                j .= ',"v":' . Json(e.c.Value) . (all ? ',"w":' . e.w : "")
            case "toggle":
                j .= ',"v":' . ChkVal(e.c)
                if all
                    j .= ',"text":' . Json(e.text) . ',"half":' . (e.half ? 1 : 0)
            case "slider":
                sl := e.sl
                j .= ',"v":' . (UI.SliderVal.Has(sl.name) ? UI.SliderVal[sl.name] : sl.lo)
                if all
                    j .= ',"lo":' . sl.lo . ',"hi":' . sl.hi . ',"step":' . sl.step . ',"unit":' . Json(sl.unit)
            case "drop":
                d := UI.Drops[e.name]
                j .= ',"v":' . Json(DropValue(e.name, "")) . ',"items":' . Json(d.items) . (all ? ',"w":' . e.w : "")
            case "button":
                j .= ',"text":' . Json(e.c.Text)
                if all
                    j .= ',"style":' . Json(e.style)
            case "color":
                if all
                    j .= ',"col":' . Json(e.col)
            case "list":
                rows := []
                for it in Log.Items
                    rows.Push([it.t, it.src, it.msg])
                j .= ',"rows":' . Json(rows) . ',"col":' . Json(Log.TextColor)
        }
    }
    return j . "}"
}

WebNav() => NavList()

; the profile-box name changed: tell the page (it keeps its own copy)
WebUserName() {
    if (Web.Loaded && !Web.Dirty)
        WebPost('{"t":"user","name":' . Json(Theme.UserName) . '}')
}

WebThemeJson() {
    logo := (Trim(Audio.LogoPath) != "") ? Audio.LogoPath : A_ScriptDir . "\logo.png"
    wall := (Theme.WallOn && FileExist(Theme.WallPath)) ? WebUrl(Theme.WallPath) : ""
    return '{"bg":' . Json(Theme.Panel) . ',"side":' . Json(Theme.Header) . ',"group":' . Json(Theme.Header)
         . ',"field":' . Json(Theme.Panel2) . ',"line":' . Json(Theme.Line) . ',"acc":' . Json(Theme.Accent)
         . ',"acc2":' . Json(Theme.Accent2) . ',"text":' . Json(Theme.Text) . ',"dim":' . Json(Theme.Dim)
         . ',"ok":' . Json(Theme.Ok) . ',"bad":' . Json(Theme.Bad) . ',"warn":"E6B800"'
         . ',"font":' . Json(Theme.FontName) . ',"effect":' . Json(Anim.Effect) . ',"speed":' . Anim.RainbowSpeed
         . ',"glow":' . (Anim.GlowOn ? 1 : 0) . ',"anim":' . (Anim.TabOn ? 1 : 0)
         . ',"logo":' . Json(FileExist(logo) ? WebUrl(logo) : "") . ',"wall":' . Json(wall)
         . ',"wallPath":' . Json(FileExist(Theme.WallPath) ? Theme.WallPath : "")
         . ',"look":' . Json(LookCode(Theme.Look)) . ',"grade":' . Json(StrLower(Theme.Grade))
         . ',"neon":' . (Theme.NeonEdges ? 1 : 0) . ',"spot":' . (Theme.Spotlight ? 1 : 0) . '}'
}

WebModelJson() {
    nav := "["
    for i, sec in WebNav() {
        items := "["
        for k, it in sec[2]
            items .= ((k > 1) ? "," : "") . '{"page":' . Json(it[1]) . ',"icon":' . Json(Chr(it[2])) . ',"label":' . Json(it[3]) . '}'
        nav .= ((i > 1) ? "," : "") . '{"sec":' . Json(sec[1]) . ',"items":' . items . ']}'
    }
    nav .= "]"
    pages := "["
    n := 0
    for sec in WebNav() {
        for it in sec[2] {
            pg := it[1]
            if !Web.Model.Has(pg)
                continue
            m := Web.Model[pg], meta := PageMeta(pg)
            gs := "["
            for gi, gr in m.groups {
                its := "["
                for ii, e in gr.items {
                    its .= ((ii > 1) ? "," : "") . WebItemJson(e, true)
                    Web.Last[e.id] := WebLive(e)
                }
                gs .= ((gi > 1) ? "," : "") . '{"title":' . Json(gr.title) . ',"col":' . gr.col . ',"y":' . gr.y
                    . ',"span":' . gr.span . ',"items":' . its . ']}'
            }
            ft := "["
            for fi, e in m.foot {
                ft .= ((fi > 1) ? "," : "") . WebItemJson(e, true)
                Web.Last[e.id] := WebLive(e)
            }
            pages .= ((n++ > 0) ? "," : "") . '{"id":' . Json(pg) . ',"crumb":' . Json(meta[1]) . ',"title":' . Json(meta[2])
                   . ',"groups":' . gs . '],"foot":' . ft . ']}'
        }
    }
    pages .= "]"
    return '{"t":"model","page":' . Json(UI.Page) . ',"user":' . Json(Theme.UserName) . ',"nav":' . nav . ',"theme":' . WebThemeJson()
         . ',"pages":' . pages . ',"chrome":' . WebChromeJson(true) . '}'
}

WebPushModel() {
    WebPost(WebModelJson())
    Web.Dirty := false
    Web.SentPage := UI.Page
}

; sidebar profile box and footer status line, from the native controls StatusTick keeps current
WebChromeJson(force := false) {
    static last := ""
    parts := []
    for name in ["arkStatus", "sessionTimer", "railStatus"] {
        if UI.Ctrl.Has(name) {
            c := UI.Ctrl[name]
            parts.Push([c.Text, UI.CustomFg.Has(c.Hwnd) ? UI.CustomFg[c.Hwnd] : Theme.Dim])
        } else
            parts.Push(["", Theme.Dim])
    }
    sig := parts[1][1] . parts[1][2] . parts[2][1] . parts[3][1] . parts[3][2]
    if (!force && sig = last)
        return ""
    last := sig
    return '{"ark":' . Json(parts[1]) . ',"timer":' . Json(parts[2][1]) . ',"rail":' . Json(parts[3]) . '}'
}

; what changed on the open page (and its footer) since the last look
WebTick(now := false) {
    if (!Web.Visible || Anim.Busy)
        return
    if (Web.Capture && A_TickCount - Web.CapAt > 15000)
        WebCapture(false)                                        ; never leave hotkeys paused
    if (Web.Dirty && Web.Loaded) {
        WebPushModel()
        return
    }
    items := ""
    if Web.Model.Has(UI.Page) {
        m := Web.Model[UI.Page]
        for list in [m.foot] {
            for e in list
                WebDiffOne(e, &items)
        }
        for gr in m.groups
            for e in gr.items
                WebDiffOne(e, &items)
    }
    ch := WebChromeJson()
    pg := (UI.Page != Web.SentPage) ? UI.Page : ""
    if (items = "" && ch = "" && pg = "")
        return
    Web.SentPage := UI.Page
    WebPost('{"t":"diff","items":[' . items . ']' . ((ch != "") ? ',"chrome":' . ch : "")
          . ((pg != "") ? ',"page":' . Json(pg) : "") . '}')
}

WebDiffOne(e, &items) {
    if (e.k = "label" || e.k = "note" || e.k = "color")
        return
    s := WebLive(e)
    if (Web.Last.Has(e.id) && Web.Last[e.id] == s)
        return
    Web.Last[e.id] := s
    items .= ((items != "") ? "," : "") . WebItemJson(e, false)
}

; ---- a change from the page, written into the native control --------------------------
WebSet(id, v) {
    if (id < 1 || id > Web.Reg.Length)
        return
    e := Web.Reg[id]
    switch e.k {
        case "field", "path":
            e.c.Value := v
        case "hot":
            e.c.Value := v
            HotSync(e.name)
            if (e.c.Value != v)
                Logg("web", "key '" . v . "' isn't accepted by the key box")
        case "swatch":
            e.c.Value := v
            if (RegExMatch(v, "^[0-9A-Fa-f]{6}$") && UI.Ctrl.Has(e.sw))
                Paint(UI.Ctrl[e.sw], v)
        case "toggle":
            UI.ChkState[e.c.Hwnd] := (v = "1") ? 1 : 0
            PaintChk(e.c)
        case "slider":
            if RegExMatch(v, "^-?\d+$")
                SliderSet(e.sl, Integer(v))
        case "drop":
            if (UI.Drops.Has(e.name)) {
                ok := false
                for it in UI.Drops[e.name].items {
                    if (it = v)
                        ok := true
                }
                if ok
                    DropPick(e.name, v)                         ; also runs its onChange
            }
    }
    try Web.Last[id] := WebLive(e)                               ; the page already shows it
}

; ---- auto theme -------------------------------------------------------------------------
; the wallpaper as a data: URL, so the page may read its pixels (a file: picture may not)
WebSendWall() {
    p := Theme.WallPath
    if (p = "" || !FileExist(p))
        return WebPost('{"t":"wall","err":"Pick a wallpaper under Window first."}')
    if (FileGetSize(p) > 12 * 1024 * 1024)
        return WebPost('{"t":"wall","err":"That picture is over 12 MB - pick a smaller one."}')
    SplitPath(p, , , &ext)
    mime := (ext ~= "i)^jpe?g$") ? "image/jpeg" : (ext ~= "i)^png$") ? "image/png" : (ext ~= "i)^gif$") ? "image/gif"
          : (ext ~= "i)^bmp$") ? "image/bmp" : (ext ~= "i)^webp$") ? "image/webp" : "image/jpeg"
    buf := FileRead(p, "RAW")
    n := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &n)
    out := Buffer(n * 2, 0)
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", out, "UInt*", &n)
        return WebPost('{"t":"wall","err":"Couldn' . "'" . 't read that picture."}')
    WebPost('{"t":"wall","data":"data:' . mime . ';base64,' . StrGet(out, n, "UTF-16") . '"}')
}

; autotheme acc acc2 bg side field line text dim
WebAutoTheme(a) {
    for v in [a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9]] {
        if !RegExMatch(v, "^[0-9A-Fa-f]{6}$")
            return
    }
    Theme.Accent := a[2], Theme.Accent2 := a[3], Theme.Panel := a[4], Theme.Header := a[5]
    Theme.Panel2 := a[6], Theme.Line := a[7], Theme.Text := a[8], Theme.Dim := a[9]
    Theme.Preset := "Auto"
    SaveIni()
    Logg("web", "auto theme from the wallpaper applied")
    Rebuild(UI.Page)
}

; ---- JSON (writing only; messages from the page are plain tab-separated text) ----------
Json(v) {
    if (v is Array) {
        s := "["
        for i, x in v
            s .= ((i > 1) ? "," : "") . Json(x)
        return s . "]"
    }
    if (v is Integer || v is Float)
        return String(v)
    s := String(v)
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    if RegExMatch(s, "[\x00-\x1F]") {
        out := ""
        Loop Parse, s {
            o := Ord(A_LoopField)
            out .= (o < 0x20) ? Format("\u{:04X}", o) : A_LoopField
        }
        s := out
    }
    return '"' . s . '"'
}

; ---- test harness (only when lib\menu\test.flag exists) ---------------------------------
; Lets the sandbox drive this file without a WebView2: the model goes to
; %TEMP%\ArkSense-model.json, messages that would go to the page are appended to
; %TEMP%\ArkSense-webout.txt, and lines written to %TEMP%\ArkSense-webcmd.txt are
; handled as if the page had sent them.
WebTestStart() {
    if !FileExist(A_ScriptDir . "\lib\menu\test.flag")
        return
    Web.Test := true
    try FileDelete(A_Temp . "\ArkSense-webout.txt")
    try FileDelete(A_Temp . "\ArkSense-webcmd.txt")
    f := FileOpen(A_Temp . "\ArkSense-model.json", "w", "UTF-8")
    f.Write(WebModelJson())
    f.Close()
    Web.Dirty := false                                           ; the dump counts as the push
    Web.SentPage := UI.Page
    SetTimer(WebTestPoll, 200)
}

WebTestPoll() {
    p := A_Temp . "\ArkSense-webcmd.txt"
    if !FileExist(p)
        return
    txt := FileRead(p, "UTF-8")
    FileDelete(p)
    Web.Visible := true                                          ; act as if the page is open
    for ln in StrSplit(txt, "`n", "`r") {
        if (ln != "")
            WebHandle(ln)
    }
    WebTick(true)
}
