. "$PSScriptRoot\common.ps1"
try {
  $front = Foreground
  $windows = @(Get-Process | Where-Object { $_.MainWindowTitle } | Select-Object -First 40 | ForEach-Object {
    @{ app = $_.ProcessName; title = $_.MainWindowTitle }
  })
  $p = New-Object SyphNative+POINT
  [SyphNative]::GetCursorPos([ref]$p) | Out-Null
  $label = if ($front.app) { $front.app } else { 'nothing' }
  Emit @{ ok = $true; summary = "$label is in front; $($windows.Count) windows open."; data = @{
    app = $front.app; window = $front.title; windows = $windows
    running_apps = @($windows | ForEach-Object { $_.app } | Select-Object -Unique)
    screen = (ScreenSize); pointer = @{ x = $p.X; y = $p.Y }; platform = 'windows'
  } }
} catch { Fail $_.Exception.Message }
