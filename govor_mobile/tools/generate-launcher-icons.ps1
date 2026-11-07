param([string]$Project = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$logo = [Drawing.Image]::FromFile((Join-Path $Project 'assets/govor.png'))
function Make-Icon([int]$size, [double]$scale, [bool]$opaque) {
    $format = if ($opaque) { [Drawing.Imaging.PixelFormat]::Format24bppRgb } else { [Drawing.Imaging.PixelFormat]::Format32bppArgb }
    $canvas = [Drawing.Bitmap]::new($size, $size, $format)
    $g = [Drawing.Graphics]::FromImage($canvas)
    try {
        if ($opaque) { $g.Clear([Drawing.Color]::FromArgb(255, 25, 26, 42)) }
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $target = [Math]::Max(1, [Math]::Round($size * $scale))
        $ratio = [Math]::Min($target / $logo.Width, $target / $logo.Height)
        $w = [int][Math]::Round($logo.Width * $ratio)
        $h = [int][Math]::Round($logo.Height * $ratio)
        $g.DrawImage($logo, [int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
        $buffer = [IO.MemoryStream]::new()
        try { $canvas.Save($buffer, [Drawing.Imaging.ImageFormat]::Png); return ,$buffer.ToArray() }
        finally { $buffer.Dispose() }
    } finally { $g.Dispose(); $canvas.Dispose() }
}

try {
    $targets = @(
        Get-ChildItem (Join-Path $Project 'android/app/src/main/res') -Filter 'ic_launcher.png' -Recurse
        Get-ChildItem (Join-Path $Project 'ios/Runner/Assets.xcassets/AppIcon.appiconset') -Filter '*.png'
        Get-ChildItem (Join-Path $Project 'macos/Runner/Assets.xcassets/AppIcon.appiconset') -Filter '*.png'
        Get-ChildItem (Join-Path $Project 'web/icons') -Filter '*.png'
        Get-Item (Join-Path $Project 'web/favicon.png')
    )
    foreach ($target in $targets) {
        $old = [Drawing.Image]::FromFile($target.FullName)
        try { $size = $old.Width } finally { $old.Dispose() }
        $maskable = $target.Name -like '*maskable*'
        $ios = $target.Name -like 'Icon-App-*'
        $scale = if ($maskable) { 0.68 } elseif ($ios) { 0.86 } else { 0.94 }
        [IO.File]::WriteAllBytes($target.FullName, (Make-Icon $size $scale ($maskable -or $ios)))
    }

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @($sizes | ForEach-Object { ,(Make-Icon $_ 0.97 $false) })
    $ico = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $Project 'windows/runner/resources/app_icon.ico')))
    try {
        $ico.Write([uint16]0); $ico.Write([uint16]1); $ico.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $ico.Write([byte]($sizes[$i] % 256)); $ico.Write([byte]($sizes[$i] % 256))
            $ico.Write([byte]0); $ico.Write([byte]0)
            $ico.Write([uint16]1); $ico.Write([uint16]32)
            $ico.Write([uint32]$frames[$i].Length); $ico.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $ico.Write([byte[]]$frame) }
    } finally { $ico.Dispose() }
} finally { $logo.Dispose() }
