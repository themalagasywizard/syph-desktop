using System.Runtime.InteropServices;

namespace Syph.Host;

/// <summary>
/// Notices the owner using the mouse or keyboard while an employee works, so the agent
/// yields at once. Low-level hooks see every input event; Syph's own are stamped with
/// Native.SyphMarker and ignored, and pointer moves are ignored while Syph is moving it.
/// Emits {"event": "human_input", "data": {"kind": "mouse" | "key"}} at most every 300 ms.
/// </summary>
public static class Watcher
{
    private const int WH_KEYBOARD_LL = 13, WH_MOUSE_LL = 14;
    private const int WM_MOUSEMOVE = 0x0200;
    private const uint LLKHF_INJECTED = 0x10, LLMHF_INJECTED = 0x01;

    [StructLayout(LayoutKind.Sequential)] private struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct MSLLHOOKSTRUCT { public Native.POINT pt; public uint mouseData, flags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public Native.POINT pt; }

    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int idHook, HookProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hhk, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern int GetMessage(out MSG msg, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string? name);

    // Delegates must outlive the hooks, or the GC collects them out from under Windows.
    private static readonly HookProc KeyProc = OnKey, MouseProc = OnMouse;
    private static IntPtr _keyHook, _mouseHook;
    private static uint _threadId;
    private static Thread? _thread;
    private static volatile bool _watching;
    private static long _lastEmit;
    private static Native.POINT _anchor;
    private static bool _anchored;

    public static object Configure(Args a)
    {
        var on = a.Bool("on", true);
        if (on) Start();
        _anchored = false;
        _watching = on;
        return new { watching = on };
    }

    private static void Start()
    {
        if (_thread is not null) return;
        var ready = new ManualResetEventSlim();
        _thread = new Thread(() =>
        {
            _threadId = Native.GetCurrentThreadId();
            var module = GetModuleHandle(null);
            _keyHook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyProc, module, 0);
            _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, MouseProc, module, 0);
            ready.Set();
            while (GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }
            UnhookWindowsHookEx(_keyHook);
            UnhookWindowsHookEx(_mouseHook);
        }) { IsBackground = true, Name = "syph-input-watch" };
        _thread.Start();
        ready.Wait(2000);
    }

    /// <summary>After Syph moves the pointer, measure the owner's moves from where it left it.</summary>
    public static void ResetAnchor() => _anchored = false;

    public static void Stop()
    {
        _watching = false;
        if (_threadId != 0) PostThreadMessage(_threadId, 0x0012 /* WM_QUIT */, IntPtr.Zero, IntPtr.Zero);
    }

    private static void Report(string kind)
    {
        var now = Environment.TickCount64;
        if (now - Interlocked.Read(ref _lastEmit) < 300) return;
        Interlocked.Exchange(ref _lastEmit, now);
        // Emit off the hook thread: hooks must return within milliseconds.
        ThreadPool.QueueUserWorkItem(_ => Program.Event("human_input", new { kind }));
    }

    private static IntPtr OnKey(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && _watching)
        {
            var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            var ours = (k.flags & LLKHF_INJECTED) != 0 && k.dwExtraInfo == Native.SyphMarker;
            if (!ours) Report("key");
        }
        return CallNextHookEx(_keyHook, code, wParam, lParam);
    }

    private static IntPtr OnMouse(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && _watching)
        {
            var m = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            var ours = (m.flags & LLMHF_INJECTED) != 0 && m.dwExtraInfo == Native.SyphMarker;
            if (!ours)
            {
                if ((int)wParam == WM_MOUSEMOVE)
                {
                    // Syph positions the pointer with SetCursorPos; only a deliberate move counts.
                    if (!Input.Acting)
                    {
                        if (!_anchored) { _anchor = m.pt; _anchored = true; }
                        else if (Math.Abs(m.pt.X - _anchor.X) + Math.Abs(m.pt.Y - _anchor.Y) > 40) Report("mouse");
                    }
                }
                else Report("mouse");
            }
        }
        return CallNextHookEx(_mouseHook, code, wParam, lParam);
    }
}
