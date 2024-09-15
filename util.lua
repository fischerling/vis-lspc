--- Module containing simple utility functions for vis-lspc/
-- @module util
-- @author Florian Fischer
-- @author git-bruh <prathamIN@proton.me>
-- @license GPL-3
-- @copyright 2024 Florian Fischer
-- @copyright 2024 git-bruh <prathamIN@proton.me>
local util = {}

local lspc

function util.init(lspc_)
  lspc = lspc_
  return util
end

--- Execute a command and capture its output.
-- @param cmd the command to execute
-- @return the output of the command written to stdout
function util.capture_cmd(cmd)
  local p = assert(io.popen(cmd, 'r'))
  local s = assert(p:read('*a'))
  local success, _, status = p:close()
  if not success then
    local err = cmd .. ' failed with exit code: ' .. status
    lspc:err(err)
  end
  return s
end

local vis_supports_pipe_buf = pcall(vis.pipe, vis, 'foo', 'true')

--- Wrapper for the two vis:pipe variants.
-- If vis does not support vis:pipe(input, cmd), prefix the command
-- with a printf call piping the result to the original command.
-- @param input The input to pipe to the command
-- @param cmd The external command to pipe the input to
function util.vis_pipe(input, cmd, fullscreen)
  if vis_supports_pipe_buf then
    return vis:pipe(input, cmd, fullscreen or false)
  end

  local escaped_input = input:gsub('\'', '\'"\'"\'')
  cmd = 'printf %s \'' .. escaped_input .. '\' | ' .. cmd
  return vis:pipe(vis.win.file, {start = 0, finish = 0}, cmd)
end

--- Split a path into its components
-- @param path the path to split into components
-- @return a table containing the path components
function util.split_path_into_components(path)
  local components = {}

  if #path == 1 then
    return nil
  end

  -- Skip the initial '/'
  local start_idx = 2

  while true do
    local slash = path:find('/', start_idx + 1)

    if slash == nil then
      table.insert(components, path:sub(start_idx, #path))
      return components
    else
      table.insert(components, path:sub(start_idx, slash - 1))
      start_idx = slash + 1
    end
  end
end

--- Get a path relative to the current working directory
-- @param cwd_components Table of the path components of the CWD
-- @param absolute_path_or_components absolute path or table of its path components
-- @return the relative path
function util.get_relative_path(cwd_components, absolute_path_or_components)
  local absolute_components
  if type(absolute_path_or_components) == "string" then
    absolute_components = util.split_path_into_components(absolute_path_or_components)
  else
    absolute_components = absolute_path_or_components
  end

  for idx = 1, #cwd_components do
    local cwd = cwd_components[idx]
    local absolute = absolute_components[idx]

    if cwd ~= absolute then
      local dir = ''

      -- Atleast the first component must match for us to convert
      -- it to a relative path
      if idx ~= 1 then
        for _ = idx, #cwd_components do
          dir = dir .. '..' .. '/'
        end

        -- Skip trailing '/'
        dir = dir:sub(1, #dir - 1)
      end

      for i = idx, #absolute_components do
        dir = dir .. '/' .. absolute_components[i]
      end

      return dir
    end
  end

  -- cwd shorter than absolute path
  local dir = ''

  for i = #cwd_components + 1, #absolute_components do
    dir = dir .. '/' .. absolute_components[i]
  end

  -- Skip leading '/'
  return dir:sub(2)
end

--- Create an iterator yielding the nth line of a file
--
-- @param path The path to the file
function util.file_line_iterator_to_n(path)
  local file = assert(io.open(path, 'r'))
  local lines = file:lines()
  local last_line = nil
  local last_n = 1

  return function(n)
    if n == -1 then
      file:close()
      return nil
    end

    if n < last_n then
      -- We might have multiple references on the same line, so we can
      -- get called again with the previous line number
      if (n + 1) == last_n then
        return last_line
      end

      return nil
    end

    for line in lines do
      if n == last_n then
        last_n = last_n + 1
        last_line = line

        return line
      end

      last_n = last_n + 1
    end

    -- Iterator exhausted
    return nil
  end
end

return util
