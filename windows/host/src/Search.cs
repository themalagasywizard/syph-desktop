using System.Data.OleDb;
using System.Diagnostics;

namespace Syph.Host;

/// <summary>Finds files by name or content with the Windows Search index; walks the folders
/// (names only, time-boxed) when the index is off, as on Windows Server.</summary>
public static class Search
{
    public static object Find(Args a)
    {
        var query = a.Req("query").Trim();
        var roots = (a.Arr("roots") ?? []).Select(n => n?.GetValue<string>()).OfType<string>().Where(Directory.Exists).ToList();
        if (roots.Count == 0) throw new HostError("There is no folder to search in.", "invalid_input");
        var limit = Math.Clamp(a.Int("limit", 50), 1, 200);
        try
        {
            var hits = Indexed(query, roots, limit);
            return new { ok = true, summary = $"{hits.Count} file(s) match ‘{query}’.", data = new { files = hits, source = "index" } };
        }
        catch (Exception)
        {
            var hits = Walk(query, roots, limit);
            return new { ok = true, summary = $"{hits.Count} file(s) named like ‘{query}’ (index unavailable: names only).", data = new { files = hits, source = "walk" } };
        }
    }

    private sealed record Hit(string Path, string Name, long Size, string Modified);

    private static string Escape(string s) => s.Replace("'", "''");

    private static List<Hit> Indexed(string query, List<string> roots, int limit)
    {
        var scopes = string.Join(" OR ", roots.Select(r => $"SCOPE='file:{Escape(r.Replace('\\', '/'))}'"));
        var words = query.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(w => Escape(w.Replace("\"", "")));
        var contains = string.Join(" AND ", words.Select(w => $"\"{w}*\""));
        var sql = $"SELECT TOP {limit} System.ItemPathDisplay, System.FileName, System.Size, System.DateModified FROM SystemIndex " +
                  $"WHERE ({scopes}) AND (System.FileName LIKE '%{Escape(query)}%' OR CONTAINS(*, '{contains}')) ORDER BY System.DateModified DESC";
        using var conn = new OleDbConnection("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';");
        conn.Open();
        using var cmd = new OleDbCommand(sql, conn) { CommandTimeout = 10 };
        using var reader = cmd.ExecuteReader();
        var hits = new List<Hit>();
        while (reader.Read())
        {
            var path = reader.GetValue(0)?.ToString() ?? "";
            if (path.Length == 0) continue;
            long size = reader.IsDBNull(2) ? 0 : Convert.ToInt64(reader.GetValue(2));
            var modified = reader.IsDBNull(3) ? "" : Convert.ToDateTime(reader.GetValue(3)).ToString("s");
            hits.Add(new Hit(path, reader.GetValue(1)?.ToString() ?? Path.GetFileName(path), size, modified));
        }
        return hits;
    }

    private static List<Hit> Walk(string query, List<string> roots, int limit)
    {
        var sw = Stopwatch.StartNew();
        var hits = new List<Hit>();
        var words = query.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.System | FileAttributes.Hidden };
        foreach (var root in roots)
        {
            foreach (var file in Directory.EnumerateFiles(root, "*", options))
            {
                if (sw.ElapsedMilliseconds > 8000 || hits.Count >= limit) return hits;
                var name = Path.GetFileName(file).ToLowerInvariant();
                if (!words.All(name.Contains)) continue;
                var info = new FileInfo(file);
                hits.Add(new Hit(file, info.Name, info.Length, info.LastWriteTime.ToString("s")));
            }
        }
        return hits.OrderByDescending(h => h.Modified).ToList();
    }
}
