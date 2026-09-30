using System.Runtime.InteropServices;
using Interop.UIAutomationClient;
using static Interop.UIAutomationClient.UIA_PropertyIds;
using static Interop.UIAutomationClient.UIA_PatternIds;

namespace Syph.Host;

/// <summary>A control on screen. Id stays the same for the same control across snapshots,
/// so the agent can say "click 14" after looking.</summary>
public sealed record Element(int Id, string Role, string Name, string? Value, int X, int Y, int W, int H,
    bool Enabled, bool Focused, bool Password, string[] Actions, string? State, string? AutomationId, long Window)
{
    public int Left => X - W / 2;
    public int Top => Y - H / 2;
}

/// <summary>UI Automation (UIA3 via COM). One cached tree query per window keeps
/// snapshots fast even for large apps.</summary>
public static class Uia
{
    private static CUIAutomation8? _auto;
    private static IUIAutomationCacheRequest? _cache;
    private static readonly Dictionary<string, int> Ids = new();
    private static readonly Dictionary<int, IUIAutomationElement> Live = new();
    private static int _nextId = 1;

    private static CUIAutomation8 Auto
    {
        get
        {
            if (_auto is not null) return _auto;
            _auto = new CUIAutomation8();
            try
            {
                var two = (IUIAutomation2)_auto;
                two.AutoSetFocus = 0;            // looking must never move focus
                two.ConnectionTimeout = 2000;    // a hung app fails fast instead of hanging the agent
                two.TransactionTimeout = 6000;
            }
            catch { /* pre-Windows 8 */ }
            var c = _auto.CreateCacheRequest();
            foreach (var p in new[] {
                UIA_NamePropertyId, UIA_ControlTypePropertyId, UIA_BoundingRectanglePropertyId, UIA_IsEnabledPropertyId,
                UIA_HasKeyboardFocusPropertyId, UIA_IsKeyboardFocusablePropertyId, UIA_IsPasswordPropertyId, UIA_AutomationIdPropertyId,
                UIA_ValueValuePropertyId, UIA_ValueIsReadOnlyPropertyId, UIA_ToggleToggleStatePropertyId,
                UIA_ExpandCollapseExpandCollapseStatePropertyId, UIA_SelectionItemIsSelectedPropertyId,
                UIA_IsInvokePatternAvailablePropertyId, UIA_IsValuePatternAvailablePropertyId, UIA_IsTogglePatternAvailablePropertyId,
                UIA_IsSelectionItemPatternAvailablePropertyId, UIA_IsExpandCollapsePatternAvailablePropertyId,
                UIA_IsScrollPatternAvailablePropertyId, UIA_IsTextPatternAvailablePropertyId, UIA_IsRangeValuePatternAvailablePropertyId,
                UIA_RangeValueValuePropertyId, UIA_NativeWindowHandlePropertyId })
                c.AddProperty(p);
            _cache = c;
            return _auto;
        }
    }

    private static readonly Dictionary<int, string> Roles = new()
    {
        [50000] = "Button", [50001] = "Calendar", [50002] = "CheckBox", [50003] = "ComboBox", [50004] = "Edit", [50005] = "Link",
        [50006] = "Image", [50007] = "ListItem", [50008] = "List", [50009] = "Menu", [50010] = "MenuBar", [50011] = "MenuItem",
        [50012] = "ProgressBar", [50013] = "RadioButton", [50014] = "ScrollBar", [50015] = "Slider", [50016] = "Spinner",
        [50017] = "StatusBar", [50018] = "Tab", [50019] = "TabItem", [50020] = "Text", [50021] = "ToolBar", [50022] = "ToolTip",
        [50023] = "Tree", [50024] = "TreeItem", [50025] = "Custom", [50026] = "Group", [50027] = "Thumb", [50028] = "DataGrid",
        [50029] = "DataItem", [50030] = "Document", [50031] = "SplitButton", [50032] = "Window", [50033] = "Pane", [50034] = "Header",
        [50035] = "HeaderItem", [50036] = "Table", [50037] = "TitleBar", [50038] = "Separator", [50039] = "SemanticZoom", [50040] = "AppBar",
    };

    private static readonly HashSet<string> Interactive =
    [
        "Button", "CheckBox", "ComboBox", "Edit", "Link", "ListItem", "MenuItem", "RadioButton", "Slider", "Spinner", "TabItem",
        "TreeItem", "SplitButton", "DataItem", "HeaderItem", "Document", "Calendar",
    ];

    private static T? Cached<T>(IUIAutomationElement e, int prop)
    {
        try { var v = e.GetCachedPropertyValue(prop); return v is T t ? t : default; } catch { return default; }
    }

    private static int IdFor(IUIAutomationElement e)
    {
        string key;
        try { key = string.Join(".", e.GetRuntimeId()); } catch { key = Guid.NewGuid().ToString(); }
        if (!Ids.TryGetValue(key, out var id))
        {
            if (Ids.Count > 20_000) { Ids.Clear(); Live.Clear(); }
            id = _nextId++;
            Ids[key] = id;
        }
        Live[id] = e;
        return id;
    }

    private static Element Describe(IUIAutomationElement e, long window)
    {
        var role = Roles.GetValueOrDefault(Cached<int>(e, UIA_ControlTypePropertyId), "Custom");
        var name = (Cached<string>(e, UIA_NamePropertyId) ?? "").Trim();
        var rect = e.CachedBoundingRectangle;
        int w = rect.right - rect.left, h = rect.bottom - rect.top;
        var password = Cached<bool>(e, UIA_IsPasswordPropertyId);
        var actions = new List<string>();
        if (Cached<bool>(e, UIA_IsInvokePatternAvailablePropertyId)) actions.Add("invoke");
        if (Cached<bool>(e, UIA_IsTogglePatternAvailablePropertyId)) actions.Add("toggle");
        if (Cached<bool>(e, UIA_IsSelectionItemPatternAvailablePropertyId)) actions.Add("select");
        if (Cached<bool>(e, UIA_IsExpandCollapsePatternAvailablePropertyId)) actions.Add("expand");
        var hasValue = Cached<bool>(e, UIA_IsValuePatternAvailablePropertyId);
        if (hasValue && !Cached<bool>(e, UIA_ValueIsReadOnlyPropertyId)) actions.Add("set_value");
        if (Cached<bool>(e, UIA_IsScrollPatternAvailablePropertyId)) actions.Add("scroll");
        if (Cached<bool>(e, UIA_IsTextPatternAvailablePropertyId)) actions.Add("get_text");
        string? value = null;
        if (hasValue && !password)
        {
            value = Cached<string>(e, UIA_ValueValuePropertyId);
            if (value is { Length: > 300 }) value = value[..300] + "…";
        }
        else if (Cached<bool>(e, UIA_IsRangeValuePatternAvailablePropertyId))
        {
            value = Cached<double>(e, UIA_RangeValueValuePropertyId).ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        var states = new List<string>();
        if (Cached<bool>(e, UIA_IsTogglePatternAvailablePropertyId))
            states.Add(Cached<int>(e, UIA_ToggleToggleStatePropertyId) switch { 1 => "checked", 2 => "mixed", _ => "unchecked" });
        if (Cached<bool>(e, UIA_IsExpandCollapsePatternAvailablePropertyId))
            states.Add(Cached<int>(e, UIA_ExpandCollapseExpandCollapseStatePropertyId) switch { 1 => "expanded", 2 => "partial", 3 => "leaf", _ => "collapsed" });
        if (Cached<bool>(e, UIA_IsSelectionItemPatternAvailablePropertyId) && Cached<bool>(e, UIA_SelectionItemIsSelectedPropertyId)) states.Add("selected");
        var aid = Cached<string>(e, UIA_AutomationIdPropertyId);
        return new Element(IdFor(e), role, name.Length > 200 ? name[..200] + "…" : name, value,
            rect.left + w / 2, rect.top + h / 2, w, h,
            Cached<bool>(e, UIA_IsEnabledPropertyId), Cached<bool>(e, UIA_HasKeyboardFocusPropertyId), password,
            actions.ToArray(), states.Count > 0 ? string.Join(",", states) : null,
            string.IsNullOrEmpty(aid) || aid.Length > 60 ? null : aid, window);
    }

    /// <summary>Windows to read for "what the owner sees in front": the foreground window plus
    /// open menus and popups above it (context menus, dropdowns) from any app.</summary>
    public static List<IntPtr> FrontWindows(IntPtr fg)
    {
        var list = new List<IntPtr> { fg };
        Native.GetWindowThreadProcessId(fg, out var fgPid);
        var popups = new List<IntPtr>();
        Native.EnumWindows((h, _) =>
        {
            if (h == fg) return false; // z-order: stop once we reach the foreground window
            if (!Native.IsWindowVisible(h) || Native.IsCloaked(h)) return true;
            var cls = Native.ClassName(h);
            Native.GetWindowThreadProcessId(h, out var pid);
            var r = Native.FrameRect(h);
            if (r.Width < 4 || r.Height < 4 || pid == Environment.ProcessId) return true;
            // Menus (#32768), and popups owned by the front app (dropdowns, autocomplete, Office backstage).
            if (cls == "#32768" || (pid == fgPid && cls != "Shell_TrayWnd")) popups.Add(h);
            return true;
        }, IntPtr.Zero);
        list.AddRange(popups.Take(6));
        return list;
    }

    public static List<Element> Elements(IEnumerable<IntPtr> windows, int limit, bool interactiveOnly)
    {
        var auto = Auto;
        var condition = auto.CreateAndCondition(auto.ControlViewCondition, auto.CreatePropertyCondition(UIA_IsOffscreenPropertyId, false));
        var all = new List<Element>();
        foreach (var hwnd in windows)
        {
            if (hwnd == IntPtr.Zero) continue;
            IUIAutomationElementArray found;
            try
            {
                var root = auto.ElementFromHandle(hwnd);
                found = root.FindAllBuildCache(TreeScope.TreeScope_Descendants, condition, _cache);
            }
            catch (COMException) { continue; }
            var frame = Native.FrameRect(hwnd);
            for (int i = 0; i < found.Length; i++)
            {
                Element el;
                try { el = Describe(found.GetElement(i), hwnd.ToInt64()); } catch (COMException) { continue; }
                if (el.W < 2 || el.H < 2) continue;
                // Clip to the window: virtualized lists report rows far outside it.
                if (el.X < frame.Left - 2 || el.X > frame.Right + 2 || el.Y < frame.Top - 2 || el.Y > frame.Bottom + 2) continue;
                var interactive = Interactive.Contains(el.Role) || el.Actions.Any(a => a is "invoke" or "toggle" or "select" or "expand" or "set_value");
                if (interactiveOnly && !interactive) continue;
                if (!interactive && el.Name.Length == 0) continue;
                all.Add(el);
            }
        }
        // Keep controls first when trimming, then reading order.
        return all
            .GroupBy(e => e.Id).Select(g => g.First())
            .OrderByDescending(e => Interactive.Contains(e.Role) || e.Actions.Length > 0)
            .Take(limit)
            .OrderBy(e => e.Window == all.FirstOrDefault()?.Window ? 1 : 0) // popups above the window first
            .ThenBy(e => e.Top / 8).ThenBy(e => e.Left)
            .ToList();
    }

    public static Element? Focused()
    {
        try
        {
            var e = Auto.GetFocusedElementBuildCache(_cache);
            return e is null ? null : Describe(e, Native.GetForegroundWindow().ToInt64());
        }
        catch (COMException) { return null; }
    }

    public static Element? AtPoint(int x, int y)
    {
        try
        {
            var e = Auto.ElementFromPointBuildCache(new tagPOINT { x = x, y = y }, _cache);
            return e is null ? null : Describe(e, 0);
        }
        catch (COMException) { return null; }
    }

    private static IUIAutomationElement Get(int id)
    {
        if (!Live.TryGetValue(id, out var e)) throw new HostError($"There is no element {id}. Take a new snapshot and use its ids.", "not_found");
        try { _ = e.CurrentBoundingRectangle; }
        catch (COMException) { Live.Remove(id); throw new HostError($"Element {id} is gone from the screen. Take a new snapshot.", "not_found"); }
        return e;
    }

    public static Element Refresh(int id)
    {
        var e = Get(id).BuildUpdatedCache(_cache);
        Live[id] = e;
        return Describe(e, 0);
    }

    /// <summary>Screen point to click an element at: its clickable point, else its centre.</summary>
    public static (int X, int Y) ClickPoint(int id)
    {
        var e = Get(id);
        try
        {
            if (e.CurrentIsOffscreen != 0 && e.GetCurrentPattern(UIA_ScrollItemPatternId) is IUIAutomationScrollItemPattern si)
            {
                si.ScrollIntoView();
                Thread.Sleep(150);
            }
        }
        catch (COMException) { }
        try
        {
            if (e.GetClickablePoint(out var pt) != 0) return (pt.x, pt.y);
        }
        catch (COMException) { }
        var r = e.CurrentBoundingRectangle;
        if (r.right - r.left < 1) throw new HostError($"Element {id} has no position on screen.", "not_found");
        return ((r.left + r.right) / 2, (r.top + r.bottom) / 2);
    }

    /// <summary>Acts on an element through its UIA patterns: works even when the window is behind others.</summary>
    public static Element Act(int id, string action, string? value)
    {
        var e = Get(id);
        Guard.NotSyphProcess(e.CurrentProcessId);
        switch (action)
        {
            case "invoke":
            case "press":
            {
                if (e.GetCurrentPattern(UIA_InvokePatternId) is IUIAutomationInvokePattern inv) { inv.Invoke(); break; }
                if (e.GetCurrentPattern(UIA_TogglePatternId) is IUIAutomationTogglePattern tog) { tog.Toggle(); break; }
                if (e.GetCurrentPattern(UIA_SelectionItemPatternId) is IUIAutomationSelectionItemPattern sel) { sel.Select(); break; }
                if (e.GetCurrentPattern(UIA_ExpandCollapsePatternId) is IUIAutomationExpandCollapsePattern ec)
                {
                    if (ec.CurrentExpandCollapseState == ExpandCollapseState.ExpandCollapseState_Expanded) ec.Collapse(); else ec.Expand();
                    break;
                }
                if (e.GetCurrentPattern(UIA_LegacyIAccessiblePatternId) is IUIAutomationLegacyIAccessiblePattern leg && !string.IsNullOrEmpty(leg.CurrentDefaultAction))
                {
                    leg.DoDefaultAction(); break;
                }
                var (x, y) = ClickPoint(id);
                Input.Click(x, y);
                break;
            }
            case "toggle":
                (e.GetCurrentPattern(UIA_TogglePatternId) as IUIAutomationTogglePattern ?? throw new HostError($"Element {id} can't be toggled.", "unsupported")).Toggle();
                break;
            case "select":
                (e.GetCurrentPattern(UIA_SelectionItemPatternId) as IUIAutomationSelectionItemPattern ?? throw new HostError($"Element {id} can't be selected.", "unsupported")).Select();
                break;
            case "expand":
                (e.GetCurrentPattern(UIA_ExpandCollapsePatternId) as IUIAutomationExpandCollapsePattern ?? throw new HostError($"Element {id} can't be expanded.", "unsupported")).Expand();
                break;
            case "collapse":
                (e.GetCurrentPattern(UIA_ExpandCollapsePatternId) as IUIAutomationExpandCollapsePattern ?? throw new HostError($"Element {id} can't be collapsed.", "unsupported")).Collapse();
                break;
            case "focus":
                e.SetFocus();
                break;
            case "scroll_into_view":
                (e.GetCurrentPattern(UIA_ScrollItemPatternId) as IUIAutomationScrollItemPattern ?? throw new HostError($"Element {id} can't scroll into view.", "unsupported")).ScrollIntoView();
                break;
            case "set_value":
            {
                var text = value ?? "";
                if (e.CurrentIsPassword == 0 && e.GetCurrentPattern(UIA_ValuePatternId) is IUIAutomationValuePattern vp && vp.CurrentIsReadOnly == 0)
                {
                    try
                    {
                        vp.SetValue(text);
                        Thread.Sleep(60);
                        // Some editors accept SetValue but ignore it; fall through to typing if so.
                        if ((vp.CurrentValue ?? "") == text) break;
                    }
                    catch (COMException) { }
                }
                var (x, y) = ClickPoint(id);
                Input.Click(x, y);
                try { e.SetFocus(); } catch (COMException) { }
                Input.Chords("ctrl+a");
                if (text.Length == 0) Input.Chords("delete"); else Input.Type(text);
                break;
            }
            default:
                throw new HostError($"Unknown element action '{action}'.", "invalid_input");
        }
        Thread.Sleep(80);
        try { return Refresh(id); }
        catch (HostError) { return new Element(id, "", "", null, 0, 0, 0, 0, false, false, false, [], "gone", null, 0); }
    }

    public static string Text(int id, int max = 200_000)
    {
        var e = Get(id);
        if (e.CurrentIsPassword != 0) throw new HostError("That is a password field; Syph never reads those.", "policy_denied");
        if (e.GetCurrentPattern(UIA_TextPatternId) is IUIAutomationTextPattern tp) return tp.DocumentRange.GetText(max) ?? "";
        if (e.GetCurrentPattern(UIA_ValuePatternId) is IUIAutomationValuePattern vp) return vp.CurrentValue ?? "";
        return e.CurrentName ?? "";
    }

    /// <summary>First element whose name matches (exact, then contains), optionally of a role.</summary>
    public static Element? Find(IEnumerable<Element> elements, string name, string? role = null)
    {
        var pool = elements.Where(e => role is null || e.Role.Equals(role, StringComparison.OrdinalIgnoreCase)).ToList();
        var n = name.Trim();
        return pool.FirstOrDefault(e => e.Name.Equals(n, StringComparison.OrdinalIgnoreCase) && e.Enabled)
            ?? pool.FirstOrDefault(e => e.Name.Equals(n, StringComparison.OrdinalIgnoreCase))
            ?? pool.Where(e => e.Name.Contains(n, StringComparison.OrdinalIgnoreCase)).OrderBy(e => e.Name.Length).FirstOrDefault()
            ?? pool.FirstOrDefault(e => e.AutomationId is not null && e.AutomationId.Equals(n, StringComparison.OrdinalIgnoreCase));
    }
}
