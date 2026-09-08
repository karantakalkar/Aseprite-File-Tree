-- Selection, batch operations, search, watcher, and platform behavior.
local repo_path = ...
local fake = assert(loadfile(app.fs.joinPath(repo_path, "tests", "fake_filesystem.lua")))()
local env = fake.environment()
local core = assert(loadfile(app.fs.joinPath(repo_path, "browser_core.lua"), "t", env))()
local watcher = assert(loadfile(app.fs.joinPath(repo_path, "filesystem_watcher.lua"), "t", env))(core)
local platform = assert(loadfile(app.fs.joinPath(repo_path, "platform.lua"), "t", env))()
local real_refresh = core.refresh
local function expect(value, message) assert(value, message) end
local function row(path) return { path = path, name = env.app.fs.fileName(path), is_folder = env.app.fs.isDirectory(path) } end
local function folder(path) expect(fake.add_directory(path), "create folder " .. path) end
local function file(path, content) expect(fake.add_file(path, content or "pixels"), "create file " .. path) end
local function reset()
  fake.reset()
  folder("/workspace")
  core.plugin = { preferences = { expanded = {} } }
  core.platform = platform
  core.root_path = "/workspace"
  core.selection = {}
  core.selected = nil
  core.selection_anchor = nil
  core.clipboard_items = {}
  core.file_cache = {}
  core.search_index = {}
  core.search_index_root = nil
  core.search_job = nil
  core.search_query = nil
  core.schedule_search = nil
  core.preview_mode = "off"
  core.preview_path = nil
  core.filter_text = ""
  core.filter_mode = "All"
  core.color_tags = {}
  core.favorites = {}
  core.history = {}
  core.pinned_root = ""
  core.ref_viewer = nil
  core.save_prefs = function() end
  core.save_browser_settings = function() end
  core.refresh = function() end
  core.dialog = { modify = function() end, repaint = function() end }
  env.app.os.windows, env.app.os.macos, env.app.os.linux = true, false, false
  watcher:reset()
end

local function select_paths(...)
  core.selection = {}
  for _, path in ipairs({...}) do core.selection[path] = true; core.selected = path end
end

reset()
file("/workspace/a.png"); file("/workspace/b.png"); file("/workspace/c.png")
core.visible_rows = { row("/workspace/a.png"), { is_divider = true }, row("/workspace/b.png"), row("/workspace/c.png") }
core.select_row(core.visible_rows[1], false, false)
core.select_row(core.visible_rows[4], false, true)
expect(#core.operation_rows(core.visible_rows[1]) == 3, "Shift range omitted files or selected divider")
core.select_row(core.visible_rows[3], true, false)
expect(not core.is_selected("/workspace/b.png"), "Ctrl click did not deselect")
core.select_row(core.visible_rows[3], true, false)
expect(core.is_selected("/workspace/b.png"), "Ctrl click did not add")
core.open_context_menu(core.visible_rows[1], 0, 0)
expect(#core.operation_rows(core.visible_rows[1]) == 3, "context menu collapsed group")
core.run_context_action({ action = "color_tag", color = "blue" })
expect(core.color_tags["/workspace/a.png"] == "blue" and core.color_tags["/workspace/c.png"] == "blue", "color tag omitted selected files")
core.context_menu = { row = core.visible_rows[1] }
core.run_context_action({ action = "copy_path" })
expect(env.app.clipboard.text:find("/workspace/b.png", 1, true), "copy paths omitted selection")

reset()
folder("/workspace/source"); folder("/workspace/target")
file("/workspace/source/a.png"); file("/workspace/b.png")
select_paths("/workspace/source", "/workspace/source/a.png", "/workspace/b.png")
local selected_rows = core.operation_rows(row("/workspace/source"))
expect(#selected_rows == 2, "parent/child selection duplicated transfer")
core.set_clipboard(row("/workspace/source"), "copy")
expect(core.paste_into("/workspace/target"), "batch copy failed")
expect(fake.read_file("/workspace/target/source/a.png") and fake.read_file("/workspace/target/b.png"), "batch copy omitted items")
expect(fake.read_file("/workspace/source/a.png"), "copy removed source")
select_paths("/workspace/source", "/workspace/source/a.png", "/workspace/b.png")
expect(not core.can_drop_items(core.operation_rows(row("/workspace/source")), "/workspace/source"), "batch accepted a recursive destination")
folder("/workspace/moved")
core.set_clipboard(row("/workspace/source"), "cut")
expect(core.paste_into("/workspace/moved"), "batch cut failed")
expect(not env.app.fs.isDirectory("/workspace/source") and not fake.read_file("/workspace/b.png"), "cut retained source")
expect(fake.read_file("/workspace/moved/source/a.png") and fake.read_file("/workspace/moved/b.png"), "cut omitted destination")
expect(#core.clipboard_items == 0, "cut clipboard not cleared")

reset()
folder("/workspace/target")
file("/workspace/a.png"); file("/workspace/b.png"); file("/workspace/target/b.png", "old")
select_paths("/workspace/a.png", "/workspace/b.png")
core.set_clipboard(row("/workspace/a.png"), "cut")
core.ask_paste_conflict = function() return nil end
expect(not core.paste_into("/workspace/target"), "cancelled batch reported success")
expect(fake.read_file("/workspace/target/a.png") and not fake.read_file("/workspace/a.png"), "completed cut was lost")
expect(#core.clipboard_items == 1 and core.clipboard_items[1].path == "/workspace/b.png", "cancel lost remaining clipboard items")
expect(fake.read_file("/workspace/b.png") and fake.read_file("/workspace/target/b.png") == "old", "cancel altered conflicting files")

reset()
folder("/workspace/target")
file("/workspace/a.png", "a"); file("/workspace/b.png", "b")
file("/workspace/target/a.png", "old"); file("/workspace/target/b.png", "old")
select_paths("/workspace/a.png", "/workspace/b.png")
local prompts = 0
core.ask_paste_conflict = function() prompts = prompts + 1; return "replace", true end
core.set_clipboard(row("/workspace/a.png"), "copy")
expect(core.paste_into("/workspace/target"), "replace all failed")
expect(prompts == 1 and fake.read_file("/workspace/target/b.png") == "b", "apply-to-all did not span batch")

reset()
folder("/workspace/folder"); file("/workspace/folder/child.png"); file("/workspace/other.png")
select_paths("/workspace/folder", "/workspace/folder/child.png", "/workspace/other.png")
local renamed = {}
core.show_rename_dialog = function(item)
  table.insert(renamed, item.path)
  return core.rename_path(item, "renamed-" .. env.app.fs.fileName(item.path))
end
core.context_menu = { row = row("/workspace/folder") }
core.run_context_action({ action = "rename" })
expect(fake.read_file("/workspace/renamed-folder/renamed-child.png"), "batch rename lost child path")
expect(fake.read_file("/workspace/renamed-other.png") and #renamed == 3, "batch rename omitted selected items")
expect(core.selection["/workspace/renamed-folder/renamed-child.png"], "rename did not update selection")
select_paths("/workspace/renamed-folder", "/workspace/renamed-other.png")
core.context_menu = { row = row("/workspace/renamed-folder") }
core.run_context_action({ action = "add_favorites" })
expect(core.is_favorite("/workspace/renamed-folder"), "batch favorites omitted folder")
expect(not core.is_favorite("/workspace/renamed-other.png"), "batch favorites added file")

reset()
folder("/workspace/target")
file("/workspace/a.png"); file("/workspace/b.png")
select_paths("/workspace/a.png", "/workspace/b.png")
expect(core.drop_path_into("/workspace/a.png", "/workspace/target", true), "batch copy drop failed")
expect(fake.read_file("/workspace/target/a.png") and fake.read_file("/workspace/target/b.png"), "drop omitted selected file")
folder("/workspace/moved")
expect(core.drop_path_into("/workspace/target/a.png", "/workspace/moved", false), "batch move drop failed")
expect(fake.read_file("/workspace/moved/b.png") and not fake.read_file("/workspace/target/b.png"), "move drop omitted selection")
local deleted = core.operation_rows(row("/workspace/moved/a.png"))
for _, item in ipairs(deleted) do expect(core.delete_path(item), "batch delete failed") end
expect(not fake.read_file("/workspace/moved/a.png") and not fake.read_file("/workspace/moved/b.png"), "delete omitted selection")
expect(next(core.selection) == nil, "delete retained selected paths")

reset()
folder("/workspace/sub"); folder("/workspace/sub/deep"); file("/workspace/sub/deep/hero.png")
core.refresh = real_refresh
env.app.activeSprite = { filename = "/workspace/sub/deep/hero.png" }
core.filter_mode = ".jpg"
core.reveal_active_sprite()
expect(core.root_path == "/workspace", "reveal changed containing root")
expect(core.is_selected(env.app.activeSprite.filename), "reveal did not select sprite")
expect(core.expanded_set()["/workspace/sub/deep"] and core.expanded_set()["/workspace/sub"], "reveal did not expand ancestors")
expect(core.filter_mode == "All", "reveal left hiding filter")
folder("/other"); file("/other/other.png")
env.app.activeSprite.filename = "/other/other.png"
core.reveal_active_sprite()
expect(core.root_path == "/other" and core.is_selected("/other/other.png"), "outside-root reveal failed")

reset()
file("/workspace/a.png"); file("/workspace/b.png"); file("/workspace/c.png"); file("/workspace/no.txt")
folder("/workspace/folder")
local loaded
core.ref_viewer = { path = "/workspace/b.png", load = function(path) loaded = path; core.ref_viewer.path = path end }
expect(core.switch_reference(1) and loaded == "/workspace/c.png", "next reference failed")
expect(not core.switch_reference(1), "reference navigation unexpectedly wrapped")
expect(core.switch_reference(-1) and loaded == "/workspace/b.png", "previous reference failed")

reset()
folder("/workspace/nested"); folder("/workspace/nested/deep"); folder("/workspace/empty")
file("/workspace/nested/deep/hero.png"); file("/workspace/nested/deep/hero.jpg"); file("/workspace/hero.png")
core.filter_mode = ".png"
core.rebuild_rows()
while core.search_job do core.rebuild_rows() end
expect(core.search_matches["/workspace/nested/deep/hero.png"], "type-only search missed nested file")
expect(not core.search_matches["/workspace/nested/deep/hero.jpg"], "type search included wrong extension")
expect(core.search_ancestors["/workspace/nested"], "search omitted ancestor")
expect(not core.search_matches["/workspace/empty"], "type-only search retained empty folder")
core.filter_text = "HERO"
core.rebuild_rows()
expect(core.search_matches["/workspace/hero.png"], "case-insensitive search failed")
core.filter_text = "["
core.rebuild_rows()
expect(next(core.search_matches) == nil, "search interpreted Lua pattern syntax")

reset()
for index = 1, 30 do folder("/workspace/f" .. index); file("/workspace/f" .. index .. "/sprite.png") end
core.filter_text = "sprite"
core.rebuild_rows()
expect(core.search_job ~= nil, "large search did not yield")
local passes = 0
while core.search_job do core.rebuild_rows(); passes = passes + 1; expect(passes < 20, "search did not finish") end
expect(core.search_matches["/workspace/f30/sprite.png"], "incremental search missed final folder")

reset()
file("/workspace/a.png", "old")
core.preview_mode = "preview"
core.preview_path = "/workspace/a.png"
local reloads = 0
core.load_preview = function() reloads = reloads + 1 end
watcher:check()
file("/workspace/a.png", "new")
watcher:check()
expect(reloads == 1, "watcher missed same-size edit")
watcher:check()
expect(reloads == 1, "unchanged preview reloaded")
env.os.remove("/workspace/a.png")
watcher:check()
expect(core.preview_path == nil, "deleted preview stayed visible")

reset()
folder("/workspace/gone")
core.file_cache["/workspace/gone"] = {}
local invalidations = 0
core.invalidate_folders = function() invalidations = invalidations + 1 end
watcher:check()
env.os.remove("/workspace/gone")
watcher:check()
folder("/workspace/gone")
watcher:check()
expect(invalidations == 2, "watcher missed delete/recreate transition")
core.expanded_set()["/unrelated"] = true
expect(watcher.snapshots["/unrelated"] == nil, "watcher included another project")

reset()
env.app.os.windows, env.app.os.macos = false, true
file("/workspace/it's.png")
expect(platform.reveal("/workspace/it's.png"), "mac reveal failed")
expect(fake.executed_commands[1] == "open -R -- '/workspace/it'\\''s.png'", "mac filename quoting failed")
env.app.os.macos, env.app.os.linux = false, true
expect(platform.reveal("/workspace/it's.png"), "linux reveal failed")
expect(fake.executed_commands[2] == "xdg-open '/workspace' >/dev/null 2>&1 &", "Linux file reveal did not open parent")
local command = platform.windows_command("Write-Output 'café 💙 %TEMP% & $x'")
expect(not command:find("%%TEMP%%") and command:match("EncodedCommand [%w+/=]+$"), "Windows command exposed shell syntax")

-- Run the Windows encoder against PowerShell, including non-BMP Unicode and metacharacters.
if app.os.windows and app.params.result then
  local live_platform = assert(loadfile(app.fs.joinPath(repo_path, "platform.lua")))()
  local temporary = app.params.result .. ".unicode"
  local expected = "café 💙 %TEMP% & $x"
  local script = "[IO.File]::WriteAllText('" .. temporary:gsub("'", "''") .. "', '" .. expected .. "', [Text.UTF8Encoding]::new($false))"
  local ok = os.execute(live_platform.windows_command(script))
  local output = assert(io.open(temporary, "rb"))
  local actual = output:read("*a")
  output:close()
  expect(live_platform.remove(temporary), "native file removal failed")
  expect(ok == true or ok == 0, "native PowerShell command failed")
  expect(actual == expected, "native Windows command changed Unicode or expanded shell syntax")
  local source = app.params.result .. " %TEMP% & café 💙.png"
  local target = app.params.result .. " renamed.png"
  local source_file = assert(io.open(source, "wb"))
  source_file:write("native pixels")
  source_file:close()
  expect(live_platform.rename(source, target), "native Unicode rename failed")
  expect(not app.fs.isFile(source) and app.fs.isFile(target), "native rename did not move file")
  expect(live_platform.remove(target), "native renamed file removal failed")
  local live_core = assert(loadfile(app.fs.joinPath(repo_path, "browser_core.lua")))()
  live_core.platform = live_platform
  live_core.plugin = { preferences = { expanded = {} } }
  live_core.save_browser_settings = function() end
  live_core.refresh = function() end
  local root = app.fs.normalizePath(app.params.result .. ".files")
  expect(not app.fs.isDirectory(root), "native fixture already exists")
  expect(app.fs.makeDirectory(root), "native fixture creation failed")
  local destination = app.fs.joinPath(root, "destination")
  expect(app.fs.makeDirectory(destination), "native destination creation failed")
  local rows = {}
  for _, name in ipairs({ "one.png", "two %TEMP% & café.png" }) do
    local path = app.fs.joinPath(root, name)
    local output_file = assert(io.open(path, "wb"))
    output_file:write(name)
    output_file:close()
    table.insert(rows, { path = path, is_folder = false })
  end
  expect(live_core.transfer_items(rows, destination, true), "native batch copy failed")
  for _, item in ipairs(rows) do
    expect(app.fs.isFile(item.path), "native copy removed a source")
    expect(app.fs.isFile(app.fs.joinPath(destination, app.fs.fileName(item.path))), "native copy omitted a destination")
  end
  -- This exact newly-created fixture is the sole recursive deletion target.
  expect(live_core.delete_folder(root), "native recursive fixture deletion failed")
  expect(not app.fs.isDirectory(root), "native fixture remained after deletion")
  print("Native Windows file operations passed on Aseprite " .. tostring(app.version))
end

print("Browser batch, search, watcher, and platform tests passed.")
