# Mouse and keyboard, as the owner watches. mode: click | move | type | keys | scroll
. "$PSScriptRoot\common.ps1"
try {
  $mode = Arg 'mode'
  function Glide([int]$x, [int]$y) {
    $p = New-Object SyphNative+POINT
    [SyphNative]::GetCursorPos([ref]$p) | Out-Null
    for ($i = 1; $i -le 14; $i++) {
      $t = $i / 14.0
      $e = if ($t -lt 0.5) { 2 * $t * $t } else { 1 - [Math]::Pow(-2 * $t + 2, 2) / 2 }
      [SyphNative]::SetCursorPos([int]($p.X + ($x - $p.X) * $e), [int]($p.Y + ($y - $p.Y) * $e)) | Out-Null
      Start-Sleep -Milliseconds 18
    }
  }
  switch ($mode) {
    'click' {
      $x = [int](Arg 'x'); $y = [int](Arg 'y')
      $right = (Arg 'button' 'left') -eq 'right'
      $count = [Math]::Max(1, [Math]::Min(3, [int](Arg 'count' 1)))
      Glide $x $y
      $down = if ($right) { 0x8 } else { 0x2 }; $up = if ($right) { 0x10 } else { 0x4 }
      for ($i = 0; $i -lt $count; $i++) {
        [SyphNative]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 15
        [SyphNative]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
      }
      Emit @{ ok = $true; summary = "Clicked at $x, $y." }
    }
    'move' { Glide ([int](Arg 'x')) ([int](Arg 'y')); Emit @{ ok = $true; summary = 'Moved the pointer.' } }
    'type' {
      Add-Type -AssemblyName System.Windows.Forms
      $text = [string](Arg 'text' '')
      $sb = New-Object System.Text.StringBuilder
      foreach ($ch in $text.ToCharArray()) {
        if ('+^%~(){}[]'.Contains([string]$ch)) { [void]$sb.Append('{' + $ch + '}') }
        elseif ($ch -eq "`n") { [void]$sb.Append('{ENTER}') }
        elseif ($ch -eq "`r") { }
        elseif ($ch -eq "`t") { [void]$sb.Append('{TAB}') }
        else { [void]$sb.Append($ch) }
      }
      [System.Windows.Forms.SendKeys]::SendWait($sb.ToString())
      $front = Foreground
      Emit @{ ok = $true; summary = "Typed $($text.Length) characters into $($front.app)." }
    }
    'keys' {
      Add-Type -AssemblyName System.Windows.Forms
      $combo = [string](Arg 'keys' '')
      $names = @{ enter = '{ENTER}'; return = '{ENTER}'; tab = '{TAB}'; esc = '{ESC}'; escape = '{ESC}'; backspace = '{BACKSPACE}'
                  delete = '{DELETE}'; del = '{DELETE}'; up = '{UP}'; down = '{DOWN}'; left = '{LEFT}'; right = '{RIGHT}'
                  home = '{HOME}'; end = '{END}'; pageup = '{PGUP}'; pagedown = '{PGDN}'; space = ' '; insert = '{INSERT}' }
      for ($i = 1; $i -le 12; $i++) { $names["f$i"] = "{F$i}" }
      $prefix = ''; $key = $null; $win = $false
      foreach ($part in ($combo.ToLower() -replace ' ', '').Split('+')) {
        switch ($part) {
          { $_ -in 'ctrl', 'control', 'cmd', 'command' } { $prefix += '^' }
          'shift' { $prefix += '+' }
          { $_ -in 'alt', 'opt', 'option' } { $prefix += '%' }
          { $_ -in 'win', 'windows', 'super', 'meta' } { $win = $true }
          default { if ($names.ContainsKey($_)) { $key = $names[$_] } elseif ($_.Length -eq 1) { $key = $_ } }
        }
      }
      if (-not $key) { Fail "'$combo' isn't a shortcut this PC understands." }
      if ($win) {
        [SyphNative]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)
        $vk = [byte]([SyphNative]::VkKeyScan([char]$key) -band 0xFF)
        [SyphNative]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); [SyphNative]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
        [SyphNative]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
      } else {
        [System.Windows.Forms.SendKeys]::SendWait($prefix + $key)
      }
      Emit @{ ok = $true; summary = "Pressed $combo." }
    }
    'scroll' {
      $dir = [string](Arg 'direction' 'down'); $amount = [Math]::Max(1, [Math]::Min(50, [int](Arg 'amount' 5)))
      switch ($dir) {
        'up' { [SyphNative]::mouse_event(0x0800, 0, 0, 120 * $amount, [UIntPtr]::Zero) }
        'left' { [SyphNative]::mouse_event(0x01000, 0, 0, -120 * $amount, [UIntPtr]::Zero) }
        'right' { [SyphNative]::mouse_event(0x01000, 0, 0, 120 * $amount, [UIntPtr]::Zero) }
        default { [SyphNative]::mouse_event(0x0800, 0, 0, -120 * $amount, [UIntPtr]::Zero) }
      }
      Emit @{ ok = $true; summary = "Scrolled $dir." }
    }
    default { Fail "Unknown input mode $mode." }
  }
} catch { Fail $_.Exception.Message }
