using System.Runtime.InteropServices;
using static Syph.Host.Native;

namespace Syph.Host;

/// <summary>Mouse and keyboard through SendInput. Text is typed as Unicode, so every
/// language and emoji works regardless of the keyboard layout.</summary>
public static class Input
{
    /// <summary>True while Syph is injecting input; the watcher ignores pointer moves then.</summary>
    public static volatile bool Acting;

    private static void Send(params INPUT[] inputs)
    {
        if (inputs.Length == 0) return;
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        if (sent != inputs.Length)
            throw new HostError("Windows blocked the input. An administrator window or the lock screen may be in front; Syph cannot act on those.", "blocked");
    }

    private static INPUT Mouse(uint flags, int data = 0, int dx = 0, int dy = 0) => new()
    {
        type = INPUT_MOUSE,
        U = new InputUnion { mi = new MOUSEINPUT { dx = dx, dy = dy, mouseData = unchecked((uint)data), dwFlags = flags, dwExtraInfo = SyphMarker } },
    };

    private static INPUT Key(ushort vk, bool up, bool extended = false) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, wScan = (ushort)MapVirtualKey(vk, 0), dwFlags = (up ? KEYEVENTF_KEYUP : 0) | (extended ? KEYEVENTF_EXTENDEDKEY : 0), dwExtraInfo = SyphMarker } },
    };

    private static INPUT Unicode(char ch, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = 0, wScan = ch, dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0), dwExtraInfo = SyphMarker } },
    };

    public static void MoveTo(int x, int y, bool glide = true)
    {
        GetCursorPos(out var p);
        if (glide)
        {
            // A short eased glide: the owner can follow where the agent is going.
            var distance = Math.Sqrt(Math.Pow(x - p.X, 2) + Math.Pow(y - p.Y, 2));
            var steps = Math.Clamp((int)(distance / 60), 3, 12);
            for (int i = 1; i < steps; i++)
            {
                var t = (double)i / steps;
                var e = t < 0.5 ? 2 * t * t : 1 - Math.Pow(-2 * t + 2, 2) / 2;
                SetCursorPos((int)(p.X + (x - p.X) * e), (int)(p.Y + (y - p.Y) * e));
                Thread.Sleep(8);
            }
        }
        SetCursorPos(x, y);
        // A zero-length relative move so the target window gets WM_MOUSEMOVE (hover states, tooltips).
        Send(Mouse(MOUSEEVENTF_MOVE));
    }

    private static (uint Down, uint Up) Buttons(string button) => button switch
    {
        "right" => (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
        "middle" => (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
        _ => (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
    };

    public static void Click(int x, int y, string button = "left", int count = 1, IEnumerable<string>? modifiers = null)
    {
        var mods = (modifiers ?? []).Select(m => Keys.Resolve(m)).ToList();
        MoveTo(x, y);
        foreach (var m in mods) Send(Key(m.Vk, false, m.Extended));
        try
        {
            var (down, up) = Buttons(button);
            for (int i = 0; i < Math.Clamp(count, 1, 3); i++)
            {
                Send(Mouse(down));
                Thread.Sleep(12);
                Send(Mouse(up));
                if (i + 1 < count) Thread.Sleep(45);
            }
        }
        finally
        {
            foreach (var m in Enumerable.Reverse(mods)) Send(Key(m.Vk, true, m.Extended));
        }
    }

    public static void Drag(int fromX, int fromY, int toX, int toY, string button = "left", int holdMs = 120)
    {
        var (down, up) = Buttons(button);
        MoveTo(fromX, fromY);
        Send(Mouse(down));
        try
        {
            Thread.Sleep(Math.Clamp(holdMs, 30, 2000));
            // Move in small steps so drag-and-drop targets see the pointer travel.
            const int steps = 20;
            for (int i = 1; i <= steps; i++)
            {
                SetCursorPos(fromX + (toX - fromX) * i / steps, fromY + (toY - fromY) * i / steps);
                Send(Mouse(MOUSEEVENTF_MOVE));
                Thread.Sleep(12);
            }
            Thread.Sleep(80);
        }
        finally
        {
            Send(Mouse(up));
        }
    }

    public static void MouseButton(string button, bool upNotDown)
    {
        var (down, up) = Buttons(button);
        Send(Mouse(upNotDown ? up : down));
    }

    public static void Scroll(string direction, int amount, int? x = null, int? y = null)
    {
        if (x is int px && y is int py) MoveTo(px, py, glide: false);
        amount = Math.Clamp(amount, 1, 50);
        for (int i = 0; i < amount; i++)
        {
            switch (direction)
            {
                case "up": Send(Mouse(MOUSEEVENTF_WHEEL, 120)); break;
                case "left": Send(Mouse(MOUSEEVENTF_HWHEEL, -120)); break;
                case "right": Send(Mouse(MOUSEEVENTF_HWHEEL, 120)); break;
                default: Send(Mouse(MOUSEEVENTF_WHEEL, -120)); break;
            }
            Thread.Sleep(15);
        }
    }

    /// <summary>Types text as Unicode key events. Newlines become Enter and tabs Tab,
    /// so multi-line text works in editors and forms alike.</summary>
    public static void Type(string text, int delayMs = 4)
    {
        var batch = new List<INPUT>();
        void Flush() { if (batch.Count > 0) { Send(batch.ToArray()); batch.Clear(); } }
        for (int i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (ch == '\r') continue;
            if (ch == '\n' || ch == '\t')
            {
                Flush();
                var vk = (ushort)(ch == '\n' ? 0x0D : 0x09);
                Send(Key(vk, false), Key(vk, true));
                if (delayMs > 0) Thread.Sleep(delayMs);
                continue;
            }
            batch.Add(Unicode(ch, false));
            batch.Add(Unicode(ch, true));
            // Small batches keep ordering reliable in apps that process input slowly.
            if (batch.Count >= 32 || delayMs > 0) { Flush(); if (delayMs > 0) Thread.Sleep(delayMs); }
        }
        Flush();
    }

    /// <summary>Presses one or more chords in sequence: "ctrl+s", "alt+f4", "ctrl+a delete", "win+r".</summary>
    public static void Chords(string spec, int holdMs = 0)
    {
        var chords = Keys.ParseSequence(spec);
        if (chords.Count == 0) throw new HostError($"'{spec}' isn't a key or shortcut this PC understands.", "invalid_input");
        foreach (var chord in chords)
        {
            var downs = chord.Select(k => Key(k.Vk, false, k.Extended)).ToArray();
            var ups = chord.AsEnumerable().Reverse().Select(k => Key(k.Vk, true, k.Extended)).ToArray();
            Send(downs);
            try { Thread.Sleep(Math.Clamp(holdMs, 15, 10_000)); }
            finally { Send(ups); }
            Thread.Sleep(30);
        }
    }

    public static void KeyDown(string spec) { foreach (var k in Keys.ParseChord(spec)) Send(Key(k.Vk, false, k.Extended)); }
    public static void KeyUp(string spec) { foreach (var k in Keys.ParseChord(spec).AsEnumerable().Reverse()) Send(Key(k.Vk, true, k.Extended)); }

    /// <summary>Releases every modifier, in case an interrupted action left one down.</summary>
    public static void ReleaseModifiers()
    {
        foreach (var vk in new ushort[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) Send(Key(vk, true, vk is 0x5B or 0x5C));
    }
}

public readonly record struct VKey(ushort Vk, bool Extended);

public static class Keys
{
    private static readonly Dictionary<string, VKey> Named = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ctrl"] = new(0x11, false), ["control"] = new(0x11, false), ["cmd"] = new(0x11, false), ["command"] = new(0x11, false),
        ["shift"] = new(0x10, false), ["alt"] = new(0x12, false), ["option"] = new(0x12, false), ["opt"] = new(0x12, false), ["menu"] = new(0x12, false),
        ["win"] = new(0x5B, true), ["windows"] = new(0x5B, true), ["super"] = new(0x5B, true), ["meta"] = new(0x5B, true), ["start"] = new(0x5B, true),
        ["enter"] = new(0x0D, false), ["return"] = new(0x0D, false), ["tab"] = new(0x09, false), ["esc"] = new(0x1B, false), ["escape"] = new(0x1B, false),
        ["space"] = new(0x20, false), ["spacebar"] = new(0x20, false), ["backspace"] = new(0x08, false), ["bksp"] = new(0x08, false),
        ["delete"] = new(0x2E, true), ["del"] = new(0x2E, true), ["insert"] = new(0x2D, true), ["ins"] = new(0x2D, true),
        ["home"] = new(0x24, true), ["end"] = new(0x23, true), ["pageup"] = new(0x21, true), ["pgup"] = new(0x21, true),
        ["pagedown"] = new(0x22, true), ["pgdn"] = new(0x22, true),
        ["up"] = new(0x26, true), ["down"] = new(0x28, true), ["left"] = new(0x25, true), ["right"] = new(0x27, true),
        ["arrowup"] = new(0x26, true), ["arrowdown"] = new(0x28, true), ["arrowleft"] = new(0x25, true), ["arrowright"] = new(0x27, true),
        ["capslock"] = new(0x14, false), ["numlock"] = new(0x90, true), ["scrolllock"] = new(0x91, false),
        ["printscreen"] = new(0x2C, true), ["prtsc"] = new(0x2C, true), ["pause"] = new(0x13, false),
        ["apps"] = new(0x5D, true), ["contextmenu"] = new(0x5D, true),
        ["volumeup"] = new(0xAF, true), ["volumedown"] = new(0xAE, true), ["volumemute"] = new(0xAD, true), ["mute"] = new(0xAD, true),
        ["playpause"] = new(0xB3, true), ["nexttrack"] = new(0xB0, true), ["prevtrack"] = new(0xB1, true),
        ["plus"] = new(0xBB, false), ["minus"] = new(0xBD, false), ["comma"] = new(0xBC, false), ["period"] = new(0xBE, false),
    };

    static Keys()
    {
        for (int i = 1; i <= 24; i++) Named[$"f{i}"] = new((ushort)(0x70 + i - 1), false);
        for (int i = 0; i <= 9; i++) Named[$"num{i}"] = new((ushort)(0x60 + i), false);
    }

    public static VKey Resolve(string token)
    {
        var t = token.Trim();
        if (Named.TryGetValue(t, out var k)) return k;
        if (t.Length == 1)
        {
            var ch = t[0];
            if (char.IsLetter(ch) && ch < 128) return new((ushort)char.ToUpperInvariant(ch), false);
            if (char.IsDigit(ch)) return new((ushort)ch, false);
            var scan = Native.VkKeyScanEx(ch, Native.GetKeyboardLayout(0));
            if (scan != -1) return new((ushort)(scan & 0xFF), false);
        }
        throw new HostError($"'{token}' isn't a key this PC understands.", "invalid_input");
    }

    public static List<VKey> ParseChord(string chord)
    {
        // "ctrl++" means ctrl and the plus key.
        var c = chord.Trim().ToLowerInvariant();
        var parts = new List<string>();
        foreach (var raw in c.Replace("++", "+plus").Split('+', StringSplitOptions.RemoveEmptyEntries)) parts.Add(raw.Trim());
        return parts.Select(Resolve).ToList();
    }

    public static List<List<VKey>> ParseSequence(string spec) =>
        spec.Split([' ', ','], StringSplitOptions.RemoveEmptyEntries).Select(ParseChord).Where(c => c.Count > 0).ToList();
}
