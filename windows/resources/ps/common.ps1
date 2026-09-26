# Shared prelude for Syph computer-control scripts (Windows PowerShell 5.1).
# Arguments arrive as JSON in SYPH_ARGS; every script prints one JSON line.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$A = if ($env:SYPH_ARGS) { $env:SYPH_ARGS | ConvertFrom-Json } else { [pscustomobject]@{} }

if (-not ('SyphNative' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SyphNative {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, int data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char ch);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
  public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
}
"@
}
# Physical pixels everywhere: capture, OCR boxes, UIA rects and clicks share one space.
[SyphNative]::SetProcessDPIAware() | Out-Null

function Emit($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Depth 6 -Compress)) }
function Fail([string]$message) { Emit @{ ok = $false; summary = $message }; exit 0 }
function Arg([string]$name, $default = $null) {
  if ($A.PSObject.Properties.Name -contains $name -and $null -ne $A.$name -and "$($A.$name)" -ne '') { return $A.$name }
  return $default
}
function ScreenSize { @{ width = [SyphNative]::GetSystemMetrics(0); height = [SyphNative]::GetSystemMetrics(1) } }
function Foreground {
  $h = [SyphNative]::GetForegroundWindow()
  $procId = 0
  [SyphNative]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
  $name = ''
  try { $name = (Get-Process -Id $procId).ProcessName } catch {}
  @{ hwnd = $h; pid = $procId; app = $name; title = [SyphNative]::Title($h) }
}
