using System.Diagnostics;
using static Syph.Host.Native;

namespace Syph.Host;

public sealed record WindowInfo(long Handle, string Title, string App, int Pid, string ClassName,
    int X, int Y, int W, int H, string State, int Monitor, bool Foreground, bool Topmost);

public static class WindowManager
{
    private static readonly Dictionary<int, string> ProcessNames = new();

    public static string ProcessName(int pid)
    {
        if (ProcessNames.TryGetValue(pid, out var name)) return name;
        try { name = Process.GetProcessById(pid).ProcessName; } catch { name = ""; }
        if (ProcessNames.Count > 500) ProcessNames.Clear();
        return ProcessNames[pid] = name;
    }

    /// <summary>Visible, titled top-level windows in z-order (front first), like Alt+Tab shows them.</summary>
    public static List<WindowInfo> List(bool includeUntitled = false)
    {
        var fg = GetForegroundWindow();
        var monitors = Screens.Monitors();
        var list = new List<WindowInfo>();
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h) || IsCloaked(h)) return true;
            var title = WindowText(h);
            var ex = GetWindowLong(h, GWL_EXSTYLE);
            if (!includeUntitled && (title.Length == 0 || (ex & WS_EX_TOOLWINDOW) != 0)) return true;
            if (GetWindow(h, GW_OWNER) != IntPtr.Zero && title.Length == 0) return true;
            var r = FrameRect(h);
            if (r.Width <= 1 || r.Height <= 1) return true;
            GetWindowThreadProcessId(h, out var pid);
            if (pid == Environment.ProcessId) return true;
            var state = IsIconic(h) ? "minimized" : IsZoomed(h) ? "maximized" : "normal";
            var cx = r.Left + r.Width / 2; var cy = r.Top + r.Height / 2;
            var mon = monitors.FirstOrDefault(m => cx >= m.Left && cx < m.Left + m.Width && cy >= m.Top && cy < m.Top + m.Height)?.Index ?? 0;
            list.Add(new WindowInfo(h.ToInt64(), title, ProcessName(pid), pid, Native.ClassName(h), r.Left, r.Top, r.Width, r.Height,
                state, mon, h == fg, (ex & WS_EX_TOPMOST) != 0));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static WindowInfo? Foreground()
    {
        var fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return null;
        var root = GetAncestor(fg, GA_ROOTOWNER);
        GetWindowThreadProcessId(fg, out var pid);
        var r = FrameRect(fg);
        return new WindowInfo(fg.ToInt64(), WindowText(fg), ProcessName(pid), pid, Native.ClassName(fg), r.Left, r.Top, r.Width, r.Height,
            IsIconic(fg) ? "minimized" : IsZoomed(fg) ? "maximized" : "normal", Screens.MonitorOfWindow(fg).Index, true, false)
            with { Title = WindowText(fg).Length > 0 ? WindowText(fg) : WindowText(root) };
    }

    /// <summary>Finds a window by handle, exact app name, or title words; front-most match wins.</summary>
    public static IntPtr Find(Args a)
    {
        if (a.Num("handle") is double hv && hv > 0)
        {
            var h = new IntPtr((long)hv);
            if (!IsWindow(h)) throw new HostError("That window has closed.", "not_found");
            return h;
        }
        var query = (a.Str("window") ?? a.Str("title") ?? a.Str("app") ?? "").Trim();
        if (query.Length == 0)
        {
            var fg = GetForegroundWindow();
            if (fg == IntPtr.Zero) throw new HostError("No window is in front.", "not_found");
            return fg;
        }
        var windows = List();
        var q = query.ToLowerInvariant().Replace(".exe", "");
        var match = windows.FirstOrDefault(w => w.App.Equals(q, StringComparison.OrdinalIgnoreCase))
            ?? windows.FirstOrDefault(w => w.Title.Equals(query, StringComparison.OrdinalIgnoreCase))
            ?? windows.FirstOrDefault(w => w.Title.Contains(query, StringComparison.OrdinalIgnoreCase))
            ?? windows.FirstOrDefault(w => w.App.Contains(q, StringComparison.OrdinalIgnoreCase));
        if (match is null)
        {
            var open = string.Join(", ", windows.Take(12).Select(w => $"{w.App}: {Trim(w.Title, 40)}"));
            throw new HostError($"No open window matches '{query}'. Open: {open}", "not_found");
        }
        return new IntPtr(match.Handle);
    }

    private static string Trim(string s, int n) => s.Length <= n ? s : s[..n] + "…";

    /// <summary>Brings a window to the front. Windows restricts SetForegroundWindow, so this
    /// taps Alt first and, if needed, attaches to the foreground thread.</summary>
    public static bool Focus(IntPtr h)
    {
        if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
        if (GetForegroundWindow() == h) return true;
        Input.Chords("alt", 0);
        if (SetForegroundWindow(h) && WaitForeground(h)) return true;
        var fg = GetForegroundWindow();
        var fgThread = GetWindowThreadProcessId(fg, out _);
        var me = GetCurrentThreadId();
        AttachThreadInput(me, fgThread, true);
        try
        {
            BringWindowToTop(h);
            ShowWindow(h, SW_SHOW);
            SetForegroundWindow(h);
        }
        finally { AttachThreadInput(me, fgThread, false); }
        return WaitForeground(h);
    }

    private static bool WaitForeground(IntPtr h)
    {
        for (int i = 0; i < 20; i++)
        {
            var fg = GetForegroundWindow();
            if (fg == h || GetAncestor(fg, GA_ROOTOWNER) == h) return true;
            Thread.Sleep(25);
        }
        return false;
    }

    public static WindowInfo Describe(IntPtr h) => List(includeUntitled: true).FirstOrDefault(w => w.Handle == h.ToInt64())
        ?? throw new HostError("That window is no longer open.", "not_found");

    public static object Act(Args a)
    {
        var action = (a.Str("action") ?? "focus").ToLowerInvariant();
        var h = Find(a);
        var before = Describe(h);
        if (Guard.IsSyph(before.Pid) && action is "close" or "minimize" or "move" or "resize" or "set_bounds")
            throw new HostError("Syph's own windows stay where the owner put them.", "policy_denied");
        switch (action)
        {
            case "focus":
            case "activate":
                if (!Focus(h)) throw new HostError($"Windows would not bring '{before.Title}' to the front. Click on it instead.", "blocked");
                break;
            case "minimize": ShowWindow(h, SW_MINIMIZE); break;
            case "maximize": ShowWindow(h, SW_MAXIMIZE); Focus(h); break;
            case "restore": ShowWindow(h, SW_RESTORE); Focus(h); break;
            case "close": PostMessage(h, WM_CLOSE, IntPtr.Zero, IntPtr.Zero); break;
            case "move":
            case "resize":
            case "set_bounds":
            {
                if (IsZoomed(h) || IsIconic(h)) ShowWindow(h, SW_RESTORE);
                var x = a.Int("x", before.X); var y = a.Int("y", before.Y);
                var w = a.Int("w", a.Int("width", before.W)); var hgt = a.Int("h", a.Int("height", before.H));
                SetWindowPos(h, IntPtr.Zero, x, y, Math.Max(120, w), Math.Max(80, hgt), SWP_NOZORDER);
                break;
            }
            case "snap_left":
            case "snap_right":
            case "snap_top":
            case "snap_bottom":
            case "fill":
            {
                var monitors = Screens.Monitors();
                var target = a.IntOrNull("monitor") is int mi && mi >= 0 && mi < monitors.Count ? monitors[mi] : monitors[before.Monitor];
                int x = target.WorkLeft, y = target.WorkTop, w = target.WorkWidth, hgt = target.WorkHeight;
                if (action == "snap_left") w /= 2;
                if (action == "snap_right") { w /= 2; x += w; }
                if (action == "snap_top") hgt /= 2;
                if (action == "snap_bottom") { hgt /= 2; y += hgt; }
                if (IsZoomed(h) || IsIconic(h)) ShowWindow(h, SW_RESTORE);
                SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, SWP_NOZORDER);
                Focus(h);
                break;
            }
            case "to_monitor":
            {
                var monitors = Screens.Monitors();
                var mi = a.IntOrNull("monitor") ?? throw new HostError("to_monitor needs a monitor index.", "invalid_input");
                if (mi < 0 || mi >= monitors.Count) throw new HostError($"There is no monitor {mi}.", "invalid_input");
                var from = Screens.Monitors()[before.Monitor]; var to = monitors[mi];
                var wasMax = IsZoomed(h);
                if (wasMax) ShowWindow(h, SW_RESTORE);
                var nx = to.WorkLeft + Math.Max(0, before.X - from.WorkLeft); var ny = to.WorkTop + Math.Max(0, before.Y - from.WorkTop);
                SetWindowPos(h, IntPtr.Zero, nx, ny, Math.Min(before.W, to.WorkWidth), Math.Min(before.H, to.WorkHeight), SWP_NOZORDER);
                if (wasMax) ShowWindow(h, SW_MAXIMIZE);
                Focus(h);
                break;
            }
            default:
                throw new HostError($"Unknown window action '{action}'. Use focus, minimize, maximize, restore, close, move, snap_left, snap_right, fill or to_monitor.", "invalid_input");
        }
        Thread.Sleep(action == "close" ? 400 : 120);
        var after = IsWindow(h) && IsWindowVisible(h) ? Describe(h) : null;
        return new { window = after ?? before, closed = after is null, action };
    }
}
