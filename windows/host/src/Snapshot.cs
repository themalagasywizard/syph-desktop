using System.Drawing;

namespace Syph.Host;

/// <summary>
/// What the agent sees: the monitor with the front window, every control boxed and numbered,
/// and the list of those controls in the screenshot's own pixels. Password fields are blacked
/// out before anything leaves the PC.
/// </summary>
public static class Snapshot
{
    private static byte[]? _lastFingerprint;

    public static object Take(Args a)
    {
        var explicitWindow = a.Has("window") || a.Has("app") || a.Has("handle");
        var fg = explicitWindow ? WindowManager.Find(a) : Native.GetForegroundWindow();
        if (explicitWindow) WindowManager.Focus(fg);

        Rectangle area;
        string label;
        if (a.Has("monitor"))
        {
            area = Screens.Target(a, out label);
        }
        else
        {
            var m = fg != IntPtr.Zero ? Screens.MonitorOfWindow(fg) : Screens.Monitors()[0];
            area = new Rectangle(m.Left, m.Top, m.Width, m.Height);
            label = $"monitor {m.Index}";
        }

        using var full = Screens.Grab(area);
        List<Element> elements = [];
        string? uiaNote = null;
        try
        {
            var windows = fg != IntPtr.Zero ? Uia.FrontWindows(fg) : [];
            elements = Uia.Elements(windows, a.Int("limit", 150), a.Bool("interactive", false))
                .Where(e => area.Contains(e.X, e.Y)).ToList();
        }
        catch (Exception e) { uiaNote = $"Controls could not be listed ({e.Message}); use x/y from the image."; }

        var redacted = Marks.Redact(full, area.Left, area.Top, elements);
        var fingerprint = Screens.Fingerprint(full);
        var changed = _lastFingerprint is null ? (bool?)null : Screens.Changed(_lastFingerprint, fingerprint);
        _lastFingerprint = fingerprint;

        List<OcrLine>? lines = null;
        if (a.Bool("ocr", false)) lines = Ocr.Read(full, area.Left, area.Top);

        var (image, scale) = Screens.Fit(full, a.Int("maxSide", 1568));
        using (image)
        {
            var t = new ImageTransform(area.Left, area.Top, scale, image.Width, image.Height);
            Screens.Last = t;
            if (a.Bool("marks", true)) Marks.Draw(image, t, elements);
            var front = fg != IntPtr.Zero && Native.IsWindow(fg) ? WindowManager.Describe(fg) : null;
            var focused = Uia.Focused();
            return new
            {
                width = image.Width,
                height = image.Height,
                scale = Math.Round(scale, 4),
                screen = label,
                monitors = Screens.Monitors().Count,
                app = front?.App,
                window = front?.Title,
                handle = front?.Handle,
                focused = focused is null || !area.Contains(focused.X, focused.Y) ? null : InImage(focused, t),
                elements = elements.Select(e => InImage(e, t)),
                windows = WindowManager.List().Take(10).Select(w => new { app = w.App, title = w.Title, handle = w.Handle, state = w.State, monitor = w.Monitor }),
                text = lines?.Select(l => { var (x, y) = t.ToImage(l.X, l.Y); return new { text = l.Text, x = (int)x, y = (int)y }; }),
                redacted = redacted > 0 ? redacted : (int?)null,
                changed,
                note = uiaNote ?? (lines is not null ? Ocr.Unavailable : null),
                _image = Screens.Jpeg(image, a.Int("quality", 72)),
            };
        }
    }

    /// <summary>An element described in screenshot pixels, compact for the model.</summary>
    public static object InImage(Element e, ImageTransform t)
    {
        var (x, y) = t.ToImage(e.X, e.Y);
        return new
        {
            id = e.Id, role = e.Role, name = e.Name.Length > 0 ? e.Name : null, value = e.Value,
            x = (int)Math.Round(x), y = (int)Math.Round(y), w = (int)Math.Round(e.W / t.Scale), h = (int)Math.Round(e.H / t.Scale),
            state = e.State, disabled = e.Enabled ? (bool?)null : true, focused = e.Focused ? true : (bool?)null,
            password = e.Password ? true : (bool?)null,
            actions = e.Actions.Length > 0 ? e.Actions : null,
        };
    }
}
