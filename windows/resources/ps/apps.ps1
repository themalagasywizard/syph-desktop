# Open or quit applications by name. mode: open | quit
. "$PSScriptRoot\common.ps1"
try {
  $mode = Arg 'mode'
  $name = [string](Arg 'app' '')
  if (-not $name) { Fail 'Give an app name.' }
  $bare = ($name -replace '\.exe$', '').ToLower()
  if ($mode -eq 'open') {
    # Start menu entries cover Win32 and Store apps alike.
    $entry = $null
    try {
      $apps = Get-StartApps
      $entry = $apps | Where-Object { $_.Name.ToLower() -eq $bare } | Select-Object -First 1
      if (-not $entry) { $entry = $apps | Where-Object { $_.Name.ToLower().Contains($bare) } | Sort-Object { $_.Name.Length } | Select-Object -First 1 }
    } catch {}
    if ($entry) {
      Start-Process "shell:AppsFolder\$($entry.AppID)"
      Start-Sleep -Milliseconds 900
      Emit @{ ok = $true; summary = "Opened $($entry.Name)." }
      exit 0
    }
    try {
      Start-Process $bare
      Start-Sleep -Milliseconds 900
      Emit @{ ok = $true; summary = "Opened $name." }
    } catch { Fail "Couldn't find an app called '$name'." }
  } elseif ($mode -eq 'quit') {
    $procs = @(Get-Process | Where-Object { $_.ProcessName.ToLower() -eq $bare -or ($_.MainWindowTitle -and $_.MainWindowTitle.ToLower().Contains($bare)) })
    $procs = @($procs | Where-Object { $_.ProcessName -notmatch '^(Syph|electron)$' })
    if ($procs.Count -eq 0) { Fail "$name isn't running." }
    foreach ($p in $procs) { [void]$p.CloseMainWindow() }
    Emit @{ ok = $true; summary = "Asked $($procs[0].ProcessName) to close." }
  } else { Fail "Unknown mode $mode." }
} catch { Fail $_.Exception.Message }
