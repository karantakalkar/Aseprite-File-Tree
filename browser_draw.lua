-- browser_draw.lua
-- Theme handling and all canvas rendering.

local core = ...
local D = {}

local tc = {}
local font_h = 7

function D.refresh_theme()
  local c = app.theme.color
  local wf = c.window_face or Color{ r = 43, g = 43, b = 43 }
  -- Detect light vs dark theme by average brightness.
  local bright = (wf.red + wf.green + wf.blue) / 3

  if bright > 128 then
    -- Light theme: white and light grey alternating rows.
    tc.row_even = Color{ r = 255, g = 255, b = 255, a = 255 }
    tc.row_odd  = Color{ r = 240, g = 240, b = 240, a = 255 }
    tc.bg       = tc.row_even
    tc.section_bg = Color{ r = 230, g = 230, b = 230, a = 255 }
  else
    -- Dark theme: darken window_face for inset rows.
    local d = 15
    tc.row_even = Color{
      r = math.max(0, wf.red - d),
      g = math.max(0, wf.green - d),
      b = math.max(0, wf.blue - d), a = 255
    }
    tc.row_odd = Color{
      r = math.max(0, wf.red - d + 7),
      g = math.max(0, wf.green - d + 7),
      b = math.max(0, wf.blue - d + 7), a = 255
    }
    tc.bg = tc.row_even
    tc.section_bg = Color{
      r = math.max(0, wf.red - 2),
      g = math.max(0, wf.green - 2),
      b = math.max(0, wf.blue - 2), a = 255
    }
  end

  tc.text = c.text or Color{ r = 0, g = 0, b = 0 }
  tc.sel_bg = c.filelist_selected_row_face or Color{ r = 255, g = 85, b = 85 }
  tc.sel_text = c.filelist_selected_row_text or Color{ r = 255, g = 255, b = 255 }
  tc.hover_bg = c.menuitem_highlight_face or Color{ r = 124, g = 144, b = 159 }
  tc.hover_text = c.menuitem_highlight_text or Color{ r = 255, g = 255, b = 255 }
  tc.folder = c.link_text or Color{ r = 44, g = 76, b = 145 }
  tc.dim = c.disabled or Color{ r = 150, g = 130, b = 117 }
  tc.tree_line = Color{ r = 118, g = 118, b = 118, a = 255 }
  tc.menu_bg = Color{ r = 34, g = 34, b = 38, a = 255 }
  tc.menu_hover = Color{ r = 62, g = 77, b = 105, a = 255 }
  tc.menu_text = Color{ r = 240, g = 240, b = 240, a = 255 }
  tc.menu_border = Color{ r = 150, g = 150, b = 150, a = 255 }
  tc.sb_track = tc.row_even
  tc.sb_thumb = c.tab_active_face or Color{ r = 125, g = 146, b = 158 }
end

local function measure_content_width(gc)
  local max_w = 0
  local px = core.PAD_X
  for _, row in ipairs(core.visible_rows) do
    local x = px + row.depth * core.INDENT + core.CHEVRON_W
    local w = x + gc:measureText(row.name).width + px
    if row.is_section then w = gc:measureText(row.name).width + px * 3 end
    if w > max_w then max_w = w end
  end
  core.content_w = max_w
  core.content_dirty = false
end

local function paint_empty(gc)
  gc.color = tc.bg
  gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
  gc.color = tc.dim
  local msg = app.fs.isDirectory(core.root_path) and "Empty folder." or "Set a valid path."
  gc:fillText(msg, core.PAD_X, math.floor((gc.height - font_h) / 2))
end

local function paint_tree_lines(gc, row, y)
  if row.is_section or row.depth <= 0 then return end
  local px = core.PAD_X

  gc.color = tc.tree_line
  gc.strokeWidth = 1
  gc:beginPath()

  for depth = 0, row.depth - 1 do
    local x = px + depth * core.INDENT - core.h_scroll
    gc:moveTo(x, y)
    gc:lineTo(x, y + core.ROW_H)
  end

  local elbow_x = px + (row.depth - 1) * core.INDENT - core.h_scroll
  local label_x = px + row.depth * core.INDENT - core.h_scroll
  local mid_y = y + math.floor(core.ROW_H / 2)
  gc:moveTo(elbow_x, mid_y)
  gc:lineTo(label_x, mid_y)
  gc:stroke()
end

local function paint_row(gc, row, idx, view_w)
  local y = (idx - 1) * core.ROW_H - core.scroll
  local px = core.PAD_X
  local x = px + row.depth * core.INDENT - core.h_scroll
  local is_sel = row.path == core.selected and not row.is_shortcut
  local is_hov = idx == core.hovered_idx
  local exp = core.expanded_set()
  local base_text = tc.text

  if row.is_section then
    gc.color = tc.section_bg
    gc:fillRect(Rectangle(0, y, view_w, core.ROW_H))
    gc.color = tc.text
    gc:fillText("* " .. row.name .. ":", px, y + math.floor((core.ROW_H - font_h) / 2))
    return
  end

  if row.is_root_info then
    gc.color = tc.section_bg
    gc:fillRect(Rectangle(0, y, view_w, core.ROW_H))
    gc.color = tc.text
    gc:fillText(row.name, px, y + math.floor((core.ROW_H - font_h) / 2))
    return
  end

  if row.is_divider then
    gc.color = tc.tree_line
    gc:fillRect(Rectangle(0, y + math.floor(core.ROW_H / 2), view_w, 1))
    return
  end

  if is_sel then gc.color = tc.sel_bg
  elseif is_hov then gc.color = tc.hover_bg
  elseif idx % 2 == 0 then gc.color = tc.row_even
  else gc.color = tc.row_odd end
  gc:fillRect(Rectangle(0, y, view_w, core.ROW_H))

  if is_sel then base_text = tc.sel_text
  elseif is_hov then base_text = tc.hover_text end

  paint_tree_lines(gc, row, y)

  local ty = y + math.floor((core.ROW_H - font_h) / 2)
  if row.is_folder then
    if is_sel or is_hov then gc.color = base_text else gc.color = tc.tree_line end
    gc:fillText(exp[row.path] and "v" or ">", x, ty)
  end

  local label_x = x + core.CHEVRON_W
  if is_sel or is_hov then gc.color = base_text
  elseif row.is_folder then gc.color = tc.folder
  else gc.color = base_text end

  if row.row_type == "favorite" then
    gc:fillText("* " .. row.name, label_x, ty)
  else
    gc:fillText(row.name, label_x, ty)
  end
end

function D.v_thumb_rect()
  local view_h = core.view_h()
  local content = #core.visible_rows * core.ROW_H
  local th = math.floor(view_h * view_h / content)
  if th < 20 then th = 20 end
  if th > view_h then th = view_h end
  local ty = 0
  local m = core.max_v_scroll()
  if m > 0 then ty = math.floor((view_h - th) * core.scroll / m) end
  return Rectangle(core.canvas_w - core.SB_W, ty, core.SB_W, th)
end

local function paint_v_scrollbar(gc)
  if not core.needs_v_scroll() then return end
  local view_h = core.view_h()
  local sx = gc.width - core.SB_W
  gc.color = tc.sb_track
  gc:fillRect(Rectangle(sx, 0, core.SB_W, view_h))
  local t = D.v_thumb_rect()
  local ok = pcall(function() gc:drawThemeRect("scrollbar_thumb", t) end)
  if not ok then
    gc.color = tc.sb_thumb
    gc:fillRect(Rectangle(t.x + 2, t.y + 1, t.width - 4, t.height - 2))
  end
end

function D.h_thumb_rect()
  local view_w = core.view_w()
  local th = math.floor(view_w * view_w / core.content_w)
  if th < 20 then th = 20 end
  if th > view_w then th = view_w end
  local tx = 0
  local m = core.max_h_scroll()
  if m > 0 then tx = math.floor((view_w - th) * core.h_scroll / m) end
  return Rectangle(tx, core.canvas_h - core.SB_H, th, core.SB_H)
end

local function paint_h_scrollbar(gc)
  if not core.needs_h_scroll() then return end
  local view_w = core.view_w()
  local sy = gc.height - core.SB_H
  gc.color = tc.sb_track
  gc:fillRect(Rectangle(0, sy, view_w, core.SB_H))
  local t = D.h_thumb_rect()
  local ok = pcall(function() gc:drawThemeRect("scrollbar_thumb", t) end)
  if not ok then
    gc.color = tc.sb_thumb
    gc:fillRect(Rectangle(t.x + 1, t.y + 2, t.width - 2, t.height - 4))
  end
  if core.needs_v_scroll() then
    gc.color = tc.sb_track
    gc:fillRect(Rectangle(view_w, sy, core.SB_W, core.SB_H))
  end
end

local function paint_context_menu(gc)
  local menu = core.context_menu
  if menu == nil then return end

  local h = #menu.items * core.MENU_ROW_H
  local x = math.min(menu.x, gc.width - core.MENU_W - 1)
  local y = math.min(menu.y, gc.height - h - 1)
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  menu.draw_x = x
  menu.draw_y = y

  gc.color = tc.menu_bg
  gc:fillRect(Rectangle(x, y, core.MENU_W, h))
  gc.color = tc.menu_border
  gc:strokeRect(Rectangle(x, y, core.MENU_W, h))

  for i, item in ipairs(menu.items) do
    if i == core.context_hover then
      gc.color = tc.menu_hover
      gc:fillRect(Rectangle(x + 1, y + ((i - 1) * core.MENU_ROW_H) + 1, core.MENU_W - 2, core.MENU_ROW_H - 2))
    end
    gc.color = tc.menu_text
    gc:fillText(item.label, x + 6, y + ((i - 1) * core.MENU_ROW_H) + 4)
  end
end

function D.on_paint(ev)
  local gc = ev.context
  core.canvas_w = gc.width
  core.canvas_h = gc.height
  font_h = gc:measureText("Ay").height

  D.refresh_theme()

  if #core.visible_rows == 0 then
    paint_empty(gc)
    return
  end

  if core.content_dirty then measure_content_width(gc) end

  local view_w = core.view_w()
  local view_h = core.view_h()

  gc.color = tc.bg
  gc:fillRect(Rectangle(0, 0, gc.width, gc.height))

  if core.status_text ~= "" then
    gc.color = tc.dim
    gc:fillText(core.status_text, 0, 0)
  end

  for i, row in ipairs(core.visible_rows) do
    local y = (i - 1) * core.ROW_H - core.scroll
    if y > -core.ROW_H and y < view_h then paint_row(gc, row, i, view_w) end
  end

  paint_v_scrollbar(gc)
  paint_h_scrollbar(gc)
  paint_context_menu(gc)
end

return D
