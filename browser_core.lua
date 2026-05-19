-- browser_core.lua
-- State, filesystem scanning, debounced search, favorites, and navigation.

local M = {}

M.plugin = nil
M.dialog = nil
M.root_path = ""
M.file_cache = {}
M.visible_rows = {}
M.scroll = 0
M.h_scroll = 0
M.history = {}
M.favorites = {}
M.pinned_root = ""
M.filter_text = ""
M.pending_filter_text = ""
M.filter_mode = "All"
M.status_text = ""
M.selected = nil
M.hovered_idx = nil
M.context_menu = nil
M.context_hover = nil

M.sb_dragging = false
M.sb_drag_y = 0
M.sb_drag_scroll = 0
M.hsb_dragging = false
M.hsb_drag_x = 0
M.hsb_drag_scroll = 0

M.content_w = 0
M.content_dirty = true

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

M.search_matches = {}
M.search_ancestors = {}
M.search_index = {}
M.search_index_root = nil

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
  return string.lower(s or "")
end

local function clean_list(list)
  if type(list) == "table" then return list end
  return {}
end

local function list_has(list, path)
  for _, item in ipairs(list) do
    if item == path then return true end
  end
  return false
end

local function remove_from_list(list, path)
  for i = #list, 1, -1 do
    if list[i] == path then table.remove(list, i) end
  end
end

function M.has(s)
  return s ~= nil and s ~= ""
end

function M.row_name(path)
  local name = app.fs.fileName(path)
  if M.has(name) then return name end
  return path
end

function M.is_supported(path)
  return supported[lo(app.fs.fileExtension(path))] == true
end

function M.save_prefs()
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
  if M.dialog then p.bounds = M.dialog.bounds end
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
  local parent = app.fs.filePath(path)
  local name = M.row_name(path)
  local parent_name = M.row_name(parent)
  if M.has(parent_name) and parent_name ~= parent then return parent_name .. "/" .. name end
  return name
end

function M.expanded_set()
  M.plugin.preferences.expanded = M.plugin.preferences.expanded or {}
  return M.plugin.preferences.expanded
end

function M.init_root()
  if M.has(M.plugin.preferences.root_path) then
    M.root_path = M.plugin.preferences.root_path
  else
    M.root_path = app.fs.userDocsPath
  end

  M.favorites = clean_list(M.plugin.preferences.favorites)
  M.pinned_root = M.plugin.preferences.pinned_root or ""
  M.filter_text = M.plugin.preferences.filter_text or ""
  M.pending_filter_text = M.filter_text
  M.filter_mode = M.plugin.preferences.filter_mode or "All"
end

-- Enable/disable Root button based on whether a pinned root is set.
function M.update_root_button()
  M.modify{ id = "b_root", enabled = M.has(M.pinned_root) }
end

local function sort_entries(a, b)
  if a.is_folder ~= b.is_folder then return a.is_folder end
  return lo(a.name) < lo(b.name)
end

function M.scan_folder(path)
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
  if M.file_cache[path] == nil then M.file_cache[path] = M.scan_folder(path) end
  return M.file_cache[path]
end

function M.is_favorite(path)
  return list_has(M.favorites, path)
end

function M.toggle_favorite(path)
  if not M.has(path) then return end
  if not app.fs.isDirectory(path) then return end
  if M.is_favorite(path) then
    remove_from_list(M.favorites, path)
  else
    table.insert(M.favorites, 1, path)
  end
  M.save_prefs()
end

local function mode_matches(item)
  if item.is_folder then return true end
  if M.filter_mode == "All" then return true end
  local ext = lo(app.fs.fileExtension(item.path))
  if M.filter_mode == ".ase/.aseprite" then return ext == "ase" or ext == "aseprite" end
  return M.filter_mode == "." .. ext
end

local function text_matches(item)
  if not M.has(M.filter_text) then return true end
  -- When a type filter is active, only match file names, not folder names.
  -- Folders appear only as ancestors of matching files.
  if item.is_folder and M.filter_mode ~= "All" then return false end
  return string.find(lo(item.name), lo(M.filter_text), 1, true) ~= nil
end

function M.item_matches_filter(item)
  if item.is_folder then return text_matches(item) end
  return mode_matches(item) and text_matches(item)
end

-- Compute the search label text with inline status.
local function search_label_text(status)
  if status == "" then return "Search" end
  return "Search (" .. status .. ")"
end

function M.queue_filter(text)
  M.pending_filter_text = text or ""
  M.status_text = M.pending_filter_text == "" and "" or "Waiting for input..."
  M.save_prefs()
  if M.dialog then
    M.modify{ id = "search_label", text = search_label_text(M.status_text) }
    M.dialog:repaint()
  end
end

function M.clear_filter_for_navigation()
  M.pending_filter_text = ""
  M.filter_text = ""
  M.status_text = ""
  if M.dialog then
    M.modify{ id = "filter_entry", text = "" }
    M.modify{ id = "search_label", text = "Search" }
  end
end

local function build_search_index(path, ancestors)
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
  if M.search_index_root == M.root_path then return end
  M.search_index = {}
  M.search_index_root = M.root_path
  build_search_index(M.root_path, {})
end

local function mark_search_matches()
  ensure_search_index()
  for _, indexed in ipairs(M.search_index) do
    if M.item_matches_filter(indexed.item) then
      M.search_matches[indexed.item.path] = true
      for _, ancestor in ipairs(indexed.ancestors) do M.search_ancestors[ancestor] = true end
    end
  end
end

local function add_section(title)
  table.insert(M.visible_rows, {
    name = title,
    path = title,
    is_section = true,
    depth = 0
  })
end

local function add_divider()
  table.insert(M.visible_rows, {
    name = "",
    path = "__divider__",
    is_divider = true,
    depth = 0
  })
end

local function add_favorite(path)
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
  for _, item in ipairs(folder_items(path)) do
    item.depth = depth
    if M.search_matches[item.path] or M.search_ancestors[item.path] then
      table.insert(M.visible_rows, item)
    end
    if item.is_folder and M.search_ancestors[item.path] then collect_search_rows(item.path, depth + 1) end
  end
end

local function collect_rows(path, depth)
  local exp = M.expanded_set()
  for _, item in ipairs(folder_items(path)) do
    item.depth = depth
    if mode_matches(item) then table.insert(M.visible_rows, item) end
    if item.is_folder and exp[item.path] then collect_rows(item.path, depth + 1) end
  end
end

function M.rebuild_rows()
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
  M.filter_text = text or ""
  M.pending_filter_text = M.filter_text
  M.scroll = 0
  M.h_scroll = 0
  M.refresh()
end

function M.apply_pending_filter()
  M.set_filter(M.pending_filter_text)
end

function M.set_filter_mode(mode)
  M.filter_mode = mode or "All"
  M.scroll = 0
  M.h_scroll = 0
  M.refresh()
end

function M.view_h()
  if M.needs_h_scroll() then return M.canvas_h - M.SB_H end
  return M.canvas_h
end

function M.view_w()
  if M.needs_v_scroll() then return M.canvas_w - M.SB_W end
  return M.canvas_w
end

function M.needs_v_scroll()
  return #M.visible_rows * M.ROW_H > M.canvas_h
end

function M.needs_h_scroll()
  return M.content_w > M.canvas_w
end

function M.max_v_scroll()
  local m = #M.visible_rows * M.ROW_H - M.view_h()
  return m > 0 and m or 0
end

function M.max_h_scroll()
  local m = M.content_w - M.view_w()
  return m > 0 and m or 0
end

function M.clamp_scroll()
  if M.scroll < 0 then M.scroll = 0 end
  if M.scroll > M.max_v_scroll() then M.scroll = M.max_v_scroll() end
  if M.h_scroll < 0 then M.h_scroll = 0 end
  if M.h_scroll > M.max_h_scroll() then M.h_scroll = M.max_h_scroll() end
end

function M.refresh()
  M.rebuild_rows()
  M.clamp_scroll()
  M.save_prefs()
  M.update_root_button()
  if M.dialog then
    M.modify{ id = "root_entry", text = M.root_path }
    M.modify{ id = "filter_entry", text = M.filter_text }
    M.modify{ id = "search_label", text = search_label_text(M.status_text) }
    M.dialog:repaint()
  end
end

function M.clear_root()
  M.pinned_root = ""
  M.refresh()
end

function M.set_pinned_root(path)
  M.pinned_root = path or ""
  M.refresh()
end

function M.rescan()
  M.file_cache = {}
  M.search_index = {}
  M.search_index_root = nil
  M.refresh()
end

function M.nav_to(path, push)
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
  M.refresh()
end

function M.nav_back()
  local prev = table.remove(M.history)
  if prev then M.nav_to(prev) end
end

function M.nav_up()
  local p = app.fs.filePath(M.root_path)
  if M.has(p) and p ~= M.root_path then M.nav_to(p, true) end
end

function M.nav_sprite()
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
  if row == nil or row.is_section or row.is_divider then
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

  if row.is_folder or row.is_shortcut then
    table.insert(items, { label = "Set Root", action = "set_root" })
    local favorite_text = M.is_favorite(row.path) and "Remove Favorite" or "Add Favorite"
    table.insert(items, { label = favorite_text, action = "favorite" })
  end

  -- Always available for files and folders.
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
  M.context_menu = nil
  M.context_hover = nil
end

function M.context_item_at(x, y, return_index)
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
  local menu = M.context_menu
  if item == nil or menu == nil then return false end
  local row = menu.row
  M.close_context_menu()

  if item.action == "clear_root" then
    M.clear_root()
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
  local idx = math.floor((y + M.scroll) / M.ROW_H) + 1
  if idx >= 1 and idx <= #M.visible_rows then return M.visible_rows[idx], idx end
  return nil, nil
end

return M
