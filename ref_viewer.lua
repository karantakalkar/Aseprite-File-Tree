-- ref_viewer.lua
-- Single-image reference viewing, navigation, color sampling, and crop copying.

local R = {}

R.TOOLBAR_H = 90
R.PAD = 8
R.MIN_ZOOM = 0.05
R.MAX_ZOOM = 32
R.ZOOM_STEP = 1.25

R.path = nil
R.image = nil
R.status = "Select a file before opening Preview Ref."
R.zoom = 1
R.pan_x = 0
R.pan_y = 0
R.crop_draft = nil
R.crop_mode = false
R.pick_mode = nil
R.notice = ""
R.drag_mode = nil
R.drag_start_x = 0
R.drag_start_y = 0
R.drag_pan_x = 0
R.drag_pan_y = 0
R.crop_start_x = 0
R.crop_start_y = 0
R.view_w = 0
R.view_h = 0
R.buttons = {}
R.fg_color = nil
R.bg_color = nil

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function rect_contains(rect, x, y)
  return x >= rect.x
    and y >= rect.y
    and x < rect.x + rect.width
    and y < rect.y + rect.height
end

local function screen_rect(x, y, width, height)
  local left = math.floor(x + 0.5)
  local top = math.floor(y + 0.5)
  local right = math.floor(x + width + 0.5)
  local bottom = math.floor(y + height + 0.5)
  return Rectangle(
    left,
    top,
    math.max(1, right - left),
    math.max(1, bottom - top)
  )
end

local function normalized_rect(x1, y1, x2, y2)
  local epsilon = 0.000001
  local left = math.floor(math.min(x1, x2) + epsilon)
  local top = math.floor(math.min(y1, y2) + epsilon)
  local right = math.ceil(math.max(x1, x2) - epsilon)
  local bottom = math.ceil(math.max(y1, y2) - epsilon)
  return {
    x = left,
    y = top,
    width = right - left,
    height = bottom - top
  }
end

function R.source_rect()
  if R.image == nil then return nil end
  return { x = 0, y = 0, width = R.image.width, height = R.image.height }
end

function R.content_rect(width, height)
  return {
    x = 0,
    y = 0,
    width = width,
    height = math.max(1, height - R.TOOLBAR_H)
  }
end

function R.image_rect()
  local source = R.source_rect()
  if source == nil then return nil end
  return {
    x = R.pan_x,
    y = R.pan_y,
    width = source.width * R.zoom,
    height = source.height * R.zoom
  }
end

function R.reset()
  R.path = nil
  R.image = nil
  R.status = "Select a file before opening Preview Ref."
  R.zoom = 1
  R.pan_x = 0
  R.pan_y = 0
  R.crop_draft = nil
  R.crop_mode = false
  R.pick_mode = nil
  R.notice = ""
  R.drag_mode = nil
  R.buttons = {}
  R.fg_color = nil
  R.bg_color = nil
  R.view_w = 0
  R.view_h = 0
end

function R.load(path)
  R.reset()
  if path == nil or path == "" then return false end

  local ok, image = pcall(function() return Image{ fromFile = path } end)
  if not ok or image == nil then
    R.status = "Could not open this reference image."
    return false
  end

  R.path = path
  R.image = image
  R.status = ""
  return true
end

function R.reload(path)
  -- Refresh saved pixels without moving the current reference view.
  local zoom = R.zoom
  local pan_x = R.pan_x
  local pan_y = R.pan_y
  local view_w = R.view_w
  local view_h = R.view_h

  if not R.load(path) then return false end

  R.zoom = zoom
  R.pan_x = pan_x
  R.pan_y = pan_y
  R.view_w = view_w
  R.view_h = view_h
  return true
end

function R.fit(width, height)
  if R.image == nil then return end
  local source = R.source_rect()
  local content = R.content_rect(width, height)
  local available_w = math.max(1, content.width - R.PAD * 2)
  local available_h = math.max(1, content.height - R.PAD * 2)

  R.zoom = math.min(available_w / source.width, available_h / source.height)
  R.zoom = clamp(R.zoom, R.MIN_ZOOM, R.MAX_ZOOM)
  R.pan_x = content.x + (content.width - source.width * R.zoom) / 2
  R.pan_y = content.y + (content.height - source.height * R.zoom) / 2
  R.view_w = width
  R.view_h = height
end

function R.actual_size(width, height)
  if R.image == nil then return end
  local source = R.source_rect()
  local content = R.content_rect(width, height)
  R.zoom = 1
  R.pan_x = content.x + (content.width - source.width) / 2
  R.pan_y = content.y + (content.height - source.height) / 2
  R.view_w = width
  R.view_h = height
end

function R.ensure_viewport(width, height)
  if R.image == nil then return end
  if R.view_w == width and R.view_h == height then return end
  R.fit(width, height)
end

function R.screen_to_image(x, y, should_clamp)
  local source = R.source_rect()
  if source == nil then return nil, nil end

  local image_x = source.x + (x - R.pan_x) / R.zoom
  local image_y = source.y + (y - R.pan_y) / R.zoom
  if should_clamp then
    image_x = clamp(image_x, source.x, source.x + source.width)
    image_y = clamp(image_y, source.y, source.y + source.height)
  end
  return image_x, image_y
end

function R.image_to_screen(x, y)
  local source = R.source_rect()
  if source == nil then return nil, nil end
  return R.pan_x + (x - source.x) * R.zoom,
    R.pan_y + (y - source.y) * R.zoom
end

function R.zoom_at(x, y, factor, width, height)
  if R.image == nil then return end
  local image_x, image_y = R.screen_to_image(x, y, false)
  local source = R.source_rect()

  R.zoom = clamp(R.zoom * factor, R.MIN_ZOOM, R.MAX_ZOOM)
  R.pan_x = x - (image_x - source.x) * R.zoom
  R.pan_y = y - (image_y - source.y) * R.zoom
  R.view_w = width
  R.view_h = height
end

function R.zoom_centered(factor, width, height)
  local content = R.content_rect(width, height)
  R.zoom_at(
    content.x + content.width / 2,
    content.y + content.height / 2,
    factor,
    width,
    height
  )
end

function R.reset_view(width, height)
  R.fit(width, height)
end

function R.begin_crop()
  if R.image == nil then return end
  R.crop_mode = true
  R.crop_draft = nil
  R.pick_mode = nil
  R.notice = "Drag a rectangle with the left mouse button."
  R.drag_mode = nil
end

function R.cancel_crop()
  R.crop_mode = false
  R.crop_draft = nil
  R.notice = ""
  R.drag_mode = nil
end

function R.copy_crop()
  if R.crop_draft == nil then return false end
  local area = R.crop_draft
  local copied = Image(R.image, Rectangle(area.x, area.y, area.width, area.height))
  app.clipboard.image = copied
  R.crop_mode = false
  R.crop_draft = nil
  R.notice = "Crop copied. Paste it into the active sprite with Ctrl+V."
  return true
end

function R.begin_crop_drag(x, y)
  local drawn = R.image_rect()
  if drawn == nil or not rect_contains(drawn, x, y) then return false end

  local image_x, image_y = R.screen_to_image(x, y, true)
  R.crop_start_x = image_x
  R.crop_start_y = image_y
  R.crop_draft = nil
  R.drag_mode = "crop"
  return true
end

function R.update_crop_drag(x, y)
  if R.drag_mode ~= "crop" then return end
  local image_x, image_y = R.screen_to_image(x, y, true)
  local draft = normalized_rect(R.crop_start_x, R.crop_start_y, image_x, image_y)
  if draft.width < 1 or draft.height < 1 then
    R.crop_draft = nil
    return
  end
  R.crop_draft = draft
end

function R.begin_pan(x, y)
  R.drag_mode = "pan"
  R.drag_start_x = x
  R.drag_start_y = y
  R.drag_pan_x = R.pan_x
  R.drag_pan_y = R.pan_y
end

function R.begin_pick(target)
  if R.image == nil then return end
  R.crop_mode = false
  R.crop_draft = nil
  R.pick_mode = target
  if target == "foreground" then
    R.notice = "Click the image to choose the Primary color."
  else
    R.notice = "Click the image to choose the Secondary color."
  end
end

function R.update_pan(x, y)
  if R.drag_mode ~= "pan" then return end
  R.pan_x = R.drag_pan_x + x - R.drag_start_x
  R.pan_y = R.drag_pan_y + y - R.drag_start_y
end

function R.end_drag()
  R.drag_mode = nil
end

local function pixel_to_color(pixel)
  local mode = R.image.colorMode
  if mode == nil and R.image.spec ~= nil then mode = R.image.spec.colorMode end

  if ColorMode ~= nil and mode == ColorMode.GRAY then
    local value = app.pixelColor.grayaV(pixel)
    local alpha = app.pixelColor.grayaA(pixel)
    return Color{ gray = value, alpha = alpha }
  end

  if ColorMode ~= nil and mode == ColorMode.INDEXED then
    return Color{ index = pixel }
  end

  return Color{
    r = app.pixelColor.rgbaR(pixel),
    g = app.pixelColor.rgbaG(pixel),
    b = app.pixelColor.rgbaB(pixel),
    a = app.pixelColor.rgbaA(pixel)
  }
end

function R.sample_at(x, y, target)
  local drawn = R.image_rect()
  if R.image == nil or drawn == nil or not rect_contains(drawn, x, y) then return false end

  local image_x, image_y = R.screen_to_image(x, y, false)
  image_x = clamp(math.floor(image_x), 0, R.image.width - 1)
  image_y = clamp(math.floor(image_y), 0, R.image.height - 1)

  local color = pixel_to_color(R.image:getPixel(image_x, image_y))
  if target == "foreground" then
    app.fgColor = color
    R.fg_color = color
    R.notice = "Primary color picked."
  else
    app.bgColor = color
    R.bg_color = color
    R.notice = "Secondary color picked."
  end
  R.pick_mode = nil
  return true
end

local function button_width(gc, label)
  return math.max(24, gc:measureText(label).width + 12)
end

local function add_button(gc, label, action, x, y, active)
  local button = {
    label = label,
    action = action,
    active = active == true,
    x = x,
    y = y,
    width = button_width(gc, label),
    height = 20
  }
  table.insert(R.buttons, button)
  return x + button.width + 3
end

local function draw_button(gc, button, colors)
  local rect = Rectangle(button.x, button.y, button.width, button.height)
  gc.color = button.active and colors.button_active or colors.button
  gc:fillRect(rect)
  gc.color = colors.border
  gc:strokeRect(rect)
  gc.color = colors.text
  local text_size = gc:measureText(button.label)
  local text_x = button.x + math.floor((button.width - text_size.width) / 2)
  local text_y = button.y + math.floor((button.height - text_size.height) / 2)
  gc:fillText(button.label, text_x, text_y)
end

local function paint_toolbar(gc, colors)
  local toolbar_y = gc.height - R.TOOLBAR_H
  gc.color = colors.toolbar
  gc:fillRect(Rectangle(0, toolbar_y, gc.width, R.TOOLBAR_H))
  gc.color = colors.border
  gc:fillRect(Rectangle(0, toolbar_y, gc.width, 1))

  gc.color = colors.text
  local guidance = "Wheel: zoom  Middle-drag: pan  Tools: left-click"
  if R.notice ~= "" then guidance = R.notice end
  gc:fillText(guidance, 4, toolbar_y + 6)

  R.buttons = {}
  local x = 4
  local row_one_y = toolbar_y + 22
  x = add_button(gc, "Fit", "fit", x, row_one_y)
  x = add_button(gc, "100%", "actual", x, row_one_y)
  x = add_button(gc, "-", "zoom_out", x, row_one_y)
  add_button(gc, "+", "zoom_in", x, row_one_y)

  x = 4
  local row_two_y = toolbar_y + 44
  x = add_button(
    gc,
    "Pick Primary Color",
    "pick_foreground",
    x,
    row_two_y,
    R.pick_mode == "foreground"
  )
  add_button(
    gc,
    "Pick Secondary Color",
    "pick_background",
    x,
    row_two_y,
    R.pick_mode == "background"
  )

  x = 4
  local row_three_y = toolbar_y + 66
  if R.crop_mode and R.crop_draft ~= nil then
    x = add_button(gc, "Copy Crop", "copy_crop", x, row_three_y, true)
    x = add_button(gc, "Cancel", "cancel_crop", x, row_three_y)
  elseif R.crop_mode then
    x = add_button(gc, "Cancel Crop", "cancel_crop", x, row_three_y, true)
  else
    x = add_button(gc, "Crop", "begin_crop", x, row_three_y)
  end

  for _, button in ipairs(R.buttons) do draw_button(gc, button, colors) end
end

local function crop_screen_rect()
  if R.crop_draft == nil then return nil end
  local x, y = R.image_to_screen(R.crop_draft.x, R.crop_draft.y)
  return {
    x = x,
    y = y,
    width = R.crop_draft.width * R.zoom,
    height = R.crop_draft.height * R.zoom
  }
end

local function paint_crop_overlay(gc, colors)
  local crop_rect = crop_screen_rect()
  local image_rect = R.image_rect()
  if crop_rect == nil or image_rect == nil then return end

  local left = math.max(image_rect.x, crop_rect.x)
  local top = math.max(image_rect.y, crop_rect.y)
  local right = math.min(image_rect.x + image_rect.width, crop_rect.x + crop_rect.width)
  local bottom = math.min(image_rect.y + image_rect.height, crop_rect.y + crop_rect.height)

  gc.color = colors.crop_dim
  if top > image_rect.y then
    gc:fillRect(screen_rect(image_rect.x, image_rect.y, image_rect.width, top - image_rect.y))
  end
  if bottom < image_rect.y + image_rect.height then
    gc:fillRect(screen_rect(image_rect.x, bottom, image_rect.width, image_rect.y + image_rect.height - bottom))
  end
  if left > image_rect.x then
    gc:fillRect(screen_rect(image_rect.x, top, left - image_rect.x, bottom - top))
  end
  if right < image_rect.x + image_rect.width then
    gc:fillRect(screen_rect(right, top, image_rect.x + image_rect.width - right, bottom - top))
  end

  gc.color = colors.crop_border
  gc:strokeRect(screen_rect(left, top, right - left, bottom - top))
end

function R.paint(gc)
  local theme = app.theme.color
  local colors = {
    background = theme.window_face or Color{ r = 35, g = 35, b = 35 },
    toolbar = Color{ r = 22, g = 24, b = 30, a = 255 },
    button = Color{ r = 65, g = 78, b = 102, a = 255 },
    button_active = Color{ r = 23, g = 132, b = 170, a = 255 },
    border = Color{ r = 178, g = 190, b = 212, a = 255 },
    text = Color{ r = 255, g = 255, b = 255, a = 255 },
    dim_text = theme.disabled or Color{ r = 150, g = 150, b = 150 },
    crop_dim = Color{ r = 0, g = 0, b = 0, a = 145 },
    crop_border = Color{ r = 255, g = 215, b = 65, a = 255 }
  }

  gc.color = colors.background
  gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
  R.ensure_viewport(gc.width, gc.height)

  if R.image == nil then
    gc.color = colors.dim_text
    local size = gc:measureText(R.status)
    gc:fillText(
      R.status,
      math.max(R.PAD, math.floor((gc.width - size.width) / 2)),
      math.floor((gc.height - R.TOOLBAR_H - size.height) / 2)
    )
  else
    local source = R.source_rect()
    local destination = R.image_rect()
    gc:drawImage(
      R.image,
      Rectangle(source.x, source.y, source.width, source.height),
      screen_rect(destination.x, destination.y, destination.width, destination.height)
    )

    paint_crop_overlay(gc, colors)
  end

  paint_toolbar(gc, colors)
end

function R.button_at(x, y)
  for _, button in ipairs(R.buttons) do
    if rect_contains(button, x, y) then return button end
  end
  return nil
end

function R.run_button(button, width, height)
  if button == nil then return false end
  if button.action == "fit" then R.fit(width, height)
  elseif button.action == "actual" then R.actual_size(width, height)
  elseif button.action == "zoom_out" then R.zoom_centered(1 / R.ZOOM_STEP, width, height)
  elseif button.action == "zoom_in" then R.zoom_centered(R.ZOOM_STEP, width, height)
  elseif button.action == "pick_foreground" then R.begin_pick("foreground")
  elseif button.action == "pick_background" then R.begin_pick("background")
  elseif button.action == "begin_crop" then R.begin_crop()
  elseif button.action == "copy_crop" then R.copy_crop()
  elseif button.action == "cancel_crop" then R.cancel_crop()
  end
  return true
end

function R.mousedown(x, y, ctrl_key, shift_key, middle_button, width, height)
  if middle_button then
    if R.image ~= nil and y < height - R.TOOLBAR_H then R.begin_pan(x, y) end
    return true
  end

  local button = R.button_at(x, y)
  if button ~= nil then return R.run_button(button, width, height) end
  if y >= height - R.TOOLBAR_H or R.image == nil then return true end

  if ctrl_key then
    R.sample_at(x, y, "foreground")
    return true
  end
  if shift_key then
    R.sample_at(x, y, "background")
    return true
  end
  if R.pick_mode ~= nil then
    R.sample_at(x, y, R.pick_mode)
    return true
  end
  if R.crop_mode then
    R.begin_crop_drag(x, y)
    return true
  end

  return true
end

function R.mousemove(x, y, left_down, middle_down)
  if R.drag_mode == "crop" and not left_down then
    R.end_drag()
    return
  end
  if R.drag_mode == "pan" and not middle_down then
    R.end_drag()
    return
  end
  if R.drag_mode == "crop" then
    R.update_crop_drag(x, y)
  elseif R.drag_mode == "pan" then
    R.update_pan(x, y)
  end
end

function R.mouseup()
  R.end_drag()
end

function R.mouseleave()
  R.end_drag()
end

function R.wheel(x, y, delta_y, width, height)
  if R.image == nil or y >= height - R.TOOLBAR_H then return end
  local factor = delta_y < 0 and R.ZOOM_STEP or 1 / R.ZOOM_STEP
  R.zoom_at(x, y, factor, width, height)
end

return R
