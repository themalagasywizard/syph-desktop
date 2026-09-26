# Read the controls of the foreground window with UI Automation, or press one by name.
. "$PSScriptRoot\common.ps1"
try {
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $front = Foreground
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($front.hwnd)
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $limit = [int](Arg 'limit' 220)
  $found = New-Object System.Collections.ArrayList
  $refs = New-Object System.Collections.ArrayList

  function Walk($el, [int]$depth) {
    if ($depth -gt 12 -or $found.Count -ge $limit) { return }
    $child = $walker.GetFirstChild($el)
    while ($null -ne $child -and $found.Count -lt $limit) {
      try {
        $cur = $child.Current
        $role = $cur.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        $name = $cur.Name
        $value = ''
        if ($role -eq 'Edit' -or $role -eq 'Document') {
          try { $value = $child.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch {}
        }
        $r = $cur.BoundingRectangle
        if (($name -or $value -or $role -eq 'Edit') -and -not $r.IsEmpty -and $r.Width -gt 1 -and $r.Height -gt 1) {
          [void]$found.Add(@{ role = $role; title = $name; value = "$value".Substring(0, [Math]::Min(200, "$value".Length))
                              x = [int]($r.X + $r.Width / 2); y = [int]($r.Y + $r.Height / 2); w = [int]$r.Width; h = [int]$r.Height })
          [void]$refs.Add($child)
        }
      } catch {}
      Walk $child ($depth + 1)
      $child = $walker.GetNextSibling($child)
    }
  }
  Walk $root 0

  $press = Arg 'press'
  if ($press) {
    $needle = "$press".ToLower()
    $actionable = @('Button', 'MenuItem', 'CheckBox', 'RadioButton', 'Hyperlink', 'TabItem', 'ListItem', 'TreeItem', 'SplitButton', 'ComboBox', 'Text')
    $index = -1
    for ($i = 0; $i -lt $found.Count; $i++) { if ($actionable -contains $found[$i].role -and "$($found[$i].title)".ToLower() -eq $needle) { $index = $i; break } }
    if ($index -lt 0) { for ($i = 0; $i -lt $found.Count; $i++) { if ($actionable -contains $found[$i].role -and "$($found[$i].title)".ToLower().Contains($needle)) { $index = $i; break } } }
    if ($index -lt 0) { Fail "No control named '$press' in the front window. Try read_ui to see what's there." }
    $el = $refs[$index]
    $done = $false
    foreach ($pattern in @([System.Windows.Automation.InvokePattern]::Pattern, [System.Windows.Automation.TogglePattern]::Pattern,
                           [System.Windows.Automation.SelectionItemPattern]::Pattern, [System.Windows.Automation.ExpandCollapsePattern]::Pattern)) {
      $p = $null
      if ($el.TryGetCurrentPattern($pattern, [ref]$p)) {
        if ($p -is [System.Windows.Automation.InvokePattern]) { $p.Invoke() }
        elseif ($p -is [System.Windows.Automation.TogglePattern]) { $p.Toggle() }
        elseif ($p -is [System.Windows.Automation.SelectionItemPattern]) { $p.Select() }
        else { $p.Expand() }
        $done = $true; break
      }
    }
    if (-not $done) {
      [SyphNative]::SetCursorPos($found[$index].x, $found[$index].y) | Out-Null
      [SyphNative]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); [SyphNative]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)
    }
    Emit @{ ok = $true; summary = "Pressed '$($found[$index].title)'."; data = @{ x = $found[$index].x; y = $found[$index].y } }
    exit 0
  }
  $where = if ($front.title) { " - $($front.title)" } else { '' }
  Emit @{ ok = $true; summary = "Found $($found.Count) controls in $($front.app)$where."; data = @{
    app = $front.app; window = $front.title; elements = @($found) } }
} catch { Fail $_.Exception.Message }
