# ส่งออกต้นแบบไอคอน Linko เป็นขนาดที่แต่ละแพลตฟอร์มใช้ โดยไม่เปลี่ยนรูปทรงของภาพต้นฉบับ
# ใช้ System.Drawing บน Windows จึงไม่เพิ่ม dependency เข้าแอปหรือเปลี่ยนกุญแจเซ็น
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = Join-Path $projectRoot 'assets/branding/linko-icon-source.png'
$source = [System.Drawing.Bitmap]::new($sourcePath)
$writtenCount = 0

function New-IconBitmap([int]$Size) {
    # ใช้ RGB ที่ไม่มี alpha เพื่อให้ไฟล์ไอคอน iOS ทึบทั้งภาพ รวมถึงขอบทั้งสี่ด้าน
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        # สะท้อนพิกเซลที่ขอบขณะย่อภาพ เพื่อไม่ให้เกิดเส้นขอบโปร่งใสหรือเส้นสีดำ
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $rectangle = [System.Drawing.Rectangle]::new(0, 0, $Size, $Size)
        $graphics.DrawImage($source, $rectangle, 0, 0, $source.Width, $source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        return $bitmap
    } catch {
        $bitmap.Dispose()
        throw
    } finally {
        $attributes.Dispose()
        $graphics.Dispose()
    }
}

function Write-IconPng([string]$RelativePath, [int]$Size) {
    $destination = Join-Path $projectRoot $RelativePath
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
    $bitmap = New-IconBitmap $Size
    try { $bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    $script:writtenCount++
}

function Write-AppleCatalog([string]$RelativeDirectory) {
    # อ่านชื่อและสเกลจาก catalog จริง เพื่อไม่ทำไฟล์ขนาดเฉพาะของ iPad/Mac ตกหล่น
    $catalogPath = Join-Path $projectRoot "$RelativeDirectory/Contents.json"
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exported = @{}
    foreach ($entry in $catalog.images) {
        if ($exported.ContainsKey($entry.filename)) { continue }
        $points = [double]::Parse($entry.size.Split('x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]$entry.scale.TrimEnd('x')
        Write-IconPng "$RelativeDirectory/$($entry.filename)" ([int]($points * $scale))
        $exported[$entry.filename] = $true
    }
}

function Write-WindowsIcon {
    # ICO รวมหลายขนาด: Windows เลือกภาพที่เหมาะกับ taskbar, หน้าต่าง และ Explorer
    $entries = @()
    foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
        $bitmap = New-IconBitmap $size
        $buffer = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($buffer, [System.Drawing.Imaging.ImageFormat]::Png)
            $entries += [pscustomobject]@{ Size = $size; Bytes = $buffer.ToArray() }
        } finally {
            $buffer.Dispose()
            $bitmap.Dispose()
        }
    }
    $destination = Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'
    $stream = [System.IO.File]::Create($destination)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$entries.Count)
        $offset = 6 + 16 * $entries.Count
        foreach ($entry in $entries) {
            # ICO ใช้ค่า 0 แทนความกว้างหรือสูง 256 พิกเซล
            $dimension = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]24)
            $writer.Write([uint32]$entry.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $entry.Bytes.Length
        }
        foreach ($entry in $entries) { $writer.Write([byte[]]$entry.Bytes) }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
    $script:writtenCount++
}

try {
    if ($source.Width -ne $source.Height) { throw 'The source icon must be square.' }
    Write-IconPng 'assets/branding/linko-icon.png' 1024
    foreach ($density in @(
        @{ Name = 'mdpi'; Size = 48 },
        @{ Name = 'hdpi'; Size = 72 },
        @{ Name = 'xhdpi'; Size = 96 },
        @{ Name = 'xxhdpi'; Size = 144 },
        @{ Name = 'xxxhdpi'; Size = 192 }
    )) {
        Write-IconPng "android/app/src/main/res/mipmap-$($density.Name)/ic_launcher.png" $density.Size
    }
    Write-AppleCatalog 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    Write-AppleCatalog 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    Write-IconPng 'web/favicon.png' 32
    foreach ($size in @(192, 512)) {
        Write-IconPng "web/icons/Icon-$size.png" $size
        Write-IconPng "web/icons/Icon-maskable-$size.png" $size
    }
    Write-WindowsIcon
    Write-Output "Exported $writtenCount Linko icon files."
} finally {
    $source.Dispose()
}
