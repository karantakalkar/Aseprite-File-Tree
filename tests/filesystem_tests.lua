-- Behavioral tests for filesystem operations. Run through run-tests.ps1.

local script_path = debug.getinfo(1, "S").source:sub(2)
local tests_path = app.fs.filePath(script_path)
local repo_path = app.fs.filePath(tests_path)
local fake_path = app.fs.joinPath(tests_path, "fake_filesystem.lua")
local core_path = app.fs.joinPath(repo_path, "browser_core.lua")
local platform_path = app.fs.joinPath(repo_path, "platform.lua")
local ref_viewer_path = app.fs.joinPath(repo_path, "ref_viewer.lua")

local fake = assert(loadfile(fake_path))()
local environment = fake.environment()
local core = assert(loadfile(core_path, "t", environment))()
local platform = assert(loadfile(platform_path, "t", environment))()
environment.ColorMode = { RGB = 1, GRAY = 2, INDEXED = 3 }
environment.Color = function(value)
  return {
    red = value.r or value.gray or 0,
    green = value.g or value.gray or 0,
    blue = value.b or value.gray or 0,
    alpha = value.a or value.alpha or 255,
    index = value.index
  }
end
environment.app.pixelColor = {
  rgbaR = function() return 12 end,
  rgbaG = function() return 34 end,
  rgbaB = function() return 56 end,
  rgbaA = function() return 78 end,
  grayaV = function() return 40 end,
  grayaA = function() return 90 end
}
environment.Image = function(source, rect)
  if rect == nil then
    return {
      source = source.fromFile,
      width = 32,
      height = 32
    }
  end
  return {
    source = source,
    source_rect = rect,
    width = rect.width,
    height = rect.height
  }
end
local ref_viewer = assert(loadfile(ref_viewer_path, "t", environment))()

core.plugin = { preferences = { expanded = {} } }
core.platform = platform
core.save_browser_settings = function() end
core.refresh = function() end

local function fail(message)
  error("Filesystem test failed: " .. message)
end

local function expect(value, message)
  if not value then fail(message) end
end

local function make_folder(path)
  local ok, err = core.make_directory(path)
  if not ok then fail(err) end
end

local function reset()
  fake.reset()
  fake.add_directory("/workspace")
  core.plugin.preferences.expanded = {}
  core.color_tags = {}
  core.file_cache = {}
  core.all_folders_expanded = false
end

local function test_directory_creation()
  reset()
  local ok, err = core.make_directory("/workspace/created")
  expect(ok, err or "directory creation returned false")
  expect(environment.app.fs.isDirectory("/workspace/created"), "created directory is missing")

  ok = core.make_directory("/workspace/created")
  expect(not ok, "duplicate directory creation unexpectedly succeeded")
end

local function test_chunked_file_copy()
  reset()
  local content = string.rep("0123456789abcdef", 10000)
  fake.add_file("/workspace/source.bin", content)

  local ok, err = core.copy_file("/workspace/source.bin", "/workspace/target.bin")
  expect(ok, err or "file copy failed")
  expect(fake.read_file("/workspace/target.bin") == content, "copied bytes differ")
end

local function test_failed_write_cleanup()
  reset()
  fake.add_file("/workspace/source.bin", "content")
  fake.fail_writes["/workspace/target.bin"] = true

  local ok = core.copy_file("/workspace/source.bin", "/workspace/target.bin")
  expect(not ok, "failed write unexpectedly succeeded")
  expect(not environment.app.fs.isFile("/workspace/target.bin"), "failed write left a file")
end

local function test_recursive_copy_guard()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/source/child")

  local ok, err = core.copy_path_to_folder(
    "/workspace/source",
    "/workspace/source/child"
  )
  expect(not ok, "folder copied into its own descendant")
  expect(err == "cannot copy a folder inside itself", "unexpected recursive-copy error")
end

local function test_transactional_folder_copy()
  reset()
  make_folder("/workspace/source")
  fake.add_file("/workspace/source/item.txt", "content")

  local ok, err = core.copy_folder_transaction(
    "/workspace/source",
    "/workspace/copied"
  )
  expect(ok, err or "transactional folder copy failed")
  expect(fake.read_file("/workspace/copied/item.txt") == "content", "folder content is missing")
end

local function test_directory_removal_fallback()
  reset()
  make_folder("/workspace/folder")

  local remove_directory = environment.app.fs.removeDirectory
  environment.app.fs.removeDirectory = function() return false end
  local ok, err = core.delete_folder("/workspace/folder")
  environment.app.fs.removeDirectory = remove_directory

  expect(ok, err or "empty-directory fallback failed")
  expect(not environment.app.fs.isDirectory("/workspace/folder"), "fallback left the folder behind")
end

local function test_keep_both()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/target")
  fake.add_file("/workspace/source/sample.txt", "new")
  fake.add_file("/workspace/target/sample.txt", "old")

  local ok, result = core.copy_path_to_folder(
    "/workspace/source/sample.txt",
    "/workspace/target",
    "keep_both",
    {}
  )
  expect(ok, result or "keep-both copy failed")
  expect(fake.read_file("/workspace/target/sample.txt") == "old", "existing file changed")
  expect(fake.read_file(result) == "new", "keep-both content is wrong")
end

local function test_concise_copy_names()
  reset()
  expect(
    core.copy_name_path("/workspace/UI", true) == "/workspace/UI copy",
    "folder copy name is not concise"
  )
  make_folder("/workspace/UI copy")
  expect(
    core.copy_name_path("/workspace/UI", true) == "/workspace/UI copy 2",
    "folder copy collision was not numbered"
  )
  expect(
    core.copy_name_path("/workspace/sprite.png", false) == "/workspace/sprite copy.png",
    "file copy name misplaced the extension"
  )
end

local function test_replace()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/target")
  fake.add_file("/workspace/source/sample.txt", "new")
  fake.add_file("/workspace/target/sample.txt", "old")

  local ok, err = core.copy_path_to_folder(
    "/workspace/source/sample.txt",
    "/workspace/target",
    "replace",
    {}
  )
  expect(ok, err or "replace failed")
  expect(fake.read_file("/workspace/target/sample.txt") == "new", "replace kept old content")
  expect(fake.read_file("/workspace/source/sample.txt") == "new", "replace removed source")
end

local function test_folder_merge()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/target")
  make_folder("/workspace/source/Pack")
  make_folder("/workspace/target/Pack")
  fake.add_file("/workspace/source/Pack/new.txt", "new")
  fake.add_file("/workspace/target/Pack/old.txt", "old")

  local ok, err = core.copy_path_to_folder(
    "/workspace/source/Pack",
    "/workspace/target",
    "merge",
    {}
  )
  expect(ok, err or "folder merge failed")
  expect(fake.read_file("/workspace/target/Pack/new.txt") == "new", "merge missed source")
  expect(fake.read_file("/workspace/target/Pack/old.txt") == "old", "merge lost target")
end

local function test_cut_fallback()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/target")
  fake.add_file("/workspace/source/item.txt", "content")

  local real_rename = environment.os.rename
  local first_call = true
  environment.os.rename = function(source, target)
    if first_call then
      first_call = false
      return nil, "cross-device move"
    end
    return real_rename(source, target)
  end

  local ok, result = core.cut_path_to_folder(
    "/workspace/source/item.txt",
    "/workspace/target",
    nil,
    {}
  )
  environment.os.rename = real_rename

  expect(ok, result or "cut fallback failed")
  expect(fake.read_file("/workspace/target/item.txt") == "content", "cut target is wrong")
  expect(not environment.app.fs.isFile("/workspace/source/item.txt"), "cut source remains")
end

local function test_drop_guards()
  reset()
  make_folder("/workspace/source")
  make_folder("/workspace/source/child")
  make_folder("/workspace/other")

  expect(not core.can_drop_path("/workspace/source", "/workspace"), "same-parent drop allowed")
  expect(not core.can_drop_path("/workspace/source", "/workspace/source/child"), "descendant drop allowed")
  expect(core.can_drop_path("/workspace/source", "/workspace/other"), "valid drop blocked")
end

local function test_case_rename()
  reset()
  fake.add_file("/workspace/sprite.png", "sprite")

  local ok = core.rename_path(
    { path = "/workspace/sprite.png", is_folder = false },
    "SPRITE.PNG"
  )
  expect(ok, "case rename failed")
  expect(fake.read_file("/workspace/SPRITE.PNG") == "sprite", "renamed file is missing")
end

local function test_rename_dialog_name()
  expect(
    core.rename_dialog_name({ path = "/workspace/sprite.png", is_folder = false }) == "sprite",
    "file rename autofill included the extension"
  )
  expect(
    core.rename_dialog_name({ path = "/workspace/archive.tar.gz", is_folder = false }) == "archive.tar",
    "file rename autofill removed more than the final extension"
  )
  expect(
    core.rename_dialog_name({ path = "/workspace/folder", is_folder = true }) == "folder",
    "folder rename autofill changed the folder name"
  )
end

local function test_color_tags()
  reset()
  make_folder("/workspace/folder")
  make_folder("/workspace/folder/child")

  core.set_color_tag("/workspace/folder", "red")
  expect(core.color_tag_for_path("/workspace/folder/child") == "red", "folder tag did not cascade")

  core.set_color_tag("/workspace/folder/child", "blue")
  expect(core.color_tag_for_path("/workspace/folder/child") == "blue", "child tag did not override")

  core.update_renamed_paths("/workspace/folder", "/workspace/renamed", true)
  expect(core.color_tag_for_path("/workspace/renamed") == "red", "rename lost folder tag")
  expect(core.color_tag_for_path("/workspace/renamed/child") == "blue", "rename lost child tag")

  core.clear_deleted_paths("/workspace/renamed")
  expect(core.color_tag_for_path("/workspace/renamed") == nil, "delete kept folder tag")
  expect(core.color_tag_for_path("/workspace/renamed/child") == nil, "delete kept child tag")
end

local function test_expand_collapse_all()
  reset()
  core.root_path = "/workspace"
  make_folder("/workspace/one")
  make_folder("/workspace/one/two")

  core.toggle_all_folders()
  expect(core.expanded_set()["/workspace/one"], "expand all missed first folder")
  expect(core.expanded_set()["/workspace/one/two"], "expand all missed nested folder")

  core.toggle_all_folders()
  expect(core.expanded_set()["/workspace/one"] == nil, "collapse all kept first folder")
  expect(core.expanded_set()["/workspace/one/two"] == nil, "collapse all kept nested folder")
end

local function test_color_submenu()
  reset()
  fake.add_file("/workspace/item.png", "item")
  core.dialog = { repaint = function() end }

  core.open_context_menu({
    path = "/workspace/item.png",
    name = "item.png",
    is_folder = false
  }, 10, 10)

  local color_menu = nil
  for _, item in ipairs(core.context_menu.items) do
    if item.submenu ~= nil then color_menu = item end
  end

  expect(color_menu ~= nil, "color submenu is missing")
  expect(#color_menu.submenu.items == 5, "color submenu has unexpected options")
  expect(core.run_context_action(color_menu), "color submenu did not open")
  expect(core.context_menu ~= nil, "opening submenu closed the context menu")

  core.run_context_action(color_menu.submenu.items[1])
  expect(core.color_tags["/workspace/item.png"] == "red", "submenu did not assign color")
  core.dialog = nil
end

local function test_drag_state_cleanup()
  reset()
  core.drag_source = "/workspace/item.png"
  core.drag_row = { path = core.drag_source, is_folder = false }
  core.drag_pointer_down = true
  core.drag_started = true
  core.drag_expand_path = "/workspace/folder"

  core.clear_file_drag()
  expect(core.drag_source == nil, "drag source was not cleared")
  expect(core.drag_row == nil, "drag row was not cleared")
  expect(not core.drag_pointer_down, "drag pointer state remained pressed")
  expect(not core.drag_started, "drag remained active")
  expect(core.drag_expand_path == nil, "drag expansion target was not cleared")
end

local function test_windows_reveal_uses_shell_launch()
  reset()
  fake.add_file("/workspace/item.png", "content")

  expect(platform.reveal("/workspace"), "folder reveal failed")
  expect(
    fake.executed_commands[1] == 'start "" explorer.exe "/workspace"',
    "folder reveal did not use an asynchronous Explorer launch"
  )

  expect(platform.reveal("/workspace/item.png"), "file reveal failed")
  expect(
    fake.executed_commands[2] == 'start "" explorer.exe /select,"/workspace/item.png"',
    "file reveal did not use an asynchronous Explorer launch"
  )

  expect(platform.remove_empty_directory("/workspace/empty"), "native directory removal failed")
  expect(
    fake.executed_commands[3] == 'attrib -R "/workspace/empty" >nul 2>&1 & rmdir "/workspace/empty"',
    "native directory removal did not clear read-only before rmdir"
  )
end

local function test_dialog_bounds_capture()
  reset()
  core.dialog = {
    bounds = { x = 40, y = 50, width = 600, height = 700 }
  }

  core.save_prefs()
  expect(core.dialog_bounds.x == 40, "dialog x position was not captured")
  expect(core.dialog_bounds.y == 50, "dialog y position was not captured")
  expect(core.dialog_bounds.width == 600, "dialog width was not captured")
  expect(core.dialog_bounds.height == 700, "dialog height was not captured")
  core.dialog = nil
end

local function test_path_draft_waits_before_navigation()
  reset()
  make_folder("/workspace/folder")
  fake.add_file("/workspace/reference.png", "image")
  core.root_path = "/workspace"
  core.dialog = nil

  core.set_path_draft("\\\\server\\share")
  expect(core.path_draft == "\\\\server\\share", "path draft changed while typing")
  expect(core.root_path == "/workspace", "editing the path navigated immediately")

  core.set_path_draft("/workspace/folder")
  expect(core.open_path_draft(), "debounced navigation did not open an existing folder")
  expect(core.root_path == "/workspace/folder", "debounced navigation opened the wrong folder")

  local entry_text = nil
  core.dialog = {
    bounds = { x = 0, y = 0, width = 400, height = 500 },
    modify = function(_, options)
      if options.id == "root_entry" then entry_text = options.text end
    end
  }
  core.select_path({ path = "/workspace", is_folder = true })
  expect(core.path_draft == "/workspace", "folder selection did not update the path draft")
  expect(entry_text == "/workspace", "folder selection did not update the visible Path field")
  core.dialog = nil

  core.preview_mode = "preview"
  core.set_path_draft("/workspace/reference.png")
  expect(core.open_path_draft(), "pasted image path was rejected")
  expect(core.root_path == "/workspace", "pasted image path did not navigate to its parent folder")
  expect(core.selected == "/workspace/reference.png", "pasted image path was not selected")
  expect(core.path_draft == "/workspace/reference.png", "file navigation did not preserve the file path")
  expect(core.preview_path == "/workspace/reference.png", "pasted image path was not previewed")

  local ref_path = nil
  core.ref_viewer = {
    load = function(path) ref_path = path end,
    reset = function() end
  }
  core.preview_mode = "ref"
  core.set_path_draft("/workspace/reference.png")
  expect(core.open_path_draft(), "reference mode rejected a pasted image path")
  expect(ref_path == "/workspace/reference.png", "reference mode did not load the pasted image path")
end

local function test_preview_mode_cycle_and_migration()
  reset()
  local reset_count = 0
  core.ref_viewer = {
    reset = function() reset_count = reset_count + 1 end,
    load = function() end
  }
  core.dialog = nil
  core.selected = nil
  core.preview_mode = "off"

  core.cycle_preview_mode()
  expect(core.preview_mode == "preview", "preview cycle did not enter normal preview")
  core.cycle_preview_mode()
  expect(core.preview_mode == "ref", "preview cycle did not enter reference mode")
  core.cycle_preview_mode()
  expect(core.preview_mode == "off", "preview cycle did not return to off")
  expect(reset_count == 2, "reference state was not reset on entry and exit")

  core.plugin.preferences = { expanded = {}, preview_enabled = true }
  core.init_root()
  expect(core.preview_mode == "preview", "legacy preview preference was not migrated")

  core.plugin.preferences = { expanded = {}, preview_mode = "ref" }
  core.init_root()
  expect(core.preview_mode == "ref", "saved reference mode was not restored")

  local visibility = {}
  core.dialog = {
    bounds = { x = 0, y = 0, width = 400, height = 500 },
    modify = function(_, options)
      if options.visible ~= nil then visibility[options.id] = options.visible end
    end
  }
  core.update_mode_controls()
  expect(visibility.filter_entry == false, "search remained visible in reference mode")
  expect(visibility.filter_mode == false, "file type remained visible in reference mode")

  core.preview_mode = "off"
  core.update_mode_controls()
  expect(visibility.filter_entry == true, "search did not return in preview-off mode")
  expect(visibility.filter_mode == true, "file type did not return in preview-off mode")
  core.dialog = nil
end

local function set_ref_test_image()
  ref_viewer.reset()
  ref_viewer.image = {
    width = 100,
    height = 50,
    colorMode = environment.ColorMode.RGB,
    getPixel = function(_, x, y)
      ref_viewer.sampled_x = x
      ref_viewer.sampled_y = y
      return 1
    end
  }
  ref_viewer.status = ""
  ref_viewer.fit(220, 190)
end

local function close_enough(a, b)
  return math.abs(a - b) < 0.001
end

local function test_ref_view_navigation()
  set_ref_test_image()
  expect(close_enough(ref_viewer.zoom, 1.68), "fit zoom is incorrect")
  expect(close_enough(ref_viewer.pan_x, 26), "fit horizontal centering is incorrect")
  expect(close_enough(ref_viewer.pan_y, 8), "fit vertical centering is incorrect")

  local before_x, before_y = ref_viewer.screen_to_image(110, 50, false)
  ref_viewer.zoom_at(110, 50, ref_viewer.ZOOM_STEP, 220, 190)
  local after_x, after_y = ref_viewer.screen_to_image(110, 50, false)
  expect(close_enough(before_x, after_x), "cursor-centered zoom moved the sampled x coordinate")
  expect(close_enough(before_y, after_y), "cursor-centered zoom moved the sampled y coordinate")

  ref_viewer.begin_pan(10, 20)
  local old_x = ref_viewer.pan_x
  local old_y = ref_viewer.pan_y
  ref_viewer.update_pan(25, 35)
  expect(close_enough(ref_viewer.pan_x, old_x + 15), "pan did not track horizontal drag")
  expect(close_enough(ref_viewer.pan_y, old_y + 15), "pan did not track vertical drag")
  ref_viewer.end_drag()

  ref_viewer.mousedown(20, 20, false, false, false, 220, 190)
  expect(ref_viewer.drag_mode == nil, "left mouse button started panning")
  ref_viewer.mousedown(20, 20, false, false, true, 220, 190)
  expect(ref_viewer.drag_mode == "pan", "middle mouse button did not start panning")
  ref_viewer.mouseup()
end

local function test_ref_view_reload_preserves_camera()
  expect(ref_viewer.load("/workspace/reference.png"), "reference image did not load")
  ref_viewer.zoom = 3.25
  ref_viewer.pan_x = -47
  ref_viewer.pan_y = 86
  ref_viewer.view_w = 640
  ref_viewer.view_h = 480

  expect(ref_viewer.reload("/workspace/reference.png"), "reference image did not reload")
  expect(close_enough(ref_viewer.zoom, 3.25), "reference reload reset zoom")
  expect(close_enough(ref_viewer.pan_x, -47), "reference reload reset horizontal pan")
  expect(close_enough(ref_viewer.pan_y, 86), "reference reload reset vertical pan")
  expect(ref_viewer.view_w == 640, "reference reload reset viewport width")
  expect(ref_viewer.view_h == 480, "reference reload reset viewport height")
end

local function test_ref_view_crop()
  set_ref_test_image()
  local directions = {
    { 10, 5, 70, 40 },
    { 70, 5, 10, 40 },
    { 10, 40, 70, 5 },
    { 70, 40, 10, 5 }
  }
  local start_x, start_y = nil, nil
  for _, points in ipairs(directions) do
    ref_viewer.begin_crop()
    start_x, start_y = ref_viewer.image_to_screen(points[1], points[2])
    local end_x, end_y = ref_viewer.image_to_screen(points[3], points[4])
    expect(ref_viewer.begin_crop_drag(start_x, start_y), "crop drag did not start inside the image")
    ref_viewer.update_crop_drag(end_x, end_y)
    expect(ref_viewer.crop_draft.x == 10, "crop direction has the wrong x")
    expect(ref_viewer.crop_draft.y == 5, "crop direction has the wrong y")
    expect(ref_viewer.crop_draft.width == 60, "crop direction has the wrong width")
    expect(ref_viewer.crop_draft.height == 35, "crop direction has the wrong height")
  end

  expect(ref_viewer.copy_crop(), "crop was not copied")
  expect(environment.app.clipboard.image.width == 60, "clipboard crop has the wrong width")
  expect(environment.app.clipboard.image.height == 35, "clipboard crop has the wrong height")
  expect(not ref_viewer.crop_mode, "crop mode stayed active after copying")
  expect(ref_viewer.notice:find("Ctrl%+V") ~= nil, "copy confirmation omitted paste guidance")

  ref_viewer.begin_crop()
  start_x, start_y = ref_viewer.image_to_screen(20, 20)
  ref_viewer.begin_crop_drag(start_x, start_y)
  ref_viewer.update_crop_drag(start_x, start_y)
  expect(ref_viewer.crop_draft == nil, "zero-size crop was accepted")
end

local function test_ref_view_color_sampling()
  set_ref_test_image()
  local x, y = ref_viewer.image_to_screen(25, 15)
  ref_viewer.begin_pick("foreground")
  expect(ref_viewer.pick_mode == "foreground", "primary color picker did not activate")
  expect(ref_viewer.sample_at(x, y, "foreground"), "foreground sample failed")
  expect(ref_viewer.pick_mode == nil, "primary color picker stayed active after sampling")
  expect(environment.app.fgColor.red == 12, "foreground sample has the wrong red component")
  expect(environment.app.fgColor.alpha == 78, "foreground sample lost transparency")
  expect(ref_viewer.sampled_x == 25 and ref_viewer.sampled_y == 15, "sample used the wrong source pixel")

  expect(ref_viewer.sample_at(x, y, "background"), "background sample failed")
  expect(environment.app.bgColor.green == 34, "background sample has the wrong green component")
end

test_directory_creation()
test_chunked_file_copy()
test_failed_write_cleanup()
test_recursive_copy_guard()
test_transactional_folder_copy()
test_directory_removal_fallback()
test_keep_both()
test_concise_copy_names()
test_replace()
test_folder_merge()
test_cut_fallback()
test_drop_guards()
test_case_rename()
test_rename_dialog_name()
test_color_tags()
test_expand_collapse_all()
test_color_submenu()
test_drag_state_cleanup()
test_windows_reveal_uses_shell_launch()
test_dialog_bounds_capture()
test_path_draft_waits_before_navigation()
test_preview_mode_cycle_and_migration()
test_ref_view_navigation()
test_ref_view_reload_preserves_camera()
test_ref_view_crop()
test_ref_view_color_sampling()

if app.params and app.params.result then
  local result_file = assert(io.open(app.params.result, "wb"))
  assert(result_file:write("passed"))
  assert(result_file:close())
end

print("Filesystem behavior tests passed.")
