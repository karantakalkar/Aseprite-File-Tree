-- folder_browser.lua
-- Extension entry point: loads modules, builds the dialog, and wires events.

local script_src = debug.getinfo(1, "S").source:sub(2)
local script_dir = app.fs.filePath(script_src)

local function load_mod(name, ...)
  -- Load sibling Lua modules from the installed extension folder.
  local path = app.fs.joinPath(script_dir, name .. ".lua")
  local chunk = assert(loadfile(path))
  return chunk(...)
end

local core = load_mod("browser_core")
local draw = load_mod("browser_draw", core)

-- Timers implement debounced search without blocking canvas repaint.
local debounce_timer = nil
local search_timer = nil

local function stop_timers()
  -- Stop search timers before closing or restarting debounce.
  if debounce_timer ~= nil and debounce_timer.isRunning then debounce_timer:stop() end
  if search_timer ~= nil and search_timer.isRunning then search_timer:stop() end
end

local function restart_filter_timer()
  -- Restart the debounce delay after each search text edit.
  stop_timers()
  debounce_timer:start()
end

local function is_right_click(ev)
  -- Aseprite versions differ between MouseButton enum and numeric button values.
  if MouseButton ~= nil and ev.button == MouseButton.RIGHT then return true end
  return ev.button == 2
end

local function in_v_scrollbar(x)
  -- Vertical scrollbar lives on the right edge of the tree area.
  return core.needs_v_scroll() and x >= core.tree_w() - core.SB_W and x < core.tree_w()
end

local function in_h_scrollbar(y)
  -- Horizontal scrollbar lives on the bottom edge of the canvas.
  return core.needs_h_scroll() and y >= core.canvas_h - core.SB_H
end

local function in_preview_pane(x)
  -- Preview pane consumes the right side when enabled and wide enough.
  return core.has_preview_pane() and x >= core.tree_w()
end

local function in_preview_divider(x)
  -- Resize handle is a small band around the tree/preview divider.
  return core.is_preview_divider(x)
end

local function on_v_sb_click(x, y)
  -- Start vertical thumb drag or page the tree up/down.
  if not in_v_scrollbar(x) then return false end
  local t = draw.v_thumb_rect()
  if y >= t.y and y <= t.y + t.height then
    core.sb_dragging = true
    core.sb_drag_y = y
    core.sb_drag_scroll = core.scroll
  elseif y < t.y then
    core.scroll = core.scroll - core.view_h()
  else
    core.scroll = core.scroll + core.view_h()
  end
  core.clamp_scroll()
  core.save_prefs()
  core.dialog:repaint()
  return true
end

local function on_h_sb_click(x, y)
  -- Start horizontal thumb drag or page the tree left/right.
  if not in_h_scrollbar(y) then return false end
  local t = draw.h_thumb_rect()
  if x >= t.x and x <= t.x + t.width then
    core.hsb_dragging = true
    core.hsb_drag_x = x
    core.hsb_drag_scroll = core.h_scroll
  elseif x < t.x then
    core.h_scroll = core.h_scroll - core.view_w()
  else
    core.h_scroll = core.h_scroll + core.view_w()
  end
  core.clamp_scroll()
  core.save_prefs()
  core.dialog:repaint()
  return true
end

local function select_row(row)
  -- Select real tree rows and refresh preview when needed.
  if row == nil or row.is_section or row.is_divider or row.is_shortcut then return end
  core.selected = row.path
  core.preview_row(row)
  core.save_prefs()
end

local function on_mousedown(ev)
  -- Ignore clicks outside canvas bounds.
  if ev.x < 0 or ev.y < 0 or ev.x >= core.canvas_w or ev.y >= core.canvas_h then return end

  -- Context menu clicks are handled before tree/scrollbar hit tests.
  local menu_item = core.context_item_at(ev.x, ev.y)
  if core.run_context_action(menu_item) then return end

  -- The preview divider can be dragged to resize the pane.
  if in_preview_divider(ev.x) and not is_right_click(ev) then
    core.preview_dragging = true
    core.set_resize_cursor(true)
    core.close_context_menu()
    return
  end

  -- Preview area is passive; it does not select tree rows.
  if in_preview_pane(ev.x) then
    core.close_context_menu()
    core.dialog:repaint()
    return
  end

  -- Scrollbars take priority over row clicks.
  if on_v_sb_click(ev.x, ev.y) then return end
  if on_h_sb_click(ev.x, ev.y) then return end

  local row = core.row_at_y(ev.y)
  if row == nil or row.is_divider then
    -- Empty tree space has a small creation menu on right-click.
    if row == nil and is_right_click(ev) then
      core.open_context_menu(nil, ev.x, ev.y)
      return
    end
    core.close_context_menu()
    core.dialog:repaint()
    return
  end

  -- Right-click opens the menu only; it must not select or preview-load files.
  if is_right_click(ev) then
    core.open_context_menu(row, ev.x, ev.y)
    return
  end

  -- Left-click selection is the only click path that refreshes preview content.
  select_row(row)

  core.close_context_menu()

  -- Shortcuts: single-click only selects, double-click navigates.
  if row.is_shortcut then
    core.dialog:repaint()
  elseif row.is_folder then
    local exp = core.expanded_set()
    exp[row.path] = not exp[row.path]
    core.refresh()
  else
    core.dialog:repaint()
  end
end

local function on_dblclick(ev)
  -- Ignore clicks outside canvas bounds.
  if ev.x < 0 or ev.y < 0 or ev.x >= core.canvas_w or ev.y >= core.canvas_h then return end
  if in_preview_pane(ev.x) then return end
  if in_v_scrollbar(ev.x) or in_h_scrollbar(ev.y) then return end
  local row = core.row_at_y(ev.y)
  if row == nil or row.is_section or row.is_root_info or row.is_divider then return end
  core.close_context_menu()
  -- Favourite shortcuts and folders navigate into the directory.
  if row.is_shortcut then
    if app.fs.isDirectory(row.path) then
      core.nav_to(row.path, true)
    end
  elseif row.is_folder then
    local exp = core.expanded_set()
    exp[row.path] = not exp[row.path]
    core.refresh()
  else
    app.open(row.path)
  end
end

local function on_mousemove(ev)
  -- Resizing preview is continuous while the mouse is held down.
  if core.preview_dragging then
    core.set_resize_cursor(true)
    core.resize_preview_at(ev.x)
    return
  end

  local over_divider = in_preview_divider(ev.x)

  -- Guard: if cursor is outside canvas bounds, treat as mouse leave.
  if ev.x < 0 or ev.y < 0 or ev.x >= core.canvas_w or ev.y >= core.canvas_h or (in_preview_pane(ev.x) and not over_divider) then
    core.set_resize_cursor(false)
    if core.hovered_idx ~= nil then
      core.hovered_idx = nil
      core.dialog:repaint()
    end
    core.sb_dragging = false
    core.hsb_dragging = false
    return
  end

  core.set_resize_cursor(over_divider)

  -- When a context menu is open, mouse movement only updates menu hover.
  if core.context_menu ~= nil then
    local _, idx = core.context_item_at(ev.x, ev.y, true)
    if core.context_hover ~= idx then
      core.context_hover = idx
      core.dialog:repaint()
    end
    return
  end

  -- Vertical scrollbar thumb drag updates scroll based on mouse movement.
  if core.sb_dragging then
    local m = core.max_v_scroll()
    local t = draw.v_thumb_rect()
    local range = core.view_h() - t.height
    if range > 0 then
      core.scroll = core.sb_drag_scroll + ((ev.y - core.sb_drag_y) * m / range)
      core.clamp_scroll()
      core.save_prefs()
      core.dialog:repaint()
    end
    return
  end

  -- Horizontal scrollbar thumb drag updates h_scroll based on mouse movement.
  if core.hsb_dragging then
    local m = core.max_h_scroll()
    local t = draw.h_thumb_rect()
    local range = core.view_w() - t.width
    if range > 0 then
      core.h_scroll = core.hsb_drag_scroll + ((ev.x - core.hsb_drag_x) * m / range)
      core.clamp_scroll()
      core.save_prefs()
      core.dialog:repaint()
    end
    return
  end

  -- Normal movement updates row hover for highlight repainting.
  local idx = nil
  if not in_v_scrollbar(ev.x) and not in_h_scrollbar(ev.y) then
    local _, row_idx = core.row_at_y(ev.y)
    idx = row_idx
  end
  if core.hovered_idx ~= idx then
    core.hovered_idx = idx
    core.dialog:repaint()
  end
end

local function on_mouseup()
  -- Release all drag modes on mouse up.
  core.sb_dragging = false
  core.hsb_dragging = false
  core.preview_dragging = false
  core.set_resize_cursor(false)
end

local function on_mouseleave()
  -- Clear hover when cursor leaves the canvas area.
  core.sb_dragging = false
  core.hsb_dragging = false
  core.preview_dragging = false
  core.set_resize_cursor(false)
  if core.hovered_idx ~= nil then
    core.hovered_idx = nil
    core.dialog:repaint()
  end
  core.close_context_menu()
end

local function on_wheel(ev)
  -- Wheel scrolls vertically, shift+wheel scrolls horizontally.
  if in_preview_pane(ev.x) then return end
  if ev.shiftKey then
    core.h_scroll = core.h_scroll + ev.deltaY * core.ROW_H * core.SCROLL_ROWS
  else
    core.scroll = core.scroll + ev.deltaY * core.ROW_H * core.SCROLL_ROWS
  end
  core.clamp_scroll()
  core.save_prefs()
  core.dialog:repaint()
end

local function create_dialog()
  -- Build the floating browser dialog and wire all controls.
  core.init_root()
  core.scroll = core.plugin.preferences.scroll or 0
  core.h_scroll = core.plugin.preferences.h_scroll or 0
  core.history = core.plugin.preferences.history or {}

  core.dialog = Dialog{
    title = "File Tree",
    resizeable = true,
    onclose = function()
      -- Persist dialog state when the floating window closes.
      stop_timers()
      core.save_prefs()
      core.dialog = nil
    end
  }

  -- Two-timer approach: debounce waits, then shows "Searching..." and
  -- starts search_timer which actually runs the filter after a brief repaint.
  debounce_timer = Timer{
    interval = 1.5,
    ontick = function()
      debounce_timer:stop()
      core.show_searching()
      search_timer:start()
    end
  }

  search_timer = Timer{
    interval = 0.05,
    ontick = function()
      search_timer:stop()
      core.apply_pending_filter()
    end
  }

  core.dialog:label{ id = "path_label", label = "", text = "Path" }
  core.dialog:entry{
    id = "root_entry",
    label = "",
    text = core.root_path,
    onchange = function()
      core.nav_to(core.dialog.data.root_entry)
    end
  }

  core.dialog:newrow()
  core.dialog:label{ id = "search_label", label = "", text = "Search" }
  core.dialog:entry{
    id = "filter_entry",
    label = "",
    text = core.filter_text,
    onchange = function()
      core.queue_filter(core.dialog.data.filter_entry)
      restart_filter_timer()
    end
  }

  core.dialog:newrow()
  core.dialog:label{ id = "type_label", label = "", text = "Type" }
  core.dialog:combobox{
    id = "filter_mode",
    label = "",
    option = core.filter_mode,
    options = { "All", ".ase/.aseprite", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp" },
    onchange = function()
      core.set_filter_mode(core.dialog.data.filter_mode)
    end
  }

  core.dialog:newrow()
  core.dialog:button{ id = "b_back", text = "< Back", onclick = core.nav_back }
  core.dialog:button{ id = "b_up", text = "^ Up", onclick = core.nav_up }
  core.dialog:button{ id = "b_sprite", text = "Sprite", onclick = core.nav_sprite }
  core.dialog:button{ id = "b_root", text = "Root", enabled = core.has(core.pinned_root), onclick = core.nav_root_selected }
  core.dialog:button{ id = "b_rescan", text = "Rescan", onclick = core.rescan }
  core.dialog:button{ id = "b_preview", text = "Preview: Off", onclick = core.toggle_preview }

  core.dialog:separator{}

  core.dialog:canvas{
    id = "tree",
    label = "",
    width = core.DEF_W,
    height = core.DEF_H,
    hexpand = true,
    vexpand = true,
    onpaint = draw.on_paint,
    onmousedown = on_mousedown,
    ondblclick = on_dblclick,
    onmousemove = on_mousemove,
    onmouseup = on_mouseup,
    onmouseleave = on_mouseleave,
    onwheel = on_wheel
  }

  local saved = core.plugin.preferences.bounds
  if saved then core.dialog.bounds = saved end

  core.dialog:show{ wait = false, autoscrollbars = false }
  core.refresh()
end

local function toggle_browser()
  -- Toggle: close if open, open if closed. Works as a keyboard shortcut toggle.
  if core.dialog then
    core.save_prefs()
    core.dialog:close()
    return
  end
  create_dialog()
end

function init(plugin)
  -- Register the File Tree command with Aseprite.
  core.plugin = plugin
  plugin:newCommand{
    id = "FileTree",
    title = "File Tree",
    group = "file_scripts",
    onclick = toggle_browser
  }
end

function exit(plugin)
  -- Clean up timers and save state when Aseprite unloads the extension.
  stop_timers()
  if core.dialog then
    core.save_prefs()
    core.dialog:close()
  end
end
