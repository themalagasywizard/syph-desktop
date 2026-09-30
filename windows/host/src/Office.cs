using System.Runtime.InteropServices;

namespace Syph.Host;

/// <summary>
/// Excel, Word and classic Outlook through their COM object models: whole sheets and documents
/// in one call instead of hundreds of clicks. The apps stay visible so the owner sees the work.
/// File paths are checked against the shared folders by the Electron side before they get here.
/// Outlook only ever creates drafts and shows them; it never sends.
/// </summary>
public static class Office
{
    [DllImport("ole32.dll")] private static extern int CLSIDFromProgID([MarshalAs(UnmanagedType.LPWStr)] string progId, out Guid clsid);
    [DllImport("oleaut32.dll")] private static extern int GetActiveObject(ref Guid rclsid, IntPtr reserved, [MarshalAs(UnmanagedType.IUnknown)] out object? ppunk);

    private const int MaxCells = 20_000;

    /// <summary>A parameterized COM property (Range, Cells, Resize, Address): an explicit property get,
    /// which Office's IDispatch always accepts, unlike a late-bound method call.</summary>
    private static dynamic Prop(object target, string name, params object[] args) =>
        target.GetType().InvokeMember(name, System.Reflection.BindingFlags.GetProperty, null, target, args)!;

    private static dynamic App(string progId, string name, bool create)
    {
        if (CLSIDFromProgID(progId, out var clsid) != 0)
            throw new HostError($"{name} isn't installed on this PC (or it's the new Outlook, which has no automation).", "unavailable");
        if (GetActiveObject(ref clsid, IntPtr.Zero, out var running) == 0 && running is not null) return running;
        if (!create) throw new HostError($"{name} isn't open.", "not_found");
        var type = Type.GetTypeFromProgID(progId) ?? throw new HostError($"{name} isn't installed on this PC.", "unavailable");
        dynamic app = Activator.CreateInstance(type)!;
        try { app.Visible = true; } catch { }
        return app;
    }

    public static object Dispatch(string method, Args a) => Sta.Run<object>(() => method switch
    {
        "excel.list" => ExcelList(),
        "excel.read" => ExcelRead(a),
        "excel.write" => ExcelWrite(a),
        "excel.save" => ExcelSave(a),
        "word.read" => WordRead(a),
        "word.write" => WordWrite(a),
        "word.save" => WordSave(a),
        "outlook.list" => OutlookList(a),
        "outlook.read" => OutlookRead(a),
        "outlook.search" => OutlookSearch(a),
        "outlook.draft" => OutlookDraft(a),
        _ => throw new HostError($"Unknown Office method {method}.", "invalid_input"),
    }, 120_000);

    // ------------------------------------------------------------------ Excel

    private static object ExcelList()
    {
        dynamic excel = App("Excel.Application", "Excel", create: false);
        var books = new List<object>();
        foreach (dynamic wb in excel.Workbooks)
        {
            var sheets = new List<string>();
            foreach (dynamic ws in wb.Worksheets) sheets.Add((string)ws.Name);
            books.Add(new { name = (string)wb.Name, path = (string)wb.FullName, sheets, active = (string)wb.ActiveSheet.Name, saved = (bool)wb.Saved });
        }
        return new { workbooks = books };
    }

    private static dynamic Workbook(Args a, bool create = false)
    {
        var path = a.Str("path");
        dynamic excel = App("Excel.Application", "Excel", create: path is not null || create);
        var wanted = a.Str("workbook");
        foreach (dynamic wb in excel.Workbooks)
        {
            string name = wb.Name, full = wb.FullName;
            if ((path is not null && string.Equals(full, path, StringComparison.OrdinalIgnoreCase))
                || (wanted is not null && (name.Equals(wanted, StringComparison.OrdinalIgnoreCase) || name.StartsWith(wanted, StringComparison.OrdinalIgnoreCase))))
                return wb;
        }
        if (path is not null)
        {
            if (!File.Exists(path)) throw new HostError($"{Path.GetFileName(path)} doesn't exist.", "not_found");
            return excel.Workbooks.Open(path);
        }
        if (wanted is not null) throw new HostError($"No open workbook called '{wanted}'.", "not_found");
        if (excel.ActiveWorkbook is null)
        {
            if (create) return excel.Workbooks.Add();
            throw new HostError("Excel has no workbook open.", "not_found");
        }
        return excel.ActiveWorkbook;
    }

    private static dynamic Sheet(dynamic wb, Args a)
    {
        var name = a.Str("sheet");
        if (name is null) return wb.ActiveSheet;
        foreach (dynamic ws in wb.Worksheets) if (((string)ws.Name).Equals(name, StringComparison.OrdinalIgnoreCase)) return ws;
        if (a.Bool("create_sheet", false)) { dynamic ws = wb.Worksheets.Add(); ws.Name = name; return ws; }
        throw new HostError($"No sheet called '{name}'.", "not_found");
    }

    private static object? Cell(object? v) => v switch
    {
        null => null,
        double d when Math.Abs(d % 1) < 1e-12 && Math.Abs(d) < 1e15 => (long)d,
        _ => v,
    };

    private static object ExcelRead(Args a)
    {
        dynamic wb = Workbook(a);
        dynamic ws = Sheet(wb, a);
        dynamic range = a.Str("range") is string r ? Prop(ws, "Range", r) : ws.UsedRange;
        int rows = range.Rows.Count, cols = range.Columns.Count;
        var truncated = false;
        if ((long)rows * cols > MaxCells)
        {
            rows = Math.Max(1, MaxCells / Math.Max(1, cols));
            range = Prop(range, "Resize", rows, cols);
            truncated = true;
        }
        object raw = a.Bool("formulas", false) ? range.Formula : range.Value2;
        var data = new List<List<object?>>();
        if (raw is object[,] grid)
        {
            for (int i = grid.GetLowerBound(0); i <= grid.GetUpperBound(0); i++)
            {
                var row = new List<object?>();
                for (int j = grid.GetLowerBound(1); j <= grid.GetUpperBound(1); j++) row.Add(Cell(grid[i, j]));
                data.Add(row);
            }
        }
        else data.Add([Cell(raw)]);
        // Trailing empty rows are noise for the model.
        while (data.Count > 0 && data[^1].All(c => c is null || (c is string s && s.Length == 0))) data.RemoveAt(data.Count - 1);
        return new
        {
            ok = true,
            summary = $"Read {data.Count} rows × {cols} columns from {(string)ws.Name}{(truncated ? " (first part only)" : "")}.",
            data = new { workbook = (string)wb.Name, sheet = (string)ws.Name, address = (string)Prop(range, "Address", false, false), rows = data, truncated },
        };
    }

    private static object ExcelWrite(Args a)
    {
        dynamic wb = Workbook(a, create: true);
        dynamic ws = Sheet(wb, a);
        var values = a.Arr("values") ?? throw new HostError("excel_write needs values: a list of rows.", "invalid_input");
        var rows = values.Select(r => r as System.Text.Json.Nodes.JsonArray ?? [r?.DeepClone()]).ToList();
        int nr = rows.Count, nc = rows.Max(r => r.Count);
        if (nr == 0 || nc == 0) throw new HostError("values is empty.", "invalid_input");
        if ((long)nr * nc > MaxCells) throw new HostError($"Write at most {MaxCells} cells at once.", "invalid_input");
        var grid = new object?[nr, nc];
        for (int i = 0; i < nr; i++)
            for (int j = 0; j < nc; j++)
            {
                var node = j < rows[i].Count ? rows[i][j] : null;
                grid[i, j] = node switch
                {
                    null => null,
                    System.Text.Json.Nodes.JsonValue v when v.TryGetValue<double>(out var d) => d,
                    System.Text.Json.Nodes.JsonValue v when v.TryGetValue<bool>(out var b) => b,
                    System.Text.Json.Nodes.JsonValue v when v.TryGetValue<string>(out var s) => s,
                    _ => node.ToJsonString(),
                };
            }
        dynamic start = Prop(ws, "Range", a.Str("range") ?? "A1");
        dynamic target = Prop(Prop(start, "Cells", 1, 1), "Resize", nr, nc);
        // Formula accepts both values and "=..." formulas in one assignment.
        target.Formula = grid;
        if (a.Bool("autofit", true)) target.Columns.AutoFit();
        return new
        {
            ok = true,
            summary = $"Wrote {nr} rows × {nc} columns to {(string)ws.Name}!{(string)Prop(target, "Address", false, false)} (not saved yet).",
            data = new { workbook = (string)wb.Name, sheet = (string)ws.Name, address = (string)Prop(target, "Address", false, false) },
        };
    }

    private static object ExcelSave(Args a)
    {
        dynamic wb = Workbook(a);
        var target = a.Str("save_as");
        var format = (a.Str("format") ?? Path.GetExtension(target ?? "")?.TrimStart('.') ?? "xlsx").ToLowerInvariant();
        if (target is null) { wb.Save(); return new { ok = true, summary = $"Saved {(string)wb.Name}.", data = new { path = (string)wb.FullName } }; }
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        if (format == "pdf") wb.ExportAsFixedFormat(0, target);
        else
        {
            var code = format switch { "csv" => 6, "xls" => 56, "xlsm" => 52, _ => 51 };
            wb.Application.DisplayAlerts = false;
            try { wb.SaveAs(target, code); } finally { wb.Application.DisplayAlerts = true; }
        }
        return new { ok = true, summary = $"Saved {(string)wb.Name} as {Path.GetFileName(target)}.", data = new { path = target } };
    }

    // ------------------------------------------------------------------ Word

    private static dynamic Document(Args a, bool create = false)
    {
        var path = a.Str("path");
        dynamic word = App("Word.Application", "Word", create: path is not null || create);
        var wanted = a.Str("document");
        foreach (dynamic d in word.Documents)
        {
            string name = d.Name, full = d.FullName;
            if ((path is not null && full.Equals(path, StringComparison.OrdinalIgnoreCase))
                || (wanted is not null && name.StartsWith(wanted, StringComparison.OrdinalIgnoreCase))) return d;
        }
        if (path is not null)
        {
            if (!File.Exists(path)) throw new HostError($"{Path.GetFileName(path)} doesn't exist.", "not_found");
            return word.Documents.Open(path);
        }
        if (word.Documents.Count == 0)
        {
            if (create) return word.Documents.Add();
            throw new HostError("Word has no document open.", "not_found");
        }
        return word.ActiveDocument;
    }

    private static object WordRead(Args a)
    {
        dynamic doc = Document(a);
        string text = doc.Content.Text ?? "";
        text = text.Replace("\r", "\n");
        var max = a.Int("max", 200_000);
        return new
        {
            ok = true,
            summary = $"Read {(string)doc.Name}: {text.Length} characters, {(int)doc.Paragraphs.Count} paragraphs.",
            data = new { document = (string)doc.Name, path = (string)doc.FullName, content = text.Length > max ? text[..max] : text, length = text.Length },
        };
    }

    private static object WordWrite(Args a)
    {
        dynamic doc = Document(a, create: true);
        var mode = a.Str("mode") ?? (a.Has("find") ? "replace" : "append");
        switch (mode)
        {
            case "replace":
            {
                var find = a.Req("find");
                var replacement = a.Str("text") ?? a.Str("replace") ?? "";
                dynamic range = doc.Content;
                bool found = range.Find.Execute(FindText: find, MatchCase: false, Forward: true, Wrap: 1, ReplaceWith: replacement, Replace: 2);
                return new { ok = found, summary = found ? $"Replaced '{find}' in {(string)doc.Name}." : $"'{find}' isn't in {(string)doc.Name}.", data = new { document = (string)doc.Name } };
            }
            case "replace_all":
                doc.Content.Text = a.Str("text") ?? "";
                break;
            default:
                doc.Content.InsertAfter((doc.Content.Text.Length > 1 ? "\r" : "") + (a.Str("text") ?? "").Replace("\n", "\r"));
                break;
        }
        return new { ok = true, summary = $"Updated {(string)doc.Name} (not saved yet).", data = new { document = (string)doc.Name } };
    }

    private static object WordSave(Args a)
    {
        dynamic doc = Document(a);
        var target = a.Str("save_as");
        if (target is null) { doc.Save(); return new { ok = true, summary = $"Saved {(string)doc.Name}.", data = new { path = (string)doc.FullName } }; }
        var format = (a.Str("format") ?? Path.GetExtension(target).TrimStart('.')).ToLowerInvariant();
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        doc.SaveAs2(target, format switch { "pdf" => 17, "txt" => 2, "rtf" => 6, _ => 16 });
        return new { ok = true, summary = $"Saved {(string)doc.Name} as {Path.GetFileName(target)}.", data = new { path = target } };
    }

    // ------------------------------------------------------------------ Outlook (classic)

    private static dynamic Namespace() => App("Outlook.Application", "Outlook", create: true).GetNamespace("MAPI");

    private static object Mail(dynamic item, bool full)
    {
        string body = "";
        try { body = item.Body ?? ""; } catch { }
        var flat = string.Join(" ", body.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        var attachments = new List<string>();
        try { foreach (dynamic att in item.Attachments) attachments.Add((string)att.FileName); } catch { }
        return new
        {
            id = (string)item.EntryID,
            subject = (string)(item.Subject ?? ""),
            from = SafeStr(() => item.SenderName),
            fromAddress = SafeStr(() => item.SenderEmailAddress),
            to = SafeStr(() => item.To),
            received = SafeStr(() => ((DateTime)item.ReceivedTime).ToString("s")),
            unread = SafeBool(() => item.UnRead),
            body = full ? (body.Length > 50_000 ? body[..50_000] : body) : null,
            preview = full ? null : flat[..Math.Min(200, flat.Length)],
            attachments,
        };
    }

    private static string SafeStr(Func<object?> get) { try { return get()?.ToString() ?? ""; } catch { return ""; } }
    private static bool SafeBool(Func<object?> get) { try { return get() is true; } catch { return false; } }

    private static dynamic Folder(dynamic ns, string? name) => (name ?? "inbox").ToLowerInvariant() switch
    {
        "sent" => ns.GetDefaultFolder(5),
        "drafts" => ns.GetDefaultFolder(16),
        "outbox" => ns.GetDefaultFolder(4),
        _ => ns.GetDefaultFolder(6),
    };

    private static object OutlookList(Args a)
    {
        dynamic folder = Folder(Namespace(), a.Str("folder"));
        dynamic items = folder.Items;
        items.Sort("[ReceivedTime]", true);
        if (a.Bool("unread_only", false)) items = items.Restrict("[UnRead] = True");
        var list = new List<object>();
        var count = Math.Clamp(a.Int("count", 20), 1, 100);
        foreach (dynamic item in items)
        {
            if (list.Count >= count) break;
            try { if ((int)item.Class != 43) continue; } catch { continue; } // mail items only
            list.Add(Mail(item, full: false));
        }
        return new { ok = true, summary = $"{list.Count} messages in {(string)folder.Name}.", data = new { folder = (string)folder.Name, messages = list } };
    }

    private static object OutlookRead(Args a)
    {
        dynamic item = Namespace().GetItemFromID(a.Req("id"));
        return new { ok = true, summary = $"Read ‘{(string)(item.Subject ?? "")}’.", data = Mail(item, full: true) };
    }

    private static object OutlookSearch(Args a)
    {
        var q = a.Req("query").Replace("'", "''");
        dynamic folder = Folder(Namespace(), a.Str("folder"));
        var filter = $"@SQL=(\"urn:schemas:httpmail:subject\" LIKE '%{q}%' OR \"urn:schemas:httpmail:fromname\" LIKE '%{q}%' OR \"urn:schemas:httpmail:textdescription\" LIKE '%{q}%')";
        dynamic items = folder.Items.Restrict(filter);
        items.Sort("[ReceivedTime]", true);
        var list = new List<object>();
        var count = Math.Clamp(a.Int("count", 20), 1, 100);
        foreach (dynamic item in items)
        {
            if (list.Count >= count) break;
            try { if ((int)item.Class != 43) continue; } catch { continue; }
            list.Add(Mail(item, full: false));
        }
        return new { ok = true, summary = $"{list.Count} messages match ‘{a.Str("query")}’.", data = new { messages = list } };
    }

    private static object OutlookDraft(Args a)
    {
        var ns = Namespace();
        dynamic app = ns.Application;
        dynamic mail;
        if (a.Str("reply_to") is string id)
        {
            dynamic original = ns.GetItemFromID(id);
            mail = a.Bool("reply_all", false) ? original.ReplyAll() : original.Reply();
        }
        else
        {
            mail = app.CreateItem(0);
            mail.To = a.Req("to");
        }
        if (a.Str("cc") is string cc) mail.CC = cc;
        if (a.Str("subject") is string subject) mail.Subject = subject;
        var body = a.Str("body") ?? "";
        mail.Body = a.Has("reply_to") ? body + "\n\n" + (string)(mail.Body ?? "") : body;
        foreach (var node in a.Arr("attachments") ?? [])
        {
            var file = node?.GetValue<string>();
            if (file is not null && File.Exists(file)) mail.Attachments.Add(file);
        }
        mail.Save();
        mail.Display(false);
        return new
        {
            ok = true,
            summary = $"Drafted ‘{(string)(mail.Subject ?? "")}’ to {(string)(mail.To ?? "")} and opened it in Outlook for the owner to send.",
            data = new { id = (string)mail.EntryID, to = (string)(mail.To ?? ""), subject = (string)(mail.Subject ?? "") },
        };
    }
}
