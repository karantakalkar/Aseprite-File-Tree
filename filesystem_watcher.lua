-- Round-robin directory polling, plus bounded content checks for the active preview.
local core = ...
local W = { interval = 1.0, snapshots = {}, timer = nil, cursor = 1, folder_budget = 16 }

local function folder_snapshot(path)
  if not app.fs.isDirectory(path) then return false end
  local ok, snapshot = pcall(function()
    local entries = {}
    for _, name in ipairs(app.fs.listFiles(path)) do
      local child = app.fs.joinPath(path, name)
      if app.fs.isDirectory(child) then entries[name] = "directory"
      elseif core.is_supported(child) then entries[name] = "file" end
    end
    return entries
  end)
  if not ok then return nil end
  return snapshot
end

local function snapshots_equal(first, second)
  if first == second then return true end
  if type(first) ~= "table" or type(second) ~= "table" then return false end
  for name, value in pairs(first) do if second[name] ~= value then return false end end
  for name in pairs(second) do if first[name] == nil then return false end end
  return true
end

function W:reset()
  self.snapshots = {}
  self.cursor = 1
  self.content = nil
end

function W:check_preview()
  local path
  if core.preview_mode == "preview" then path = core.preview_path end
  if core.preview_mode == "ref" and core.ref_viewer then path = core.ref_viewer.path end
  if not path then self.content = nil; return end
  if not app.fs.isFile(path) then
    core.clear_preview("Reference file was removed.")
    if core.ref_viewer then core.ref_viewer.reset() end
    self.content = nil
    core.dialog:repaint()
    return
  end
  local size = app.fs.fileSize(path)
  if not self.content or self.content.path ~= path then
    self.content = { path = path, offset = 0, hash = 2166136261, size = size }
  end
  local content = self.content
  if size ~= content.size then content.offset, content.hash, content.size = 0, 2166136261, size end
  -- Reopen each tick so Windows saves/renames aren't held up by a persistent handle.
  local file = io.open(path, "rb")
  if not file then return end
  file:seek("set", content.offset)
  local chunk = file:read(262144)
  file:close()
  if chunk then
    for index = 1, #chunk do
      content.hash = ((content.hash ~ chunk:byte(index)) * 16777619) & 0xffffffff
    end
    content.offset = content.offset + #chunk
  end
  if content.offset < size then return end
  local signature = tostring(size) .. ":" .. tostring(content.hash)
  if content.previous and content.previous ~= signature then
    if core.preview_mode == "ref" then core.ref_viewer.reload(path) else core.load_preview(path) end
    core.dialog:repaint()
  end
  content.previous = signature
  content.offset, content.hash = 0, 2166136261
end

function W:check()
  if core.dialog == nil then return end
  local paths, watched = {}, {}
  local function watch(path)
    if not core.has(path) or watched[path] then return end
    watched[path] = true
    table.insert(paths, path)
  end
  watch(core.root_path)
  for path in pairs(core.file_cache) do watch(path) end
  -- Expanded preferences can include other projects; only watch the current cache.
  table.sort(paths)
  local changed, checked = {}, {}
  local function check(path)
    if not path or checked[path] then return end
    checked[path] = true
    local current = folder_snapshot(path)
    if current == nil then return end
    local previous = self.snapshots[path]
    if previous ~= nil and not snapshots_equal(previous, current) then table.insert(changed, path) end
    self.snapshots[path] = current
  end
  check(core.root_path)
  for _ = 1, math.min(self.folder_budget, #paths) do
    if self.cursor > #paths then self.cursor = 1 end
    check(paths[self.cursor])
    self.cursor = self.cursor + 1
  end
  for path in pairs(self.snapshots) do
    if not watched[path] then self.snapshots[path] = nil end
  end
  if #changed > 0 then core.invalidate_folders(changed) end
  self:check_preview()
end

function W:start()
  if self.timer == nil then
    self.timer = Timer{ interval = self.interval, ontick = function() self:check() end }
  end
  self:reset()
  self:check()
  self.timer:start()
end

function W:stop()
  if self.timer ~= nil and self.timer.isRunning then self.timer:stop() end
  self.content = nil
end

return W
