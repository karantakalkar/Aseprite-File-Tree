$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$packagePath = Join-Path $root "package.json"
$mainPath = Join-Path $root "folder_browser.lua"
$corePath = Join-Path $root "browser_core.lua"
$drawPath = Join-Path $root "browser_draw.lua"
$readmePath = Join-Path $root "README.md"
$buildPath = Join-Path $root "build-extension.ps1"
$extensionPath = Join-Path $root "aseprite-folder-browser.aseprite-extension"

foreach ($path in @($packagePath, $mainPath, $corePath, $drawPath, $readmePath, $buildPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
}

$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
if ($package.name -ne "aseprite-folder-browser") {
    throw "package.json name must be aseprite-folder-browser"
}

if ($package.contributes.scripts[0].path -ne "./folder_browser.lua") {
    throw "package.json must contribute ./folder_browser.lua"
}

$main = Get-Content -LiteralPath $mainPath -Raw
$core = Get-Content -LiteralPath $corePath -Raw
$draw = Get-Content -LiteralPath $drawPath -Raw
$readme = Get-Content -LiteralPath $readmePath -Raw
$packageText = Get-Content -LiteralPath $packagePath -Raw
$allText = "$main`n$core`n$draw`n$readme`n$packageText"

foreach ($localPattern in @(
    "[A-Za-z]:\\Users\\[^\\]+\\",
    "default_[a-z]+_art_path"
)) {
    if ($allText -match $localPattern) {
        throw "Extension files must not contain local workspace reference matching: $localPattern"
    }
}

foreach ($removedText in @(
    "recent_roots",
    "add_recent_root",
    "Recent Folders",
    "Recent automatically",
    "Double-click a folder to use it as the new root",
    "nav_home",
    'text = "Home"',
    "Set as Top",
    "Go to Parent",
    "Folders",
    "Images",
    "MIN_DEEP_SEARCH",
    "collect_filtered_expanded_rows"
)) {
    if ($allText.Contains($removedText)) {
        throw "Removed confusing behavior is still referenced: $removedText"
    }
}

foreach ($text in @(
    "plugin:newCommand",
    "Folder Browser",
    "Dialog",
    "browser_core",
    "browser_draw"
)) {
    if (-not $main.Contains($text)) {
        throw "folder_browser.lua is missing: $text"
    }
}

foreach ($text in @(
    "app.fs.listFiles",
    "app.open",
    ".aseprite",
    ".ase",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".bmp",
    "filter_text",
    "filter_mode",
    "favorites",
    "context_menu",
    "toggle_favorite",
    "queue_filter",
    "apply_pending_filter",
    "pending_filter_text"
)) {
    if (-not $core.Contains($text) -and -not $main.Contains($text)) {
        throw "Core browser feature is missing: $text"
    }
}

foreach ($text in @(
    "search_matches",
    "search_ancestors",
    "mark_search_matches",
    "draw_x",
    "draw_y",
    "context_hover",
    "collect_search_rows",
    "search_index",
    "ensure_search_index",
    "build_search_index",
    "status_text"
)) {
    if (-not $core.Contains($text) -and -not $draw.Contains($text)) {
        throw "Bugfix behavior is missing: $text"
    }
}

foreach ($text in @(
    "paint_tree_lines",
    "paint_context_menu",
    "section_bg",
    "menu_text",
    "Favorites"
)) {
    if (-not $draw.Contains($text) -and -not $main.Contains($text) -and -not $core.Contains($text)) {
        throw "Drawing or tree feature is missing: $text"
    }
}

foreach ($text in @(
    "root_label",
    "clear_root",
    'text = "Path"',
    'text = "Search"',
    'text = "Type"',
    'text = "Root"',
    'text = "Clear"',
    "Set Root"
)) {
    if (-not $allText.Contains($text)) {
        throw "Requested root/label behavior is missing: $text"
    }
}

foreach ($text in @(
    "CHANGELOG",
    "Release",
    "Search",
    "Favorites",
    "Right-click"
)) {
    if (-not $readme.Contains($text)) {
        throw "README is missing publish-ready documentation: $text"
    }
}

if ($package.version -ne "0.2.0") {
    throw "package.json version must be 0.2.0"
}

if (-not (Test-Path -LiteralPath $extensionPath)) {
    throw "Missing built extension: $extensionPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($extensionPath)
try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName }
    foreach ($entry in @("package.json", "folder_browser.lua", "browser_core.lua", "browser_draw.lua", "README.md", "CHANGELOG.md")) {
        if ($entries -notcontains $entry) {
            throw "Extension archive must contain $entry at the root"
        }
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Aseprite Folder Browser extension package verified."
