-- platform.lua
-- Cross-platform clipboard and file-manager integration.

local P = {}

local function posix_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function powershell_quote(value)
  return "'" .. value:gsub("'", "''") .. "'"
end

local function base64(value)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  for index = 1, #value, 3 do
    local a, b, c = value:byte(index, index + 2)
    local number = a * 65536 + (b or 0) * 256 + (c or 0)
    for shift = 18, 0, -6 do
      local digit = math.floor(number / 2 ^ shift) % 64 + 1
      table.insert(result, alphabet:sub(digit, digit))
    end
    if c == nil then result[#result] = "=" end
    if b == nil then result[#result - 1] = "=" end
  end
  return table.concat(result)
end

function P.windows_command(script)
  -- EncodedCommand bypasses cmd.exe expansion of %, &, and other filename characters.
  local bytes = {}
  local function append_unit(unit)
    table.insert(bytes, string.char(unit % 256, math.floor(unit / 256)))
  end
  for _, code in utf8.codes(script) do
    if code < 65536 then append_unit(code)
    else
      code = code - 65536
      append_unit(55296 + math.floor(code / 1024))
      append_unit(56320 + code % 1024)
    end
  end
  return "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " .. base64(table.concat(bytes))
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

function P.remove(path)
  local called, ok, err = pcall(os.remove, path)
  if called then return ok, err end
  if not tostring(ok):find("unsupported function", 1, true) then return false, ok end
  -- Older Aseprite builds disable os.remove. Keep directory removal non-recursive.
  if app.fs.isDirectory(path) then return app.fs.removeDirectory(path) end
  if app.os.windows then
    return command_succeeded(P.windows_command("$ErrorActionPreference = 'Stop'; [IO.File]::Delete(" .. powershell_quote(path) .. ")"))
  end
  return command_succeeded("rm -f -- " .. posix_quote(path))
end

function P.rename(source, target)
  local called, ok, err = pcall(os.rename, source, target)
  if called then return ok, err end
  if not tostring(ok):find("unsupported function", 1, true) then return false, ok end
  if app.os.windows then
    local kind = app.fs.isDirectory(source) and "Directory" or "File"
    local script = "$ErrorActionPreference = 'Stop'; [IO." .. kind .. "]::Move("
      .. powershell_quote(source) .. ", " .. powershell_quote(target) .. ")"
    return command_succeeded(P.windows_command(script))
  end
  local moved, move_error = command_succeeded("mv -n -- " .. posix_quote(source) .. " " .. posix_quote(target))
  if not moved then return false, move_error end
  if app.fs.isFile(source) or app.fs.isDirectory(source) then return false, "destination already exists" end
  return true
end

function P.reveal(path)
  if app.os.windows then
    local argument = '"' .. path .. '"'
    if not app.fs.isDirectory(path) then argument = '/select,' .. argument end
    return command_succeeded(P.windows_command("Start-Process explorer.exe -ArgumentList " .. powershell_quote(argument)))
  end

  if app.os.macos then
    if app.fs.isDirectory(path) then
      return command_succeeded("open -- " .. posix_quote(path))
    end
    return command_succeeded("open -R -- " .. posix_quote(path))
  end

  if app.os.linux then
    local folder = app.fs.isDirectory(path) and path or app.fs.filePath(path)
    return command_succeeded("xdg-open " .. posix_quote(folder) .. " >/dev/null 2>&1 &")
  end

  return false, "unsupported operating system"
end

function P.remove_empty_directory(path)
  if not app.os.windows then return false, "unsupported operating system" end

  local script = "$ErrorActionPreference = 'Stop'; $item = Get-Item -LiteralPath " .. powershell_quote(path)
    .. "; $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)"
    .. "; Remove-Item -LiteralPath " .. powershell_quote(path) .. " -Force"
  return command_succeeded(P.windows_command(script))
end

return P
