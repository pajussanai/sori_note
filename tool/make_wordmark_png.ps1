# 워드마크 PNG(심볼 + 글자)를 만든다. generate_brand_icons_test.dart를 먼저 실행해
# brand/png/sori_symbol_256.png가 있어야 한다. Windows PowerShell에서 실행한다.
#   powershell -File tool/make_wordmark_png.ps1
Add-Type -AssemblyName System.Drawing
$root = Join-Path $PSScriptRoot '..\brand\png'
$symbol = [System.Drawing.Image]::FromFile((Join-Path $root 'sori_symbol_256.png'))
$charcoal = [System.Drawing.Color]::FromArgb(255, 0x30, 0x3A, 0x38)

function Make-Wordmark([string]$text, [string]$font, [string]$out) {
  $height = 320
  $f = New-Object System.Drawing.Font $font, 150, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $probe = New-Object System.Drawing.Bitmap 10, 10
  $pg = [System.Drawing.Graphics]::FromImage($probe)
  $textSize = $pg.MeasureString($text, $f)
  $pg.Dispose(); $probe.Dispose()
  $width = [int]($height + 56 + $textSize.Width + 24)
  $bmp = New-Object System.Drawing.Bitmap $width, $height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($symbol, 24, 24, $height - 48, $height - 48)
  $brush = New-Object System.Drawing.SolidBrush $charcoal
  $y = ($height - $textSize.Height) / 2
  $g.DrawString($text, $f, $brush, ($height + 24), $y)
  $g.Dispose()
  $bmp.Save((Join-Path $root $out), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# 스크립트 인코딩과 상관없도록 '소리노트'를 유니코드 코드값으로 만든다.
$ko = -join ([char]0xC18C, [char]0xB9AC, [char]0xB178, [char]0xD2B8)
Make-Wordmark $ko 'Malgun Gothic' 'sori_wordmark_ko.png'
Make-Wordmark 'Sori Note' 'Segoe UI' 'sori_wordmark_en.png'
$symbol.Dispose()
