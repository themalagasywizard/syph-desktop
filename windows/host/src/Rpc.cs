using System.Text.Json;
using System.Text.Json.Nodes;

namespace Syph.Host;

/// <summary>A failure the caller can act on; its message goes back to the agent verbatim.</summary>
public sealed class HostError(string message, string code = "failed") : Exception(message)
{
    public string Code { get; } = code;
}

/// <summary>Typed reads of a request's params object.</summary>
public sealed class Args(JsonObject? obj)
{
    private readonly JsonObject _o = obj ?? new JsonObject();
    public JsonObject Raw => _o;

    public bool Has(string key) => _o.TryGetPropertyValue(key, out var v) && v is not null
        && !(v is JsonValue jv && jv.TryGetValue<string>(out var s) && s.Length == 0);

    public string? Str(string key)
    {
        if (!_o.TryGetPropertyValue(key, out var v) || v is null) return null;
        if (v is JsonValue jv)
        {
            if (jv.TryGetValue<string>(out var s)) return s.Length == 0 ? null : s;
            return jv.ToJsonString();
        }
        return v.ToJsonString();
    }

    public string Req(string key) => Str(key) ?? throw new HostError($"'{key}' is required.", "invalid_input");

    public double? Num(string key)
    {
        if (!_o.TryGetPropertyValue(key, out var v) || v is not JsonValue jv) return null;
        if (jv.TryGetValue<double>(out var d)) return d;
        if (jv.TryGetValue<string>(out var s) && double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out d)) return d;
        return null;
    }

    public int Int(string key, int fallback) => Num(key) is double d ? (int)Math.Round(d) : fallback;
    public int? IntOrNull(string key) => Num(key) is double d ? (int)Math.Round(d) : null;

    public bool Bool(string key, bool fallback)
    {
        if (!_o.TryGetPropertyValue(key, out var v) || v is not JsonValue jv) return fallback;
        if (jv.TryGetValue<bool>(out var b)) return b;
        if (jv.TryGetValue<string>(out var s)) return s is "true" or "1" or "yes";
        if (jv.TryGetValue<double>(out var d)) return d != 0;
        return fallback;
    }

    public JsonArray? Arr(string key) => _o.TryGetPropertyValue(key, out var v) ? v as JsonArray : null;
    public Args Obj(string key) => new(_o.TryGetPropertyValue(key, out var v) ? v as JsonObject : null);
}

internal static class J
{
    public static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = false };
    public static JsonNode? From(object? value) => value is null ? null : JsonSerializer.SerializeToNode(value, value.GetType(), Options);
}
