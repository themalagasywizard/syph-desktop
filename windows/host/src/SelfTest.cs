using System.Text.Json;
using System.Text.Json.Nodes;

namespace Syph.Host;

/// <summary>
/// `SyphHost.exe --selftest [--out report.json]`: drives the real desktop (Notepad) through every
/// capability and reports pass/fail per check. Used by Windows CI; safe to run on a dev PC.
/// </summary>
public static class SelfTest
{
    private sealed record Check(string Name, bool Ok, string Detail, long Ms);

    public static int Run(string[] argv)
    {
        var checks = new List<Check>();
        var outIndex = Array.IndexOf(argv, "--out");
        var reportPath = outIndex >= 0 && outIndex + 1 < argv.Length ? argv[outIndex + 1] : null;

        JsonNode? Call(string method, object? p = null)
        {
            var node = p is null ? new JsonObject() : JsonSerializer.SerializeToNode(p, J.Options) as JsonObject;
            var result = Program.Dispatch(method, new Args(node));
            return J.From(result);
        }

        void Test(string name, Func<string> body)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try { checks.Add(new Check(name, true, body(), sw.ElapsedMilliseconds)); }
            catch (Exception e) { checks.Add(new Check(name, false, $"{e.GetType().Name}: {e.Message}", sw.ElapsedMilliseconds)); }
            finally { Input.Acting = false; }
        }

        const string Sample = "Syph héllo ✓ 日本語 — line one\nline two";
        long notepad = 0;

        Test("monitors", () => { var m = Call("monitors")!["monitors"]!.AsArray(); if (m.Count == 0) throw new Exception("none"); return $"{m.Count} monitor(s), first {m[0]!["width"]}x{m[0]!["height"]} @ {m[0]!["scalePercent"]}%"; });
        Test("observe", () => { var o = Call("observe")!; return $"front={o["front"]?["app"]} windows={o["windows"]!.AsArray().Count}"; });
        Test("capture", () =>
        {
            var c = Call("capture", new { maxSide = 1280 })!;
            var bytes = Convert.FromBase64String(c["image"]!.GetValue<string>()).Length;
            if (bytes < 2000) throw new Exception($"image too small ({bytes} bytes) — capture may be blank");
            return $"{c["width"]}x{c["height"]} jpeg {bytes / 1024} KB scale={c["transform"]!["scale"]}";
        });
        Test("apps.list", () => { var a = Call("apps.list", new { query = "Notepad" })!["apps"]!.AsArray(); return $"{a.Count} match(es): {string.Join(", ", a.Take(3))}"; });
        Test("apps.open notepad", () =>
        {
            var r = Call("apps.open", new { app = "Notepad" })!;
            notepad = r["data"]?["window"]?["handle"]?.GetValue<long>() ?? 0;
            if (notepad == 0) throw new Exception(r["summary"]?.GetValue<string>() ?? "no window");
            Thread.Sleep(800);
            return r["summary"]!.GetValue<string>();
        });
        Test("window.act focus+fill", () =>
        {
            Call("window.act", new { handle = notepad, action = "focus" });
            var r = Call("window.act", new { handle = notepad, action = "snap_left" })!;
            return $"now {r["window"]!["w"]}x{r["window"]!["h"]} at {r["window"]!["x"]},{r["window"]!["y"]}";
        });
        Test("input.type unicode", () =>
        {
            Call("window.act", new { handle = notepad, action = "focus" });
            Call("input.keys", new { keys = "ctrl+a delete" });
            Call("input.type", new { text = Sample });
            Thread.Sleep(300);
            return "typed";
        });
        Test("ui.elements + ui.text roundtrip", () =>
        {
            var els = Call("ui.elements", new { handle = notepad })!["elements"]!.AsArray();
            var doc = els.FirstOrDefault(e => e!["role"]!.GetValue<string>() is "Document" or "Edit")
                ?? throw new Exception($"no text area among {els.Count} elements");
            var text = Call("ui.text", new { id = doc!["id"]!.GetValue<int>() })!["text"]!.GetValue<string>().Replace("\r\n", "\n").Replace("\r", "\n").TrimEnd('\n');
            if (text != Sample) throw new Exception($"read back '{text}'");
            return $"{els.Count} elements; text area #{doc["id"]} read back exactly";
        });
        Test("stable ids", () =>
        {
            var a = Call("ui.elements", new { handle = notepad })!["elements"]!.AsArray().Select(e => $"{e!["id"]}:{e["role"]}:{e["name"]}").ToHashSet();
            var b = Call("ui.elements", new { handle = notepad })!["elements"]!.AsArray().Select(e => $"{e!["id"]}:{e["role"]}:{e["name"]}").ToHashSet();
            var same = a.Intersect(b).Count();
            if (same < Math.Min(a.Count, b.Count) * 0.8) throw new Exception($"only {same} of {a.Count} ids stable");
            return $"{same}/{a.Count} ids identical across two reads";
        });
        Test("ocr sees typed text", () =>
        {
            var r = Call("ocr", new { thumbnail = false })!;
            var text = r["text"]!.GetValue<string>();
            if (!text.Contains("line two", StringComparison.OrdinalIgnoreCase) && !text.Contains("hello", StringComparison.OrdinalIgnoreCase) && !text.Contains("Syph"))
                throw new Exception($"OCR text: {text[..Math.Min(200, text.Length)]} {r["note"]}");
            return $"{r["lines"]!.AsArray().Count} lines";
        });
        Test("snapshot with marks", () =>
        {
            var r = Call("snapshot", new { })!;
            var bytes = Convert.FromBase64String(r["_image"]!.GetValue<string>()).Length;
            var els = r["elements"]!.AsArray();
            if (els.Count == 0) throw new Exception("no elements listed");
            if (els.Any(e => e!["x"]!.GetValue<int>() < 0 || e["x"]!.GetValue<int>() > r["width"]!.GetValue<int>())) throw new Exception("element outside image");
            return $"{r["width"]}x{r["height"]}, {els.Count} numbered controls, {bytes / 1024} KB, app={r["app"]}";
        });
        Test("snapshot notices change", () =>
        {
            Call("snapshot", new { });
            Call("input.type", new { text = " more text" });
            Thread.Sleep(250);
            var r = Call("snapshot", new { })!;
            if (r["changed"]?.GetValue<bool>() != true) throw new Exception("typing did not register as a change");
            return "changed=true after typing";
        });
        Test("keys + clipboard shortcut", () => { Call("input.keys", new { keys = "ctrl+a ctrl+c" }); return "sent"; });
        Test("focused element", () => { var f = Call("ui.focused")!["element"]; return $"{f?["role"]} '{f?["name"]}'"; });
        Test("click in image space", () =>
        {
            Call("capture", new { maxSide = 800 });
            var w = Call("window.act", new { handle = notepad, action = "focus" })!["window"]!;
            var t = Screens.Last!;
            var (ix, iy) = t.ToImage(w["x"]!.GetValue<int>() + w["w"]!.GetValue<int>() / 2, w["y"]!.GetValue<int>() + w["h"]!.GetValue<int>() / 2);
            var r = Call("input.click", new { x = ix, y = iy, space = "image" })!;
            return $"image ({ix:0},{iy:0}) -> screen ({r["x"]},{r["y"]})";
        });
        Test("apps.quit notepad", () =>
        {
            var r = Call("apps.quit", new { app = "Notepad" })!;
            if (r["ok"]!.GetValue<bool>()) return r["summary"]!.GetValue<string>();
            // Notepad asks to save: answer "Don't save" through UI Automation, like the agent would.
            Thread.Sleep(500);
            var found = Call("ui.find", new { name = "Don't save" })!["element"];
            if (found is null) { Call("input.keys", new { keys = "alt+n" }); }
            else Call("ui.act", new { id = found["id"]!.GetValue<int>(), action = "invoke" });
            Thread.Sleep(800);
            var again = Call("apps.quit", new { app = "Notepad", force = true })!;
            return "answered the save prompt; " + again["summary"]!.GetValue<string>();
        });

        var report = new { version = Program.Version, passed = checks.Count(c => c.Ok), total = checks.Count, checks };
        var json = JsonSerializer.Serialize(report, new JsonSerializerOptions(J.Options) { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
        if (reportPath is not null) File.WriteAllText(reportPath, json);
        foreach (var c in checks) Program.Emit(new JsonObject { ["check"] = c.Name, ["ok"] = c.Ok, ["ms"] = c.Ms, ["detail"] = c.Detail });
        Program.Emit(new JsonObject { ["passed"] = report.passed, ["total"] = report.total });
        return checks.All(c => c.Ok) ? 0 : 1;
    }
}
