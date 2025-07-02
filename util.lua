--- Module containing simple utility functions for vis-lspc/
-- @module util
-- @author Florian Fischer
-- @author git-bruh <prathamIN@proton.me>
-- @license GPL-3
-- @copyright 2024 Florian Fischer
-- @copyright 2024 git-bruh <prathamIN@proton.me>
local util = {}

local source_str = debug.getinfo(1, 'S').source:sub(2)
local source_path = source_str:match('(.*/)')

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

local vis_supports_pipe_buf = pcall(vis.pipe, vis, 'foo', 'true', false)

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
  if type(absolute_path_or_components) == 'string' then
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

--- Strip the last component from a pathname
-- @param the pathname
-- @return the pathname up to the last '/'
function util.dirname(name)
  if name == '.' or name == '..' or name == '/' then
    return name
  end

  -- strip a trailing path separator
  if name:sub(#name, #name) == '/' then
    name = name:sub(1, #name - 1)
  end

  local dirname = name:match('(.*)[/]')
  -- There was no path separator in name.
  if not dirname then
    return '.'
  end

  -- The name started with the root dir.
  if dirname == '' then
    return '/'
  end

  return dirname
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

--- Find file based on globs in the parent file system tree
-- @param globs a new line separated string of file globs
-- @param start the starting path
function util.find_upwards(globs, start)
  local status, out = util.vis_pipe(globs, '\'' .. source_path:gsub('\'', '\'\\\'\'') ..
                                        '/tools/find-upwards\' "' .. start .. '"')

  if status ~= 0 or out == nil then
    return nil
  end

  -- Skip trailing newline
  return out:sub(1, #out - 1)
end

-- get the vis_selection from current primary selection
local function get_selection(win)
  return {line = win.selection.line, col = win.selection.col}
end

--- Calculate the 0-based byte offsets from multiple sorted selections
-- @param file the file to calculate the positions in
-- @param sorted_selections a table of sorted vis_selections
-- @return a table of positions
function util.vis_sorted_selections_to_pos(file, sorted_selections)
  local positions = {}
  if file.pos_by_linecol then
    for _, sel in ipairs(sorted_selections) do
      table.insert(positions, file:pos_by_linecol(sel.line, sel.col))
    end
    return positions
  end

  local line_count = 0
  local pos = 0
  local sel_i = 1
  local sel = sorted_selections[sel_i]
  for line in file:lines_iterator() do
    line_count = line_count + 1
    while line_count == sel.line do
      table.insert(positions, pos + (sel.col - 1))
      sel_i = sel_i + 1
      -- no more selections to convert
      if sel_i > #sorted_selections then
        break
      end
      sel = sorted_selections[sel_i]
    end

    pos = pos + #line + 1
  end

  -- Some language servers (pylsp) sends a range including the first character after the last line.
  -- e.g. [{"line":1, "col":1}, {"line":#lines+1, "col":1}]
  -- But this selection can not be handled by iterating all lines.
  -- Add a special case for the selection of the first char after the last line.
  if sel.line == line_count + 1 and sel.col == 1 then
    table.insert(positions, pos)
  end
  return positions
end

local function vis_pos_before(p1, p2)
  return p1.line < p2.line or (p1.line == p2.line and p1.col < p2.col)
end

--- Calculate the 0-based byte offsets from multiple selections
-- @param file the file to calculate the positions in
-- @param selections a table of selections
-- @return a table of positions
function util.vis_selections_to_pos(file, selections)
  table.sort(selections, vis_pos_before)
  return util.vis_sorted_selections_to_pos(file, selections)
end

--- Get the line and column from a 0-based byte offset
-- ATTENTION: the fallback version of this function modifies the primary
-- selection so it is not safe to call it for example during WIN_HIGHLIGHT events
-- @param pos the 0-based byte offset into the file
-- @return the 1-based line number
-- @return the 1-based column
function util.vis_pos_to_sel(win, pos)
  if win.file.linecol_by_pos then
    local lineno, col = win.file:linecol_by_pos(pos)
    return {line = lineno, col = col}
  end

  local old_selection = get_selection(win)
  -- move primary selection
  win.selection.pos = pos
  local sel = get_selection(win)
  -- restore old primary selection
  win.selection:to(old_selection.line, old_selection.col)
  return sel
end

--- Count the visual characters in a line
-- This is useful to detect wrapped lines including tabs which may add a
-- unspecified amount of white space to a line depending on their position and
-- the used tabwidth.
-- @param win the window containing the line
-- @param line the line to count
-- @param nchars the number of characters in the line
-- @return the number of visual characters
util.visual_chars_in_line = function(win, line, nchars)
  -- fast string iteration inspired by:
  -- https://stackoverflow.com/a/49222705
  local l = {string.byte(line, 1, nchars)}
  local line_len = 0
  for i = 1, nchars do
    local c = l[i] -- Note: produces char codes instead of chars.
    if c == 9 then -- '\t'
      local chars_to_tab_stop = win.options.tabwidth - (line_len % win.options.tabwidth)
      line_len = line_len + chars_to_tab_stop
    else
      line_len = line_len + 1
    end
  end
  return line_len
end

return util
