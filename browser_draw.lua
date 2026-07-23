-- browser_draw.lua
-- Theme handling and all canvas rendering.

local core = ...
local D = {}

-- Theme colors are cached so paint functions stay small and consistent.
local tc = {}
local font_h = 7

function D.refresh_theme()
  -- Pull colors from the current Aseprite theme and derive row/menu colors.
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
    tc.tag_text = Color{ r = 35, g = 35, b = 35, a = 255 }
    tc.tag_bg = {
      red = Color{ r = 255, g = 200, b = 200, a = 255 },
      green = Color{ r = 199, g = 235, b = 199, a = 255 },
      blue = Color{ r = 195, g = 218, b = 255, a = 255 },
      yellow = Color{ r = 250, g = 235, b = 160, a = 255 },
      purple = Color{ r = 225, g = 199, b = 245, a = 255 }
    }
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
    tc.tag_text = Color{ r = 245, g = 245, b = 245, a = 255 }
    tc.tag_bg = {
      red = Color{ r = 112, g = 46, b = 46, a = 255 },
      green = Color{ r = 45, g = 92, b = 54, a = 255 },
      blue = Color{ r = 44, g = 70, b = 112, a = 255 },
      yellow = Color{ r = 105, g = 88, b = 34, a = 255 },
      purple = Color{ r = 82, g = 50, b = 108, a = 255 }
    }
  end

  tc.text = c.text or Color{ r = 0, g = 0, b = 0 }
  tc.sel_bg = c.filelist_selected_row_face or Color{ r = 255, g = 85, b = 85 }
  tc.sel_text = c.filelist_selected_row_text or Color{ r = 255, g = 255, b = 255 }
  tc.hover_bg = c.menuitem_highlight_face or Color{ r = 124, g = 144, b = 159 }
  tc.hover_text = c.menuitem_highlight_text or Color{ r = 255, g = 255, b = 255 }
  tc.drop_bg = c.filelist_selected_row_face or tc.hover_bg
  tc.drop_text = c.filelist_selected_row_text or tc.hover_text
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
  -- Measure the widest visible row for horizontal scrolling.
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
  -- Draw an empty-state message when the root is invalid or has no rows.
  local tree_w = core.tree_w()
  gc.color = tc.bg
  gc:fillRect(Rectangle(0, 0, tree_w, gc.height))
  gc.color = tc.dim
  local msg = app.fs.isDirectory(core.root_path) and "Empty folder." or "Set a valid path."
  gc:fillText(msg, core.PAD_X, math.floor((gc.height - font_h) / 2))
end

local function paint_tree_lines(gc, row, y)
  -- Draw lightweight connector lines for nested folder/file rows.
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
  -- Draw one visible tree row, including special section/root/divider rows.
  local y = (idx - 1) * core.ROW_H - core.scroll
  local px = core.PAD_X
  local x = px + row.depth * core.INDENT - core.h_scroll
  local is_sel = row.path == core.selected and not row.is_shortcut
  local is_hov = idx == core.hovered_idx
  local is_drop = core.drag_started and row.path == core.drag_target_path
  local tag_name = core.color_tag_for_path(row.path)
  local tag_bg = tag_name and tc.tag_bg[tag_name] or nil
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
    local root_drop = core.drag_started and core.drag_target_path == core.root_path
    gc.color = root_drop and tc.drop_bg or tc.section_bg
    gc:fillRect(Rectangle(0, y, view_w, core.ROW_H))
    gc.color = root_drop and tc.drop_text or tc.text
    local text = root_drop and "Move to current root" or row.name
    if root_drop and core.drag_copy then text = "Copy to current root" end
    gc:fillText(text, px, y + math.floor((core.ROW_H - font_h) / 2))
    return
  end

  if row.is_divider then
    gc.color = tc.tree_line
    gc:fillRect(Rectangle(0, y + math.floor(core.ROW_H / 2), view_w, 1))
    return
  end

  if is_drop then gc.color = tc.drop_bg
  elseif is_sel then gc.color = tc.sel_bg
  elseif is_hov then gc.color = tc.hover_bg
  elseif tag_bg then gc.color = tag_bg
  elseif idx % 2 == 0 then gc.color = tc.row_even
  else gc.color = tc.row_odd end
  gc:fillRect(Rectangle(0, y, view_w, core.ROW_H))

  if is_drop then base_text = tc.drop_text
  elseif is_sel then base_text = tc.sel_text
  elseif is_hov then base_text = tc.hover_text
  elseif tag_bg then base_text = tc.tag_text end

  paint_tree_lines(gc, row, y)

  local ty = y + math.floor((core.ROW_H - font_h) / 2)
  if row.is_folder then
    if is_drop or is_sel or is_hov or tag_bg then gc.color = base_text else gc.color = tc.tree_line end
    gc:fillText(exp[row.path] and "v" or ">", x, ty)
  end

  local label_x = x + core.CHEVRON_W
  if is_drop or is_sel or is_hov or tag_bg then gc.color = base_text
  elseif row.is_folder then gc.color = tc.folder
  else gc.color = base_text end

  if row.row_type == "favorite" then
    gc:fillText("* " .. row.name, label_x, ty)
  else
    gc:fillText(row.name, label_x, ty)
  end
end

function D.v_thumb_rect()
  -- Compute vertical scrollbar thumb position from current scroll offset.
  local view_h = core.view_h()
  local content = #core.visible_rows * core.ROW_H
  local th = math.floor(view_h * view_h / content)
  if th < 20 then th = 20 end
  if th > view_h then th = view_h end
  local ty = 0
  local m = core.max_v_scroll()
  if m > 0 then ty = math.floor((view_h - th) * core.scroll / m) end
  return Rectangle(core.tree_w() - core.SB_W, ty, core.SB_W, th)
end

local function paint_v_scrollbar(gc)
  -- Draw the vertical scrollbar when rows overflow the tree height.
  if not core.needs_v_scroll() then return end
  local view_h = core.view_h()
  local sx = core.tree_w() - core.SB_W
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
  -- Compute horizontal scrollbar thumb position from current h_scroll.
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
  -- Draw the horizontal scrollbar when row labels overflow the tree width.
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
  -- Draw the custom context menu inside the canvas.
  local menu = core.context_menu
  if menu == nil then return end

  local h = #menu.items * core.MENU_ROW_H
  local x = math.min(menu.x, core.tree_w() - core.MENU_W - 1)
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

local function preview_rect()
  -- Return the preview pane rectangle based on the current divider position.
  local x = core.preview_x()
  return Rectangle(x, 0, core.canvas_w - x, core.canvas_h)
end

local function image_fit_rect(image, rect)
  -- Scale the image to fit fully inside the preview pane.
  local pad = 8
  local max_w = rect.width - pad * 2
  local max_h = rect.height - pad * 2
  local scale = math.min(max_w / image.width, max_h / image.height)
  local w = math.max(1, math.floor(image.width * scale))
  local h = math.max(1, math.floor(image.height * scale))
  local x = rect.x + math.floor((rect.width - w) / 2)
  local y = rect.y + math.floor((rect.height - h) / 2)
  return Rectangle(x, y, w, h)
end

local function paint_centered_preview_text(gc, rect, text)
  -- Preview status needs strong contrast and centered placement.
  local size = gc:measureText(text)
  local x = rect.x + math.floor((rect.width - size.width) / 2)
  local y = rect.y + math.floor((rect.height - size.height) / 2)
  if x < rect.x + core.PAD_X then x = rect.x + core.PAD_X end
  gc.color = tc.text
  gc:fillText(text, x, y)
end

local function paint_preview(gc)
  -- Draw preview background, divider, status text, or the selected image.
  if not core.has_preview_pane() then return end

  local rect = preview_rect()
  gc.color = tc.section_bg
  gc:fillRect(rect)
  gc.color = tc.tree_line
  gc:fillRect(Rectangle(rect.x - core.PREVIEW_GAP, 0, core.PREVIEW_GAP, rect.height))

  if core.preview_image == nil then
    paint_centered_preview_text(gc, rect, core.preview_status)
    return
  end

  local dst = image_fit_rect(core.preview_image, rect)
  gc:drawImage(core.preview_image, Rectangle(0, 0, core.preview_image.width, core.preview_image.height), dst)
end

function D.on_paint(ev)
  -- Main canvas paint entry point called by Aseprite.
  local gc = ev.context
  core.canvas_w = gc.width
  core.canvas_h = gc.height
  font_h = gc:measureText("Ay").height

  D.refresh_theme()

  if #core.visible_rows == 0 then
    paint_empty(gc)
    paint_preview(gc)
    return
  end

  if core.content_dirty then measure_content_width(gc) end

  local view_w = core.view_w()
  local view_h = core.view_h()

  gc.color = tc.bg
  gc:fillRect(Rectangle(0, 0, core.tree_w(), gc.height))

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
  paint_preview(gc)
  paint_context_menu(gc)
end

return D
