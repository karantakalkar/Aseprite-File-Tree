$ErrorActionPreference = "Stop"

# Build paths are rooted beside this script so it works from any shell cwd.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$extensionPath = Join-Path $root "aseprite-file-tree.aseprite-extension"
$zipPath = Join-Path $root "aseprite-file-tree.zip"

# Only ship source and metadata files that Aseprite needs at runtime.
$files = @(
    "package.json",
    "folder_browser.lua",
    "browser_core.lua",
    "browser_draw.lua",
    "README.md"
)

# Remove previous build artifacts before creating a fresh archive.
foreach ($path in @($extensionPath, $zipPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path
    }
}

# Aseprite extensions are zip archives renamed with the .aseprite-extension suffix.
$fullPaths = $files | ForEach-Object { Join-Path $root $_ }
Compress-Archive -LiteralPath $fullPaths -DestinationPath $zipPath
Move-Item -LiteralPath $zipPath -Destination $extensionPath

# Print the exact artifact path for install/debugging.
Write-Host "Built $extensionPath"
