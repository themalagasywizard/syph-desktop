using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Syph.Host;

public sealed record MonitorInfo(int Index, string Device, bool Primary, int Left, int Top, int Width, int Height,
    int WorkLeft, int WorkTop, int WorkWidth, int WorkHeight, int Dpi, double ScalePercent);

/// <summary>How an image the agent saw maps back to screen pixels:
/// screen = (Left + x * Scale, Top + y * Scale).</summary>
public sealed record ImageTransform(int Left, int Top, double Scale, int Width, int Height)
{
    public (int X, int Y) ToScreen(double x, double y) => ((int)Math.Round(Left + x * Scale), (int)Math.Round(Top + y * Scale));
    public (double X, double Y) ToImage(int x, int y) => ((x - Left) / Scale, (y - Top) / Scale);
}

public static class Screens
{
    /// <summary>The transform of the last image handed to the agent, so it can click in image coordinates.</summary>
    public static ImageTransform? Last { get; set; }

    public static List<MonitorInfo> Monitors()
    {
        var list = new List<MonitorInfo>();
        Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr _, ref Native.RECT _, IntPtr _) =>
        {
            var info = new Native.MONITORINFOEX { cbSize = Marshal.SizeOf<Native.MONITORINFOEX>() };
            if (Native.GetMonitorInfo(h, ref info))
            {
                uint dpi = 96;
                try { Native.GetDpiForMonitor(h, 0, out dpi, out _); } catch { /* pre-8.1 */ }
                var m = info.rcMonitor; var w = info.rcWork;
                list.Add(new MonitorInfo(list.Count, info.szDevice, (info.dwFlags & 1) != 0, m.Left, m.Top, m.Width, m.Height,
                    w.Left, w.Top, w.Width, w.Height, (int)dpi, Math.Round(dpi / 96.0 * 100)));
            }
            return true;
        }, IntPtr.Zero);
        // Primary first, then left to right: "monitor 0" is what people call their main screen.
        list = list.OrderByDescending(m => m.Primary).ThenBy(m => m.Left).ThenBy(m => m.Top)
            .Select((m, i) => m with { Index = i }).ToList();
        return list;
    }

    public static MonitorInfo MonitorAt(int x, int y)
    {
        var all = Monitors();
        return all.FirstOrDefault(m => x >= m.Left && x < m.Left + m.Width && y >= m.Top && y < m.Top + m.Height) ?? all[0];
    }

    public static MonitorInfo MonitorOfWindow(IntPtr hwnd)
    {
        var r = Native.FrameRect(hwnd);
        return MonitorAt(r.Left + r.Width / 2, r.Top + r.Height / 2);
    }

    /// <summary>Resolves what to capture: a monitor index, "all", a window, or the monitor of the foreground window.</summary>
    public static Rectangle Target(Args a, out string label)
    {
        var mon = a.Str("monitor");
        if (mon == "all")
        {
            var v = Native.VirtualScreen();
            label = "all screens";
            return new Rectangle(v.Left, v.Top, v.Width, v.Height);
        }
        if (a.IntOrNull("monitor") is int index)
        {
            var all = Monitors();
            if (index < 0 || index >= all.Count) throw new HostError($"There is no monitor {index}; this PC has {all.Count}.", "invalid_input");
            var m = all[index];
            label = $"monitor {index}";
            return new Rectangle(m.Left, m.Top, m.Width, m.Height);
        }
        if (a.Has("region"))
        {
            var r = a.Obj("region");
            label = "region";
            return new Rectangle(r.Int("x", 0), r.Int("y", 0), Math.Max(1, r.Int("w", 1)), Math.Max(1, r.Int("h", 1)));
        }
        var fg = Native.GetForegroundWindow();
        var mi = fg != IntPtr.Zero ? MonitorOfWindow(fg) : Monitors()[0];
        label = $"monitor {mi.Index}";
        return new Rectangle(mi.Left, mi.Top, mi.Width, mi.Height);
    }

    /// <summary>Copies a screen rectangle (physical pixels) into a bitmap.</summary>
    public static Bitmap Grab(Rectangle area)
    {
        var bmp = new Bitmap(area.Width, area.Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.CopyFromScreen(area.Left, area.Top, 0, 0, area.Size, CopyPixelOperation.SourceCopy);
        return bmp;
    }

    /// <summary>Renders one window even when it is covered (PW_RENDERFULLCONTENT handles GPU-drawn apps).</summary>
    public static Bitmap GrabWindow(IntPtr hwnd, out Rectangle bounds)
    {
        Native.GetWindowRect(hwnd, out var r);
        bounds = new Rectangle(r.Left, r.Top, Math.Max(1, r.Width), Math.Max(1, r.Height));
        var bmp = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        var hdc = g.GetHdc();
        try { if (!Native.PrintWindow(hwnd, hdc, 2)) Native.PrintWindow(hwnd, hdc, 0); }
        finally { g.ReleaseHdc(hdc); }
        return bmp;
    }

    /// <summary>Downscales so the long side is at most maxSide; returns the new bitmap and the scale (screen px per image px).</summary>
    public static (Bitmap Image, double Scale) Fit(Bitmap source, int maxSide)
    {
        var longSide = Math.Max(source.Width, source.Height);
        if (maxSide <= 0 || longSide <= maxSide) return (new Bitmap(source), 1.0);
        var ratio = (double)maxSide / longSide;
        var w = Math.Max(1, (int)Math.Round(source.Width * ratio));
        var h = Math.Max(1, (int)Math.Round(source.Height * ratio));
        var small = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(small);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.DrawImage(source, 0, 0, w, h);
        return (small, (double)source.Width / w);
    }

    public static string Jpeg(Bitmap bmp, long quality)
    {
        var codec = ImageCodecInfo.GetImageEncoders().First(c => c.MimeType == "image/jpeg");
        using var p = new EncoderParameters(1);
        p.Param[0] = new EncoderParameter(Encoder.Quality, Math.Clamp(quality, 20L, 95L));
        using var ms = new MemoryStream();
        bmp.Save(ms, codec, p);
        return Convert.ToBase64String(ms.ToArray());
    }

    public static string Png(Bitmap bmp)
    {
        using var ms = new MemoryStream();
        bmp.Save(ms, ImageFormat.Png);
        return Convert.ToBase64String(ms.ToArray());
    }

    /// <summary>A cheap perceptual fingerprint (16x16 grey) used to tell whether the screen changed.</summary>
    public static byte[] Fingerprint(Bitmap bmp)
    {
        using var tiny = new Bitmap(16, 16, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(tiny))
        {
            g.InterpolationMode = InterpolationMode.Bilinear;
            g.DrawImage(bmp, 0, 0, 16, 16);
        }
        var bytes = new byte[256];
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++)
            {
                var c = tiny.GetPixel(x, y);
                bytes[y * 16 + x] = (byte)((c.R * 30 + c.G * 59 + c.B * 11) / 100);
            }
        return bytes;
    }

    /// <summary>Mean absolute difference between two fingerprints, 0..255.</summary>
    public static double Difference(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return 255;
        double sum = 0;
        for (int i = 0; i < a.Length; i++) sum += Math.Abs(a[i] - b[i]);
        return sum / a.Length;
    }
}
