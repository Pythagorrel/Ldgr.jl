// RETIRED (2026-10-09): ldgr.ico and favicon.ico now come from packaging\brand\icon\. Do not run this tool: it would overwrite them with the old mark.
// MakeIcon.cs - draws the LDGR brand mark (document glyph on a rounded green square,
// as in public/index.html .brand-mark) and writes ldgr.ico, favicon.ico and preview.png.
// C# 5, System.Drawing.  Usage: MakeIcon.exe <output folder>
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

static class MakeIcon
{
    static readonly Color Green = Color.FromArgb(0x1F, 0x6F, 0x5C);

    // The form's mark: 38 px square, 11 px radius, 20 px glyph on a 24-unit
    // viewBox, stroke 1.8, white. Same proportions here; the glyph is enlarged
    // a little at small sizes so the strokes survive.
    static Bitmap Render(int size)
    {
        int ss = size >= 64 ? 1 : 4;
        int n = size * ss;
        Bitmap big = new Bitmap(n, n, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(big))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);

            float margin = size <= 24 ? 0.5f * ss : (size <= 48 ? 1f * ss : size / 32f * ss);
            float side = n - 2 * margin;
            float radius = side * (11f / 38f);
            using (GraphicsPath sq = Rounded(margin, margin, side, side, radius))
            using (SolidBrush b = new SolidBrush(Green))
                g.FillPath(b, sq);

            float frac = size <= 16 ? 0.80f : size <= 20 ? 0.66f : (size <= 32 ? 0.60f : (size <= 48 ? 0.56f : 0.526f));
            float glyph = side * frac;
            float k = glyph / 24f;
            float ox = margin + (side - glyph) / 2f;
            float oy = margin + (side - glyph) / 2f;
            float sw = 1.8f * k;
            float minSw = size <= 16 ? 1.25f : (size <= 24 ? 1.15f : 1.0f);
            if (size <= 16) sw = 1.0f * ss;   // k = 0.5 puts strokes on pixel centres
            else if (sw < minSw * ss) sw = minSw * ss;

            using (Pen p = new Pen(Color.White, sw))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                // M6 3h8l5 5v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z
                using (GraphicsPath o = new GraphicsPath())
                {
                    o.StartFigure();
                    o.AddLine(P(6, 3, k, ox, oy), P(14, 3, k, ox, oy));
                    o.AddLine(P(14, 3, k, ox, oy), P(19, 8, k, ox, oy));
                    o.AddLine(P(19, 8, k, ox, oy), P(19, 20, k, ox, oy));
                    o.AddArc(ox + 17 * k, oy + 19 * k, 2 * k, 2 * k, 0, 90);
                    o.AddLine(P(18, 21, k, ox, oy), P(6, 21, k, ox, oy));
                    o.AddArc(ox + 5 * k, oy + 19 * k, 2 * k, 2 * k, 90, 90);
                    o.AddLine(P(5, 20, k, ox, oy), P(5, 4, k, ox, oy));
                    o.AddArc(ox + 5 * k, oy + 3 * k, 2 * k, 2 * k, 180, 90);
                    o.CloseFigure();
                    g.DrawPath(p, o);
                }
                g.DrawLines(p, new PointF[] { P(14, 3, k, ox, oy), P(14, 8, k, ox, oy), P(19, 8, k, ox, oy) });
                g.DrawLine(p, P(8.5f, 13, k, ox, oy), P(15.5f, 13, k, ox, oy));
                g.DrawLine(p, P(8.5f, 17, k, ox, oy), P(13, 17, k, ox, oy));
            }
        }
        if (ss == 1) return big;
        Bitmap small = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                double a = 0, r = 0, gg = 0, bb = 0;
                for (int dy = 0; dy < ss; dy++)
                    for (int dx = 0; dx < ss; dx++)
                    {
                        Color c = big.GetPixel(x * ss + dx, y * ss + dy);
                        a += c.A; r += c.R * c.A; gg += c.G * c.A; bb += c.B * c.A;
                    }
                int cnt = ss * ss;
                if (a <= 0) { small.SetPixel(x, y, Color.FromArgb(0, 0, 0, 0)); continue; }
                small.SetPixel(x, y, Color.FromArgb((int)Math.Round(a / cnt), (int)Math.Round(r / a), (int)Math.Round(gg / a), (int)Math.Round(bb / a)));
            }
        big.Dispose();
        return small;
    }

    static PointF P(float x, float y, float k, float ox, float oy) { return new PointF(ox + x * k, oy + y * k); }

    static GraphicsPath Rounded(float x, float y, float w, float h, float r)
    {
        GraphicsPath p = new GraphicsPath();
        float d = r * 2;
        p.AddArc(x, y, d, d, 180, 90);
        p.AddArc(x + w - d, y, d, d, 270, 90);
        p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        p.AddArc(x, y + h - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    static byte[] Png(Bitmap b)
    {
        using (MemoryStream ms = new MemoryStream()) { b.Save(ms, ImageFormat.Png); return ms.ToArray(); }
    }

    static byte[] Dib(Bitmap b)
    {
        int s = b.Width;
        int maskRow = ((s + 31) / 32) * 4;
        using (MemoryStream ms = new MemoryStream())
        using (BinaryWriter w = new BinaryWriter(ms))
        {
            w.Write(40); w.Write(s); w.Write(s * 2); w.Write((short)1); w.Write((short)32);
            w.Write(0); w.Write(s * s * 4 + maskRow * s); w.Write(0); w.Write(0); w.Write(0); w.Write(0);
            for (int y = s - 1; y >= 0; y--)
                for (int x = 0; x < s; x++)
                {
                    Color c = b.GetPixel(x, y);
                    w.Write(c.B); w.Write(c.G); w.Write(c.R); w.Write(c.A);
                }
            w.Write(new byte[maskRow * s]);
            w.Flush();
            return ms.ToArray();
        }
    }

    static void WriteIco(string path, int[] sizes)
    {
        List<byte[]> data = new List<byte[]>();
        foreach (int s in sizes)
        {
            using (Bitmap b = Render(s)) data.Add(s >= 256 ? Png(b) : Dib(b));
        }
        using (FileStream fs = new FileStream(path, FileMode.Create))
        using (BinaryWriter w = new BinaryWriter(fs))
        {
            w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++)
            {
                int s = sizes[i];
                w.Write((byte)(s >= 256 ? 0 : s)); w.Write((byte)(s >= 256 ? 0 : s));
                w.Write((byte)0); w.Write((byte)0); w.Write((short)1); w.Write((short)32);
                w.Write(data[i].Length); w.Write(offset);
                offset += data[i].Length;
            }
            foreach (byte[] d in data) w.Write(d);
        }
    }

    static void WritePreview(string path, int[] sizes)
    {
        int pad = 24, total = pad;
        foreach (int s in sizes) total += s + pad;
        int h = 256 + pad * 2;
        int zoomH = 32 * 4 + pad;
        using (Bitmap bmp = new Bitmap(total, h + zoomH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.White);
            int x = pad;
            foreach (int s in sizes)
            {
                using (Bitmap b = Render(s)) g.DrawImageUnscaled(b, x, pad + (256 - s));
                x += s + pad;
            }
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            int zx = pad;
            foreach (int s in new int[] { 16, 20, 24, 32 })
            {
                using (Bitmap b = Render(s)) g.DrawImage(b, new Rectangle(zx, h, s * 4, s * 4));
                zx += s * 4 + pad;
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    static int Main(string[] args)
    {
        string dir = args.Length > 0 ? args[0] : ".";
        Directory.CreateDirectory(dir);
        int[] all = new int[] { 16, 20, 24, 32, 40, 48, 64, 96, 128, 256 };
        WriteIco(Path.Combine(dir, "ldgr.ico"), all);
        WriteIco(Path.Combine(dir, "favicon.ico"), new int[] { 16, 32, 48 });
        WritePreview(Path.Combine(dir, "preview.png"), all);
        Console.WriteLine("wrote ldgr.ico, favicon.ico, preview.png in " + dir);
        return 0;
    }
}
