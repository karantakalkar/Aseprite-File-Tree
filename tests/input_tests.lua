-- Exercise the actual canvas callbacks with lightweight Dialog/Timer adapters.
local repo_path = ...
local fake = assert(loadfile(app.fs.joinPath(repo_path, "tests", "fake_filesystem.lua")))()
local env = fake.environment()
local native_loadfile = loadfile
local core, controls, command
local timers = {}
local function expect(value, message) assert(value, message) end

env.loadfile = function(path)
  local chunk, err = native_loadfile(path, "t", env)
  if not chunk then return nil, err end
  return function(...)
    local result = chunk(...)
    if path:match("browser_core.lua$") then
      core = result
      core.save_prefs = function() end
      core.save_browser_settings = function() end
    end
    return result
  end
end
env.Timer = function(options)
  options.isRunning = false
  options.start = function(self) self.isRunning = true end
  options.stop = function(self) self.isRunning = false end
  table.insert(timers, options)
  return options
end
env.Dialog = function()
  controls = {}
  local dialog = { data = {}, bounds = { x = 0, y = 0, width = 400, height = 500 } }
  for _, method in ipairs({ "label", "entry", "button", "canvas", "combobox", "check" }) do
    dialog[method] = function(self, options)
      if options.id then
        controls[options.id] = options
        self.data[options.id] = options.text or options.option
      end
      return self
    end
  end
  for _, method in ipairs({ "newrow", "separator", "show", "close", "repaint" }) do
    dialog[method] = function(self) return self end
  end
  dialog.modify = function(self, options)
    if options.text then self.data[options.id] = options.text end
    return self
  end
  return dialog
end

fake.add_directory("/workspace")
fake.add_directory("/workspace/target")
fake.add_file("/workspace/a.png", "a")
fake.add_file("/workspace/b.png", "b")
assert(native_loadfile(app.fs.joinPath(repo_path, "folder_browser.lua"), "t", env))()
env.init({ preferences = { root_path = "/workspace", expanded = {} }, newCommand = function(_, definition) command = definition end })
command.onclick()
local canvas = controls.tree
expect(canvas and canvas.onkeydown, "canvas keyboard handler missing")
core.canvas_w, core.canvas_h = 400, 500
local function y_for(path)
  for index, row in ipairs(core.visible_rows) do
    if row.path == path then
      local position = (index - 1) * core.ROW_H
      local y = position - core.scroll + 5
      if y < 0 or y >= core.canvas_h then core.scroll = position; y = 5 end
      return y
    end
  end
  error("missing row " .. path)
end
local function click(path, modifiers)
  local event = modifiers or {}
  event.x, event.y, event.button = 60, y_for(path), 1
  canvas.onmousedown(event)
  canvas.onmouseup()
end
local function key(code, modifiers)
  local event = modifiers or {}
  event.code = code
  event.stopPropagation = function(self) self.stopped = true end
  canvas.onkeydown(event)
  expect(event.stopped, "handled shortcut propagated into sprite editor")
end

click("/workspace/a.png")
click("/workspace/b.png", { ctrlKey = true })
expect(core.selection["/workspace/a.png"] and core.selection["/workspace/b.png"], "Ctrl-click did not keep selection")
canvas.onmousedown({ x = 60, y = y_for("/workspace/a.png"), button = 1 })
expect(core.selection["/workspace/b.png"], "mousedown collapsed selection before drag")
canvas.onmousemove({ x = 65, y = y_for("/workspace/target"), button = 1 })
canvas.onmouseup()
expect(fake.read_file("/workspace/target/a.png") and fake.read_file("/workspace/target/b.png"), "drag callbacks did not move group")
expect(not fake.read_file("/workspace/a.png") and not fake.read_file("/workspace/b.png"), "drag left source items")

click("/workspace/target/a.png")
click("/workspace/target/b.png", { shiftKey = true })
key("KeyC", { ctrlKey = true })
expect(#core.clipboard_items == 2, "copy shortcut omitted group")
core.selected = nil -- empty-space paste targets the root
key("KeyV", { ctrlKey = true })
expect(fake.read_file("/workspace/a.png") and fake.read_file("/workspace/b.png"), "paste shortcut omitted group")
click("/workspace/a.png")
click("/workspace/b.png", { ctrlKey = true })
click("/workspace/a.png")
expect(not core.selection["/workspace/b.png"], "plain click did not collapse selection on mouseup")

env.app.os.windows, env.app.os.macos = false, true
click("/workspace/b.png", { metaKey = true })
expect(core.selection["/workspace/a.png"] and core.selection["/workspace/b.png"], "Command-click did not add on macOS")
key("KeyX", { metaKey = true })
expect(#core.clipboard_items == 2 and core.clipboard_action == "cut", "Command-X omitted group")
key("Escape")
expect(next(core.selection) == nil, "Escape did not clear selection")

-- A new query must take effect even while an earlier index is still building.
for index = 1, 30 do fake.add_directory("/workspace/f" .. index) end
core.file_cache = {}
core.dialog.data.filter_entry = "old query"
controls.filter_entry.onchange()
timers[1].ontick()
expect(core.search_job ~= nil, "search did not yield through the real timer path")
core.dialog.data.filter_entry = "a.png"
controls.filter_entry.onchange()
timers[1].ontick()
expect(core.filter_text == "a.png", "new query was lost during indexing")
while core.search_job do timers[2].ontick() end
expect(core.search_matches["/workspace/a.png"], "timer search missed result")
expect(not timers[2].isRunning, "completed search timer kept running")
core.set_filter("")
click("/workspace/a.png")
click("/workspace/b.png", { ctrlKey = true })
key("Delete")
expect(core.selection["/workspace/a.png"] and core.selection["/workspace/b.png"], "delete shortcut lost group selection")
expect(fake.read_file("/workspace/a.png") and fake.read_file("/workspace/b.png"), "delete ran before confirmation")
controls.delete.onclick()
expect(not fake.read_file("/workspace/a.png") and not fake.read_file("/workspace/b.png"), "confirmed Delete shortcut omitted group")
print("Canvas input and timer tests passed.")
