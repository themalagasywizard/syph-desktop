# Capture the primary display, read it with Windows OCR, and return text with
# click-ready coordinates (physical pixels) plus a small JPEG thumbnail.
. "$PSScriptRoot\common.ps1"
try {
  Add-Type -AssemblyName System.Drawing
  $size = ScreenSize
  $bmp = New-Object System.Drawing.Bitmap $size.width, $size.height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
  $g.Dispose()
  $tmp = Join-Path $env:TEMP ("syph-screen-" + [guid]::NewGuid().ToString() + ".png")
  $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)

  $thumb = $null
  if ((Arg 'thumbnail' $true) -ne $false) {
    $ratio = [Math]::Min(1.0, 1280.0 / [Math]::Max($size.width, $size.height))
    $small = New-Object System.Drawing.Bitmap ([int]($size.width * $ratio)), ([int]($size.height * $ratio))
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.DrawImage($bmp, 0, 0, $small.Width, $small.Height)
    $sg.Dispose()
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $params = New-Object System.Drawing.Imaging.EncoderParameters 1
    $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 55L
    $ms = New-Object System.IO.MemoryStream
    $small.Save($ms, $codec, $params)
    $thumb = [Convert]::ToBase64String($ms.ToArray())
    $small.Dispose(); $ms.Dispose()
  }
  $bmp.Dispose()

  $lines = @()
  $note = ''
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    function Await($op, [Type]$type) {
      $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
      $task.Wait(-1) | Out-Null
      $task.Result
    }
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) {
      $note = 'Windows has no OCR language installed; add one in Settings > Time & language > Language.'
    } else {
      $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
      $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
      $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
      $soft = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
      $result = Await ($engine.RecognizeAsync($soft)) ([Windows.Media.Ocr.OcrResult])
      foreach ($line in $result.Lines) {
        $minX = [double]::MaxValue; $minY = [double]::MaxValue; $maxX = 0.0; $maxY = 0.0
        foreach ($word in $line.Words) {
          $r = $word.BoundingRect
          $minX = [Math]::Min($minX, $r.X); $minY = [Math]::Min($minY, $r.Y)
          $maxX = [Math]::Max($maxX, $r.X + $r.Width); $maxY = [Math]::Max($maxY, $r.Y + $r.Height)
        }
        $lines += @{ text = $line.Text; x = [int](($minX + $maxX) / 2); y = [int](($minY + $maxY) / 2)
                     w = [int]($maxX - $minX); h = [int]($maxY - $minY); left = [int]$minX }
      }
      $stream.Dispose()
    }
  } catch {
    $note = "Windows OCR failed: $($_.Exception.Message)"
  }
  Remove-Item $tmp -ErrorAction SilentlyContinue

  # Reading order: top to bottom, then left to right within a row.
  $sorted = @($lines | Sort-Object @{ Expression = { [Math]::Round($_.y / 8) } }, @{ Expression = { $_.left } })
  $front = Foreground
  $data = @{ text = (($sorted | ForEach-Object { $_.text }) -join "`n"); lines = @($sorted | Select-Object -First 250)
             screen = $size; app = $front.app }
  if ($thumb) { $data._image = $thumb }
  if ($note) { $data.note = $note }
  $summary = if ($note -and $sorted.Count -eq 0) { "Captured the screen. $note" } else { "Read $($sorted.Count) lines of text on screen." }
  Emit @{ ok = $true; summary = $summary; data = $data }
} catch { Fail $_.Exception.Message }
