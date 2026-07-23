-- browser_core.lua
-- State, filesystem scanning, debounced search, favorites, and navigation.

local M = {}

-- Runtime handles supplied by Aseprite when the plugin starts.
M.plugin = nil
M.dialog = nil

-- Browser navigation and row state.
M.root_path = ""
M.file_cache = {}
M.visible_rows = {}
M.scroll = 0
M.h_scroll = 0
M.history = {}
M.favorites = {}
M.pinned_root = ""

-- Search/filter state. pending_filter_text is used by the debounce timer.
M.filter_text = ""
M.pending_filter_text = ""
M.filter_mode = "All"
M.status_text = ""

-- Selection, hover, and right-click menu state for the tree canvas.
M.selected = nil
M.hovered_idx = nil
M.context_menu = nil
M.context_hover = nil
M.clipboard_path = nil
M.clipboard_action = nil
M.clipboard_is_folder = false
M.drag_source = nil
M.drag_started = false
M.drag_start_x = 0
M.drag_start_y = 0
M.drag_target_path = nil
M.drag_target_idx = nil
M.drag_copy = false

-- Preview pane state. preview_image is an Aseprite Image rendered by browser_draw.lua.
M.preview_enabled = false
M.preview_w = 150
M.preview_path = nil
M.preview_image = nil
M.preview_status = "Preview off."
M.tree_cursor = nil

-- Drag state for vertical, horizontal, and preview-resize interactions.
M.sb_dragging = false
M.sb_drag_y = 0
M.sb_drag_scroll = 0
M.hsb_dragging = false
M.hsb_drag_x = 0
M.hsb_drag_scroll = 0
M.preview_dragging = false

M.content_w = 0
M.content_dirty = true

-- Shared layout constants for row height, scrollbars, menus, and preview sizing.
M.ROW_H = 14
M.INDENT = 10
M.SB_W = 10
M.SB_H = 10
M.CHEVRON_W = 8
M.SCROLL_ROWS = 3
M.PAD_X = 6
M.PAD_Y = 2
M.DEF_W = 260
M.DEF_H = 300
M.MENU_W = 148
M.MENU_ROW_H = 16
M.PREVIEW_DEFAULT_W = 150
M.PREVIEW_MIN_W = 80
M.PREVIEW_MIN_TREE_W = 130
M.PREVIEW_GAP = 3
M.PREVIEW_HANDLE_W = 7

-- Search index caches a flattened tree so text search can expose matching ancestors.
M.search_matches = {}
M.search_ancestors = {}
M.search_index = {}
M.search_index_root = nil

-- Canvas size is updated during paint; input handlers read the latest values.
M.canvas_w = M.DEF_W
M.canvas_h = M.DEF_H

-- File formats the browser shows: .ase, .aseprite, .png, .jpg, .jpeg, .gif, .webp, .bmp.
local supported = {
  ase = true,
  aseprite = true,
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  bmp = true
}

local function lo(s)
  -- Normalize text for case-insensitive extension/name comparisons.
  return string.lower(s or "")
end

local function clean_list(list)
  -- Preferences can be absent or malformed; browser code always wants a table.
  if type(list) == "table" then return list end
  return {}
end

local function list_has(list, path)
  -- Simple membership test for favorite paths.
  for _, item in ipairs(list) do
    if item == path then return true end
  end
  return false
end

local function remove_from_list(list, path)
  -- Remove all matching paths so duplicate favorites cannot survive cleanup.
  for i = #list, 1, -1 do
    if list[i] == path then table.remove(list, i) end
  end
end

local function trimmed(value)
  -- Dialog entries are free text; trim before using them as file/folder names.
  return (value or ""):match("^%s*(.-)%s*$")
end

local function file_exists(path)
  -- Creation and rename operations should not overwrite files or folders.
  return app.fs.isFile(path) or app.fs.isDirectory(path)
end

local function file_type_options()
  -- File types shown in the New File dialog.
  return { ".aseprite", ".ase", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp" }
end

local function file_type_extension(file_type)
  -- Fall back to the native Aseprite file type when dialog data is missing.
  if M.has(file_type) then return file_type end
  return ".aseprite"
end

local function replace_file_extension(name, file_type)
  -- The dropdown is authoritative: typed extensions are replaced by the selected type.
  local ext = app.fs.fileExtension(name)
  local base = name
  if M.has(ext) then base = name:sub(1, #name - #ext - 1) end
  return base .. file_type_extension(file_type)
end

local function row_is_folder(row)
  -- Favorites are folder shortcuts, so folder actions apply to both row shapes.
  return row.is_folder or row.is_shortcut
end

local function rename_file_name(row, name)
  -- File rename preserves the old extension only when the user omits one.
  if row_is_folder(row) then return name end
  if M.has(app.fs.fileExtension(name)) then return name end
  local ext = app.fs.fileExtension(row.path)
  if M.has(ext) then return name .. "." .. ext end
  return name
end

local function replace_path_prefix(path, old_path, new_path)
  -- Keep stored paths valid when a folder moves or is renamed.
  if not M.has(path) then return path end
  local clean_path = app.fs.normalizePath(path)
  local clean_old = app.fs.normalizePath(old_path)
  local clean_new = app.fs.normalizePath(new_path)
  local prefix = clean_old .. app.fs.pathSeparator

  if clean_path == clean_old then return clean_new end
  if clean_path:sub(1, #prefix) == prefix then return clean_new .. clean_path:sub(#clean_old + 1) end
  return path
end

local function path_is_same_or_child(path, parent)
  -- Used for delete cleanup so nested favorite/history/expanded paths are removed.
  if not M.has(path) then return false end
  local clean_path = app.fs.normalizePath(path)
  local clean_parent = app.fs.normalizePath(parent)
  local prefix = clean_parent .. app.fs.pathSeparator
  return clean_path == clean_parent or clean_path:sub(1, #prefix) == prefix
end

local function update_path_list(list, old_path, new_path)
  -- Rewrite every stored path that points at a renamed folder or its children.
  for i, path in ipairs(list) do
    list[i] = replace_path_prefix(path, old_path, new_path)
  end
end

local function reset_cached_tree()
  -- Force the next refresh to read the filesystem again.
  M.file_cache = {}
  M.search_index = {}
  M.search_index_root = nil
end

local function remove_path_prefixes(list, old_path)
  -- Drop stored paths that were deleted along with a file/folder tree.
  for i = #list, 1, -1 do
    if path_is_same_or_child(list[i], old_path) then table.remove(list, i) end
  end
end

local function settings_path()
  -- Small companion settings file for values Aseprite preferences may skip.
  return app.fs.joinPath(app.fs.userConfigPath, "aseprite-file-tree-settings.lua")
end

local function quoted(value)
  -- Serialize settings as safe Lua string literals.
  return string.format("%q", value or "")
end

local function write_setting_line(file, key, value)
  -- Write one key/value line into the Lua settings file.
  file:write("  ", key, " = ", quoted(value), ",\n")
end

local function write_favorites(file)
  -- Persist favorite folder paths as a Lua array.
  file:write("  favorites = {\n")
  for _, path in ipairs(M.favorites) do
    file:write("    ", quoted(path), ",\n")
  end
  file:write("  }\n")
end

function M.has(s)
  -- Treat nil and empty string as absent for path/text values.
  return s ~= nil and s ~= ""
end

function M.row_name(path)
  -- Return a compact display name while still handling root-like paths.
  local name = app.fs.fileName(path)
  if M.has(name) then return name end
  return path
end

function M.is_supported(path)
  -- Only supported art/image files are shown in the tree.
  return supported[lo(app.fs.fileExtension(path))] == true
end

function M.load_preview(path)
  -- Load the selected file directly into an Image for the preview pane.
  M.preview_path = path

  local ok, image = pcall(function() return Image{ fromFile = path } end)
  if ok and image ~= nil then
    M.preview_image = image
    M.preview_status = ""
    return
  end

  M.preview_path = nil
  M.preview_image = nil
  M.preview_status = "Could not preview this file."
end

function M.preview_row(row)
  -- Selection drives preview content when the preview pane is enabled.
  if not M.preview_enabled then return end
  if row == nil or row.is_folder or row.is_shortcut then
    M.clear_preview("Select a file to preview.")
    return
  end
  if M.preview_path == row.path and M.preview_image ~= nil then return end
  M.load_preview(row.path)
end

function M.toggle_preview()
  -- Show/hide the preview pane without changing the current tree selection.
  M.preview_enabled = not M.preview_enabled
  if not M.preview_enabled then M.clear_preview("Preview off.") end
  if M.preview_enabled and M.selected ~= nil and app.fs.isFile(M.selected) then M.load_preview(M.selected) end
  M.clamp_scroll()
  M.save_prefs()
  M.update_preview_button()
  if M.dialog then M.dialog:repaint() end
end

function M.save_prefs()
  -- Save UI state into Aseprite's plugin preferences.
  local p = M.plugin.preferences
  p.root_path = M.root_path
  p.expanded = p.expanded or {}
  p.scroll = M.scroll
  p.h_scroll = M.h_scroll
  p.history = M.history
  p.favorites = M.favorites
  p.pinned_root = M.pinned_root
  p.filter_text = M.filter_text
  p.filter_mode = M.filter_mode
  p.preview_enabled = M.preview_enabled
  p.preview_w = M.preview_w
  if M.dialog then p.bounds = M.dialog.bounds end

  M.write_browser_settings()
end

function M.write_browser_settings()
  -- Persist key browser settings even when Aseprite skips plugin preference flushing.
  local file = io.open(settings_path(), "w")
  if file then
    file:write("return {\n")
    write_setting_line(file, "root_path", M.root_path)
    write_setting_line(file, "pinned_root", M.pinned_root)
    write_favorites(file)
    file:write("}\n")
    file:close()
  end
end

function M.save_browser_settings()
  -- Save durable navigation settings to both plugin prefs and a small Lua file.
  local p = M.plugin.preferences
  p.root_path = M.root_path
  p.favorites = M.favorites
  p.pinned_root = M.pinned_root
  M.write_browser_settings()
end

function M.load_browser_settings()
  -- Load the companion Lua settings file if it exists.
  local chunk = loadfile(settings_path())
  if not chunk then return nil end
  return chunk()
end

-- Modify a dialog widget while preserving window bounds.
function M.modify(opts)
  if M.dialog then
    local b = M.dialog.bounds
    M.dialog:modify(opts)
    M.dialog.bounds = b
  end
end

function M.short_path(path)
  -- Compact path label for menus and confirmation dialogs.
  local parent = app.fs.filePath(path)
  local name = M.row_name(path)
  local parent_name = M.row_name(parent)
  if M.has(parent_name) and parent_name ~= parent then return parent_name .. "/" .. name end
  return name
end

function M.expanded_set()
  -- Expanded folders are stored in plugin preferences to survive dialog closes.
  M.plugin.preferences.expanded = M.plugin.preferences.expanded or {}
  return M.plugin.preferences.expanded
end

function M.init_root()
  -- Initialize root, favorites, filters, and preview state from saved settings.
  local settings = M.load_browser_settings() or {}

  if M.has(settings.root_path) then
    M.root_path = settings.root_path
  elseif M.has(M.plugin.preferences.root_path) then
    M.root_path = M.plugin.preferences.root_path
  else
    M.root_path = app.fs.userDocsPath
  end

  M.favorites = clean_list(settings.favorites or M.plugin.preferences.favorites)
  M.pinned_root = settings.pinned_root or M.plugin.preferences.pinned_root or ""
  M.filter_text = M.plugin.preferences.filter_text or ""
  M.pending_filter_text = M.filter_text
  M.filter_mode = M.plugin.preferences.filter_mode or "All"
  M.preview_enabled = M.plugin.preferences.preview_enabled == true
  M.preview_w = M.plugin.preferences.preview_w or M.PREVIEW_DEFAULT_W
  M.preview_status = M.preview_enabled and "Select a file to preview." or "Preview off."
end

-- Enable/disable Root button based on whether a pinned root is set.
function M.update_root_button()
  M.modify{ id = "b_root", enabled = M.has(M.pinned_root) }
end

function M.update_preview_button()
  -- Keep the preview toggle button text synced with preview_enabled.
  local text = M.preview_enabled and "Preview: On" or "Preview: Off"
  M.modify{ id = "b_preview", text = text }
end

function M.set_tree_cursor(cursor)
  -- Aseprite supports changing a canvas cursor through Dialog:modify().
  if M.tree_cursor == cursor then return end
  M.tree_cursor = cursor
  if M.dialog == nil then return end
  if MouseCursor == nil then return end

  pcall(function()
    M.modify{ id = "tree", mousecursor = cursor }
  end)
end

function M.set_resize_cursor(active)
  -- Use the standard horizontal resize cursor on the tree/preview divider.
  if MouseCursor == nil then return end
  if active then
    M.set_tree_cursor(MouseCursor.WE_RESIZE)
  else
    M.set_tree_cursor(MouseCursor.ARROW)
  end
end

function M.tree_w()
  -- Tree width shrinks when the preview pane is visible.
  if not M.preview_enabled then return M.canvas_w end
  if M.canvas_w < M.PREVIEW_MIN_TREE_W + M.PREVIEW_MIN_W then return M.canvas_w end
  M.clamp_preview_w()
  return M.canvas_w - M.preview_w - M.PREVIEW_GAP
end

function M.preview_x()
  -- Preview pane starts just after the tree and divider gap.
  return M.tree_w() + M.PREVIEW_GAP
end

function M.has_preview_pane()
  -- Small windows hide the preview pane rather than crushing the tree.
  return M.preview_enabled and M.tree_w() < M.canvas_w
end

function M.clear_preview(status)
  -- Clear cached preview image and show a status message instead.
  M.preview_path = nil
  M.preview_image = nil
  M.preview_status = status or "Select a file to preview."
end

function M.clamp_preview_w()
  -- Keep the draggable preview width within usable bounds.
  local max_w = M.canvas_w - M.PREVIEW_MIN_TREE_W - M.PREVIEW_GAP
  if max_w < M.PREVIEW_MIN_W then max_w = M.PREVIEW_MIN_W end
  if M.preview_w < M.PREVIEW_MIN_W then M.preview_w = M.PREVIEW_MIN_W end
  if M.preview_w > max_w then M.preview_w = max_w end
end

function M.preview_divider_x()
  -- Divider x is nil when the preview pane is hidden.
  if not M.has_preview_pane() then return nil end
  return M.tree_w()
end

function M.is_preview_divider(x)
  -- Hit-test a forgiving resize handle around the divider line.
  local divider_x = M.preview_divider_x()
  if divider_x == nil then return false end
  local half = math.floor(M.PREVIEW_HANDLE_W / 2)
  return x >= divider_x - half and x <= divider_x + half
end

function M.resize_preview_at(x)
  -- Convert a dragged divider position into a preview pane width.
  M.preview_w = M.canvas_w - x - M.PREVIEW_GAP
  M.clamp_preview_w()
  M.clamp_scroll()
  M.content_dirty = true
  M.save_prefs()
  if M.dialog then M.dialog:repaint() end
end

local function sort_entries(a, b)
  -- Folders sort before files; names are case-insensitive.
  if a.is_folder ~= b.is_folder then return a.is_folder end
  return lo(a.name) < lo(b.name)
end

function M.scan_folder(path)
  -- Read one folder level and keep only folders plus supported files.
  local items = {}
  for _, name in ipairs(app.fs.listFiles(path)) do
    local fp = app.fs.joinPath(path, name)
    if app.fs.isDirectory(fp) then
      table.insert(items, { name = name, path = fp, is_folder = true })
    elseif M.is_supported(fp) then
      table.insert(items, { name = name, path = fp, is_folder = false })
    end
  end
  table.sort(items, sort_entries)
  return items
end

local function folder_items(path)
  -- Lazy cache folder scans so expanding/collapsing stays quick.
  if M.file_cache[path] == nil then M.file_cache[path] = M.scan_folder(path) end
  return M.file_cache[path]
end

function M.is_favorite(path)
  -- Favorites are stored as absolute folder paths.
  return list_has(M.favorites, path)
end

function M.toggle_favorite(path)
  -- Add/remove a folder favorite and persist it immediately.
  if not M.has(path) then return end
  if not app.fs.isDirectory(path) then return end
  if M.is_favorite(path) then
    remove_from_list(M.favorites, path)
  else
    table.insert(M.favorites, 1, path)
  end
  M.save_browser_settings()
end

local function mode_matches(item)
  -- Type filter always lets folders through so matching files can remain reachable.
  if item.is_folder then return true end
  if M.filter_mode == "All" then return true end
  local ext = lo(app.fs.fileExtension(item.path))
  if M.filter_mode == ".ase/.aseprite" then return ext == "ase" or ext == "aseprite" end
  return M.filter_mode == "." .. ext
end

local function text_matches(item)
  -- Plain substring matching keeps search predictable and cheap.
  if not M.has(M.filter_text) then return true end
  -- When a type filter is active, only match file names, not folder names.
  -- Folders appear only as ancestors of matching files.
  if item.is_folder and M.filter_mode ~= "All" then return false end
  return string.find(lo(item.name), lo(M.filter_text), 1, true) ~= nil
end

function M.item_matches_filter(item)
  -- File rows must pass both type and text filters.
  if item.is_folder then return text_matches(item) end
  return mode_matches(item) and text_matches(item)
end

-- Compute the search label text with inline status.
local function search_label_text(status)
  if status == "" then return "Search" end
  return "Search (" .. status .. ")"
end

function M.queue_filter(text)
  -- Store text immediately, then let the debounce timers apply it.
  M.pending_filter_text = text or ""
  M.status_text = M.pending_filter_text == "" and "" or "Waiting for input..."
  M.save_prefs()
  if M.dialog then
    M.modify{ id = "search_label", text = search_label_text(M.status_text) }
    M.dialog:repaint()
  end
end

function M.clear_filter_for_navigation()
  -- Navigation resets search so the destination folder is visible.
  M.pending_filter_text = ""
  M.filter_text = ""
  M.status_text = ""
  if M.dialog then
    M.modify{ id = "filter_entry", text = "" }
    M.modify{ id = "search_label", text = "Search" }
  end
end

local function build_search_index(path, ancestors)
  -- Flatten the tree with ancestor paths so search can show containing folders.
  for _, item in ipairs(folder_items(path)) do
    local next_ancestors = {}
    for _, ancestor in ipairs(ancestors) do table.insert(next_ancestors, ancestor) end

    table.insert(M.search_index, { item = item, ancestors = ancestors })
    if item.is_folder then
      table.insert(next_ancestors, item.path)
      build_search_index(item.path, next_ancestors)
    end
  end
end

local function ensure_search_index()
  -- Rebuild the search index only when the root changes or cache is reset.
  if M.search_index_root == M.root_path then return end
  M.search_index = {}
  M.search_index_root = M.root_path
  build_search_index(M.root_path, {})
end

local function mark_search_matches()
  -- Record direct matches and every ancestor needed to display them.
  ensure_search_index()
  for _, indexed in ipairs(M.search_index) do
    if M.item_matches_filter(indexed.item) then
      M.search_matches[indexed.item.path] = true
      for _, ancestor in ipairs(indexed.ancestors) do M.search_ancestors[ancestor] = true end
    end
  end
end

local function add_section(title)
  -- Add non-clickable section rows such as "Favorites".
  table.insert(M.visible_rows, {
    name = title,
    path = title,
    is_section = true,
    depth = 0
  })
end

local function add_divider()
  -- Add a thin visual separator row.
  table.insert(M.visible_rows, {
    name = "",
    path = "__divider__",
    is_divider = true,
    depth = 0
  })
end

local function add_favorite(path)
  -- Favorites are displayed as shortcut rows above the main tree.
  if not app.fs.isDirectory(path) then return end
  table.insert(M.visible_rows, {
    name = M.row_name(path),
    path = path,
    is_folder = false,
    is_shortcut = true,
    row_type = "favorite",
    depth = 0
  })
end

local function collect_search_rows(path, depth)
  -- Add only search matches and ancestor folders to visible_rows.
  for _, item in ipairs(folder_items(path)) do
    item.depth = depth
    if M.search_matches[item.path] or M.search_ancestors[item.path] then
      table.insert(M.visible_rows, item)
    end
    if item.is_folder and M.search_ancestors[item.path] then collect_search_rows(item.path, depth + 1) end
  end
end

local function collect_rows(path, depth)
  -- Add expanded tree rows for normal browsing.
  local exp = M.expanded_set()
  for _, item in ipairs(folder_items(path)) do
    item.depth = depth
    if mode_matches(item) then table.insert(M.visible_rows, item) end
    if item.is_folder and exp[item.path] then collect_rows(item.path, depth + 1) end
  end
end

function M.rebuild_rows()
  -- Rebuild every visible row: root panel, favorites, and filtered tree.
  M.visible_rows = {}
  M.search_matches = {}
  M.search_ancestors = {}
  M.content_dirty = true

  if M.has(M.filter_text) and app.fs.isDirectory(M.root_path) then
    M.status_text = "Searching..."
    if M.dialog then M.modify{ id = "search_label", text = search_label_text(M.status_text) } end
    mark_search_matches()
    M.status_text = ""
  else
    M.status_text = ""
  end

  -- Panel: pinned root info row at the top.
  local root_name = M.has(M.pinned_root) and "Root: " .. M.short_path(M.pinned_root) or ""
  table.insert(M.visible_rows, {
    name = root_name,
    path = "__root__",
    is_root_info = true,
    depth = 0
  })

  -- Favourites below root info, with their own divider.
  if #M.favorites > 0 then
    add_divider()
    add_section("Favorites")
    for _, path in ipairs(M.favorites) do add_favorite(path) end
  end

  -- Divider separating panel (root + favourites) from tree.
  add_divider()

  if app.fs.isDirectory(M.root_path) then
    if M.has(M.filter_text) then collect_search_rows(M.root_path, 0) else collect_rows(M.root_path, 0) end
  end
end

-- Called by the debounce timer to show "Searching..." before the actual search runs.
function M.show_searching()
  M.status_text = "Searching..."
  M.modify{ id = "search_label", text = search_label_text(M.status_text) }
end

function M.set_filter(text)
  -- Apply text search and reset scroll to the top of results.
  M.filter_text = text or ""
  M.pending_filter_text = M.filter_text
  M.scroll = 0
  M.h_scroll = 0
  M.refresh()
end

function M.apply_pending_filter()
  -- Timer callback entry point for debounced search.
  M.set_filter(M.pending_filter_text)
end

function M.set_filter_mode(mode)
  -- Apply extension filter and reset scroll.
  M.filter_mode = mode or "All"
  M.scroll = 0
  M.h_scroll = 0
  M.refresh()
end

function M.view_h()
  -- Horizontal scrollbar consumes vertical space when visible.
  if M.needs_h_scroll() then return M.canvas_h - M.SB_H end
  return M.canvas_h
end

function M.view_w()
  -- Vertical scrollbar consumes tree width when visible.
  if M.needs_v_scroll() then return M.tree_w() - M.SB_W end
  return M.tree_w()
end

function M.needs_v_scroll()
  -- Vertical scroll is based on row count and canvas height.
  return #M.visible_rows * M.ROW_H > M.canvas_h
end

function M.needs_h_scroll()
  -- Horizontal scroll is based on measured row text width.
  return M.content_w > M.tree_w()
end

function M.max_v_scroll()
  -- Maximum vertical scroll offset in pixels.
  local m = #M.visible_rows * M.ROW_H - M.view_h()
  return m > 0 and m or 0
end

function M.max_h_scroll()
  -- Maximum horizontal scroll offset in pixels.
  local m = M.content_w - M.view_w()
  return m > 0 and m or 0
end

function M.clamp_scroll()
  -- Keep scroll offsets valid after resizing, filtering, and rescanning.
  if M.scroll < 0 then M.scroll = 0 end
  if M.scroll > M.max_v_scroll() then M.scroll = M.max_v_scroll() end
  if M.h_scroll < 0 then M.h_scroll = 0 end
  if M.h_scroll > M.max_h_scroll() then M.h_scroll = M.max_h_scroll() end
end

function M.refresh()
  -- Single refresh path for rebuilding rows, saving state, and repainting.
  M.rebuild_rows()
  M.clamp_scroll()
  M.save_prefs()
  M.update_root_button()
  M.update_preview_button()
  if M.dialog then
    M.modify{ id = "root_entry", text = M.root_path }
    M.modify{ id = "filter_entry", text = M.filter_text }
    M.modify{ id = "search_label", text = search_label_text(M.status_text) }
    M.dialog:repaint()
  end
end

function M.clear_root()
  -- Remove the pinned root shortcut.
  M.pinned_root = ""
  M.save_browser_settings()
  M.refresh()
end

function M.set_pinned_root(path)
  -- Store a folder for the Root button.
  M.pinned_root = path or ""
  M.save_browser_settings()
  M.refresh()
end

function M.rescan()
  -- Manual refresh from disk.
  reset_cached_tree()
  M.refresh()
end

function M.make_directory(path)
  local call_ok, created = pcall(function()
    return app.fs.makeDirectory(path)
  end)

  if not call_ok then return false, created end
  if not created then return false, "could not create directory" end
  return true
end

function M.create_file(folder_path, name, file_type)
  -- Create a new blank 16x16 sprite and save it with the chosen extension.
  local base_name = app.fs.fileName(trimmed(name))
  if not M.has(base_name) then
    app.alert("Enter a file name.")
    return false
  end

  local clean_name = replace_file_extension(base_name, file_type)
  local target = app.fs.joinPath(folder_path, clean_name)
  if file_exists(target) then
    app.alert("A file or folder with that name already exists.")
    return false
  end

  local sprite = nil
  local ok, err = pcall(function()
    sprite = Sprite(16, 16)
    sprite:saveAs(target)
  end)

  if sprite ~= nil then pcall(function() sprite:close() end) end
  if not ok then
    app.alert("Could not create file: " .. tostring(err))
    return false
  end

  local exp = M.expanded_set()
  exp[folder_path] = true
  M.selected = target
  if M.preview_enabled then M.load_preview(target) end
  reset_cached_tree()
  M.refresh()
  return true
end

function M.create_aseprite_file(folder_path, name)
  -- Compatibility wrapper for callers that still ask for an Aseprite file.
  return M.create_file(folder_path, name, ".aseprite")
end

function M.create_folder(folder_path, name)
  -- Create a child folder under the requested parent folder.
  local clean_name = app.fs.fileName(trimmed(name))
  if not M.has(clean_name) then
    app.alert("Enter a folder name.")
    return false
  end

  local target = app.fs.joinPath(folder_path, clean_name)
  if file_exists(target) then
    app.alert("A file or folder with that name already exists.")
    return false
  end

  local ok, err = M.make_directory(target)
  if not ok then
    app.alert("Could not create folder: " .. tostring(err))
    return false
  end

  local exp = M.expanded_set()
  exp[folder_path] = true
  M.selected = target
  M.clear_preview("Select a file to preview.")
  reset_cached_tree()
  M.refresh()
  return true
end

function M.show_new_file_dialog(folder_path)
  -- Ask for file name and file type before creating a blank sprite file.
  local dialog = nil
  dialog = Dialog{ title = "New File" }
  dialog:entry{ id = "name", label = "Name", text = "New File", focus = true }
  dialog:combobox{
    id = "file_type",
    label = "Type",
    option = ".aseprite",
    options = file_type_options()
  }
  dialog:button{
    id = "create",
    text = "Create",
    onclick = function()
      if M.create_file(folder_path, dialog.data.name, dialog.data.file_type) then dialog:close() end
    end
  }
  dialog:button{ id = "cancel", text = "Cancel", onclick = function() dialog:close() end }
  dialog:show{ wait = false }
end

function M.show_new_folder_dialog(folder_path)
  -- Ask for a folder name before creating it.
  local dialog = nil
  dialog = Dialog{ title = "New Folder" }
  dialog:entry{ id = "name", label = "Name", text = "New Folder", focus = true }
  dialog:button{
    id = "create",
    text = "Create",
    onclick = function()
      if M.create_folder(folder_path, dialog.data.name) then dialog:close() end
    end
  }
  dialog:button{ id = "cancel", text = "Cancel", onclick = function() dialog:close() end }
  dialog:show{ wait = false }
end

function M.update_renamed_paths(old_path, new_path, is_folder)
  -- Rewrite state that references a renamed file or folder.
  M.selected = replace_path_prefix(M.selected, old_path, new_path)
  M.preview_path = replace_path_prefix(M.preview_path, old_path, new_path)

  if is_folder then
    M.root_path = replace_path_prefix(M.root_path, old_path, new_path)
    M.pinned_root = replace_path_prefix(M.pinned_root, old_path, new_path)
    update_path_list(M.history, old_path, new_path)
    update_path_list(M.favorites, old_path, new_path)

    local exp = M.expanded_set()
    local next_exp = {}
    for path, value in pairs(exp) do
      next_exp[replace_path_prefix(path, old_path, new_path)] = value
    end
    M.plugin.preferences.expanded = next_exp
  end
end

function M.clear_deleted_paths(path)
  -- Remove state that points at a deleted file/folder tree.
  if path_is_same_or_child(M.selected, path) then M.selected = nil end
  if path_is_same_or_child(M.preview_path, path) then M.clear_preview("Select a file to preview.") end

  if path_is_same_or_child(M.root_path, path) then M.root_path = app.fs.filePath(path) end
  if path_is_same_or_child(M.pinned_root, path) then M.pinned_root = "" end
  remove_path_prefixes(M.history, path)
  remove_path_prefixes(M.favorites, path)

  local exp = M.expanded_set()
  local next_exp = {}
  for expanded_path, value in pairs(exp) do
    if not path_is_same_or_child(expanded_path, path) then next_exp[expanded_path] = value end
  end
  M.plugin.preferences.expanded = next_exp
end

function M.delete_folder(path)
  -- Recursively delete folder contents before removing the folder itself.
  for _, name in ipairs(app.fs.listFiles(path)) do
    local child = app.fs.joinPath(path, name)
    if app.fs.isDirectory(child) then
      local ok, err = M.delete_folder(child)
      if not ok then return false, err end
    else
      local ok, err = os.remove(child)
      if not ok then return false, err end
    end
  end

  if app.fs.removeDirectory then
    local ok, err = pcall(function() return app.fs.removeDirectory(path) end)
    if ok and err ~= false then return true end
    if ok then return false, "removeDirectory failed" end
    return false, err
  end
  return os.remove(path)
end

function M.delete_path(row)
  -- Delete a file or folder row after confirmation has already happened.
  local path = row.path
  local ok = nil
  local err = nil

  if row_is_folder(row) then
    ok, err = M.delete_folder(path)
  else
    ok, err = os.remove(path)
  end

  if not ok then
    app.alert("Could not delete: " .. tostring(err))
    return false
  end

  M.clear_deleted_paths(path)
  reset_cached_tree()
  M.save_browser_settings()
  M.refresh()
  return true
end

function M.show_delete_dialog(row)
  -- Confirm destructive delete operations in a small modal dialog.
  local dialog = nil
  local item_type = row_is_folder(row) and "folder and all contents" or "file"
  dialog = Dialog{ title = "Delete" }
  dialog:label{ id = "message", label = "", text = "Delete this " .. item_type .. "?" }
  dialog:label{ id = "name", label = "", text = M.short_path(row.path) }
  dialog:button{
    id = "delete",
    text = "Delete",
    onclick = function()
      if M.delete_path(row) then dialog:close() end
    end
  }
  dialog:button{ id = "cancel", text = "Cancel", onclick = function() dialog:close() end }
  dialog:show{ wait = false }
end

function M.copy_file(source, target)
  -- Copy in small chunks so large files do not have to fit in Lua memory.
  local input, input_error = io.open(source, "rb")
  if input == nil then return false, input_error or "could not read source file" end

  local output, output_error = io.open(target, "wb")
  if output == nil then
    input:close()
    return false, output_error or "could not write target file"
  end

  while true do
    local read_ok, data = pcall(function()
      return input:read(64 * 1024)
    end)

    if not read_ok then
      input:close()
      output:close()
      os.remove(target)
      return false, data
    end

    if data == nil then break end

    local wrote, write_error = output:write(data)
    if wrote == nil then
      input:close()
      output:close()
      os.remove(target)
      return false, write_error or "could not write target file"
    end
  end

  input:close()

  local closed, close_error = output:close()
  if closed == nil then
    os.remove(target)
    return false, close_error or "could not finish target file"
  end

  if app.fs.fileSize(source) ~= app.fs.fileSize(target) then
    os.remove(target)
    return false, "copied file size does not match source"
  end

  return true
end

function M.copy_folder(source, target)
  -- Recursively copy a folder tree.
  local ok, err = M.make_directory(target)
  if not ok then return false, err end

  for _, name in ipairs(app.fs.listFiles(source)) do
    local child_source = app.fs.joinPath(source, name)
    local child_target = app.fs.joinPath(target, name)
    if app.fs.isDirectory(child_source) then
      ok, err = M.copy_folder(child_source, child_target)
    else
      ok, err = M.copy_file(child_source, child_target)
    end
    if not ok then
      M.delete_folder(target)
      return false, err
    end
  end

  return true
end

local function temporary_copy_path(target)
  local candidate = target .. ".aseprite-file-tree-copy"
  local number = 2

  while file_exists(candidate) do
    candidate = target .. ".aseprite-file-tree-copy-" .. number
    number = number + 1
  end

  return candidate
end

function M.copy_file_transaction(source, target)
  local temporary = temporary_copy_path(target)
  local ok, err = M.copy_file(source, temporary)
  if not ok then return false, err end

  ok, err = os.rename(temporary, target)
  if ok then return true end

  os.remove(temporary)
  return false, err
end

function M.copy_folder_transaction(source, target)
  local temporary = temporary_copy_path(target)
  local ok, err = M.copy_folder(source, temporary)
  if not ok then return false, err end

  ok, err = os.rename(temporary, target)
  if ok then return true end

  M.delete_folder(temporary)
  return false, err
end

function M.copy_path_to_target(source, target_path)
  if file_exists(target_path) then return false, "target already exists" end
  if app.fs.isDirectory(source) then
    if path_is_same_or_child(app.fs.filePath(target_path), source) then
      return false, "cannot copy a folder inside itself"
    end

    local ok, err = M.copy_folder_transaction(source, target_path)
    if not ok then return false, err end
    return true, target_path
  end

  local ok, err = M.copy_file_transaction(source, target_path)
  if not ok then return false, err end
  return true, target_path
end

local function keep_both_path(path)
  local parent = app.fs.filePath(path)
  local name = app.fs.fileName(path)
  local extension = app.fs.fileExtension(name)
  local title = name
  local suffix = ""

  if M.has(extension) then
    title = name:sub(1, #name - #extension - 1)
    suffix = "." .. extension
  end

  local candidate = app.fs.joinPath(parent, title .. " copy" .. suffix)
  local number = 2
  while file_exists(candidate) do
    candidate = app.fs.joinPath(parent, title .. " copy " .. number .. suffix)
    number = number + 1
  end
  return candidate
end

local function remove_path(path)
  if app.fs.isDirectory(path) then return M.delete_folder(path) end
  return os.remove(path)
end

local function swap_staged_path(staged, target)
  local backup = temporary_copy_path(target .. ".backup")
  local ok, err = os.rename(target, backup)
  if not ok then return false, err end

  ok, err = os.rename(staged, target)
  if not ok then
    os.rename(backup, target)
    return false, err
  end

  remove_path(backup)
  return true
end

function M.replace_path(source, target)
  local staged = temporary_copy_path(target)
  local ok, err

  if app.fs.isDirectory(source) then
    ok, err = M.copy_folder(source, staged)
  else
    ok, err = M.copy_file(source, staged)
  end

  if not ok then return false, err end

  ok, err = swap_staged_path(staged, target)
  if ok then return true, target end

  remove_path(staged)
  return false, err
end

function M.ask_paste_conflict(source, target)
  local source_is_folder = app.fs.isDirectory(source)
  local target_is_folder = app.fs.isDirectory(target)
  local can_merge = source_is_folder and target_is_folder
  local action = nil
  local apply_to_all = false
  local dialog = Dialog{ title = can_merge and "Folder Exists" or "File Exists" }

  dialog:label{ text = "An item with this name already exists:" }
  dialog:label{ text = M.short_path(target) }
  dialog:check{ id = "apply_all", text = "Apply to all conflicts" }

  if can_merge then
    dialog:button{
      text = "Merge",
      onclick = function()
        action = "merge"
        apply_to_all = dialog.data.apply_all
        dialog:close()
      end
    }
  elseif app.fs.normalizePath(source) ~= app.fs.normalizePath(target) then
    dialog:button{
      text = "Replace",
      onclick = function()
        action = "replace"
        apply_to_all = dialog.data.apply_all
        dialog:close()
      end
    }
  end

  dialog:button{
    text = "Keep Both",
    onclick = function()
      action = "keep_both"
      apply_to_all = dialog.data.apply_all
      dialog:close()
    end
  }
  dialog:button{ text = "Cancel", onclick = function() dialog:close() end }
  dialog:show{ wait = true }
  return action, apply_to_all
end

local function conflict_action(source, target, state)
  if state.child_action ~= nil then return state.child_action end

  local action, apply_to_all = M.ask_paste_conflict(source, target)
  if apply_to_all then state.child_action = action end
  return action
end

function M.merge_folder(source, target, state)
  for _, name in ipairs(app.fs.listFiles(source)) do
    local child_source = app.fs.joinPath(source, name)
    local child_target = app.fs.joinPath(target, name)

    if not file_exists(child_target) then
      local ok, err = M.copy_path_to_target(child_source, child_target)
      if not ok then return false, err end
    elseif app.fs.isDirectory(child_source) and app.fs.isDirectory(child_target) then
      local ok, err = M.merge_folder(child_source, child_target, state)
      if not ok then return false, err end
    else
      local action = conflict_action(child_source, child_target, state)
      if action == nil then return false, "paste cancelled" end

      if action == "replace" then
        local ok, err = M.replace_path(child_source, child_target)
        if not ok then return false, err end
      elseif action == "keep_both" then
        local ok, err = M.copy_path_to_target(child_source, keep_both_path(child_target))
        if not ok then return false, err end
      end
    end
  end

  return true
end

function M.merge_folder_transaction(source, target, state)
  local staged = temporary_copy_path(target)
  local ok, err = M.copy_folder(target, staged)
  if not ok then return false, err end

  ok, err = M.merge_folder(source, staged, state)
  if not ok then
    M.delete_folder(staged)
    return false, err
  end

  ok, err = swap_staged_path(staged, target)
  if ok then return true, target end

  M.delete_folder(staged)
  return false, err
end

function M.copy_path_to_folder(source, target, action, state)
  local target_path = app.fs.joinPath(target, M.row_name(source))
  if not file_exists(target_path) then return M.copy_path_to_target(source, target_path) end

  if action == "keep_both" then
    return M.copy_path_to_target(source, keep_both_path(target_path))
  end

  if action == "replace" then return M.replace_path(source, target_path) end
  if action == "merge" then return M.merge_folder_transaction(source, target_path, state) end
  return false, "target already exists"
end

function M.cut_path_to_folder(source, target, action, state)
  -- Move directly when possible; otherwise copy safely before deleting the source.
  local target_path = app.fs.joinPath(target, M.row_name(source))

  if app.fs.isDirectory(source) and path_is_same_or_child(target, source) then
    return false, "cannot paste a folder inside itself"
  end

  if not file_exists(target_path) then
    local ok = os.rename(source, target_path)
    if ok then return true, target_path end
  end

  local ok, result = M.copy_path_to_folder(source, target, action, state)
  if not ok then return false, result end

  local removed, remove_error = remove_path(source)
  if not removed then
    return false, "copied item but could not remove source: " .. tostring(remove_error)
  end
  return true, result
end

function M.set_clipboard(row, action)
  -- Store an internal cut/copy target for later Paste.
  M.clipboard_path = row.path
  M.clipboard_action = action
  M.clipboard_is_folder = row_is_folder(row)
end

function M.can_paste()
  -- Paste is available only while the internal clipboard points at an existing item.
  if not M.has(M.clipboard_path) then return false end
  return app.fs.isFile(M.clipboard_path) or app.fs.isDirectory(M.clipboard_path)
end

function M.paste_into(folder_path)
  -- Paste the internal clipboard item into a folder destination.
  if not M.can_paste() then
    app.alert("Nothing to paste.")
    return false
  end

  local source = M.clipboard_path
  local action = M.clipboard_action
  local target = app.fs.joinPath(folder_path, M.row_name(source))
  local conflict = nil
  local state = {}

  if file_exists(target) then
    conflict, state.apply_to_all = M.ask_paste_conflict(source, target)
    if conflict == nil then return false end
  end

  local ok = nil
  local result = nil

  if action == "cut" then
    ok, result = M.cut_path_to_folder(source, folder_path, conflict, state)
  else
    ok, result = M.copy_path_to_folder(source, folder_path, conflict, state)
  end

  if not ok then
    app.alert("Could not paste: " .. tostring(result))
    return false
  end

  local pasted_folder = M.clipboard_is_folder
  if action == "cut" then
    M.update_renamed_paths(source, result, M.clipboard_is_folder)
    M.clipboard_path = nil
    M.clipboard_action = nil
    M.clipboard_is_folder = false
  else
    M.selected = result
  end

  if pasted_folder then M.clear_preview("Select a file to preview.") end

  local exp = M.expanded_set()
  exp[folder_path] = true
  reset_cached_tree()
  M.save_browser_settings()
  M.refresh()
  return true
end

function M.can_drop_path(source, folder_path)
  if not M.has(source) then return false end
  if not M.has(folder_path) then return false end
  if not app.fs.isDirectory(folder_path) then return false end
  if app.fs.normalizePath(app.fs.filePath(source)) == app.fs.normalizePath(folder_path) then
    return false
  end
  if app.fs.isDirectory(source) and path_is_same_or_child(folder_path, source) then
    return false
  end
  return true
end

function M.drop_path_into(source, folder_path, copy)
  if not M.can_drop_path(source, folder_path) then return false end

  local target = app.fs.joinPath(folder_path, M.row_name(source))
  local conflict = nil
  local state = {}

  if file_exists(target) then
    conflict, state.apply_to_all = M.ask_paste_conflict(source, target)
    if conflict == nil then return false end
  end

  local source_is_folder = app.fs.isDirectory(source)
  local ok, result
  if copy then
    ok, result = M.copy_path_to_folder(source, folder_path, conflict, state)
  else
    ok, result = M.cut_path_to_folder(source, folder_path, conflict, state)
  end

  if not ok then
    app.alert("Could not drop item: " .. tostring(result))
    return false
  end

  if copy then
    M.selected = result
  else
    M.update_renamed_paths(source, result, source_is_folder)
  end

  local expanded = M.expanded_set()
  expanded[folder_path] = true
  reset_cached_tree()
  M.save_browser_settings()
  M.refresh()
  return true
end

function M.clear_file_drag()
  M.drag_source = nil
  M.drag_started = false
  M.drag_target_path = nil
  M.drag_target_idx = nil
  M.drag_copy = false
end

function M.rename_path(row, name)
  -- Rename a file/folder without converting file contents.
  local clean_name = rename_file_name(row, app.fs.fileName(trimmed(name)))
  if not M.has(clean_name) then
    app.alert("Enter a name.")
    return false
  end

  local old_path = row.path
  local new_path = app.fs.joinPath(app.fs.filePath(old_path), clean_name)
  local normalized_old = app.fs.normalizePath(old_path)
  local normalized_new = app.fs.normalizePath(new_path)
  if normalized_old == normalized_new then return true end

  local case_only = (app.os.windows or app.os.macos)
    and lo(normalized_old) == lo(normalized_new)

  if case_only then
    local temporary = temporary_copy_path(old_path .. ".rename")
    local moved, move_error = os.rename(old_path, temporary)
    if not moved then
      app.alert("Could not rename: " .. tostring(move_error))
      return false
    end

    moved, move_error = os.rename(temporary, new_path)
    if not moved then
      os.rename(temporary, old_path)
      app.alert("Could not rename: " .. tostring(move_error))
      return false
    end

    M.update_renamed_paths(old_path, new_path, row_is_folder(row))
    if M.preview_enabled and M.selected == new_path and app.fs.isFile(new_path) then
      M.load_preview(new_path)
    end
    reset_cached_tree()
    M.save_browser_settings()
    M.refresh()
    return true
  end

  if file_exists(new_path) then
    app.alert("A file or folder with that name already exists.")
    return false
  end

  local ok, err = os.rename(old_path, new_path)
  if not ok then
    app.alert("Could not rename: " .. tostring(err))
    return false
  end

  M.update_renamed_paths(old_path, new_path, row_is_folder(row))
  if M.preview_enabled and M.selected == new_path and app.fs.isFile(new_path) then M.load_preview(new_path) end
  reset_cached_tree()
  M.save_browser_settings()
  M.refresh()
  return true
end

function M.show_rename_dialog(row)
  -- Ask for the new display name for a file or folder row.
  local dialog = nil
  dialog = Dialog{ title = "Rename" }
  dialog:entry{ id = "name", label = "Name", text = M.row_name(row.path), focus = true }
  dialog:button{
    id = "rename",
    text = "Rename",
    onclick = function()
      if M.rename_path(row, dialog.data.name) then dialog:close() end
    end
  }
  dialog:button{ id = "cancel", text = "Cancel", onclick = function() dialog:close() end }
  dialog:show{ wait = false }
end

function M.nav_to(path, push)
  -- Change the browser root and optionally push the old root into history.
  if push and M.has(M.root_path) then table.insert(M.history, M.root_path) end
  M.clear_filter_for_navigation()
  M.root_path = app.fs.normalizePath(path)
  M.file_cache = {}
  M.search_index = {}
  M.search_index_root = nil
  M.scroll = 0
  M.h_scroll = 0
  M.hovered_idx = nil
  M.selected = nil
  M.context_menu = nil
  M.save_browser_settings()
  M.refresh()
end

function M.nav_back()
  -- Return to the last root path from history.
  local prev = table.remove(M.history)
  if prev then M.nav_to(prev) end
end

function M.nav_up()
  -- Use the parent folder as the current root.
  local p = app.fs.filePath(M.root_path)
  if M.has(p) and p ~= M.root_path then M.nav_to(p, true) end
end

function M.nav_sprite()
  -- Jump to the active sprite's folder when a sprite is open.
  local s = app.activeSprite
  if s and M.has(s.filename) then M.nav_to(app.fs.filePath(s.filename), true) end
end

function M.nav_root_selected()
  -- Navigate to the pinned root.
  if M.has(M.pinned_root) and app.fs.isDirectory(M.pinned_root) then
    M.nav_to(M.pinned_root, true)
  end
end

function M.open_context_menu(row, x, y)
  -- Build a context menu for a row, or for empty tree space when row is nil.
  if row == nil then
    M.context_menu = {
      x = x,
      y = y,
      row = { path = M.root_path, is_folder = true, is_empty_space = true },
      items = {
        { label = "New File", action = "new_file" },
        { label = "New Folder", action = "new_folder" }
      }
    }
    if M.can_paste() then table.insert(M.context_menu.items, { label = "Paste", action = "paste" }) end
    M.dialog:repaint()
    return
  end

  if row.is_section or row.is_divider then
    M.context_menu = nil
    return
  end

  local items = {}

  -- Root info row: Clear Root, Copy Path, Reveal.
  if row.is_root_info then
    table.insert(items, { label = "Clear Root", action = "clear_root" })
    if M.has(M.pinned_root) then
      table.insert(items, { label = "Copy Path", action = "copy_path" })
      table.insert(items, { label = "Reveal in Explorer", action = "reveal" })
    end
    M.context_menu = { x = x, y = y, row = row, items = items }
    M.dialog:repaint()
    return
  end

  table.insert(items, { label = "Open", action = "open" })
  table.insert(items, { label = "Cut", action = "cut" })
  table.insert(items, { label = "Copy", action = "copy" })

  if row_is_folder(row) then
    table.insert(items, { label = "New File", action = "new_file" })
    table.insert(items, { label = "New Folder", action = "new_folder" })
    if M.can_paste() then table.insert(items, { label = "Paste", action = "paste" }) end
    table.insert(items, { label = "Set Root", action = "set_root" })
    local favorite_text = M.is_favorite(row.path) and "Remove Favorite" or "Add Favorite"
    table.insert(items, { label = favorite_text, action = "favorite" })
  end

  if row_is_folder(row) or not row.is_shortcut then
    table.insert(items, { label = "Rename", action = "rename" })
    table.insert(items, { label = "Delete", action = "delete" })
  end

  -- Always available for files, folders, and favorites.
  table.insert(items, { label = "Copy Path", action = "copy_path" })
  table.insert(items, { label = "Reveal in Explorer", action = "reveal" })

  M.context_menu = {
    x = x,
    y = y,
    row = row,
    items = items
  }
  M.dialog:repaint()
end

function M.close_context_menu()
  -- Hide the custom context menu and clear hover state.
  M.context_menu = nil
  M.context_hover = nil
end

function M.context_item_at(x, y, return_index)
  -- Hit-test the custom context menu drawn on the canvas.
  local menu = M.context_menu
  if menu == nil then return nil end
  local menu_x = menu.draw_x or menu.x
  local menu_y = menu.draw_y or menu.y
  if x < menu_x or x > menu_x + M.MENU_W then return nil end
  if y < menu_y or y > menu_y + (#menu.items * M.MENU_ROW_H) then return nil end
  local idx = math.floor((y - menu_y) / M.MENU_ROW_H) + 1
  if return_index then return menu.items[idx], idx end
  return menu.items[idx]
end

function M.run_context_action(item)
  -- Execute the selected context-menu action.
  local menu = M.context_menu
  if item == nil or menu == nil then return false end
  local row = menu.row
  M.close_context_menu()

  if item.action == "clear_root" then
    M.clear_root()
  elseif item.action == "new_file" then
    M.show_new_file_dialog(row.path)
  elseif item.action == "new_folder" then
    M.show_new_folder_dialog(row.path)
  elseif item.action == "rename" then
    M.show_rename_dialog(row)
  elseif item.action == "delete" then
    M.show_delete_dialog(row)
  elseif item.action == "cut" then
    M.set_clipboard(row, "cut")
  elseif item.action == "copy" then
    M.set_clipboard(row, "copy")
  elseif item.action == "paste" then
    M.paste_into(row.path)
  elseif item.action == "set_root" then
    M.set_pinned_root(row.path)
  elseif item.action == "open" then
    if row.is_shortcut or row.is_folder then M.nav_to(row.path, true) else app.open(row.path) end
  elseif item.action == "copy_path" then
    -- Copy absolute path to clipboard (Windows).
    local target = row.is_root_info and M.pinned_root or row.path
    os.execute('cmd /c "set /p =' .. target .. '" < nul | clip')
  elseif item.action == "reveal" then
    -- Reveal in Windows Explorer.
    local target = row.is_root_info and M.pinned_root or row.path
    if app.fs.isDirectory(target) then
      os.execute('explorer "' .. target .. '"')
    else
      os.execute('explorer /select,"' .. target .. '"')
    end
  elseif item.action == "favorite" then
    if row.is_folder or row.is_shortcut then
      M.toggle_favorite(row.path)
      M.refresh()
    end
  end

  return true
end

function M.row_at_y(y)
  -- Convert a canvas y coordinate into a visible row.
  local idx = math.floor((y + M.scroll) / M.ROW_H) + 1
  if idx >= 1 and idx <= #M.visible_rows then return M.visible_rows[idx], idx end
  return nil, nil
end

return M
