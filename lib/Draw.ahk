; ArkSense - lib\Draw.ahk
; Small GDI+ helpers: smooth (anti-aliased) lines, see-through fills, rounded boxes,
; text and pictures. Used by the classic stats card's graph and the Now playing card.
; Part of ArkSense.ahk; run that file, not this one.
;
; Only plain numbers, handles and small fixed-size buffers (float points, a 16-byte
; rectangle) cross into gdiplus.dll. Every helper frees what it creates.

; start GDI+ once; false if it can't (then callers fall back to plain GDI)
GdipReady() {
    static tok := 0, tried := false
    if tok
        return true
    if tried
        return false
    tried := true
    try {
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(24, 0)                          ; GdiplusStartupInput
        NumPut("UInt", 1, si, 0)                     ; version 1
        t := 0
        if (DllCall("gdiplus\GdiplusStartup", "UPtr*", &t, "Ptr", si, "Ptr", 0) = 0 && t)
            tok := t
    }
    if !tok
        Logg("overlay", "GDI+ unavailable - plain lines instead")
    return tok != 0
}

; "RRGGBB" + alpha -> 0xAARRGGBB
Argb(hex, a) => ((Integer(a) & 0xFF) << 24) | (Integer("0x" . hex) & 0xFFFFFF)

; a GDI+ surface on a device context: smooth edges, smooth text
GpGraphics(hdc) {
    g := 0
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &g)
    if g {
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)        ; anti-alias
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", g, "Int", 4)    ; anti-alias (alpha-safe)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)    ; high-quality bicubic
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)      ; high quality
    }
    return g
}

GpDone(g) {
    if g
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
}

; [[x, y], ...] -> packed float pairs
GpPoints(pts) {
    buf := Buffer(8 * pts.Length, 0)
    for i, p in pts {
        NumPut("Float", p[1], buf, (i - 1) * 8)
        NumPut("Float", p[2], buf, (i - 1) * 8 + 4)
    }
    return buf
}

GpRectF(x, y, w, h) {
    r := Buffer(16, 0)
    NumPut("Float", x, r, 0), NumPut("Float", y, r, 4), NumPut("Float", w, r, 8), NumPut("Float", h, r, 12)
    return r
}

; a polyline with round joins and ends
GpLines(g, pts, argb, w) {
    if (pts.Length < 2)
        return
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", w, "Int", 2, "Ptr*", &pen)  ; UnitPixel
    if !pen
        return
    DllCall("gdiplus\GdipSetPenLineJoin", "Ptr", pen, "Int", 2)
    DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pen, "Int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pen, "Int", 2)
    buf := GpPoints(pts)
    DllCall("gdiplus\GdipDrawLines", "Ptr", g, "Ptr", pen, "Ptr", buf, "Int", pts.Length)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

; the area under a line down to baseY, fading from argbTop (at topY) to argbBottom
GpArea(g, pts, baseY, argbTop, argbBottom, topY) {
    if (pts.Length < 2)
        return
    poly := pts.Clone()
    poly.Push([pts[pts.Length][1], baseY])
    poly.Push([pts[1][1], baseY])
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    buf := GpPoints(poly)
    DllCall("gdiplus\GdipAddPathPolygon", "Ptr", path, "Ptr", buf, "Int", poly.Length)
    rc := GpRectF(pts[1][1] - 1, topY - 1, pts[pts.Length][1] - pts[1][1] + 2, baseY - topY + 2)
    DllCall("gdiplus\GdipCreateLineBrushFromRect", "Ptr", rc, "UInt", argbTop, "UInt", argbBottom,
            "Int", 1, "Int", 3, "Ptr*", &br)                   ; vertical, tile-flip (no seam)
    if br {
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; rounded-rectangle path (caller deletes it)
GpRoundPath(x, y, w, h, r) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return 0
    d := Min(r * 2, w, h)
    if (d < 1) {
        DllCall("gdiplus\GdipAddPathRectangle", "Ptr", path, "Float", x, "Float", y, "Float", w, "Float", h)
        return path
    }
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y + h - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    return path
}

GpFillRound(g, x, y, w, h, r, argb) {
    path := GpRoundPath(x, y, w, h, r)
    if !path
        return
    br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br)
    if br {
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

GpStrokeRound(g, x, y, w, h, r, argb, pw) {
    path := GpRoundPath(x, y, w, h, r)
    if !path
        return
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", pw, "Int", 2, "Ptr*", &pen)
    if pen {
        DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; one line of text in a box; too long = cut with "...". align 0 left, 1 centre, 2 right.
; px = font height in pixels. GpTextB takes a brush instead (gradient text).
GpText(g, s, face, px, bold, argb, x, y, w, h, align := 0) {
    if (s = "")
        return
    br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br)
    if !br
        return
    GpTextB(g, s, face, px, bold, br, x, y, w, h, align)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

; font + one-line format (caller frees both with GpFontFree)
GpFont(face, px, bold, align, &font, &fmt) {
    fam := 0, font := 0, fmt := 0
    if (DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", face, "Ptr", 0, "Ptr*", &fam) != 0 || !fam) {
        fam := 0
        if (DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fam) != 0 || !fam) {
            fam := 0
            DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "Ptr*", &fam)
        }
    }
    if !fam
        return false
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", px, "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x1000, "Int", 0, "Ptr*", &fmt)      ; no wrap
    if fmt {
        DllCall("gdiplus\GdipSetStringFormatTrimming", "Ptr", fmt, "Int", 3)            ; ellipsis
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", align)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)           ; v-centre
    }
    return font && fmt
}

GpFontFree(font, fmt) {
    if fmt
        DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    if font
        DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
}

; fonts + formats are kept for reuse (step 20): the startup animation draws ~30 frames a
; second and Now playing once a second, and making a GDI+ font each time was the
; costliest part of a frame. Bounded: cleared when it holds more than 40.
GpFontCached(face, px, bold, align, &font, &fmt) {
    static cache := Map()
    key := face . "|" . Round(px, 1) . "|" . (bold ? 1 : 0) . "|" . align
    if cache.Has(key) {
        font := cache[key][1], fmt := cache[key][2]
        return true
    }
    if (cache.Count > 40) {
        for k, v in cache
            GpFontFree(v[1], v[2])
        cache.Clear()
    }
    if !GpFont(face, Round(px, 1), bold, align, &font, &fmt) {
        GpFontFree(font, fmt)
        return false
    }
    cache[key] := [font, fmt]
    return true
}

GpTextB(g, s, face, px, bold, br, x, y, w, h, align := 0) {
    if (s = "" || !br)
        return
    if GpFontCached(face, px, bold, align, &font, &fmt) {
        rc := GpRectF(x, y, w, h)
        DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", s, "Int", -1, "Ptr", font, "Ptr", rc,
                "Ptr", fmt, "Ptr", br)
    }
}

; width of a string in pixels (tight: the typographic format adds no side padding, so
; two strings drawn at x and x + GpTextW(first) sit right next to each other)
GpTextW(g, s, face, px, bold) {
    static tf := 0
    w := StrLen(s) * px * 0.55
    if GpFontCached(face, px, bold, 0, &font, &fmt) {
        if !tf
            DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &tf)
        lay := GpRectF(0, 0, 4000, px * 3), box := Buffer(16, 0)
        if (DllCall("gdiplus\GdipMeasureString", "Ptr", g, "WStr", s, "Int", -1, "Ptr", font, "Ptr", lay,
                    "Ptr", tf ? tf : fmt, "Ptr", box, "Ptr", 0, "Ptr", 0) = 0)
            w := NumGet(box, 8, "Float")
    }
    return w
}

; linear gradient brush over a box: mode 0 left->right, 1 top->bottom, 2 diagonal
GpGrad(x, y, w, h, argb1, argb2, mode := 0) {
    br := 0
    rc := GpRectF(x, y, Max(1, w), Max(1, h))
    DllCall("gdiplus\GdipCreateLineBrushFromRect", "Ptr", rc, "UInt", argb1, "UInt", argb2,
            "Int", mode, "Int", 3, "Ptr*", &br)
    return br
}

GpFreeBrush(br) {
    if br
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

GpFillRoundB(g, x, y, w, h, r, br) {
    path := GpRoundPath(x, y, w, h, r)
    if !path
        return
    if br
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

GpStrokeRoundB(g, x, y, w, h, r, br, pw) {
    path := GpRoundPath(x, y, w, h, r)
    if !path
        return
    pen := 0
    if br
        DllCall("gdiplus\GdipCreatePen2", "Ptr", br, "Float", pw, "Int", 2, "Ptr*", &pen)
    if pen {
        DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; soft glow around a rounded box: overlapping rings growing outwards, fading smoothly
GpGlow(g, x, y, w, h, r, hex, alpha, spread, n := 8) {
    n := Max(n, Round(spread / 1.5))
    step := spread / n
    Loop n {
        i := A_Index
        d := step * (i - 0.5)
        a := Round(alpha * (1 - (i - 1) / n) ** 2.2 / 3.2)
        if (a < 1)
            continue
        GpStrokeRound(g, x - d, y - d, w + 2 * d, h + 2 * d, r + d, Argb(hex, a), step * 1.9)
    }
}

; a 32-bit top-down DIB section selected into a fresh memory DC, for UpdateLayeredWindow
GpCanvas(W, H, &mem, &bmp, &old) {
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", W, bi, 4), NumPut("Int", -H, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", scr, "Ptr")
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    bits := 0
    bmp := DllCall("gdi32\CreateDIBSection", "Ptr", mem, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    old := bmp ? DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr") : 0
    return bmp != 0
}

GpCanvasFree(mem, bmp, old) {
    if old
        DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old, "Ptr")
    if bmp
        DllCall("gdi32\DeleteObject", "Ptr", bmp)
    if mem
        DllCall("gdi32\DeleteDC", "Ptr", mem)
}

; hand a canvas to a layered window: position, size, per-pixel alpha x `alpha`
GpPush(hwnd, mem, x, y, W, H, alpha := 255) {
    scr := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    pt := Buffer(8, 0), sz := Buffer(8, 0), src := Buffer(8, 0), bl := Buffer(4, 0)
    NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
    NumPut("Int", W, sz, 0), NumPut("Int", H, sz, 4)
    NumPut("UChar", Max(0, Min(255, Round(alpha))), bl, 2), NumPut("UChar", 1, bl, 3)   ; AC_SRC_ALPHA
    ok := DllCall("user32\UpdateLayeredWindow", "Ptr", hwnd, "Ptr", scr, "Ptr", pt, "Ptr", sz,
                  "Ptr", mem, "Ptr", src, "UInt", 0, "Ptr", bl, "UInt", 2)              ; ULW_ALPHA
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", scr)
    return ok
}

; a soft round light: argb in the middle fading to nothing at radius rx / ry
GpRadial(g, x, y, rx, ry, argb) {
    if ((argb >> 24) & 0xFF) = 0
        return
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    DllCall("gdiplus\GdipAddPathEllipse", "Ptr", path, "Float", x - rx, "Float", y - ry, "Float", 2 * rx, "Float", 2 * ry)
    DllCall("gdiplus\GdipCreatePathGradientFromPath", "Ptr", path, "Ptr*", &br)
    if br {
        edge := Buffer(4, 0), n := Buffer(4, 0)
        NumPut("UInt", argb & 0xFFFFFF, edge), NumPut("Int", 1, n)
        DllCall("gdiplus\GdipSetPathGradientCenterColor", "Ptr", br, "UInt", argb)
        DllCall("gdiplus\GdipSetPathGradientSurroundColorsWithCount", "Ptr", br, "Ptr", edge, "Ptr", n)
        DllCall("gdiplus\GdipSetPathGradientSigmaBlend", "Ptr", br, "Float", 1.0, "Float", 1.0)  ; soft falloff
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; darkened corners over a box: clear in the middle, argb at the edges
GpVignette(g, x, y, w, h, argb) {
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    DllCall("gdiplus\GdipAddPathEllipse", "Ptr", path, "Float", x - w * 0.2, "Float", y - h * 0.25,
            "Float", w * 1.4, "Float", h * 1.5)
    DllCall("gdiplus\GdipCreatePathGradientFromPath", "Ptr", path, "Ptr*", &br)
    if br {
        edge := Buffer(4, 0), n := Buffer(4, 0)
        NumPut("UInt", argb, edge), NumPut("Int", 1, n)
        DllCall("gdiplus\GdipSetPathGradientCenterColor", "Ptr", br, "UInt", argb & 0xFFFFFF)
        DllCall("gdiplus\GdipSetPathGradientSurroundColorsWithCount", "Ptr", br, "Ptr", edge, "Ptr", n)
        f := Buffer(12, 0), pos := Buffer(12, 0)              ; edge colour .. clear from 45% in
        NumPut("Float", 0, "Float", 1, "Float", 1, f), NumPut("Float", 0, "Float", 0.45, "Float", 1, pos)
        DllCall("gdiplus\GdipSetPathGradientBlend", "Ptr", br, "Ptr", f, "Ptr", pos, "Int", 3)
        DllCall("gdiplus\GdipFillRectangle", "Ptr", g, "Ptr", br, "Float", x, "Float", y, "Float", w, "Float", h)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; clip drawing to a rounded box (GdipResetClip ends it)
GpClipRound(g, x, y, w, h, r) {
    path := GpRoundPath(x, y, w, h, r)
    if path {
        DllCall("gdiplus\GdipSetClipPath", "Ptr", g, "Ptr", path, "Int", 0)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }
}

; an empty 32-bit (premultiplied alpha) GDI+ bitmap; free with GpFreeImage
GpBitmap(w, h) {
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0xE200B, "Ptr", 0, "Ptr*", &bmp)
    return bmp
}

; draw part of src (sx, sy, sw, sh) stretched over all of dst (w x h), smooth
GpBitmapDraw(dst, src, w, h, sx, sy, sw, sh) {
    g := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g)
    if !g
        return
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 6)       ; high-quality bilinear
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)
    DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", g, "Ptr", src, "Float", 0, "Float", 0, "Float", w, "Float", h,
            "Float", sx, "Float", sy, "Float", sw, "Float", sh, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
}

; load a picture (jpg/png/bmp); 0 if it can't be read
GpLoadImage(path) {
    if !FileExist(path)
        return 0
    img := 0
    if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &img) != 0)
        return 0
    return img
}

GpFreeImage(img) {
    if img
        DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
}

; draw a picture into a square, cropped from its centre, with rounded corners r
GpCoverSquare(g, img, x, y, side, r, ia := 0) {
    iw := 0, ih := 0
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih)
    if (iw < 1 || ih < 1)
        return
    s := Min(iw, ih)
    sx := (iw - s) // 2, sy := (ih - s) // 2
    path := GpRoundPath(x, y, side, side, r)
    if path
        DllCall("gdiplus\GdipSetClipPath", "Ptr", g, "Ptr", path, "Int", 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", img, "Int", Round(x), "Int", Round(y),
            "Int", Round(side), "Int", Round(side), "Int", sx, "Int", sy, "Int", s, "Int", s,
            "Int", 2, "Ptr", ia, "Ptr", 0, "Ptr", 0)
    if path {
        DllCall("gdiplus\GdipResetClip", "Ptr", g)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }
}
