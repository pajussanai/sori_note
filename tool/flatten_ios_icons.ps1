# iOS 앱 아이콘에서 알파 채널을 없앤다(App Store는 투명도가 있는 아이콘을 받지 않는다).
# generate_brand_icons_test.dart를 실행한 뒤 Windows PowerShell에서 실행한다.
#   powershell -File tool/flatten_ios_icons.ps1
Add-Type -AssemblyName System.Drawing
$dir = Join-Path $PSScriptRoot '..\ios\Runner\Assets.xcassets\AppIcon.appiconset'
foreach ($file in Get-ChildItem $dir -Filter 'Icon-App-*.png') {
  $src = [System.Drawing.Image]::FromFile($file.FullName)
  $rgb = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($rgb)
  $g.Clear([System.Drawing.Color]::FromArgb(255, 0x2E, 0x6E, 0x73))
  $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
  $g.Dispose()
  $src.Dispose()
  $rgb.Save($file.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
  $rgb.Dispose()
}
