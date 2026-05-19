$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$extensionPath = Join-Path $root "aseprite-file-tree.aseprite-extension"
$zipPath = Join-Path $root "aseprite-file-tree.zip"
$files = @(
    "package.json",
    "folder_browser.lua",
    "browser_core.lua",
    "browser_draw.lua",
    "README.md"
)

foreach ($path in @($extensionPath, $zipPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path
    }
}

$fullPaths = $files | ForEach-Object { Join-Path $root $_ }
Compress-Archive -LiteralPath $fullPaths -DestinationPath $zipPath
Move-Item -LiteralPath $zipPath -Destination $extensionPath

Write-Host "Built $extensionPath"
