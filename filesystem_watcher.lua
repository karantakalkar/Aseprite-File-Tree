-- filesystem_watcher.lua
-- Targeted polling for external changes in folders the browser already knows.

local core = ...

local W = {
  interval = 1.0,
  snapshots = {},
  timer = nil
}

local function folder_snapshot(path)
  if not app.fs.isDirectory(path) then return nil end

  local ok, snapshot = pcall(function()
    local names = app.fs.listFiles(path)
    table.sort(names)

    local parts = {}
    for _, name in ipairs(names) do
      local child = app.fs.joinPath(path, name)
      local kind = app.fs.isDirectory(child) and "d" or "f"
      local size = kind == "f" and app.fs.fileSize(child) or 0
      table.insert(parts, #name .. ":" .. name .. ":" .. kind .. ":" .. size)
    end
    return table.concat(parts, "|")
  end)

  if not ok then return nil end
  return snapshot
end

local function watched_folders()
  local paths = {}
  if core.has(core.root_path) then paths[core.root_path] = true end

  for path in pairs(core.file_cache) do
    paths[path] = true
  end

  for path, expanded in pairs(core.expanded_set()) do
    if expanded then paths[path] = true end
  end

  return paths
end

function W:reset()
  self.snapshots = {}
end

function W:check()
  if core.dialog == nil then return end

  local watched = watched_folders()
  local changed = {}

  for path in pairs(watched) do
    local current = folder_snapshot(path)
    local previous = self.snapshots[path]

    if previous ~= nil and previous ~= current then
      table.insert(changed, path)
    end
    self.snapshots[path] = current
  end

  for path in pairs(self.snapshots) do
    if not watched[path] then self.snapshots[path] = nil end
  end

  if #changed > 0 then core.invalidate_folders(changed) end
end

function W:start()
  if self.timer == nil then
    self.timer = Timer{
      interval = self.interval,
      ontick = function() self:check() end
    }
  end

  self:reset()
  self:check()
  self.timer:start()
end

function W:stop()
  if self.timer ~= nil and self.timer.isRunning then self.timer:stop() end
end

return W
