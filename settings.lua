--- Collect all effective settings.
-- There are three kinds of settings:
--
-- 1. Global settings explicitly set by the user in its vis configuration in the
--    language server configuration's `settings` member.
--
-- 2. Project specific settings stored in .vis-lspc-settings.json files.
--
-- 3. Settings stored by vis-lspc in its settings.json file.
--    The user settings are stored for each language server and each file path.
--    Settings for a more specific file path override settings defined for
--    a parent directory.
--
-- All settings are organized in sections which are their top-level organization.
-- Commonly a language server expects its settings to be stored in a section with
-- its name.
-- Additionally, settings can be scoped which correspond with the local file
-- system. The scoped settings are merged with more specific ones taking priority.
--
-- TODO: Implement commands to change the client settings and store them
--       permanently.
--
-- @module settings
-- @author Florian Fischer
-- @license GPL-3
-- @copyright Florian Fischer 2024
local settings = {}

local util

local lspc

--- Initialize the settings module
-- @param the lspc module table
-- @return the settings module table
function settings.init(lspc_)
  lspc = lspc_
  local source_str = debug.getinfo(1, 'S').source:sub(2)
  local source_path = source_str:match('(.*/)')

  util = dofile(source_path .. 'util.lua').init(lspc)

  return settings
end

--- Read a JSON settings file from disk
-- @param settings_path the path to the settings file
-- @return the settings table
local function read_settings(settings_path)
  local loaded_settings = {}
  local settings_file = io.open(settings_path)
  if settings_file then
    loaded_settings = lspc.json.decode(settings_file:read('*a'))
    settings_file:close()
    lspc:log('read settings from ' .. settings_path .. ': ' .. lspc.json.encode(loaded_settings))
  end
  return loaded_settings
end

--- Read the user's local settings file
--
-- Local user settings are stored at $XDG_CONFIG_HOME/vis-lspc/settings.json.
-- @return the user's local settings table
local function read_local_settings()
  local xdg_conf_dir = os.getenv('XDG_CONFIG_HOME') or os.getenv('HOME') .. '/.config'
  local settings_path = xdg_conf_dir .. '/vis-lspc/settings.json'
  return read_settings(settings_path)
end

--- Get a specific section from a settings table
-- @param tbl the settings table
-- @param section the dot-separated section name
-- @return the settings table for the requested section
function settings.get_section(tbl, section)
  local t = tbl
  -- iterate the dot-separated section components
  for k in section:gmatch('[^.]+') do
    if not t then
      break
    end
    t = t[k]
  end

  return t or {}
end

--- Merge settings along the scope of their file path
--
-- The settings are merged from the top most directory to the
-- actual file path.
-- @param path_specific_settings the path specific settings table
-- @param project_root path to the project
-- @return a table containing the effective settings
local function merge_path_specific(path_specific_settings, project_root)
  local merged_settings = {}
  local path = ''
  local file_path_components = util.split_path_into_components(project_root)

  for _, comp in ipairs(file_path_components) do
    path = path .. '/' .. comp
    if path_specific_settings[path] then
      merged_settings = util.table.merge(merged_settings, path_specific_settings[path])
    end
  end

  return merged_settings
end

--- Load the client local settings.
-- @param section the section of the settings
-- @param scope the scope of the local settings
-- @return a table containing the local settings
function settings.local_settings(section, scope)
  local local_settings = read_local_settings()
  local local_ls_settings = local_settings[section]
  if not local_ls_settings then
    return {}
  end
  return merge_path_specific(local_ls_settings, scope)
end

--- Load the project local settings.
-- @param section the section of the settings
-- @param scope the scope of the project local settings
-- @return a table containing the local settings
function settings.project_local_settings(section, scope)
  local merged_settings = {}
  local settings_name = '.vis-lspc-settings.json'

  while true do
    local settings_dir = util.find_upwards(settings_name .. '\n', scope)
    if not settings_dir or settings_dir == '/' then
      return merged_settings
    end

    scope = settings_dir

    local settings_path = settings_dir .. '/' .. settings_name
    lspc:log('settings: found project specific settings at "' .. settings_path)
    local ls_settings = read_settings(settings_path)[section] or {}
    -- The settings found later have less priority than the settings found earlier
    merged_settings = util.table.merge(ls_settings, merged_settings)
  end
end

--- Get the effective settings for a language server and an active file
-- @param section the section name of settings
-- @param scope the scope of where the settings should have effect
-- @return a table containing the effective settings
function settings.effective_settings(ls, section, scope)
  lspc:log('get effective settings (' .. tostring(section) .. ', ' .. tostring(scope) .. ') for ' ..
               ls.name)
  local effective_settings = {}
  if ls.conf.settings then
    lspc:log('global settings ' .. lspc.json.encode(effective_settings))
    effective_settings = util.table.deep_copy(ls.conf.settings)
    if section then
      effective_settings = settings.get_section(effective_settings, section)
    end
    lspc:log('-> ' .. lspc.json.encode(effective_settings))
  end

  if scope then
    local project_local_settings = settings.project_local_settings(section, scope)
    lspc:log('project local settings ' .. lspc.json.encode(project_local_settings))
    util.table.merge(effective_settings, project_local_settings)
    lspc:log('-> ' .. lspc.json.encode(effective_settings))
  end

  local local_settings = settings.local_settings(section, scope)
  lspc:log('local settings ' .. lspc.json.encode(local_settings))
  util.table.merge(effective_settings, local_settings)

  lspc:log('-> settings ' .. lspc.json.encode(effective_settings))
  return effective_settings
end

vis:command_register('lspc-settings-reload', function(argv)
  local ls, err = lspc.get_running_ls(vis.win, argv[1])
  if err then
    lspc:err(err)
    return
  end
  assert(ls)

  ls:send_default_settings()
end, 'reload language server settings')

vis:command_register('lspc-settings-show', function(argv)
  local ls, err = lspc.get_running_ls(vis.win, argv[1])
  if err then
    lspc:err(err)
    return
  end
  assert(ls)

  local scope = ls.rootUri or vis.win.file and vis.win.file.path
  local effective_ls_settings = settings.effective_settings(ls, nil, scope)
  vis:message(lspc.json.encode(effective_ls_settings))
end, 'show the language server settings')

return settings
