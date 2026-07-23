$ErrorActionPreference = "Stop"

# Resolve every checked file relative to the repo root.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$packagePath = Join-Path $root "package.json"
$mainPath = Join-Path $root "folder_browser.lua"
$corePath = Join-Path $root "browser_core.lua"
$drawPath = Join-Path $root "browser_draw.lua"
$watcherPath = Join-Path $root "filesystem_watcher.lua"
$platformPath = Join-Path $root "platform.lua"
$readmePath = Join-Path $root "README.md"
$buildPath = Join-Path $root "build-extension.ps1"
$testRunnerPath = Join-Path $root "run-tests.ps1"
$filesystemTestsPath = Join-Path $root "tests\filesystem_tests.lua"
$fakeFilesystemPath = Join-Path $root "tests\fake_filesystem.lua"
$extensionPath = Join-Path $root "aseprite-file-tree.aseprite-extension"

# Fail early when a required source/build file is missing.
foreach ($path in @($packagePath, $mainPath, $corePath, $drawPath, $watcherPath, $platformPath, $readmePath, $buildPath, $testRunnerPath, $filesystemTestsPath, $fakeFilesystemPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
}

# Check package metadata that Aseprite uses to load the extension script.
$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
if ($package.name -ne "aseprite-file-tree") {
    throw "package.json name must be aseprite-file-tree"
}

if ($package.contributes.scripts[0].path -ne "./folder_browser.lua") {
    throw "package.json must contribute ./folder_browser.lua"
}

# Load source text once so feature checks stay simple and readable.
$main = Get-Content -LiteralPath $mainPath -Raw
$core = Get-Content -LiteralPath $corePath -Raw
$draw = Get-Content -LiteralPath $drawPath -Raw
$watcher = Get-Content -LiteralPath $watcherPath -Raw
$platform = Get-Content -LiteralPath $platformPath -Raw
$readme = Get-Content -LiteralPath $readmePath -Raw
$packageText = Get-Content -LiteralPath $packagePath -Raw
$allText = "$main`n$core`n$draw`n$watcher`n$platform`n$readme`n$packageText"

# Guard against accidental local machine paths or removed defaults leaking into releases.
foreach ($localPattern in @(
    "[A-Za-z]:\\Users\\[^\\]+\\",
    "default_[a-z]+_art_path"
)) {
    if ($allText -match $localPattern) {
        throw "Extension files must not contain local workspace reference matching: $localPattern"
    }
}

# These strings represent old behavior that should stay removed.
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
    "MIN_DEEP_SEARCH",
    "collect_filtered_expanded_rows"
)) {
    if ($allText.Contains($removedText)) {
        throw "Removed confusing behavior is still referenced: $removedText"
    }
}

# Entry-point checks ensure the extension command and module loading still exist.
foreach ($text in @(
    "plugin:newCommand",
    "File Tree",
    "Dialog",
    "browser_core",
    "browser_draw"
)) {
    if (-not $main.Contains($text)) {
        throw "folder_browser.lua is missing: $text"
    }
}

# Core feature checks cover browsing, filtering, context actions, creation, preview, and delete.
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
    "clipboard_path",
    "toggle_favorite",
    "write_browser_settings",
    "queue_filter",
    "apply_pending_filter",
    "pending_filter_text",
    "New File",
    "New Folder",
    "create_file",
    "create_aseprite_file",
    "file_type_options",
    "file_type",
    "create_folder",
    "makeDirectory",
    "rename_path",
    "os.rename",
    "Sprite(16, 16)",
    "preview_enabled",
    "preview_w",
    "toggle_preview",
    "load_preview",
    "resize_preview_at",
    "is_preview_divider",
    "set_resize_cursor",
    "mousecursor",
    "MouseCursor.WE_RESIZE",
    "Image{ fromFile = path }",
    "Delete",
    "delete_path",
    "delete_folder",
    "copy_file",
    "copy_folder",
    "set_clipboard",
    "paste_into",
    "Cut",
    "Copy",
    "Paste",
    "os.remove"
)) {
    if (-not $core.Contains($text) -and -not $main.Contains($text)) {
        throw "Core browser feature is missing: $text"
    }
}

# Search behavior checks cover the debounced deep-search implementation.
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

# Draw checks cover tree lines, menus, preview rendering, and favorites sections.
foreach ($text in @(
    "paint_tree_lines",
    "paint_context_menu",
    "paint_preview",
    "drawImage",
    "section_bg",
    "menu_text",
    "Favorites"
)) {
    if (-not $draw.Contains($text) -and -not $main.Contains($text) -and -not $core.Contains($text)) {
        throw "Drawing or tree feature is missing: $text"
    }
}

# UI label checks catch accidental removal of important controls.
foreach ($text in @(
    "root_entry",
    "clear_root",
    'text = "Path"',
    'text = "Search"',
    'text = "Type"',
    'text = "Root"',
    'text = "Preview: Off"',
    "Set Root"
)) {
    if (-not $allText.Contains($text)) {
        throw "Requested root/label behavior is missing: $text"
    }
}

# README checks keep visible documentation aligned with shipped behavior.
foreach ($text in @(
    "Search",
    "Favorites",
    "Right-click",
    "Preview",
    "Drag the divider",
    "horizontal resize cursor",
    "Delete",
    "Cut",
    "Copy",
    "paste",
    "typed extension",
    "empty tree space"
)) {
    if (-not $readme.Contains($text)) {
        throw "README is missing publish-ready documentation: $text"
    }
}

# Keep release version fixed unless the package metadata is intentionally bumped.
if ($package.version -ne "0.2.0") {
    throw "package.json version must be 0.2.0"
}

# Verify the built extension exists before inspecting archive contents.
if (-not (Test-Path -LiteralPath $extensionPath)) {
    throw "Missing built extension: $extensionPath"
}

# The extension archive must contain runtime files at the zip root.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($extensionPath)
try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName }
    foreach ($entry in @("package.json", "folder_browser.lua", "browser_core.lua", "browser_draw.lua", "filesystem_watcher.lua", "platform.lua", "README.md")) {
        if ($entries -notcontains $entry) {
            throw "Extension archive must contain $entry at the root"
        }
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Aseprite Folder Browser extension package verified."
