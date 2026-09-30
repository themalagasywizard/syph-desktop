using System.Diagnostics;

namespace Syph.Host;

/// <summary>Waiting on the screen instead of sleeping: until a control, text or window
/// appears (or goes), or until the screen stops changing.</summary>
public static class Waits
{
    public static object Wait(Args a)
    {
        var until = (a.Str("until") ?? "stable").ToLowerInvariant();
        var text = a.Str("text") ?? a.Str("name") ?? "";
        var timeout = TimeSpan.FromSeconds(Math.Clamp(a.Num("timeout") ?? 15, 0.5, 60));
        var sw = Stopwatch.StartNew();
        if (until is not "stable" && text.Length == 0) throw new HostError($"wait_for {until} needs text: the words to wait for.", "invalid_input");

        while (true)
        {
            var (done, detail) = until switch
            {
                "stable" => (Stable(a.Int("quiet", 500)), "The screen settled."),
                "element" => Element(text, a.Str("role"), present: true),
                "gone" => Element(text, a.Str("role"), present: false),
                "text" => Text(text),
                "window" => Window(text),
                _ => throw new HostError($"Unknown wait '{until}'. Use element, gone, text, window or stable.", "invalid_input"),
            };
            if (done) return new { ok = true, summary = detail, data = new { until, waited_ms = sw.ElapsedMilliseconds } };
            if (sw.Elapsed > timeout)
                return new { ok = false, summary = $"Waited {timeout.TotalSeconds:0.#}s; {Describe(until, text)} did not happen.", data = new { until, waited_ms = sw.ElapsedMilliseconds } };
            Thread.Sleep(until == "stable" ? 0 : 250);
        }
    }

    private static string Describe(string until, string text) => until switch
    {
        "element" => $"no control named '{text}' appeared",
        "gone" => $"'{text}' is still there",
        "text" => $"'{text}' is not on screen",
        "window" => $"no window titled '{text}' opened",
        _ => "the screen kept changing",
    };

    /// <summary>True once the front monitor looks the same for <paramref name="quietMs"/>.</summary>
    public static bool Stable(int quietMs = 500, int maxMs = 1500)
    {
        var sw = Stopwatch.StartNew();
        var fg = Native.GetForegroundWindow();
        var m = fg != IntPtr.Zero ? Screens.MonitorOfWindow(fg) : Screens.Monitors()[0];
        var area = new System.Drawing.Rectangle(m.Left, m.Top, m.Width, m.Height);
        byte[] last;
        using (var b = Screens.Grab(area)) last = Screens.Fingerprint(b);
        var quietSince = sw.ElapsedMilliseconds;
        while (sw.ElapsedMilliseconds < maxMs)
        {
            Thread.Sleep(100);
            byte[] now;
            using (var b = Screens.Grab(area)) now = Screens.Fingerprint(b);
            if (Screens.Changed(last, now)) quietSince = sw.ElapsedMilliseconds;
            last = now;
            if (sw.ElapsedMilliseconds - quietSince >= quietMs) return true;
        }
        return false;
    }

    private static (bool, string) Element(string name, string? role, bool present)
    {
        var fg = Native.GetForegroundWindow();
        var match = fg == IntPtr.Zero ? null : Uia.Find(Uia.Elements(Uia.FrontWindows(fg), 1500, false), name, role);
        return present
            ? (match is not null, match is null ? "" : $"{match.Role} '{match.Name}' is there (element {match.Id}).")
            : (match is null, $"'{name}' is gone.");
    }

    private static (bool, string) Text(string text)
    {
        var fg = Native.GetForegroundWindow();
        var m = fg != IntPtr.Zero ? Screens.MonitorOfWindow(fg) : Screens.Monitors()[0];
        using var bmp = Screens.Grab(new System.Drawing.Rectangle(m.Left, m.Top, m.Width, m.Height));
        var lines = Ocr.Read(bmp, m.Left, m.Top);
        var hit = lines.FirstOrDefault(l => l.Text.Contains(text, StringComparison.OrdinalIgnoreCase));
        return (hit is not null, hit is null ? "" : $"'{hit.Text}' is on screen.");
    }

    private static (bool, string) Window(string title)
    {
        var w = WindowManager.List().FirstOrDefault(w => w.Title.Contains(title, StringComparison.OrdinalIgnoreCase) || w.App.Equals(title, StringComparison.OrdinalIgnoreCase));
        return (w is not null, w is null ? "" : $"'{w.Title}' is open.");
    }
}
