-- Small in-memory filesystem used by the behavioral tests.

local F = {
  entries = {},
  fail_writes = {},
  executed_commands = {}
}

local function normalize(path)
  local clean = (path or ""):gsub("\\", "/"):gsub("/+", "/")
  if #clean > 1 then clean = clean:gsub("/$", "") end
  return clean
end

local function parent_path(path)
  local clean = normalize(path)
  local parent = clean:match("^(.*)/[^/]+$")
  if parent == "" then return "/" end
  return parent or clean
end

local function file_name(path)
  return normalize(path):match("([^/]+)$") or normalize(path)
end

local function join_path(...)
  local parts = { ... }
  local path = table.concat(parts, "/")
  return normalize(path)
end

local function is_child(path, parent)
  local prefix = normalize(parent) .. "/"
  return normalize(path):sub(1, #prefix) == prefix
end

function F.reset()
  F.entries = {
    ["/"] = { kind = "directory" }
  }
  F.fail_writes = {}
  F.executed_commands = {}
end

function F.add_directory(path)
  local clean = normalize(path)
  if F.entries[clean] ~= nil then return false end
  if F.entries[parent_path(clean)] == nil then return false end
  F.entries[clean] = { kind = "directory" }
  return true
end

function F.add_file(path, content)
  local clean = normalize(path)
  if F.entries[parent_path(clean)] == nil then return false end
  F.entries[clean] = { kind = "file", content = content or "" }
  return true
end

function F.read_file(path)
  local entry = F.entries[normalize(path)]
  if entry == nil or entry.kind ~= "file" then return nil end
  return entry.content
end

local fake_fs = {
  pathSeparator = "/",
  userConfigPath = "/config",
  userDocsPath = "/documents",
  tempPath = "/temp"
}

function fake_fs.normalizePath(path)
  return normalize(path)
end

function fake_fs.joinPath(...)
  return join_path(...)
end

function fake_fs.filePath(path)
  return parent_path(path)
end

function fake_fs.fileName(path)
  return file_name(path)
end

function fake_fs.fileExtension(path)
  return file_name(path):match("%.([^%.]+)$") or ""
end

function fake_fs.isFile(path)
  local entry = F.entries[normalize(path)]
  return entry ~= nil and entry.kind == "file"
end

function fake_fs.isDirectory(path)
  local entry = F.entries[normalize(path)]
  return entry ~= nil and entry.kind == "directory"
end

function fake_fs.fileSize(path)
  local content = F.read_file(path)
  return content and #content or 0
end

function fake_fs.listFiles(path)
  local clean = normalize(path)
  local names = {}
  for child in pairs(F.entries) do
    if parent_path(child) == clean and child ~= clean then
      table.insert(names, file_name(child))
    end
  end
  table.sort(names)
  return names
end

function fake_fs.makeDirectory(path)
  return F.add_directory(path)
end

function fake_fs.makeAllDirectories(path)
  local current = ""
  for part in normalize(path):gmatch("[^/]+") do
    current = current .. "/" .. part
    if F.entries[current] == nil then F.add_directory(current) end
  end
  return true
end

function fake_fs.removeDirectory(path)
  local clean = normalize(path)
  for child in pairs(F.entries) do
    if is_child(child, clean) then return false end
  end
  F.entries[clean] = nil
  return true
end

local fake_os = {
  windows = true,
  macos = false,
  linux = false
}

function fake_os.rename(source, target)
  local clean_source = normalize(source)
  local clean_target = normalize(target)
  local entry = F.entries[clean_source]
  if entry == nil or F.entries[clean_target] ~= nil then return nil, "rename failed" end

  local moved = {}
  for path, value in pairs(F.entries) do
    if path == clean_source or is_child(path, clean_source) then
      moved[path] = value
    end
  end

  for path in pairs(moved) do F.entries[path] = nil end
  for path, value in pairs(moved) do
    local suffix = path:sub(#clean_source + 1)
    F.entries[clean_target .. suffix] = value
  end
  return true
end

function fake_os.remove(path)
  local clean = normalize(path)
  if fake_fs.isFile(clean) then
    F.entries[clean] = nil
    return true
  end
  if fake_fs.isDirectory(clean) then
    for child in pairs(F.entries) do
      if is_child(child, clean) then return nil, "remove failed" end
    end
    F.entries[clean] = nil
    return true
  end
  return nil, "remove failed"
end

function fake_os.execute(command)
  table.insert(F.executed_commands, command)
  return true
end

local fake_io = {}

function fake_io.open(path, mode)
  local clean = normalize(path)

  if mode == "rb" then
    local content = F.read_file(clean)
    if content == nil then return nil, "open failed" end
    local position = 1
    return {
      read = function(_, amount)
        if position > #content then return nil end
        if amount == "*a" then
          local rest = content:sub(position)
          position = #content + 1
          return rest
        end
        local chunk = content:sub(position, position + amount - 1)
        position = position + #chunk
        return chunk
      end,
      close = function() return true end
    }
  end

  if mode == "wb" then
    local buffer = ""
    return {
      write = function(_, data)
        if F.fail_writes[clean] then return nil, "write failed" end
        buffer = buffer .. data
        return true
      end,
      close = function()
        if F.fail_writes[clean] then return nil, "close failed" end
        F.add_file(clean, buffer)
        return true
      end
    }
  end

  return nil, "unsupported mode"
end

function F.environment()
  local app = {
    fs = fake_fs,
    os = fake_os,
    clipboard = {},
    alert = function(message) error(message) end
  }

  local environment = {
    app = app,
    os = fake_os,
    io = fake_io
  }
  setmetatable(environment, { __index = _G })
  return environment
end

F.reset()
return F
