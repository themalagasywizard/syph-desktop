using System.Collections.Concurrent;
using System.Drawing;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Syph.Host;

/// <summary>
/// syph-host: one long-lived process that sees and acts on this PC for Syph.
///
/// Protocol: JSON lines. Request  {"id": 1, "method": "snapshot", "params": {...}}
///                       Response {"id": 1, "ok": true, "result": {...}}  or  {"id": 1, "ok": false, "error": "...", "code": "..."}
///                       Event    {"event": "human_input", "data": {...}}
/// Requests run one at a time, in order, on a worker thread; "ping" and "cancel" are answered at once.
/// </summary>
public static class Program
{
    public const string Version = "1.1.0";
    private static readonly object WriteLock = new();
    private static TextWriter _out = Console.Out;

    public static void Emit(JsonObject message)
    {
        var line = message.ToJsonString(J.Options);
        lock (WriteLock) { _out.WriteLine(line); _out.Flush(); }
    }

    public static void Event(string name, object data) => Emit(new JsonObject { ["event"] = name, ["data"] = J.From(data) });

    public static int Main(string[] args)
    {
        var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = false };
        _out = stdout;
        Console.SetOut(TextWriter.Null); // nothing else may write to the protocol stream
        if (args.Contains("--selftest")) return SelfTest.Run(args);

        var queue = new BlockingCollection<JsonObject>();
        var worker = new Thread(() =>
        {
            foreach (var request in queue.GetConsumingEnumerable()) Handle(request);
        }) { IsBackground = true, Name = "syph-worker" };
        worker.Start();

        var stdin = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
        Event("ready", new { version = Version, pid = Environment.ProcessId });
        string? line;
        while ((line = stdin.ReadLine()) is not null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            JsonObject? request;
            try { request = JsonNode.Parse(line) as JsonObject; }
            catch (JsonException) { continue; }
            if (request is null) continue;
            var method = request["method"]?.GetValue<string>();
            if (method == "ping") { Reply(request, new { version = Version, pid = Environment.ProcessId }); continue; }
            // Answered at once, even while a long action is running.
            if (method == "watch") { Handle(request); continue; }
            queue.Add(request);
        }
        queue.CompleteAdding();
        Watcher.Stop();
        return 0;
    }

    private static void Reply(JsonObject request, object? result) =>
        Emit(new JsonObject { ["id"] = request["id"]?.DeepClone(), ["ok"] = true, ["result"] = J.From(result) });

    private static void Handle(JsonObject request)
    {
        var method = request["method"]?.GetValue<string>() ?? "";
        var args = new Args(request["params"] as JsonObject);
        try
        {
            Reply(request, Dispatch(method, args));
        }
        catch (Exception e)
        {
            var (message, code) = e switch
            {
                HostError h => (h.Message, h.Code),
                System.Runtime.InteropServices.COMException c => ($"The app didn't answer ({c.Message.Split('\n')[0]}). It may be busy or not responding.", "external"),
                TimeoutException => ("That took too long.", "timeout"),
                _ => (e.Message, "failed"),
            };
            Emit(new JsonObject { ["id"] = request["id"]?.DeepClone(), ["ok"] = false, ["error"] = message, ["code"] = code });
        }
        finally
        {
            if (Input.Acting) Watcher.ResetAnchor();
            Input.Acting = false;
        }
    }

    public static object? Dispatch(string method, Args a)
    {
        switch (method)
        {
            case "observe": return Observe(a);
            case "monitors": return new { monitors = Screens.Monitors() };
            case "windows.list": return new { windows = WindowManager.List(a.Bool("all", false)).Take(a.Int("limit", 60)) };
            case "window.act": Input.Acting = true; return WindowManager.Act(a);
            case "apps.open": Input.Acting = true; return Apps.Open(a);
            case "apps.quit": Input.Acting = true; return Apps.Quit(a);
            case "apps.list":
            {
                var q = a.Str("query");
                var apps = Apps.StartMenu().Where(x => q is null || x.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).Select(x => x.Name).Distinct().OrderBy(x => x);
                return new { apps = apps.Take(a.Int("limit", 400)) };
            }
            case "capture": return Capture(a);
            case "ocr": return ReadScreen(a);
            case "snapshot": return Snapshot.Take(a);
            case "files.find": return Search.Find(a);
            case var m when m.StartsWith("excel.") || m.StartsWith("word.") || m.StartsWith("outlook."):
                return Office.Dispatch(m, a);
            case "ui.elements":
            {
                var fg = a.Has("handle") || a.Has("window") || a.Has("app") ? WindowManager.Find(a) : Native.GetForegroundWindow();
                var front = a.Has("handle") || a.Has("window") || a.Has("app") ? [fg] : Uia.FrontWindows(fg);
                var els = Uia.Elements(front, a.Int("limit", 300), a.Bool("interactive", false));
                var w = WindowManager.Describe(fg);
                return new { app = w.App, window = w.Title, handle = w.Handle, elements = els.Select(Wire) };
            }
            case "ui.act":
            {
                Input.Acting = true;
                var id = a.IntOrNull("id") ?? a.IntOrNull("element") ?? throw new HostError("ui.act needs an element id.", "invalid_input");
                return new { element = Wire(Uia.Act(id, a.Str("action") ?? "invoke", a.Str("value") ?? a.Str("text"))) };
            }
            case "ui.text":
            {
                var id = a.IntOrNull("id") ?? a.IntOrNull("element") ?? throw new HostError("ui.text needs an element id.", "invalid_input");
                var text = Uia.Text(id, a.Int("max", 200_000));
                return new { text, length = text.Length };
            }
            case "ui.describe":
            {
                var id = a.IntOrNull("id") ?? throw new HostError("ui.describe needs an element id.", "invalid_input");
                return new { element = Wire(Uia.Refresh(id)) };
            }
            case "ui.focused": return new { element = Uia.Focused() is { } f ? Wire(f) : null };
            case "ui.at":
            {
                var (x, y) = Point(a);
                return new { element = Uia.AtPoint(x, y) is { } e ? Wire(e) : null };
            }
            case "ui.find":
            {
                var fg = a.Has("handle") || a.Has("window") || a.Has("app") ? WindowManager.Find(a) : Native.GetForegroundWindow();
                var els = Uia.Elements(Uia.FrontWindows(fg), 1500, false);
                var match = Uia.Find(els, a.Req("name"), a.Str("role"));
                return new { element = match is null ? null : Wire(match), candidates = match is null ? els.Where(e => e.Name.Length > 0).Take(40).Select(e => $"{e.Role} '{e.Name}'") : null };
            }
            case "input.click":
            {
                Input.Acting = true;
                var (x, y) = Point(a);
                var mods = a.Arr("modifiers")?.Select(m => m?.GetValue<string>() ?? "").Where(m => m.Length > 0).ToList();
                Input.Click(x, y, a.Str("button") ?? "left", a.Int("count", 1), mods);
                return new { x, y };
            }
            case "input.move": { Input.Acting = true; var (x, y) = Point(a); Input.MoveTo(x, y); return new { x, y }; }
            case "input.drag":
            {
                Input.Acting = true;
                var (fx, fy) = Point(a.Obj("from"));
                var (tx, ty) = Point(a.Obj("to"));
                Input.Drag(fx, fy, tx, ty, a.Str("button") ?? "left", a.Int("hold", 120));
                return new { from = new { x = fx, y = fy }, to = new { x = tx, y = ty } };
            }
            case "input.scroll":
            {
                Input.Acting = true;
                int? x = null, y = null;
                if (a.Has("x") || a.Has("element") || a.Has("id")) { var p = Point(a); x = p.X; y = p.Y; }
                Input.Scroll(a.Str("direction") ?? "down", a.Int("amount", 5), x, y);
                return new { x, y };
            }
            case "input.type":
            {
                Input.Acting = true;
                var text = a.Str("text") ?? "";
                if (a.IntOrNull("element") is int id) { var (x, y) = Uia.ClickPoint(id); Input.Click(x, y); Thread.Sleep(80); }
                Input.Type(text, a.Int("delay", 4));
                return new { typed = text.Length, focused = Uia.Focused() is { } now ? Wire(now) : null };
            }
            case "input.keys": Input.Acting = true; Input.Chords(a.Req("keys"), a.Int("hold", 0)); return new { keys = a.Str("keys") };
            case "input.key_down": Input.Acting = true; Input.KeyDown(a.Req("keys")); return new { down = a.Str("keys") };
            case "input.key_up": Input.Acting = true; Input.KeyUp(a.Req("keys")); return new { up = a.Str("keys") };
            case "input.mouse_down": Input.Acting = true; Input.MouseButton(a.Str("button") ?? "left", false); return new { };
            case "input.mouse_up": Input.Acting = true; Input.MouseButton(a.Str("button") ?? "left", true); return new { };
            case "input.release": Input.ReleaseModifiers(); return new { };
            case "wait": return Waits.Wait(a);
            case "stable": return new { stable = Waits.Stable(a.Int("quiet", 400), a.Int("max", 2500)) };
            case "watch": return Watcher.Configure(a);
            case "cursor": { Native.GetCursorPos(out var p); return new { x = p.X, y = p.Y }; }
            default: throw new HostError($"Unknown method '{method}'.", "invalid_input");
        }
    }

    /// <summary>A point from {element}, {x, y, space: "image"} (last snapshot), or {x, y} screen pixels.</summary>
    public static (int X, int Y) Point(Args a)
    {
        var id = a.IntOrNull("element") ?? a.IntOrNull("id");
        if (id is int element) return Uia.ClickPoint(element);
        var x = a.Num("x") ?? throw new HostError("A point needs x and y, or an element id.", "invalid_input");
        var y = a.Num("y") ?? throw new HostError("A point needs x and y, or an element id.", "invalid_input");
        if ((a.Str("space") ?? "screen") == "image")
        {
            var t = Screens.Last ?? throw new HostError("There is no screenshot to measure from. Take a snapshot first.", "invalid_input");
            if (x < 0 || y < 0 || x > t.Width || y > t.Height) throw new HostError($"({x}, {y}) is outside the {t.Width}x{t.Height} screenshot.", "invalid_input");
            return t.ToScreen(x, y);
        }
        return ((int)Math.Round(x), (int)Math.Round(y));
    }

    public static object Wire(Element e) => new
    {
        id = e.Id, role = e.Role, name = e.Name, value = e.Value, x = e.X, y = e.Y, w = e.W, h = e.H,
        enabled = e.Enabled ? (bool?)null : false, focused = e.Focused ? true : (bool?)null,
        password = e.Password ? true : (bool?)null, actions = e.Actions.Length > 0 ? e.Actions : null, state = e.State, automationId = e.AutomationId,
    };

    private static object Observe(Args a)
    {
        var windows = WindowManager.List();
        Native.GetCursorPos(out var cursor);
        return new
        {
            front = WindowManager.Foreground(),
            windows = windows.Take(a.Int("limit", 25)),
            apps = windows.Select(w => w.App).Where(n => n.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            monitors = Screens.Monitors(),
            cursor = new { x = cursor.X, y = cursor.Y },
            focused = Uia.Focused() is { } f ? Wire(f) : null,
        };
    }

    private static object Capture(Args a)
    {
        Bitmap full;
        Rectangle area;
        string label;
        if (a.Has("handle") || a.Has("window") || a.Has("app"))
        {
            var h = WindowManager.Find(a);
            full = Screens.GrabWindow(h, out area);
            label = "window";
        }
        else
        {
            area = Screens.Target(a, out label);
            full = Screens.Grab(area);
        }
        using (full)
        {
            var (img, scale) = Screens.Fit(full, a.Int("maxSide", 1568));
            using (img)
            {
                var t = new ImageTransform(area.Left, area.Top, scale, img.Width, img.Height);
                Screens.Last = t;
                return new { image = Screens.Jpeg(img, a.Int("quality", 70)), mime = "image/jpeg", width = img.Width, height = img.Height, transform = t, target = label };
            }
        }
    }

    /// <summary>OCR of the target area plus a thumbnail: the original read_screen contract.</summary>
    private static object ReadScreen(Args a)
    {
        var area = Screens.Target(a, out var label);
        using var full = Screens.Grab(area);
        // Never OCR or show a password field, even a visible one.
        var front = Native.GetForegroundWindow();
        List<Element> secrets = [];
        try { secrets = Uia.Elements([front], 400, true).Where(e => e.Password).ToList(); } catch { }
        Marks.Redact(full, area.Left, area.Top, secrets);
        var lines = Ocr.Read(full, area.Left, area.Top);
        string? thumb = null;
        if (a.Bool("thumbnail", true))
        {
            var (small, _) = Screens.Fit(full, 1280);
            using (small) thumb = Screens.Jpeg(small, 55);
        }
        var fg = WindowManager.Foreground();
        return new
        {
            text = string.Join("\n", lines.Select(l => l.Text)),
            lines = lines.Take(a.Int("limit", 300)).Select(l => new { text = l.Text, x = l.X, y = l.Y, w = l.W, h = l.H, left = l.Left }),
            screen = new { width = area.Width, height = area.Height, left = area.Left, top = area.Top },
            app = fg?.App, window = fg?.Title, target = label, note = Ocr.Unavailable, _image = thumb,
        };
    }
}
