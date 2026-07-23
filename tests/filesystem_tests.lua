-- Behavioral tests for filesystem operations. Run through run-tests.ps1.

local script_path = debug.getinfo(1, "S").source:sub(2)
local tests_path = app.fs.filePath(script_path)
local repo_path = app.fs.filePath(tests_path)
local fake_path = app.fs.joinPath(tests_path, "fake_filesystem.lua")
local core_path = app.fs.joinPath(repo_path, "browser_core.lua")

local fake = assert(loadfile(fake_path))()
local environment = fake.environment()
local core = assert(loadfile(core_path, "t", environment))()

core.plugin = { preferences = { expanded = {} } }
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

test_directory_creation()
test_chunked_file_copy()
test_failed_write_cleanup()
test_recursive_copy_guard()
test_transactional_folder_copy()
test_keep_both()
test_replace()
test_folder_merge()
test_cut_fallback()
test_drop_guards()
test_case_rename()

if app.params and app.params.result then
  local result_file = assert(io.open(app.params.result, "wb"))
  assert(result_file:write("passed"))
  assert(result_file:close())
end

print("Filesystem behavior tests passed.")
