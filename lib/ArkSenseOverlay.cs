// ArkSense - lib\ArkSenseOverlay.cs
// Smooth overlay renderer: the status pills, the stats card and the alert toasts.
// Part of ArkSense.ahk. ArkSense compiles this file by itself on first start with
// the C# compiler that ships inside Windows (.NET Framework 4, so C# 5 only: no
// $"", no ?., no => members) and starts it hidden - see lib\Ovl.ahk.
//
// How it works: every overlay piece is its own see-through window. A frame is
// drawn off-screen with anti-aliased GDI+ (smooth edges, gradients, soft glow and
// shadow) and handed to Windows in one UpdateLayeredWindow call with per-pixel
// alpha, so the screen only ever shows finished frames.
//
// Cost: it draws only when ArkSense sends new content (a pill changed, the card's
// once-a-second update, a toast). Between updates it sits in the Windows message
// loop at 0% CPU. A 60 fps timer runs only while a fade or toast slide is moving,
// and a 2 s timer checks that ArkSense is still running (it quits with it).
//
// It reads nothing from the game, sends no input and makes no network calls.
// Talk: ArkSense -> here = WM_COPYDATA text to the hidden "ArkSenseOverlayHost"
// window; here -> ArkSense = WM_COPYDATA text to the window handle given on the
// command line (hello, positions after a drag, errors).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace ArkSense
{
    static class N
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE { public int W; public int H; public SIZE(int w, int h) { W = w; H = h; } }
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int L; public int T; public int R; public int B; }
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct BLEND { public byte Op; public byte Flags; public byte Alpha; public byte Format; }
        [StructLayout(LayoutKind.Sequential)]
        public struct COPYDATA { public IntPtr Data; public int Bytes; public IntPtr Ptr; }

        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT dst, ref SIZE size,
            IntPtr hdcSrc, ref POINT src, int key, ref BLEND blend, int flags);
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
            int x, int y, int w, int h, uint flags);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int idx);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hwnd, int idx, int val);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hwnd, int msg, IntPtr w, ref COPYDATA l,
            int flags, int timeout, out IntPtr result);
        [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint aff);
    }

    // ---- theme (sent by ArkSense) --------------------------------------------------
    static class Th
    {
        public static string Font = "Segoe UI";
        public static Color Text = Color.White, Dim = Hex("7C7C8A"), Accent = Hex("FF2836"),
            Accent2 = Hex("18C8E6"), Panel = Hex("0E0E12"), Panel2 = Hex("1C1C24"), Ok = Hex("4CD07A"),
            Bad = Hex("FF5C7A"), Warn = Hex("E6B800"), HudText = Color.White, HudBorder = Hex("FF2E63"),
            Line = Hex("251F2E");
        public static Color Fx = Color.Empty;     // outline colour from a menu effect
        public static bool Border = false, Bg = true, Streamer = false, Glow = true;
        public static int Opacity = 205;
        public static string ToastPos = "tr";
        public static int Gen = 1;                // bumped on every theme change -> re-render
        public static float Dpi = 96f;

        public static Color Hex(string s)
        {
            int v;
            if (s != null && s.Length == 6 && int.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out v))
                return Color.FromArgb(255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
            return Color.Empty;
        }
        public static Color Hex(string s, Color def) { Color c = Hex(s); return c.IsEmpty ? def : c; }
    }

    // ---- drawing helpers ---------------------------------------------------------------
    static class P
    {
        static Bitmap measureBmp = new Bitmap(1, 1);
        public static Graphics M = Graphics.FromImage(measureBmp);
        static Dictionary<string, Font> fonts = new Dictionary<string, Font>();

        public static StringFormat Fmt()
        {
            StringFormat f = (StringFormat)StringFormat.GenericTypographic.Clone();
            f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap;
            return f;
        }
        public static readonly StringFormat SF = Fmt();

        // pt -> a cached font at the screen DPI (pixel units, so sizes match ArkSense)
        public static Font F(string face, float pt, bool bold)
        {
            float px = Math.Max(4f, pt * Th.Dpi / 72f);
            string k = face + "|" + px.ToString("0.0", CultureInfo.InvariantCulture) + "|" + bold;
            Font f;
            if (!fonts.TryGetValue(k, out f))
            {
                if (fonts.Count > 64) { foreach (Font o in fonts.Values) o.Dispose(); fonts.Clear(); }
                try { f = new Font(face, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); }
                catch { f = new Font(FontFamily.GenericSansSerif, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); }
                fonts[k] = f;
            }
            return f;
        }
        public static void ClearFonts() { foreach (Font o in fonts.Values) o.Dispose(); fonts.Clear(); }

        public static SizeF Measure(string s, Font f)
        {
            if (string.IsNullOrEmpty(s)) return new SizeF(0, f.GetHeight(M));
            SizeF z = M.MeasureString(s, f, PointF.Empty, SF);
            return new SizeF(z.Width, Math.Max(z.Height, f.GetHeight(M)));
        }

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            rad = Math.Max(0.5f, Math.Min(rad, Math.Min(r.Width, r.Height) / 2f));
            float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static Color A(Color c, int a) { return Color.FromArgb(Math.Max(0, Math.Min(255, a)), c.R, c.G, c.B); }
        public static Color Mix(Color a, Color b, float t)
        {
            t = Math.Max(0f, Math.Min(1f, t));
            return Color.FromArgb(a.A + (int)((b.A - a.A) * t), a.R + (int)((b.R - a.R) * t),
                                  a.G + (int)((b.G - a.G) * t), a.B + (int)((b.B - a.B) * t));
        }
        public static Color Light(Color c, float t) { return Mix(c, Color.FromArgb(c.A, 255, 255, 255), t); }
        public static Color Dark(Color c, float t) { return Mix(c, Color.FromArgb(c.A, 0, 0, 0), t); }

        public static Graphics G(Bitmap b)
        {
            Graphics g = Graphics.FromImage(b);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;   // ClearType can't blend onto alpha
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.Clear(Color.Transparent);
            return g;
        }

        // soft shadow under a body: a few widening, fading copies of its outline
        public static void Shadow(Graphics g, RectangleF r, float rad, float f, int strength)
        {
            for (int i = 3; i >= 1; i--)
            {
                float grow = i * 1.6f * f;
                RectangleF s = new RectangleF(r.X - grow, r.Y - grow + 1.5f * f, r.Width + 2 * grow, r.Height + 2 * grow);
                using (GraphicsPath p = Round(s, rad + grow))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(strength / (i + 1), 0, 0, 0)))
                    g.FillPath(b, p);
            }
        }

        // the body: vertical gradient, a faint top highlight, an optional outline with glow
        public static void Body(Graphics g, RectangleF r, float rad, float f, bool fill, int fillA,
                                bool outline, Color oc1, Color oc2, bool glow)
        {
            // step-11 look: near-black body with a faint lift at the top and a hairline edge
            if (fill)
            {
                using (GraphicsPath p = Round(r, rad))
                using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(r.X, r.Y - 1, r.Width, r.Height + 2),
                           A(Light(Th.Panel, 0.045f), fillA), A(Th.Panel, fillA), LinearGradientMode.Vertical))
                    g.FillPath(lb, p);
            }
            if (fill && !outline)
            {
                RectangleF ri = new RectangleF(r.X + 0.5f, r.Y + 0.5f, r.Width - 1, r.Height - 1);
                using (GraphicsPath p = Round(ri, Math.Max(1f, rad - 0.5f)))
                using (Pen pn = new Pen(A(Light(Th.Line, 0.06f), Math.Max(150, fillA)), 1f))
                    g.DrawPath(pn, p);
            }
            if (outline)
            {
                float w = Math.Max(1f, 1.1f * f);
                if (glow)
                {
                    for (int i = 3; i >= 1; i--)
                    {
                        using (GraphicsPath p = Round(r, rad))
                        using (Pen pg = new Pen(A(oc1, 22 * (4 - i)), w + i * 2.2f * f))
                        {
                            pg.LineJoin = LineJoin.Round;
                            g.DrawPath(pg, p);
                        }
                    }
                }
                RectangleF ri = new RectangleF(r.X + w / 2, r.Y + w / 2, r.Width - w, r.Height - w);
                using (GraphicsPath p = Round(ri, Math.Max(1f, rad - w / 2)))
                using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(r.X - 1, r.Y, r.Width + 2, r.Height), oc1, oc2, LinearGradientMode.Horizontal))
                using (Pen pn = new Pen(lb, w))
                    g.DrawPath(pn, p);
            }
        }

        // primary -> second colour across the first 55%, then fading out; a soft glow under it
        public static void TopLine(Graphics g, RectangleF r, float rad, float f)
        {
            float h = Math.Max(1.5f, 2f * f);
            using (GraphicsPath clip = Round(r, rad))
            {
                g.SetClip(clip);
                RectangleF lr = new RectangleF(r.X, r.Y, r.Width, h);
                using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(r.X - 1, r.Y, r.Width + 2, h), Color.Black, Color.Black, LinearGradientMode.Horizontal))
                {
                    ColorBlend cb = new ColorBlend(3);
                    cb.Colors = new Color[] { Th.Accent, Th.Accent2, A(Th.Accent2, 0) };
                    cb.Positions = new float[] { 0f, 0.55f, 1f };
                    lb.InterpolationColors = cb;
                    g.FillRectangle(lb, lr);
                }
                RectangleF gr = new RectangleF(r.X, r.Y + h, r.Width * 0.7f, 7 * f);
                using (LinearGradientBrush gb = new LinearGradientBrush(new RectangleF(gr.X, gr.Y - 1, gr.Width, gr.Height + 2), A(Th.Accent, 46), A(Th.Accent, 0), LinearGradientMode.Vertical))
                    g.FillRectangle(gb, gr);
                g.ResetClip();
            }
        }

        // status bar along the bottom edge (green = on, primary = off), with a glow above it
        public static void BottomMark(Graphics g, RectangleF r, float rad, float f, Color c)
        {
            if (c.IsEmpty) return;
            float h = Math.Max(1.5f, 2f * f);
            using (GraphicsPath clip = Round(r, rad))
            {
                g.SetClip(clip);
                RectangleF gl = new RectangleF(r.X, r.Bottom - h - 8 * f, r.Width, 8 * f);
                using (LinearGradientBrush gb = new LinearGradientBrush(new RectangleF(gl.X, gl.Y - 1, gl.Width, gl.Height + 2), A(c, 0), A(c, 60), LinearGradientMode.Vertical))
                    g.FillRectangle(gb, gl);
                using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, r.X, r.Bottom - h, r.Width, h);
                g.ResetClip();
            }
        }

        public static void Text(Graphics g, string s, Font f, Color c, float x, float y)
        {
            if (string.IsNullOrEmpty(s)) return;
            using (SolidBrush b = new SolidBrush(c)) g.DrawString(s, f, b, x, y, SF);
        }
    }

    // ---- what ArkSense asks for ------------------------------------------------------------
    class PillSpec
    {
        public string Key, Text; public int Icon; public Color Tc, Ic, Mark; public bool Saved, Hide; public int X, Y, Size;
    }

    class CardSpec
    {
        public bool Graph;
        public List<string[]> Cells = new List<string[]>();   // label, value, colour, pct
        public List<int> Main = new List<int>(), Faint = new List<int>(), Fps = new List<int>();
        public Color FpsC = Color.Empty;
        public string Tag = "--", Foot = "", Host = ""; public Color TagC = Color.Empty, FootC = Color.Empty;
        public string Sig = "";
        // clantag in the top line (step 23): the tag, its look, and the frame ArkSense sends
        // ~16x a second ("ctag"): what each letter shows, mask 0 hidden / 1 text / 2 accent,
        // and the cursor slot (-1 = none)
        public bool CtOn, CtBold = true, CtCursorRoom = true; public int CtScale = 100;
        public string CtReal = "", CtFont = "Consolas", CtTxt = "", CtMask = ""; public int CtCur = -1;
        public Color CtC = Color.White, CtA = Color.Red;
        public string CtSig() { return CtTxt + "|" + CtMask + "|" + CtCur; }
        // stats bar (step 24): the card as one slim bar; items = kind, value, unit, value colour, icon colour, level
        public bool Bar; public Color BarText = Color.White;
        // step 25: the logo (shape text from ArkSense, see Bar.ahk BarLogoSpec) and the tag's own box
        public string Logo = ""; public Color LogoC = Color.Empty;
        public bool CtOutline; public Color CtOC = Color.Red, CtBg = Color.Black; public int CtAlpha;
        public List<string[]> BarItems = new List<string[]>();
    }

    // one rendered frame and where its hit areas are
    class Frame
    {
        public Bitmap Bmp; public int BodyW, BodyH, M; public Rectangle Grip;
    }

    static class Render
    {
        // ---- a status pill at font size `size` ---------------------------------------
        public static Frame Pill(PillSpec s, int size, bool editing)
        {
            float f = size / 9f * Th.Dpi / 96f;
            Font ft = P.F(Th.Font, size, true);
            Font fi = P.F("Segoe UI Symbol", size, false);
            string icon = s.Icon > 0 ? char.ConvertFromUtf32(s.Icon) : "";
            SizeF tz = P.Measure(s.Text, ft);
            SizeF iz = P.Measure(icon, fi);
            SizeF gz = editing ? P.Measure("\u25E2", fi) : SizeF.Empty;
            float pad = 9 * f, gap = 5 * f;
            int bh = (int)Math.Ceiling(Math.Max(Math.Max(Host.PillH * f, tz.Height + 6 * f), iz.Height + 6 * f));
            int bw = (int)Math.Ceiling(pad + iz.Width + gap + tz.Width + 2 + pad + (editing ? gz.Width + gap : 0));
            int m = (int)Math.Ceiling(6 * f) + 2;
            Frame fr = new Frame();
            fr.BodyW = bw; fr.BodyH = bh; fr.M = m;
            fr.Bmp = new Bitmap(bw + 2 * m, bh + 2 * m, PixelFormat.Format32bppArgb);
            bool filled = Th.Bg || editing;
            bool outline = Th.Border || editing;
            Color oc1 = editing ? Th.Accent : (!Th.Fx.IsEmpty ? Th.Fx : Th.HudBorder);
            Color oc2 = editing ? Th.Accent2 : (!Th.Fx.IsEmpty ? P.Light(Th.Fx, 0.25f) : P.Mix(Th.HudBorder, Th.Accent2, 0.55f));
            int fillA = editing ? Math.Max(200, Th.Opacity) : Th.Opacity;
            float rad = Math.Min(bh / 2f, 5f * f);
            using (Graphics g = P.G(fr.Bmp))
            {
                RectangleF r = new RectangleF(m, m, bw, bh);
                if (filled && fillA > 40) P.Shadow(g, r, rad, f, Math.Min(120, fillA / 2));
                P.Body(g, r, rad, f, filled, fillA, outline, oc1, oc2, Th.Glow);
                P.BottomMark(g, r, rad, f, s.Mark);
                float cy = m + bh / 2f;
                float x = m + pad;
                // without a background the text still needs to read on any scene: dark halo
                if (!filled)
                {
                    using (SolidBrush hb = new SolidBrush(Color.FromArgb(150, 0, 0, 0)))
                    {
                        g.DrawString(icon, fi, hb, x + 1, cy - iz.Height / 2 + 1, P.SF);
                        g.DrawString(s.Text, ft, hb, x + iz.Width + gap + 1, cy - tz.Height / 2 + 1, P.SF);
                    }
                }
                P.Text(g, icon, fi, s.Ic, x, cy - iz.Height / 2);
                x += iz.Width + gap;
                P.Text(g, s.Text, ft, s.Tc, x, cy - tz.Height / 2);
                if (editing)
                {
                    float gx = m + bw - pad - gz.Width;
                    P.Text(g, "\u25E2", fi, Th.Accent, gx, cy - gz.Height / 2);
                    fr.Grip = new Rectangle((int)gx - 3, m, (int)gz.Width + (int)pad + 3, bh);
                }
            }
            return fr;
        }

        static Color PingCol(int ms)
        {
            if (ms < 0 || ms >= 150) return Th.Bad;
            if (ms >= 80) return Th.Warn;
            return Th.Ok;
        }

        // ---- the stats card -------------------------------------------------------------
        public static Frame Card(CardSpec c, int size, bool editing)
        {
            float f = size / 10f * Th.Dpi / 96f;
            Font fS = P.F(Th.Font, Math.Max(6, (float)Math.Round(size * 0.75)), true);
            Font fB = P.F(Th.Font, Math.Max(7, (float)Math.Round(size * 1.3)), true);
            Font fG = P.F("Segoe UI Symbol", Math.Max(6, size), false);
            float pad = 10 * f, gap = 8 * f;
            int W = (int)Math.Round(240 * f);
            SizeF lz = P.Measure("GPU", fS), vz = P.Measure("100%", fB), tz = P.Measure("999", fS);
            float y = pad;
            // clantag line: every letter keeps its own slot, measured from the real tag
            Font fT = null; float[] ctX = null; float ctCw = 0, ctH = 0, ctY = 0, ctPx = 0, ctPy = 0;
            bool ct = c.CtOn && c.CtReal.Length > 0;
            if (ct)
            {
                fT = P.F(c.CtFont, Math.Max(7, (float)Math.Round(size * 1.15 * c.CtScale / 100.0)), c.CtBold);
                int n = c.CtReal.Length;
                ctX = new float[n + 1];
                float bar = P.Measure("|", fT).Width;
                for (int i = 1; i <= n; i++)
                    ctX[i] = Math.Max(ctX[i - 1], P.Measure(c.CtReal.Substring(0, i) + "|", fT).Width - bar);
                ctCw = P.Measure("_", fT).Width;
                ctH = P.Measure("Ag", fT).Height;
                ctPx = (c.CtOutline || c.CtAlpha > 0) ? 6 * f : 0;    // the tag's own box (step 25)
                ctPy = ctPx > 0 ? 2 * f : 0;
                ctY = y + ctPy;
                y += ctH + 2 * ctPy + 6 * f;
                W = Math.Max(W, (int)Math.Ceiling(2 * pad + ctX[n] + (c.CtCursorRoom ? ctCw : 0) + 2 * ctPx));
            }
            float cellY = y;
            if (c.Cells.Count > 0) y += lz.Height + vz.Height + 5 * f + gap;
            float gx = pad, gy = 0, gh = 56 * f, gw = W - 2 * pad - tz.Width - 10 * f, footY = 0;
            if (c.Graph)
            {
                if (c.Cells.Count > 0 || ct) y += 2 * f;
                gy = y; y += gh + 7 * f; footY = y; y += tz.Height * 2 + 3 * f;
            }
            int H = (int)Math.Ceiling(y + pad - (c.Graph ? 0 : gap));
            int m = (int)Math.Ceiling(7 * f) + 2;
            Frame fr = new Frame();
            fr.BodyW = W; fr.BodyH = H; fr.M = m;
            fr.Bmp = new Bitmap(W + 2 * m, H + 2 * m, PixelFormat.Format32bppArgb);
            bool filled = Th.Bg || editing;
            bool outline = Th.Border || editing;
            Color oc1 = editing ? Th.Accent : (!Th.Fx.IsEmpty ? Th.Fx : Th.HudBorder);
            Color oc2 = editing ? Th.Accent2 : (!Th.Fx.IsEmpty ? P.Light(Th.Fx, 0.25f) : P.Mix(Th.HudBorder, Th.Accent2, 0.55f));
            int fillA = editing ? Math.Max(200, Th.Opacity) : Th.Opacity;
            float rad = 6 * f;
            using (Graphics g = P.G(fr.Bmp))
            {
                g.TranslateTransform(m, m);
                RectangleF r = new RectangleF(0, 0, W, H);
                if (filled && fillA > 40) P.Shadow(g, r, rad, f, Math.Min(130, fillA / 2));
                P.Body(g, r, rad, f, filled, fillA, outline, oc1, oc2, Th.Glow);
                if (filled) P.TopLine(g, r, rad, f);

                // ---- clantag
                if (ct)
                {
                    Color ac = c.CtA, tc = c.CtC;
                    if (ctPx > 0)
                    {
                        float tw = ctX[c.CtReal.Length] + (c.CtCursorRoom ? ctCw : 0);
                        RectangleF cr = new RectangleF(pad, ctY - ctPy, tw + 2 * ctPx, ctH + 2 * ctPy);
                        float crad = cr.Height / 2;
                        if (c.CtAlpha > 0)
                            using (GraphicsPath cp = P.Round(cr, crad))
                            using (SolidBrush cb = new SolidBrush(P.A(c.CtBg, c.CtAlpha))) g.FillPath(cb, cp);
                        if (c.CtOutline)
                        {
                            float ow = Math.Max(1f, 1.1f * f);
                            using (GraphicsPath op = P.Round(new RectangleF(cr.X + ow / 2, cr.Y + ow / 2, cr.Width - ow, cr.Height - ow), crad - ow / 2))
                            using (Pen opn = new Pen(P.A(c.CtOC, 230), ow)) g.DrawPath(opn, op);
                        }
                    }
                    for (int i = 0; i < c.CtReal.Length && i < c.CtTxt.Length && i < c.CtMask.Length; i++)
                    {
                        char mk = c.CtMask[i];
                        string ch = c.CtTxt.Substring(i, 1);
                        if (mk == '0' || ch == " ") continue;
                        float x = pad + ctPx + ctX[i];
                        if (mk == '2') x += (ctX[i + 1] - ctX[i] - P.Measure(ch, fT).Width) / 2;
                        if (!filled)
                            using (SolidBrush hb = new SolidBrush(Color.FromArgb(150, 0, 0, 0)))
                                g.DrawString(ch, fT, hb, x + 1, ctY + 1, P.SF);
                        P.Text(g, ch, fT, mk == '2' ? ac : tc, x, ctY);
                    }
                    if (c.CtCur >= 0 && c.CtCur <= c.CtReal.Length)
                        P.Text(g, "_", fT, ac, pad + ctPx + ctX[c.CtCur], ctY);
                    if (c.Cells.Count > 0 || c.Graph)
                    {
                        float sy = cellY - 3 * f;
                        using (LinearGradientBrush sl = new LinearGradientBrush(new RectangleF(pad, sy, W - 2 * pad, 1), Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
                        {
                            ColorBlend cb = new ColorBlend(3);
                            cb.Colors = new Color[] { P.A(ac, 0), P.A(ac, 110), P.A(ac, 0) };
                            cb.Positions = new float[] { 0f, 0.5f, 1f };
                            sl.InterpolationColors = cb;
                            using (Pen sp = new Pen(sl, 1f)) g.DrawLine(sp, pad, sy, W - pad, sy);
                        }
                    }
                }

                // ---- top row: label, big value, a thin usage bar
                if (c.Cells.Count > 0)
                {
                    float cw = (W - 2 * pad) / c.Cells.Count;
                    for (int i = 0; i < c.Cells.Count; i++)
                    {
                        string[] cell = c.Cells[i];
                        float cx = pad + i * cw;
                        Color vc = Th.Hex(cell[2], Th.HudText);
                        SizeF a = P.Measure(cell[0], fS);
                        P.Text(g, cell[0], fS, Th.Dim, cx + (cw - a.Width) / 2, cellY);
                        SizeF b = P.Measure(cell[1], fB);
                        if (!filled)
                            using (SolidBrush hb = new SolidBrush(Color.FromArgb(150, 0, 0, 0)))
                                g.DrawString(cell[1], fB, hb, cx + (cw - b.Width) / 2 + 1, cellY + lz.Height + 1, P.SF);
                        P.Text(g, cell[1], fB, vc, cx + (cw - b.Width) / 2, cellY + lz.Height);
                        int pct;
                        if (int.TryParse(cell[3], out pct) && pct >= 0)
                        {
                            float bw = cw * 0.62f, bx = cx + (cw - bw) / 2, by = cellY + lz.Height + vz.Height + 1.5f * f;
                            float bt = Math.Max(2f, 2.6f * f);
                            using (GraphicsPath tp = P.Round(new RectangleF(bx, by, bw, bt), bt / 2))
                            using (SolidBrush tb = new SolidBrush(Color.FromArgb(38, 255, 255, 255)))
                                g.FillPath(tb, tp);
                            float fw = Math.Max(bt, bw * Math.Min(100, pct) / 100f);
                            using (GraphicsPath fp = P.Round(new RectangleF(bx, by, fw, bt), bt / 2))
                            using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(bx - 1, by, fw + 2, bt),
                                       P.Light(vc, 0.15f), vc, LinearGradientMode.Horizontal))
                                g.FillPath(lb, fp);
                        }
                    }
                }

                // ---- the graph
                if (c.Graph)
                {
                    if (c.Cells.Count > 0)
                    {
                        float sy = gy - 5 * f;
                        using (LinearGradientBrush sl = new LinearGradientBrush(new RectangleF(pad, sy, W - 2 * pad, 1), Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
                        {
                            ColorBlend cb = new ColorBlend(3);
                            cb.Colors = new Color[] { P.A(Th.Dim, 0), P.A(Th.Dim, 90), P.A(Th.Dim, 0) };
                            cb.Positions = new float[] { 0f, 0.5f, 1f };
                            sl.InterpolationColors = cb;
                            using (Pen sp = new Pen(sl, 1f)) g.DrawLine(sp, pad, sy, W - pad, sy);
                        }
                    }
                    Graph(g, c, gx, gy, gw, gh, f, tz, fS);
                    // footer lines
                    Color fc = c.FootC.IsEmpty ? Th.HudText : c.FootC;
                    P.Text(g, c.Foot, fS, fc, pad, footY);
                    P.Text(g, c.Host, fS, Th.Dim, pad, footY + tz.Height + 2 * f);
                }

                if (editing)
                {
                    SizeF gz = P.Measure("\u25E2", fG);
                    float gxp = W - gz.Width - 5 * f, gyp = H - gz.Height - 3 * f;
                    P.Text(g, "\u25E2", fG, Th.Accent, gxp, gyp);
                    fr.Grip = new Rectangle((int)(gxp + m) - 4, (int)(gyp + m) - 4, (int)gz.Width + 8, (int)gz.Height + 8);
                }
            }
            return fr;
        }

        // ---- the stats bar: [bolt] ArkSense | clantag | [bars] 26 ms | [chart] 77 fps | CPU 31% ...
        public static Frame Bar(CardSpec c, int size, bool editing)
        {
            float f = size / 11f * Th.Dpi / 96f;
            Font fV = P.F(Th.Font, Math.Max(6, size * 0.92f), true);
            Font fU = P.F(Th.Font, Math.Max(5, size * 0.75f), false);
            Font fL = P.F(Th.Font, Math.Max(5, size * 0.75f), true);
            float pad = 13 * f, gap = 10 * f;
            int bh = (int)Math.Round(30 * f);
            bool ct = c.CtOn && c.CtReal.Length > 0;
            Font fT = null; float[] ctX = null; float ctCw = 0;
            List<float> segs = new List<float>();
            bool hasLogo = c.Logo != "";
            float boltW = hasLogo ? 15 * f : 0;
            float brandW = P.Measure("ArkSense", fV).Width;
            segs.Add(boltW + (hasLogo ? 6 * f : 0) + brandW);
            float chip = 0;
            if (ct)
            {
                fT = P.F(c.CtFont, Math.Max(6, size * 0.92f * c.CtScale / 100f), c.CtBold);
                int n = c.CtReal.Length;
                ctX = new float[n + 1];
                float bar = P.Measure("|", fT).Width;
                for (int i = 1; i <= n; i++)
                    ctX[i] = Math.Max(ctX[i - 1], P.Measure(c.CtReal.Substring(0, i) + "|", fT).Width - bar);
                ctCw = P.Measure("_", fT).Width;
                chip = (c.CtOutline || c.CtAlpha > 0) ? 7 * f : 0;
                segs.Add(ctX[n] + (c.CtCursorRoom ? ctCw : 0) + 2 * chip);
            }
            float[] vw = new float[c.BarItems.Count], uw = new float[c.BarItems.Count];
            for (int i = 0; i < c.BarItems.Count; i++)
            {
                string[] it = c.BarItems[i];
                bool icon = it[4] != "";
                vw[i] = P.Measure(it[1], fV).Width;
                uw[i] = P.Measure(it[2], icon ? fU : fL).Width;
                segs.Add(icon ? 18 * f + vw[i] + 4 * f + uw[i] : uw[i] + 5 * f + vw[i]);
            }
            float wsum = pad * 2;
            foreach (float w in segs) wsum += w;
            wsum += (segs.Count - 1) * (2 * gap + 1);
            if (editing) wsum += 14 * f;
            int bw = (int)Math.Ceiling(wsum);
            int m = (int)Math.Ceiling(6 * f) + 2;
            Frame fr = new Frame();
            fr.BodyW = bw; fr.BodyH = bh; fr.M = m;
            fr.Bmp = new Bitmap(bw + 2 * m, bh + 2 * m, PixelFormat.Format32bppArgb);
            bool filled = Th.Bg || editing;
            bool outline = Th.Border || editing;
            Color oc1 = editing ? Th.Accent : (!Th.Fx.IsEmpty ? Th.Fx : Th.HudBorder);
            Color oc2 = editing ? Th.Accent2 : (!Th.Fx.IsEmpty ? P.Light(Th.Fx, 0.25f) : P.Mix(Th.HudBorder, Th.Accent2, 0.55f));
            int fillA = editing ? Math.Max(200, Th.Opacity) : Th.Opacity;
            Color dim = P.Mix(c.BarText, Th.Dim, 0.6f);
            using (Graphics g = P.G(fr.Bmp))
            {
                g.TranslateTransform(m, m);
                RectangleF r = new RectangleF(0, 0, bw, bh);
                float rad = bh / 2f;
                if (filled && fillA > 40) P.Shadow(g, r, rad, f, Math.Min(120, fillA / 2));
                P.Body(g, r, rad, f, filled, fillA, outline, oc1, oc2, Th.Glow);
                float cy = bh / 2f;
                float x = pad;
                bool halo = !filled || fillA < 90;
                // the logo
                if (hasLogo)
                {
                    using (GraphicsPath lp = Logo(c.Logo, x, cy - 7.5f * f, 15 * f))
                    using (SolidBrush lb = new SolidBrush(c.LogoC.IsEmpty ? Th.Accent : c.LogoC)) g.FillPath(lb, lp);
                    x += boltW + 6 * f;
                }
                BarTxt(g, "ArkSense", fV, c.BarText, x, cy, halo);
                x += brandW;
                if (ct)
                {
                    x = BarSep(g, x, gap, bh, dim);
                    float th = P.Measure("Ag", fT).Height;
                    float tw = ctX[c.CtReal.Length] + (c.CtCursorRoom ? ctCw : 0);
                    if (chip > 0)                                   // the tag's own box
                    {
                        float chh = th + 4 * f;
                        RectangleF cr = new RectangleF(x, cy - chh / 2, tw + 2 * chip, chh);
                        if (c.CtAlpha > 0)
                            using (GraphicsPath cp = P.Round(cr, chh / 2))
                            using (SolidBrush cb = new SolidBrush(P.A(c.CtBg, c.CtAlpha))) g.FillPath(cb, cp);
                        if (c.CtOutline)
                        {
                            float ow = Math.Max(1f, 1.2f * f);
                            using (GraphicsPath op = P.Round(new RectangleF(cr.X + ow / 2, cr.Y + ow / 2, cr.Width - ow, cr.Height - ow), chh / 2 - ow / 2))
                            using (Pen opn = new Pen(P.A(c.CtOC, 230), ow)) g.DrawPath(opn, op);
                        }
                        x += chip;
                    }
                    for (int i = 0; i < c.CtReal.Length && i < c.CtTxt.Length && i < c.CtMask.Length; i++)
                    {
                        char mk = c.CtMask[i];
                        string ch = c.CtTxt.Substring(i, 1);
                        if (mk == '0' || ch == " ") continue;
                        float lx = x + ctX[i];
                        if (mk == '2') lx += (ctX[i + 1] - ctX[i] - P.Measure(ch, fT).Width) / 2;
                        BarTxt(g, ch, fT, mk == '2' ? c.CtA : c.CtC, lx, cy, halo);
                    }
                    if (c.CtCur >= 0 && c.CtCur <= c.CtReal.Length) BarTxt(g, "_", fT, c.CtA, x + ctX[c.CtCur], cy, halo);
                    x += tw + chip;
                }
                for (int i = 0; i < c.BarItems.Count; i++)
                {
                    string[] it = c.BarItems[i];
                    x = BarSep(g, x, gap, bh, dim);
                    Color vc = Th.Hex(it[3], c.BarText);
                    if (it[4] != "")
                    {
                        Color ic = Th.Hex(it[4], Th.Accent2);
                        if (it[0] == "ping")
                        {
                            int lvl; int.TryParse(it[5], out lvl);
                            for (int k = 1; k <= 3; k++)
                            {
                                float sh = (2 + k * 3) * f, sw = 2.6f * f;
                                float sx = x + (k - 1) * (sw + 1.7f * f), sy = cy + 5 * f - sh;
                                using (GraphicsPath sp = P.Round(new RectangleF(sx, sy, sw, sh), 0.8f * f))
                                using (SolidBrush sb = new SolidBrush(P.A(ic, k <= lvl ? 255 : 70))) g.FillPath(sb, sp);
                            }
                        }
                        else
                        {
                            PointF[] ln = { new PointF(0, 8), new PointF(3.2f, 4.6f), new PointF(6, 6.6f), new PointF(10, 1.6f) };
                            for (int k = 0; k < ln.Length; k++) ln[k] = new PointF(x + f + ln[k].X * f, cy - 4.6f * f + ln[k].Y * f);
                            using (Pen lp = new Pen(ic, Math.Max(1.4f, 1.6f * f)))
                            {
                                lp.LineJoin = LineJoin.Round; lp.StartCap = LineCap.Round; lp.EndCap = LineCap.Round;
                                g.DrawLines(lp, ln);
                            }
                        }
                        x += 18 * f;
                        BarTxt(g, it[1], fV, vc, x, cy, halo);
                        x += vw[i] + 4 * f;
                        BarTxt(g, it[2], fU, dim, x, cy, halo);
                        x += uw[i];
                    }
                    else
                    {
                        BarTxt(g, it[2], fL, dim, x, cy, halo);
                        x += uw[i] + 5 * f;
                        BarTxt(g, it[1], fV, vc, x, cy, halo);
                        x += vw[i];
                    }
                }
                if (editing)
                {
                    float gx = bw - pad * 0.6f - 9 * f, gy = cy - 4.5f * f;
                    PointF[] tri = { new PointF(gx + 9 * f, gy), new PointF(gx + 9 * f, gy + 9 * f), new PointF(gx, gy + 9 * f) };
                    using (SolidBrush gb = new SolidBrush(Th.Accent)) g.FillPolygon(gb, tri);
                    fr.Grip = new Rectangle((int)(gx + m) - 4, m, (int)(bw - gx) + 4, bh);
                }
            }
            return fr;
        }

        // a logo from its shape text: "p x,y,..." polygon, "e cx,cy,rx,ry" ellipse, "r x,y,w,h"
        // rectangle, on a 16 x 16 grid, alternate fill (inner shapes cut holes)
        static GraphicsPath Logo(string spec, float x, float y, float sz)
        {
            GraphicsPath gp = new GraphicsPath(FillMode.Alternate);
            float k = sz / 16f;
            foreach (string part0 in spec.Split(';'))
            {
                string part = part0.Trim();
                if (part.Length < 2) continue;
                char kind = part[0];
                List<float> n = new List<float>();
                foreach (string v in part.Substring(1).Split(','))
                {
                    float fv;
                    if (float.TryParse(v.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out fv)) n.Add(fv);
                }
                if (kind == 'p' && n.Count >= 6)
                {
                    PointF[] pts = new PointF[n.Count / 2];
                    for (int i = 0; i < pts.Length; i++) pts[i] = new PointF(x + n[2 * i] * k, y + n[2 * i + 1] * k);
                    gp.AddPolygon(pts);
                }
                else if (kind == 'e' && n.Count == 4)
                    gp.AddEllipse(x + (n[0] - n[2]) * k, y + (n[1] - n[3]) * k, 2 * n[2] * k, 2 * n[3] * k);
                else if (kind == 'r' && n.Count == 4)
                    gp.AddRectangle(new RectangleF(x + n[0] * k, y + n[1] * k, n[2] * k, n[3] * k));
            }
            return gp;
        }

        // text centred on cy (with a dark halo when there is no background behind it)
        static void BarTxt(Graphics g, string s, Font f, Color c, float x, float cy, bool halo)
        {
            float y = cy - P.Measure(s, f).Height / 2;
            if (halo)
                using (SolidBrush hb = new SolidBrush(Color.FromArgb(150, 0, 0, 0)))
                    g.DrawString(s, f, hb, x + 1, y + 1, P.SF);
            P.Text(g, s, f, c, x, y);
        }

        // a hairline between two parts of the bar; returns where the next part starts
        static float BarSep(Graphics g, float x, float gap, int bh, Color c)
        {
            x += gap;
            using (SolidBrush sb = new SolidBrush(P.A(c, 110))) g.FillRectangle(sb, x, bh * 0.27f, 1, bh * 0.46f);
            return x + 1 + gap;
        }

        // median of each sample and its neighbours (drawing only): single blips flatten,
        // real changes keep steep edges - a flat line with plateaus. Newest stays exact.
        static List<int> Med3(List<int> h)
        {
            List<int> o = new List<int>(h.Count);
            for (int i = 0; i < h.Count; i++)
            {
                int v = h[i];
                if (v < 0) { o.Add(v); continue; }
                int a = (i > 0 && h[i - 1] >= 0) ? h[i - 1] : v;
                int b = (i < h.Count - 1 && h[i + 1] >= 0) ? h[i + 1] : v;
                o.Add(Math.Max(Math.Min(a, v), Math.Min(Math.Max(a, v), b)));
            }
            return o;
        }

        // a series' own scale: its usual level about 1/rise of the way up, room above the peak
        static float Top(List<int> h, float floor, float rise)
        {
            List<int> v = new List<int>();
            foreach (int x in h) if (x >= 0) v.Add(x);
            if (v.Count == 0) return floor;
            v.Sort();
            float med = v[(v.Count - 1) / 2], hi = v[v.Count - 1];
            return Math.Max(floor, Math.Max(hi * 1.2f, med * rise));
        }

        static void Graph(Graphics g, CardSpec c, float gx, float gy, float gw, float gh, float f, SizeF tz, Font fS)
        {
            int n = 60;
            float lt = Math.Max(1.6f, 2f * f);
            float top = Top(c.Main, 30, 2.2f);
            foreach (int v in c.Faint) top = Math.Max(top, v * 1.1f);   // ping and server share a scale
            // grid: faint verticals + base line
            using (Pen gp = new Pen(Color.FromArgb(22, 255, 255, 255), 1f))
                for (int i = 1; i <= 5; i++) { float x = gx + i * gw / 6f; g.DrawLine(gp, x, gy, x, gy + gh); }
            using (Pen bp = new Pen(P.A(Th.Dim, 70), 1f)) g.DrawLine(bp, gx, gy + gh - 0.5f, gx + gw, gy + gh - 0.5f);

            // faint series (server reply) behind
            DrawSeries(g, Med3(c.Faint), n, gx, gy, gw, gh, top, lt, 1, f, Color.Empty);
            // FPS, own scale, in green
            if (c.Fps.Count > 0)
            {
                DrawSeries(g, Med3(c.Fps), n, gx, gy, gw, gh, Top(c.Fps, 30, 1.12f), lt, 2, f, c.FpsC.IsEmpty ? Th.Ok : c.FpsC);
            }
            // main series (ping) with area + glow
            List<float> lost = DrawSeries(g, Med3(c.Main), n, gx, gy, gw, gh, top, lt, 0, f, Color.Empty);
            using (Pen lp = new Pen(P.A(Th.Bad, 220), Math.Max(1.5f, 1.5f * f)))
            {
                lp.StartCap = LineCap.Round; lp.EndCap = LineCap.Round;
                foreach (float lx in lost) g.DrawLine(lp, lx, gy + 1, lx, gy + 7 * f);
            }

            // latest value tags at the right end
            int last = c.Main.Count > 0 ? c.Main[c.Main.Count - 1] : -1;
            float ly = gy + gh / 2;
            if (last >= 0) ly = gy + gh - lt - Math.Min(last, top) / top * (gh - lt * 2);
            Color tc = c.TagC.IsEmpty ? PingCol(last) : c.TagC;
            SizeF az = P.Measure(c.Tag, fS);
            float tx = gx + gw + 5 * f;
            float ty = Math.Max(gy, Math.Min(gy + gh - az.Height, ly - az.Height / 2));
            RectangleF tr = new RectangleF(tx - 2 * f, ty - 0.5f * f, az.Width + 4 * f, az.Height + 1f * f);
            using (GraphicsPath tp = P.Round(tr, tr.Height / 2))
            using (SolidBrush tb = new SolidBrush(P.A(tc, 40)))
                g.FillPath(tb, tp);
            P.Text(g, c.Tag, fS, tc, tx, ty);
            if (c.Fps.Count > 0 && c.Fps[c.Fps.Count - 1] >= 0)
            {
                int fl = c.Fps[c.Fps.Count - 1];
                float ftop = Top(c.Fps, 30, 1.12f);
                float fy = gy + gh - lt - Math.Min(fl, ftop) / ftop * (gh - lt * 2) - az.Height / 2;
                if (Math.Abs(fy - ty) < az.Height) fy = fy <= ty ? ty - az.Height : ty + az.Height;
                fy = Math.Max(gy - az.Height / 2, Math.Min(gy + gh - az.Height / 2, fy));
                P.Text(g, fl.ToString(CultureInfo.InvariantCulture), fS, c.FpsC.IsEmpty ? Th.Ok : c.FpsC, tx, fy);
            }
        }

        // one series; returns the x of every "no answer" sample (main series only)
        static List<float> DrawSeries(Graphics g, List<int> h, int n, float gx, float gy, float gw, float gh,
                                      float top, float lt, int kind, float f, Color kc)
        {
            bool faint = kind != 0;
            List<float> lost = new List<float>();
            List<List<PointF>> runs = new List<List<PointF>>();
            List<PointF> cur = null;
            for (int i = 1; i <= n; i++)
            {
                int k = h.Count - n + i - 1;
                float cx = gx + (i - 1) * gw / (n - 1);
                if (k < 0) { cur = null; continue; }
                int v = h[k];
                if (v < 0) { if (!faint) lost.Add(cx); cur = null; continue; }
                float py = gy + gh - lt - Math.Min(v, top) / top * (gh - lt * 2);
                if (cur == null) { cur = new List<PointF>(); runs.Add(cur); }
                cur.Add(new PointF(cx, py));
            }
            foreach (List<PointF> run in runs)
            {
                if (run.Count == 1) run.Add(new PointF(run[0].X + 0.8f, run[0].Y));
                PointF[] pts = run.ToArray();
                if (kind == 2)
                {
                    using (Pen p = new Pen(P.A(kc, 215), Math.Max(1.2f, lt * 0.75f)))
                    {
                        p.LineJoin = LineJoin.Round;
                        g.DrawLines(p, pts);
                    }
                    continue;
                }
                if (faint)
                {
                    using (Pen p = new Pen(P.A(Th.Dim, 150), Math.Max(1f, lt - 0.6f)))
                    {
                        p.LineJoin = LineJoin.Round;
                        g.DrawLines(p, pts);
                    }
                    continue;
                }
                // area under the line, fading down
                float minY = gy + gh;
                foreach (PointF q0 in pts) minY = Math.Min(minY, q0.Y);
                using (GraphicsPath ap = new GraphicsPath())
                {
                    ap.AddLines(pts);
                    ap.AddLine(pts[pts.Length - 1].X, pts[pts.Length - 1].Y, pts[pts.Length - 1].X, gy + gh - 1);
                    ap.AddLine(pts[pts.Length - 1].X, gy + gh - 1, pts[0].X, gy + gh - 1);
                    ap.CloseFigure();
                    using (LinearGradientBrush ab = new LinearGradientBrush(new RectangleF(gx, minY - 1, gw, gy + gh - minY + 2),
                               P.A(Th.Accent, 70), P.A(Th.Accent2, 0), LinearGradientMode.Vertical))
                        g.FillPath(ab, ap);
                }
                RectangleF lr = new RectangleF(gx - 1, gy, gw + 2, gh);
                if (Th.Glow)
                {
                    using (LinearGradientBrush gb = new LinearGradientBrush(lr, P.A(Th.Accent2, 60), P.A(Th.Accent, 60), LinearGradientMode.Horizontal))
                    using (Pen gp = new Pen(gb, lt * 3.2f))
                    {
                        gp.LineJoin = LineJoin.Round; gp.StartCap = LineCap.Round; gp.EndCap = LineCap.Round;
                        g.DrawLines(gp, pts);
                    }
                }
                using (LinearGradientBrush lb = new LinearGradientBrush(lr, Th.Accent2, Th.Accent, LinearGradientMode.Horizontal))
                using (Pen lp = new Pen(lb, lt))
                {
                    lp.LineJoin = LineJoin.Round; lp.StartCap = LineCap.Round; lp.EndCap = LineCap.Round;
                    g.DrawLines(lp, pts);
                }
            }
            // dot on the newest point
            if (!faint && runs.Count > 0)
            {
                List<PointF> lastRun = runs[runs.Count - 1];
                PointF q = lastRun[lastRun.Count - 1];
                float k2 = h.Count > 0 && h[h.Count - 1] >= 0 ? 1f : 0f;
                if (k2 > 0)
                {
                    float rr = lt * 1.6f;
                    using (SolidBrush b1 = new SolidBrush(P.A(Th.Accent, 70))) g.FillEllipse(b1, q.X - rr * 2, q.Y - rr * 2, rr * 4, rr * 4);
                    using (SolidBrush b2 = new SolidBrush(Th.Accent)) g.FillEllipse(b2, q.X - rr, q.Y - rr, rr * 2, rr * 2);
                    using (SolidBrush b3 = new SolidBrush(Color.FromArgb(230, 255, 255, 255))) g.FillEllipse(b3, q.X - rr / 2.2f, q.Y - rr / 2.2f, rr / 1.1f, rr / 1.1f);
                }
            }
            return lost;
        }

        // ---- an alert toast ----------------------------------------------------------------
        public static Frame Toast(string kind, string title, string body)
        {
            float f = Th.Dpi / 96f;
            Font ft = P.F(Th.Font, 10, true);
            Font fb = P.F(Th.Font, 9, false);
            Font fi = P.F("Segoe UI Symbol", 8, true);
            Color kc = kind == "ok" ? Th.Ok : kind == "bad" ? Th.Bad : kind == "warn" ? Th.Warn : Th.Accent;
            string glyph = kind == "ok" ? "\u2714" : kind == "bad" ? "\u2716" : kind == "warn" ? "!" : "i";
            int W = (int)Math.Round(320 * f);
            float pad = 14 * f, iconD = 28 * f;
            float textX = pad + 6 * f + iconD + 12 * f;
            float textW = W - textX - pad;
            SizeF tz = P.Measure(title, ft);
            string[] lines = Wrap(body, fb, textW, 3);
            float lh = P.Measure("Ag", fb).Height;
            float contentH = tz.Height + (lines.Length > 0 ? 3 * f + lines.Length * lh : 0);
            int H = (int)Math.Ceiling(Math.Max(iconD + 2 * pad, contentH + 2 * pad));
            int m = (int)Math.Ceiling(10 * f) + 2;
            Frame fr = new Frame();
            fr.BodyW = W; fr.BodyH = H; fr.M = m;
            fr.Bmp = new Bitmap(W + 2 * m, H + 2 * m, PixelFormat.Format32bppArgb);
            float rad = 6 * f;
            using (Graphics g = P.G(fr.Bmp))
            {
                g.TranslateTransform(m, m);
                RectangleF r = new RectangleF(0, 0, W, H);
                P.Shadow(g, r, rad, f * 1.6f, 150);
                P.Body(g, r, rad, f, true, 240, false, kc, kc, false);
                // tinted wash from the left in the alert's colour, and a glowing edge bar
                using (GraphicsPath clip = P.Round(r, rad))
                {
                    g.SetClip(clip);
                    using (LinearGradientBrush wb = new LinearGradientBrush(new RectangleF(0, 0, W * 0.6f, H), P.A(kc, 34), P.A(kc, 0), LinearGradientMode.Horizontal))
                        g.FillRectangle(wb, 0, 0, W * 0.6f, H);
                    using (LinearGradientBrush gb = new LinearGradientBrush(new RectangleF(3 * f, 0, 12 * f, H), P.A(kc, 70), P.A(kc, 0), LinearGradientMode.Horizontal))
                        g.FillRectangle(gb, 3 * f, 0, 12 * f, H);
                    using (SolidBrush eb = new SolidBrush(kc)) g.FillRectangle(eb, 0, 0, 3 * f, H);
                    g.ResetClip();
                }
                // a diamond in the alert's colour with a soft glow (the menu's tab marker)
                RectangleF ic = new RectangleF(pad + 6 * f, (H - iconD) / 2, iconD, iconD);
                float cxi = ic.X + ic.Width / 2, cyi = ic.Y + ic.Height / 2, dr = iconD * 0.36f;
                for (int gi = 3; gi >= 1; gi--)
                {
                    float rr = dr + gi * 2.5f * f;
                    using (SolidBrush gb = new SolidBrush(P.A(kc, 26)))
                        g.FillPolygon(gb, new PointF[] { new PointF(cxi, cyi - rr), new PointF(cxi + rr, cyi), new PointF(cxi, cyi + rr), new PointF(cxi - rr, cyi) });
                }
                using (LinearGradientBrush db = new LinearGradientBrush(new RectangleF(cxi - dr, cyi - dr - 1, dr * 2, dr * 2 + 2), P.Light(kc, 0.3f), kc, LinearGradientMode.Vertical))
                    g.FillPolygon(db, new PointF[] { new PointF(cxi, cyi - dr), new PointF(cxi + dr, cyi), new PointF(cxi, cyi + dr), new PointF(cxi - dr, cyi) });
                SizeF gz = P.Measure(glyph, fi);
                P.Text(g, glyph, fi, Color.FromArgb(255, 18, 14, 22), cxi - gz.Width / 2, cyi - gz.Height / 2);
                float ty = (H - contentH) / 2;
                P.Text(g, title, ft, Th.Text, textX, ty);
                float by = ty + tz.Height + 3 * f;
                foreach (string ln in lines) { P.Text(g, ln, fb, P.Light(Th.Dim, 0.25f), textX, by); by += lh; }
            }
            return fr;
        }

        static string[] Wrap(string s, Font f, float w, int maxLines)
        {
            List<string> outl = new List<string>();
            if (string.IsNullOrEmpty(s)) return outl.ToArray();
            string[] words = s.Split(' ');
            string line = "";
            foreach (string wd in words)
            {
                string t = line.Length == 0 ? wd : line + " " + wd;
                if (P.Measure(t, f).Width <= w || line.Length == 0) { line = t; continue; }
                outl.Add(line);
                line = wd;
                if (outl.Count == maxLines) break;
            }
            if (outl.Count < maxLines && line.Length > 0) outl.Add(line);
            else if (outl.Count == maxLines && line.Length > 0) outl[maxLines - 1] = outl[maxLines - 1] + "...";
            return outl.ToArray();
        }
    }

    // ---- a see-through window showing one frame ----------------------------------------
    class Layer : Form
    {
        public Item It;
        Host host;
        bool through = true, shown = false;
        IntPtr memDC = IntPtr.Zero, hBmp = IntPtr.Zero, oldBmp = IntPtr.Zero;
        int bw = 1, bh = 1;
        bool resizing = false;
        int s0, w0, mx0;

        public Layer(Host h, Item it)
        {
            host = h; It = it;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            Text = "ArkSense overlay";
            IntPtr force = Handle;                    // create the window now, hidden
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                // LAYERED | TOOLWINDOW | NOACTIVATE | TOPMOST (+ TRANSPARENT = click-through)
                cp.ExStyle |= 0x80000 | 0x80 | 0x8000000 | 0x8;
                if (through) cp.ExStyle |= 0x20;
                return cp;
            }
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e) { }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            N.SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);   // HWND_TOPMOST, no move/size/activate
            ApplyAffinity();
        }

        public void ApplyAffinity()
        {
            try { N.SetWindowDisplayAffinity(Handle, Th.Streamer ? 0x11u : 0u); } catch { }
        }

        public void SetThrough(bool on)
        {
            through = on;
            int ex = N.GetWindowLong(Handle, -20);
            ex = on ? (ex | 0x20) : (ex & ~0x20);
            N.SetWindowLong(Handle, -20, ex);
        }

        // take a new frame (the bitmap is copied into a GDI bitmap and may be disposed)
        public void SetFrame(Bitmap b)
        {
            FreeGdi();
            IntPtr scr = N.GetDC(IntPtr.Zero);
            memDC = N.CreateCompatibleDC(scr);
            N.ReleaseDC(IntPtr.Zero, scr);
            hBmp = b.GetHbitmap(Color.FromArgb(0));
            oldBmp = N.SelectObject(memDC, hBmp);
            bw = b.Width; bh = b.Height;
        }

        public void Push(int x, int y, float alpha)
        {
            if (memDC == IntPtr.Zero) return;
            N.POINT dst = new N.POINT(x, y), src = new N.POINT(0, 0);
            N.SIZE sz = new N.SIZE(bw, bh);
            N.BLEND bl = new N.BLEND();
            bl.Op = 0; bl.Flags = 0; bl.Format = 1;                     // AC_SRC_ALPHA
            bl.Alpha = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(alpha * 255)));
            N.UpdateLayeredWindow(Handle, IntPtr.Zero, ref dst, ref sz, memDC, ref src, 0, ref bl, 2);   // ULW_ALPHA
            if (!shown && alpha > 0)
            {
                N.ShowWindow(Handle, 4);                                // SW_SHOWNOACTIVATE
                N.SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);
                shown = true;
            }
        }

        public void HideNow()
        {
            if (shown) { N.ShowWindow(Handle, 0); shown = false; }
        }

        void FreeGdi()
        {
            if (memDC != IntPtr.Zero)
            {
                N.SelectObject(memDC, oldBmp);
                N.DeleteDC(memDC);
                memDC = IntPtr.Zero;
            }
            if (hBmp != IntPtr.Zero) { N.DeleteObject(hBmp); hBmp = IntPtr.Zero; }
        }

        protected override void Dispose(bool disposing)
        {
            FreeGdi();
            base.Dispose(disposing);
        }

        // ---- edit mode: drag to move, drag the grip to resize --------------------------
        protected override void OnMouseDown(MouseEventArgs e)
        {
            bool ed = host.Editing || (host.CardEdit && It != null && It.IsCard);   // card-only move (step 25)
            if (!ed || e.Button != MouseButtons.Left || It == null || It.IsToast) return;
            if (It.Grip.Contains(e.Location))
            {
                resizing = true;
                Capture = true;
                s0 = It.Size; w0 = Math.Max(1, It.BW); mx0 = Cursor.Position.X;
                return;
            }
            N.ReleaseCapture();
            N.SendMessage(Handle, 0xA1, new IntPtr(2), IntPtr.Zero);   // WM_NCLBUTTONDOWN, HTCAPTION: system move loop
            N.RECT rc;
            if (N.GetWindowRect(Handle, out rc))
            {
                It.X = rc.L + It.M; It.Y = rc.T + It.M;
                It.Touched = true;
            }
            host.QueueReport();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (!resizing) return;
            int size = (int)Math.Round(s0 * (double)(w0 + Cursor.Position.X - mx0) / w0);
            size = Math.Max(6, Math.Min(48, size));
            if (size != It.Size)
            {
                It.Size = size;
                It.Touched = true;
                host.Rerender(It, true);
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (!resizing) return;
            resizing = false;
            Capture = false;
            host.QueueReport();
        }
    }

    // one overlay piece: a pill, the card or a toast
    class Item
    {
        public string Key;
        public Layer Win;
        public string Sig = null;           // what was last drawn
        public int Size, X, Y, BW = 1, BH = 1, M;
        public Rectangle Grip;
        public bool IsCard, IsToast, Touched;
        public float A = 0f, Target = 0f;   // fade
        public PillSpec Pill;
        public CardSpec Card;
        // toast only
        public float Slide = 0f, CurY, TargetY; public long Until; public bool Leaving; public bool HasY;
    }

    class Host : NativeWindow
    {
        // troubleshooting: an empty file "ArkSenseOverlay.debug" next to the .exe makes it
        // write every message it gets to %TEMP%\ArkSense-overlay-debug.txt
        static readonly bool Debug = System.IO.File.Exists(
            System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ArkSenseOverlay.debug"));
        public static void Dbg(string s)
        {
            if (!Debug) return;
            try
            {
                System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ArkSense-overlay-debug.txt"),
                    DateTime.Now.ToString("HH:mm:ss.fff") + "  " + s.Replace("\n", " | ") + "\r\n");
            }
            catch { }
        }

        public static float PillH = 24;
        IntPtr parent;
        Process parentProc;
        Dictionary<string, Item> pills = new Dictionary<string, Item>();
        Item card = null;
        List<Item> toasts = new List<Item>();
        public bool Editing = false;
        public bool CardEdit = false;          // step 25: only the card is being moved
        Timer anim = new Timer();
        Timer watch = new Timer();
        Timer hello = new Timer();
        int helloTries = 0;
        bool heard = false;                     // ArkSense has sent us something
        List<string> outbox = new List<string>();
        bool reportQueued = false;
        string lastReport = "";
        long lastStep = 0;
        int toastL, toastT, toastR, toastB;
        const int WM_FLUSH = 0x8000 + 0x41;     // WM_APP + n: send queued replies after the inbound call returned
        public const int Version = 1;

        public Host(IntPtr parent, int pid)
        {
            this.parent = parent;
            try { parentProc = Process.GetProcessById(pid); } catch { parentProc = null; }
            CreateParams cp = new CreateParams();
            cp.Caption = "ArkSenseOverlayHost";
            cp.Parent = new IntPtr(-3);          // HWND_MESSAGE: a message-only window
            CreateHandle(cp);
            anim.Interval = 15;
            anim.Tick += delegate { Step(); };
            watch.Interval = 2000;
            watch.Tick += delegate { Watch(); };
            watch.Start();
            Rectangle sb = Screen.PrimaryScreen.Bounds;
            toastL = sb.Left; toastT = sb.Top; toastR = sb.Right; toastB = sb.Bottom;
            // say hello until ArkSense answers: it may be busy (starting up) the first time
            hello.Interval = 400;
            hello.Tick += delegate
            {
                if (heard || ++helloTries > 40) { hello.Stop(); return; }
                SayHello();
            };
            SayHello();
            hello.Start();
        }

        void SayHello()
        {
            Send("hello\t" + Handle.ToInt64().ToString(CultureInfo.InvariantCulture) + "\t" + Version);
        }

        void Watch()
        {
            bool gone = !N.IsWindow(parent);
            try { if (parentProc != null && parentProc.HasExited) gone = true; } catch { }
            if (gone) Application.Exit();
        }

        // ---- talking to ArkSense --------------------------------------------------------
        bool Send(string s)
        {
            if (!N.IsWindow(parent)) return false;
            IntPtr mem = Marshal.StringToHGlobalUni(s);
            try
            {
                N.COPYDATA cd = new N.COPYDATA();
                cd.Data = new IntPtr(0x41534F56);          // 'ASOV'
                cd.Bytes = (s.Length + 1) * 2;
                cd.Ptr = mem;
                IntPtr res;
                return N.SendMessageTimeout(parent, 0x4A, Handle, ref cd, 0x2, 1000, out res) != IntPtr.Zero;   // SMTO_ABORTIFHUNG
            }
            finally { Marshal.FreeHGlobal(mem); }
        }

        void Post(string s)
        {
            outbox.Add(s);
            N.PostMessage(Handle, WM_FLUSH, IntPtr.Zero, IntPtr.Zero);
        }

        public void Log(string s) { Post("log\t" + s.Replace('\t', ' ').Replace('\n', ' ').Replace('\r', ' ')); }

        public void QueueReport()
        {
            if (reportQueued) return;
            reportQueued = true;
            N.PostMessage(Handle, WM_FLUSH, IntPtr.Zero, IntPtr.Zero);
        }

        string BuildReport()
        {
            StringBuilder sb = new StringBuilder("pos");
            foreach (Item it in pills.Values)
                if (it.Target > 0) sb.Append("\n" + it.Key + "\t" + it.X + "\t" + it.Y + "\t" + it.Size);
            if (card != null && card.Target > 0) sb.Append("\nstats\t" + card.X + "\t" + card.Y + "\t" + card.Size);
            return sb.ToString();
        }

        // "report": the positions go to a temp file before this call returns, so ArkSense
        // can read them straight after (used by LOCK)
        void WriteReport()
        {
            string path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ArkSense-overlay-pos.txt");
            string tmp = path + ".tmp";
            System.IO.File.WriteAllText(tmp, BuildReport(), Encoding.UTF8);
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            System.IO.File.Move(tmp, path);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x4A)
            {
                try
                {
                    N.COPYDATA cd = (N.COPYDATA)Marshal.PtrToStructure(m.LParam, typeof(N.COPYDATA));
                    if (cd.Data.ToInt64() == 1 && cd.Ptr != IntPtr.Zero && cd.Bytes > 0)
                    {
                        string s = Marshal.PtrToStringUni(cd.Ptr, cd.Bytes / 2).TrimEnd('\0');
                        heard = true;
                        int t0 = Environment.TickCount;
                        Handle1(s);
                        Dbg((Environment.TickCount - t0) + " ms  " + s);
                    }
                }
                catch (Exception ex) { Log("error: " + ex.Message); Dbg("error: " + ex.ToString()); }
                m.Result = new IntPtr(1);
                return;
            }
            if (m.Msg == WM_FLUSH)
            {
                List<string> q = outbox;
                outbox = new List<string>();
                foreach (string s in q) Send(s);
                if (reportQueued)
                {
                    reportQueued = false;
                    string r = BuildReport();
                    if (r != lastReport && Send(r)) lastReport = r;   // not delivered: next report tries again
                }
                return;
            }
            base.WndProc(ref m);
        }

        static int I(string[] a, int i, int def)
        {
            int v;
            return (i < a.Length && int.TryParse(a[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) ? v : def;
        }
        static string S(string[] a, int i) { return i < a.Length ? a[i] : ""; }

        public void Handle1(string s)
        {
            string[] lines = s.Replace("\r", "").Split('\n');
            string[] head = lines[0].Split('\t');
            switch (head[0])
            {
                case "theme": DoTheme(lines); break;
                case "pills": DoPills(head, lines); break;
                case "card": DoCard(head, lines); break;
                case "ctag":                                   // one clantag frame for the card
                    if (card != null && card.Card != null && card.Card.CtOn)
                    {
                        card.Card.CtTxt = S(head, 1); card.Card.CtMask = S(head, 2); card.Card.CtCur = I(head, 3, -1);
                        if (card.Target > 0 || card.A > 0) Rerender(card, true);
                    }
                    break;
                case "toast": DoToast(head); break;
                case "edit": SetEditing(S(head, 1) == "1"); break;
                case "fx":
                    Color fx = Th.Hex(S(head, 1));
                    if (fx != Th.Fx)
                    {
                        Th.Fx = fx;                            // pills now; the card on its next update
                        foreach (Item it in pills.Values) if (it.Target > 0) Rerender(it, true);
                    }
                    break;
                case "report": WriteReport(); break;
                case "quit": Application.Exit(); break;
            }
        }

        // ---- theme ---------------------------------------------------------------------
        void DoTheme(string[] lines)
        {
            bool oldStream = Th.Streamer;
            string oldFont = Th.Font;
            for (int i = 1; i < lines.Length; i++)
            {
                int eq = lines[i].IndexOf('=');
                if (eq <= 0) continue;
                string k = lines[i].Substring(0, eq), v = lines[i].Substring(eq + 1);
                int n;
                bool isNum = int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out n);
                switch (k)
                {
                    case "font": if (v.Trim() != "") Th.Font = v.Trim(); break;
                    case "text": Th.Text = Th.Hex(v, Th.Text); break;
                    case "dim": Th.Dim = Th.Hex(v, Th.Dim); break;
                    case "accent": Th.Accent = Th.Hex(v, Th.Accent); break;
                    case "accent2": Th.Accent2 = Th.Hex(v, Th.Accent2); break;
                    case "panel": Th.Panel = Th.Hex(v, Th.Panel); break;
                    case "panel2": Th.Panel2 = Th.Hex(v, Th.Panel2); break;
                    case "line": Th.Line = Th.Hex(v, Th.Line); break;
                    case "ok": Th.Ok = Th.Hex(v, Th.Ok); break;
                    case "bad": Th.Bad = Th.Hex(v, Th.Bad); break;
                    case "warn": Th.Warn = Th.Hex(v, Th.Warn); break;
                    case "hudtext": Th.HudText = Th.Hex(v, Th.HudText); break;
                    case "hudborder": Th.HudBorder = Th.Hex(v, Th.HudBorder); break;
                    case "border": Th.Border = v == "1"; break;
                    case "bg": Th.Bg = v == "1"; break;
                    case "glow": Th.Glow = v == "1"; break;
                    case "opacity": if (isNum) Th.Opacity = Math.Max(0, Math.Min(255, n)); break;
                    case "streamer": Th.Streamer = v == "1"; break;
                    case "toastpos": Th.ToastPos = v; break;
                    case "pillh": if (isNum) PillH = Math.Max(10, Math.Min(80, n)); break;
                }
            }
            if (Th.Font != oldFont) P.ClearFonts();
            Th.Gen++;
            if (oldStream != Th.Streamer)
                foreach (Item it in All()) it.Win.ApplyAffinity();
            RerenderAll();
        }

        IEnumerable<Item> All()
        {
            foreach (Item it in pills.Values) yield return it;
            if (card != null) yield return card;
            foreach (Item it in toasts) yield return it;
        }

        void SetEditing(bool on)
        {
            if (on == Editing) return;
            Editing = on;
            foreach (Item it in pills.Values) { it.Win.SetThrough(!on); if (!on) it.Touched = false; }
            if (card != null) { card.Win.SetThrough(!(on || CardEdit)); if (!on && !CardEdit) card.Touched = false; }
            RerenderAll();
        }

        public void RerenderAll()
        {
            foreach (Item it in pills.Values) if (it.Target > 0 || it.A > 0) Rerender(it, true);
            if (card != null && (card.Target > 0 || card.A > 0)) Rerender(card, true);
        }

        Item NewItem(string key)
        {
            Item it = new Item();
            it.Key = key;
            it.Win = new Layer(this, it);
            it.Win.SetThrough(!Editing);
            return it;
        }

        // draw an item's frame if its content changed, then show it at its spot
        public void Rerender(Item it, bool push)
        {
            Frame fr = null;
            string sig;
            if (it.IsCard)
            {
                if (it.Card == null) return;
                bool ed = Editing || CardEdit;
                sig = it.Card.Sig + "|" + it.Card.CtSig() + "|" + it.Size + "|" + ed + "|" + Th.Gen + "|" + Th.Fx.ToArgb();
                if (sig != it.Sig) fr = it.Card.Bar ? Render.Bar(it.Card, it.Size, ed) : Render.Card(it.Card, it.Size, ed);
            }
            else
            {
                if (it.Pill == null) return;
                PillSpec p = it.Pill;
                sig = p.Text + "|" + p.Tc.ToArgb() + "|" + p.Ic.ToArgb() + "|" + p.Mark.ToArgb() + "|" + p.Icon + "|" + it.Size + "|" + Editing + "|" + Th.Gen + "|" + Th.Fx.ToArgb();
                if (sig != it.Sig) fr = Render.Pill(p, it.Size, Editing);
            }
            if (fr != null)
            {
                it.Win.SetFrame(fr.Bmp);
                it.BW = fr.BodyW; it.BH = fr.BodyH; it.M = fr.M; it.Grip = fr.Grip;
                fr.Bmp.Dispose();
                it.Sig = sig;
            }
            if (push && it.A > 0) it.Win.Push(it.X - it.M, it.Y - it.M, it.A);
        }

        void FadeTo(Item it, float target)
        {
            it.Target = target;
            if (Math.Abs(it.A - target) > 0.001f) StartAnim();
        }

        void StartAnim()
        {
            if (!anim.Enabled) { lastStep = Environment.TickCount; anim.Interval = 15; anim.Start(); }
            else if (anim.Interval > 15) anim.Interval = 15;
        }

        // ---- pills -------------------------------------------------------------------
        // head: pills show editing ax ay vertical gap pillH defSize
        // line: key icon text textcol iconcol saved x y size hide
        void DoPills(string[] head, string[] lines)
        {
            bool show = S(head, 1) == "1";
            SetEditing(S(head, 2) == "1");
            int ax = I(head, 3, 0), ay = I(head, 4, 0);
            bool vertical = S(head, 5) == "1";
            int gap = I(head, 6, 4);
            int ph = I(head, 7, 24);
            int defSize = Math.Max(6, Math.Min(48, I(head, 8, 9)));
            if (ph != (int)PillH) { PillH = ph; Th.Gen++; }
            HashSet<string> seen = new HashSet<string>();
            for (int i = 1; i < lines.Length; i++)
            {
                string[] a = lines[i].Split('\t');
                if (a.Length < 10 || a[0] == "") continue;
                PillSpec sp = new PillSpec();
                sp.Key = a[0]; sp.Icon = I(a, 1, 0x25C9); sp.Text = a[2];
                sp.Tc = Th.Hex(a[3], Th.HudText); sp.Ic = Th.Hex(a[4], Th.Dim);
                sp.Saved = a[5] == "1"; sp.X = I(a, 6, 0); sp.Y = I(a, 7, 0);
                sp.Size = Math.Max(6, Math.Min(48, I(a, 8, defSize))); sp.Hide = a[9] == "1";
                sp.Mark = Th.Hex(S(a, 10));                     // bottom bar colour, "" = none
                seen.Add(sp.Key);
                Item it;
                if (!pills.TryGetValue(sp.Key, out it)) { it = NewItem(sp.Key); pills[sp.Key] = it; }
                it.Pill = sp;
                bool want = show && (!sp.Hide || Editing);
                if (!want) { FadeTo(it, 0f); continue; }
                if (!it.Touched) it.Size = sp.Saved ? sp.Size : defSize;
                Rerender(it, false);                            // sizes known from here on
                if (!it.Touched)
                {
                    if (sp.Saved) { it.X = sp.X; it.Y = sp.Y; }
                    else
                    {
                        it.X = ax; it.Y = ay;
                        if (vertical) ay += it.BH + gap; else ax += it.BW + gap;
                    }
                }
                if (it.A > 0) it.Win.Push(it.X - it.M, it.Y - it.M, it.A);
                FadeTo(it, 1f);
            }
            List<string> drop = new List<string>();
            foreach (string k in pills.Keys) if (!seen.Contains(k)) drop.Add(k);
            foreach (string k in drop) { pills[k].Win.Dispose(); pills.Remove(k); }
            QueueReport();
        }

        // ---- stats card ----------------------------------------------------------------
        // head: card show editing x y size graph
        void DoCard(string[] head, string[] lines)
        {
            bool show = S(head, 1) == "1";
            SetEditing(S(head, 2) == "1");
            if (card == null) { card = NewItem("stats"); card.IsCard = true; }
            // head 7: the card alone is being moved (pills untouched); head 8: go to x y now
            bool ce = S(head, 7) == "1", jump = S(head, 8) == "1";
            if (ce != CardEdit)
            {
                CardEdit = ce;
                card.Win.SetThrough(!(Editing || CardEdit));
                if (!Editing && !CardEdit) card.Touched = false;
            }
            if (!show) { FadeTo(card, 0f); QueueReport(); return; }
            CardSpec c = new CardSpec();
            c.Graph = S(head, 6) == "1";
            StringBuilder sig = new StringBuilder(c.Graph ? "g" : "n");
            for (int i = 1; i < lines.Length; i++)
            {
                string[] a = lines[i].Split('\t');
                sig.Append('\n').Append(lines[i]);
                switch (a[0])
                {
                    case "m": if (a.Length >= 5) c.Cells.Add(new string[] { a[1], a[2], a[3], a[4] }); break;
                    case "main": c.Main = Csv(S(a, 1)); break;
                    case "faint": c.Faint = Csv(S(a, 1)); break;
                    case "fps": c.Fps = Csv(S(a, 1)); c.FpsC = Th.Hex(S(a, 2)); break;
                    case "tag": c.Tag = S(a, 1); c.TagC = Th.Hex(S(a, 2)); break;
                    case "foot": c.Foot = S(a, 1); c.FootC = Th.Hex(S(a, 2)); break;
                    case "host": c.Host = S(a, 1); break;
                    case "ct":
                        c.CtOn = true; c.CtReal = S(a, 1); c.CtFont = S(a, 2) == "" ? "Consolas" : S(a, 2);
                        c.CtBold = S(a, 3) == "1"; c.CtScale = Math.Max(50, Math.Min(300, I(a, 4, 100)));
                        c.CtC = Th.Hex(S(a, 5), Th.HudText); c.CtA = Th.Hex(S(a, 6), Th.Accent);
                        c.CtCursorRoom = S(a, 7) == "1";
                        c.CtOutline = S(a, 8) == "1"; c.CtOC = Th.Hex(S(a, 9), Th.Accent);
                        c.CtBg = Th.Hex(S(a, 10), Th.Panel2); c.CtAlpha = Math.Max(0, Math.Min(255, I(a, 11, 0)));
                        break;
                    case "logo": c.Logo = S(a, 1); c.LogoC = Th.Hex(S(a, 2), Th.Accent); break;
                    case "ctf": c.CtTxt = S(a, 1); c.CtMask = S(a, 2); c.CtCur = I(a, 3, -1); break;
                    case "bar": c.Bar = S(a, 1) == "1"; c.BarText = Th.Hex(S(a, 2), Th.HudText); break;
                    case "bi": if (a.Length >= 7) c.BarItems.Add(new string[] { a[1], a[2], a[3], a[4], a[5], a[6] }); break;
                }
            }
            c.Sig = sig.ToString();
            card.Card = c;
            bool keep = (Editing || CardEdit) && card.Touched && !jump;   // being edited: don't yank it back
            if (!keep)
            {
                card.Size = Math.Max(6, Math.Min(48, I(head, 5, 11)));
                card.X = I(head, 3, 0); card.Y = I(head, 4, 30);
            }
            Rerender(card, false);
            if (card.A > 0) card.Win.Push(card.X - card.M, card.Y - card.M, card.A);
            FadeTo(card, 1f);
            QueueReport();
        }

        static List<int> Csv(string s)
        {
            List<int> o = new List<int>();
            foreach (string p in s.Split(','))
            {
                int v;
                if (int.TryParse(p, NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) o.Add(v);
            }
            return o;
        }

        // ---- toasts --------------------------------------------------------------------
        // head: toast kind title body ms left top right bottom
        void DoToast(string[] head)
        {
            int l = I(head, 5, 0), t = I(head, 6, 0), r = I(head, 7, 0), b = I(head, 8, 0);
            if (r > l + 100 && b > t + 100) { toastL = l; toastT = t; toastR = r; toastB = b; }
            Frame fr = Render.Toast(S(head, 1), S(head, 2), S(head, 3));
            Item it = NewItem("toast");
            it.IsToast = true;
            it.Win.SetThrough(true);
            it.Win.SetFrame(fr.Bmp);
            it.BW = fr.BodyW; it.BH = fr.BodyH; it.M = fr.M;
            fr.Bmp.Dispose();
            it.Until = Environment.TickCount + Math.Max(1500, Math.Min(20000, I(head, 4, 4000)));
            toasts.Insert(0, it);
            int live = 0;
            foreach (Item x in toasts) if (!x.Leaving) live++;
            for (int i = toasts.Count - 1; i >= 0 && live > 4; i--)
                if (!toasts[i].Leaving) { toasts[i].Leaving = true; live--; }
            LayoutToasts();
            StartAnim();
        }

        bool ToastBottom() { return Th.ToastPos == "br" || Th.ToastPos == "bl"; }

        void LayoutToasts()
        {
            float f = Th.Dpi / 96f;
            int margin = (int)(24 * f), gap = (int)(10 * f);
            float acc = 0;
            foreach (Item it in toasts)
            {
                if (it.Leaving) { if (!it.HasY) { it.CurY = it.TargetY; it.HasY = true; } continue; }
                it.TargetY = ToastBottom() ? toastB - margin - it.BH - acc : toastT + margin + acc;
                if (!it.HasY) { it.CurY = it.TargetY; it.HasY = true; }
                acc += it.BH + gap;
            }
        }

        void PlaceToast(Item it)
        {
            float f = Th.Dpi / 96f;
            int margin = (int)(24 * f);
            float e = 1f - (float)Math.Pow(1f - it.Slide, 3);       // ease-out
            float x, y = it.CurY;
            switch (Th.ToastPos)
            {
                case "tl":
                case "bl":
                    x = toastL + margin - (1 - e) * (it.BW + margin); break;
                case "tc":
                    x = (toastL + toastR - it.BW) / 2f; y = it.CurY - (1 - e) * (it.BH + margin); break;
                default:
                    x = toastR - margin - it.BW + (1 - e) * (it.BW + margin); break;
            }
            it.Win.Push((int)Math.Round(x) - it.M, (int)Math.Round(y) - it.M, e);
        }

        // ---- the animation timer: fades and toast slides only --------------------------
        void Step()
        {
            long now = Environment.TickCount;
            float dt = Math.Max(1, Math.Min(100, now - lastStep));
            lastStep = now;
            bool moving = false;
            float fadeStep = dt / 140f;
            foreach (Item it in All())
            {
                if (it.IsToast) continue;
                if (Math.Abs(it.A - it.Target) <= 0.001f) continue;
                it.A = it.A < it.Target ? Math.Min(it.Target, it.A + fadeStep) : Math.Max(it.Target, it.A - fadeStep);
                if (it.A <= 0.001f) { it.A = 0; it.Win.HideNow(); }
                else it.Win.Push(it.X - it.M, it.Y - it.M, it.A);
                if (Math.Abs(it.A - it.Target) > 0.001f) moving = true;
            }
            bool relayout = false;
            long nextDue = long.MaxValue;
            for (int i = toasts.Count - 1; i >= 0; i--)
            {
                Item t = toasts[i];
                if (!t.Leaving && now >= t.Until) { t.Leaving = true; relayout = true; }
                float want = t.Leaving ? 0f : 1f;
                bool changed = false;
                if (Math.Abs(t.Slide - want) > 0.001f)
                {
                    float sp = dt / (t.Leaving ? 200f : 260f);
                    t.Slide = t.Slide < want ? Math.Min(want, t.Slide + sp) : Math.Max(want, t.Slide - sp);
                    changed = true;
                }
                if (Math.Abs(t.CurY - t.TargetY) > 0.5f)
                {
                    t.CurY += (t.TargetY - t.CurY) * Math.Min(1f, dt / 90f);
                    changed = true;
                }
                else t.CurY = t.TargetY;
                if (changed) { PlaceToast(t); moving = true; }
                if (t.Leaving && t.Slide <= 0.001f)
                {
                    t.Win.Dispose();
                    toasts.RemoveAt(i);
                    relayout = true;
                    continue;
                }
                if (!t.Leaving) nextDue = Math.Min(nextDue, t.Until);
            }
            if (relayout) { LayoutToasts(); moving = true; }
            if (moving) { anim.Interval = 15; return; }
            if (nextDue != long.MaxValue)
            {
                anim.Interval = (int)Math.Max(15, Math.Min(60000, nextDue - now));   // sleep until the next toast is due
                return;
            }
            anim.Stop();
        }
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
#if TESTRENDER
            Test.Run();
            return;
#else
            try { N.SetProcessDPIAware(); } catch { }
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Th.Dpi = g.DpiY;
            long ph = 0; int pid = 0;
            if (args.Length >= 1) long.TryParse(args[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out ph);
            if (args.Length >= 2) int.TryParse(args[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out pid);
            if (ph == 0) return;                          // not started by ArkSense
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Host host = null;
            Application.ThreadException += delegate(object s, System.Threading.ThreadExceptionEventArgs e)
            {
                if (host != null) host.Log("error: " + e.Exception.Message);
            };
            host = new Host(new IntPtr(ph), pid);
            Application.Run();
#endif
        }
    }
}
