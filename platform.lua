-- platform.lua
-- Cross-platform clipboard and file-manager integration.

local P = {}

local function posix_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function windows_quote(value)
  return '"' .. value:gsub('"', '""') .. '"'
end

local function command_succeeded(command)
  local ok, reason, code = os.execute(command)
  if ok == true or ok == 0 then return true end
  return false, reason or code or "command failed"
end

function P.copy_path(path)
  local ok, err = pcall(function()
    app.clipboard.text = path
  end)
  if not ok then return false, err end
  return true
end

function P.reveal(path)
  if app.os.windows then
    if app.fs.isDirectory(path) then
      return command_succeeded('start "" explorer.exe ' .. windows_quote(path))
    end
    return command_succeeded('start "" explorer.exe /select,' .. windows_quote(path))
  end

  if app.os.macos then
    if app.fs.isDirectory(path) then
      return command_succeeded("open " .. posix_quote(path))
    end
    return command_succeeded("open -R " .. posix_quote(path))
  end

  if app.os.linux then
    local folder = app.fs.isDirectory(path) and path or app.fs.filePath(path)
    return command_succeeded("xdg-open " .. posix_quote(folder) .. " >/dev/null 2>&1 &")
  end

  return false, "unsupported operating system"
end

function P.remove_empty_directory(path)
  if not app.os.windows then return false, "unsupported operating system" end

  local quoted_path = windows_quote(path)
  local command = "attrib -R " .. quoted_path .. " >nul 2>&1 & rmdir " .. quoted_path
  return command_succeeded(command)
end

return P
