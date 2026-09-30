using System.Diagnostics;

namespace Syph.Host;

public sealed record StartApp(string Name, string Id);

/// <summary>Opens and quits apps the way a person would: from the Start menu's app list.</summary>
public static class Apps
{
    private static List<StartApp>? _cache;
    private static DateTime _cachedAt;

    /// <summary>Everything in Start (desktop and Store apps), via the shell's AppsFolder.</summary>
    public static List<StartApp> StartMenu()
    {
        if (_cache is not null && DateTime.UtcNow - _cachedAt < TimeSpan.FromMinutes(5)) return _cache;
        _cache = Sta.Run(() =>
        {
            var list = new List<StartApp>();
            var type = Type.GetTypeFromProgID("Shell.Application") ?? throw new HostError("The Windows shell is unavailable.");
            dynamic shell = Activator.CreateInstance(type)!;
            dynamic folder = shell.NameSpace("shell:AppsFolder");
            foreach (dynamic item in folder.Items())
            {
                string name = item.Name, id = item.Path;
                if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(id)) list.Add(new StartApp(name, id));
            }
            return list;
        });
        _cachedAt = DateTime.UtcNow;
        return _cache;
    }

    private static readonly Dictionary<string, string> Aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["word"] = "Word", ["excel"] = "Excel", ["powerpoint"] = "PowerPoint", ["outlook"] = "Outlook",
        ["edge"] = "Microsoft Edge", ["chrome"] = "Google Chrome", ["explorer"] = "File Explorer", ["files"] = "File Explorer",
        ["finder"] = "File Explorer", ["textedit"] = "Notepad", ["terminal"] = "Terminal", ["cmd"] = "Command Prompt",
        ["settings"] = "Settings", ["calculator"] = "Calculator", ["calc"] = "Calculator", ["paint"] = "Paint",
        ["teams"] = "Microsoft Teams", ["store"] = "Microsoft Store", ["photos"] = "Photos", ["mail"] = "Outlook",
    };

    public static StartApp? Resolve(string query)
    {
        var q = Aliases.TryGetValue(query.Trim(), out var alias) ? alias : query.Trim();
        List<StartApp> apps;
        try { apps = StartMenu(); } catch { return null; }
        return apps.FirstOrDefault(a => a.Name.Equals(q, StringComparison.OrdinalIgnoreCase))
            ?? apps.Where(a => a.Name.StartsWith(q, StringComparison.OrdinalIgnoreCase)).OrderBy(a => a.Name.Length).FirstOrDefault()
            ?? apps.Where(a => a.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).OrderBy(a => a.Name.Length).FirstOrDefault();
    }

    public static object Open(Args a)
    {
        var query = a.Req("app");
        var before = WindowManager.List().Select(w => w.Handle).ToHashSet();
        var match = Resolve(query);
        string launched;
        if (match is not null)
        {
            // AppsFolder ids launch desktop and packaged apps alike.
            Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{match.Id}") { UseShellExecute = false });
            launched = match.Name;
        }
        else
        {
            try { Process.Start(new ProcessStartInfo(query) { UseShellExecute = true }); }
            catch (Exception e) { throw new HostError($"'{query}' isn't an app in Start and Windows couldn't run it ({e.Message}).", "not_found"); }
            launched = query;
        }
        // Wait for its window so the next step acts on it, not on whatever was in front.
        var words = launched.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var deadline = DateTime.UtcNow.AddSeconds(a.Int("wait", 12));
        WindowInfo? window = null;
        while (DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
            var now = WindowManager.List();
            window = now.FirstOrDefault(w => !before.Contains(w.Handle))
                ?? now.FirstOrDefault(w => w.Foreground && words.Any(x => w.Title.Contains(x, StringComparison.OrdinalIgnoreCase) || w.App.Contains(x, StringComparison.OrdinalIgnoreCase)));
            if (window is not null) break;
        }
        if (window is null)
        {
            // Already running single-instance apps often just raise their existing window.
            var existing = WindowManager.List().FirstOrDefault(w => words.Any(x => w.Title.Contains(x, StringComparison.OrdinalIgnoreCase) || w.App.Contains(x, StringComparison.OrdinalIgnoreCase)));
            if (existing is not null) { WindowManager.Focus(new IntPtr(existing.Handle)); window = existing; }
        }
        else
        {
            Thread.Sleep(300);
            WindowManager.Focus(new IntPtr(window.Handle));
        }
        return new
        {
            ok = true,
            summary = window is null ? $"Started {launched}; its window hasn't appeared yet." : $"Opened {launched}.",
            data = new { app = launched, window },
        };
    }

    public static object Quit(Args a)
    {
        var query = a.Req("app");
        var q = query.ToLowerInvariant().Replace(".exe", "");
        var resolved = Resolve(query)?.Name.ToLowerInvariant();
        var windows = WindowManager.List().Where(w => !Guard.IsSyph(w.Pid)).Where(w =>
            w.App.Equals(q, StringComparison.OrdinalIgnoreCase)
            || (resolved is not null && w.Title.ToLowerInvariant().EndsWith(resolved))
            || w.Title.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        if (windows.Count == 0) return new { ok = true, summary = $"{query} wasn't open.", data = new { closed = 0 } };
        foreach (var w in windows) Native.PostMessage(new IntPtr(w.Handle), Native.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        Thread.Sleep(1200);
        var still = WindowManager.List().Where(w => windows.Any(x => x.Pid == w.Pid)).ToList();
        if (still.Count == 0) return new { ok = true, summary = $"Quit {query}.", data = new { closed = windows.Count } };
        if (a.Bool("force", false))
        {
            foreach (var pid in still.Select(w => w.Pid).Distinct()) try { Process.GetProcessById(pid).Kill(); } catch { }
            return new { ok = true, summary = $"Force-quit {query}.", data = new { closed = windows.Count } };
        }
        // Usually a "save changes?" prompt: leave it for the agent (or the owner) to answer.
        return new
        {
            ok = false,
            summary = $"{query} is still open; it may be asking to save. Look at the screen and answer it.",
            data = new { windows = still },
        };
    }
}

/// <summary>Syph never closes or kills its own windows: the owner's kill switch lives there.</summary>
public static class Guard
{
    private static readonly int AppPid = int.TryParse(Environment.GetEnvironmentVariable("SYPH_APP_PID"), out var p) ? p : -1;

    public static bool IsSyph(int pid)
    {
        if (pid == Environment.ProcessId || pid == AppPid) return true;
        var name = WindowManager.ProcessName(pid);
        return name.Equals("Syph", StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>Runs shell COM work on a single-threaded apartment, which the shell requires.</summary>
public static class Sta
{
    public static T Run<T>(Func<T> fn, int timeoutMs = 15_000)
    {
        T? result = default;
        Exception? error = null;
        var t = new Thread(() => { try { result = fn(); } catch (Exception e) { error = e; } }) { IsBackground = true };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        if (!t.Join(timeoutMs)) throw new HostError("Windows took too long to answer.", "timeout");
        if (error is not null) throw error is HostError ? error : new HostError(error.Message);
        return result!;
    }
}
