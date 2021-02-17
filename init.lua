-- Copyright (c) 2021 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- We require vis compiled with the communicate patch
if not vis.communicate then
  vis:info('Error: language server support requires vis communicate patch')
  return {}
end

local function load_fallback_json()
  local source_str = debug.getinfo(1, 'S').source:sub(2)
  local script_path = source_str:match('(.*/)')

  return dofile(script_path .. 'json.lua')
end

-- find a suitable json implementation
local json
if vis:module_exist('json') then
  json = require('json')
  if not json.encode or not json.decode then
    json = load_fallback_json()
  end
else
  json = load_fallback_json()
end

-- get vis's pid to pass it to the language servers
local vis_proc_file = assert(io.open('/proc/self/stat', 'r'))
local vis_pid = vis_proc_file:read('*n')
vis_proc_file:close()

-- forward declaration of our client table
local lspc

-- logging system
-- if lspc.logging is set to true the first call to lspc.log
-- will open the log file and replace lspc.log with the actual log function
local init_logging
do
  local log_fd
  local function log(msg)
    log_fd:write(msg)
    log_fd:write('\n')
    log_fd:flush()
  end

  init_logging = function(msg)
    if not lspc.logging then
      return
    end

    log_fd = assert(io.open(lspc.log_file, 'w'))
    lspc.log = log

    log(msg)
  end
end

-- state of our language server client
lspc = {
  running = {},
  name = 'vis-lspc',
  version = '0.1.0',
  -- write log messages to lspc.log_file
  logging = false,
  log_file = 'vis-lspc.log',
  log = init_logging,
  -- automatically start a language server when a new window is opened
  autostart = true,
  -- program used to let the user make choices
  -- The available choices are pass to <menu_cmd> on stdin separated by '\n'
  menu_cmd = 'vis-menu',
}

-- check if fzf is available and use fzf instead of vis-menu per default
if os.execute('type fzf >/dev/null 2>/dev/null') then
  lspc.menu_cmd = 'fzf'
end

-- clangd language server configuration
local clangd = {name = 'clangd', cmd = 'clangd'}

-- map of known language servers per syntax
lspc.ls_map = {cpp = clangd, ansi_c = clangd}

-- Document position code
-- https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentPositionParams

-- A document positions is defined by a file path and a (line, column) tuple
-- We use 1-based indices like vis and lua.
-- Note line and col numbers must be transformed into 0-based indices when communicating
-- with a language server

local function path_to_uri(path)
  return 'file://' .. path
end

-- uri decode logic taken from
-- https://stackoverflow.com/questions/20405985/lua-decodeuri-luvit
local uri_decode_table = {}
for i = 0, 255 do
  uri_decode_table[string.format('%02x', i)] = string.char(i)
  uri_decode_table[string.format('%02X', i)] = string.char(i)
end

local function decode_uri(s)
  return (s:gsub('%%(%x%x)', uri_decode_table))
end

local function uri_to_path(uri)
  return decode_uri(uri:gsub('file://', ''))
end

-- convert LSP 0-based Position to vis position
local function lsp_pos_to_vis(pos)
  return {line = pos.line + 1, col = pos.character + 1}
end

-- convert 1-based vis position to LSP Position
local function vis_pos_to_lsp(pos)
  return {line = pos.line - 1, character = pos.col - 1}
end

-- convert our doc_pos to LSP TextDocumentPosition
local function vis_doc_pos_to_lsp(doc_pos)
  return {
    textDocument = {uri = path_to_uri(doc_pos.file)},
    position = vis_pos_to_lsp({line = doc_pos.line, col = doc_pos.col}),
  }
end

-- convert LSP TextDocumentPosition to our doc_pos
local function lsp_doc_pos_to_vis(doc_pos)
  local pos = lsp_pos_to_vis(doc_pos.position)
  return {
    file = uri_to_path(doc_pos.textDocument.uri),
    line = pos.line,
    col = pos.col,
  }
end

-- get document position of the main curser
local function vis_get_doc_pos(win)
  win = win or vis.win
  return {
    file = win.file.path,
    line = win.selection.line,
    col = win.selection.col,
  }
end

-- open a doc_pos using the vis command <cmd>
local function vis_open_doc_pos(doc_pos, cmd)
  assert(cmd)
  vis:command(string.format('%s \'%s\'', cmd, doc_pos.file))
  vis.win.selection:to(doc_pos.line, doc_pos.col)
  vis:command('lspc-open')
end

-- Support jumping between document positions
-- Stack of edited document positions
local doc_pos_history = {}

-- Open a document position in the active window
local function vis_push_doc_pos(win)
  local old_doc_pos = vis_get_doc_pos(win)
  table.insert(doc_pos_history, old_doc_pos)
end

-- open a new doc_pos remembering the old if it is replaced
local function vis_open_new_doc_pos(doc_pos, cmd)
  if cmd == 'e' then
    vis_push_doc_pos(vis.win, doc_pos)
  end

  vis_open_doc_pos(doc_pos, cmd)
end

local function vis_pop_doc_pos()
  local last_doc_pos = table.remove(doc_pos_history)
  if not last_doc_pos then
    return 'Document history is empty'
  end

  vis_open_doc_pos(last_doc_pos, 'e')
end

-- apply a textEdit received from the language server
local function vis_apply_textEdit(win, file, textEdit)
  assert(win.file == file)

  local start_pos = lsp_pos_to_vis(textEdit.range.start)
  local end_pos = lsp_pos_to_vis(textEdit.range['end'])

  -- convert the LSP range into a vis range
  -- this destroys the current selection but we change it after the edit anyway
  win.selection.anchored = false
  win.selection:to(start_pos.line, start_pos.col)
  win.selection.anchored = true
  win.selection:to(end_pos.line, end_pos.col - 1)
  local range = win.selection.range

  file:delete(range)
  file:insert(range.start, textEdit.newText)

  win.selection.anchored = false
  win.selection.pos = range.start + string.len(textEdit.newText)

  win:draw()
end

-- concatenate all numeric values in choices and pass it on stdin to lspc.menu_cmd
local function lspc_select(choices)
  local menu_input = ''
  local i = 0
  for _, c in ipairs(choices) do
    i = i + 1
    menu_input = menu_input .. c .. '\n'
  end

  -- select the only possible choice
  if i < 2 then
    return choices[1]
  end

  local cmd = 'printf "' .. menu_input .. '" | ' .. lspc.menu_cmd
  lspc.log('collect choice using: ' .. cmd)
  local menu = io.popen(cmd)
  local output = menu:read('*a')
  local _, _, status = menu:close()

  local choice = nil
  if status == 0 then
    -- trim newline from selection
    if output:sub(-1) == '\n' then
      choice = output:sub(1, -2)
    else
      choice = output
    end
  end

  vis:redraw()
  return choice
end

local function lspc_select_location(locations)
  local choices = {}
  for _, location in ipairs(locations) do
    local path = uri_to_path(location.uri)
    local position = lsp_pos_to_vis(location.range.start)
    local choice = path .. ':' .. position.line .. ':' .. position.col
    table.insert(choices, choice)
    choices[choice] = location
  end

  -- select a location
  local choice = lspc_select(choices)
  if not choice then
    return nil
  end

  return choices[choice]
end

-- send a rpc message to a language server
local function ls_rpc(ls, req)
  req.jsonrpc = '2.0'

  local content_part = json.encode(req)
  local content_len = string.len(content_part)

  local header_part = 'Content-Length: ' .. tostring(content_len)
  local msg = header_part .. '\r\n\r\n' .. content_part
  lspc.log('LSPC Sending: ' .. msg)

  ls.fd:write(msg)
  ls.fd:flush()
end

-- send a rpc notification to a language server
local function ls_send_notification(ls, method, params)
  ls_rpc(ls, {method = method, params = params})
end

local function ls_send_did_change(ls, file)
  lspc.log('send didChange')
  local new_version = assert(ls.open_files[file.path]).version + 1
  ls.open_files[file.path].version = new_version

  local document = {uri = path_to_uri(file.path), version = new_version}
  local changes = {{text = file:content(0, file.size)}}
  local params = {textDocument = document, contentChanges = changes}
  ls_send_notification(ls, 'textDocument/didChange', params)
end

-- send a rpc method call to a language server
local function ls_call_method(ls, method, params, win, ctx)
  local id = ls.id
  ls.id = ls.id + 1

  local req = {id = id, method = method, params = params}
  ls.inflight[id] = req

  ls_rpc(ls, req)
  -- remember the current window to apply the effects of a
  -- method call in the original window
  ls.inflight[id].win = win

  -- remember the user provided ctx value
  -- ctx can be used to remember arbitrary data from method invocation till
  -- method response handling
  -- The goto-location methods remember in ctx how to open the location
  ls.inflight[id].ctx = ctx
end

-- call textDocument/<method> and send a didChange notification upfront
-- to make sure the server sees our current state.
-- This is not ideal since we are sending more data than needed and
-- the  server has less time to parse the new file content and do its work
-- resulting in longer stalls after method invocation.
local function ls_call_text_document_method(ls, method, params, win, ctx)
  ls_send_did_change(ls, win.file)
  ls_call_method(ls, 'textDocument/' .. method, params, win, ctx)
end

local function lspc_handle_goto_method_response(req, result, win)
  if not result or next(result) == nil then
    vis:info('LSPC Warning: ' .. req.method .. ' found no results')
    return
  end

  local location
  -- result is no plain Location -> it must be Location[]
  if not result.uri then
    location = lspc_select_location(result, win)
    if not location then
      return
    end
  else
    location = result
  end
  assert(location)

  local lsp_doc_pos = {
    textDocument = {uri = location.uri},
    position = {
      line = location.range.start.line,
      character = location.range.start.character,
    },
  }

  vis_open_new_doc_pos(lsp_doc_pos_to_vis(lsp_doc_pos), req.ctx)
end

local function lspc_handle_completion_method_response(win, result)
  if not result or not result.items then
    vis:info('LSPC Warning: no completion available')
    return
  end

  local completions = result
  if result.isIncomplete ~= nil then
    completions = result.items
  end

  local choices = {}
  for _, completion in ipairs(completions) do
    table.insert(choices, completion.label)
    choices[completion.label] = completion
  end

  -- select a completion
  local choice = lspc_select(choices)
  if not choice then
    return
  end

  local completion = choices[choice]

  vis_apply_textEdit(win, win.file, completion.textEdit)
end

-- method response dispatcher
local function ls_handle_method_response(ls, method_response)
  local req = assert(ls.inflight[method_response.id])
  local win = req.win

  local method = req.method
  local result = method_response.result
  -- LuaFormatter off
  if method == 'textDocument/definition' or
     method == 'textDocument/declaration' or
     method == 'textDocument/typeDefinition' or
     method == 'textDocument/implementation' or
     method == 'textDocument/references' then
    -- LuaFormatter on
    lspc_handle_goto_method_response(req, result, win)

  elseif method == 'initialize' then
    ls.initialized = true
    ls.capabilities = result.capabilities
    ls_send_notification(ls, 'initialized')

  elseif method == 'textDocument/completion' then
    lspc_handle_completion_method_response(win, result)

  elseif method == 'shutdown' then
    ls_send_notification(ls, 'exit')
    ls.fd:close()

    -- remove the ls from lspc.running
    for syntax, rls in pairs(lspc.running) do
      if ls == rls then
        lspc.running[syntax] = nil
        break
      end
    end
  else
    vis:info('Warning: received unknown method ' .. method)
  end

  ls.inflight[method_response.id] = nil
end

local function ls_handle_notification(ls, notification) -- luacheck: no unused args
end

-- dispatch between a method response and a notification from the server
local function ls_handle_msg(ls, response)
  if response.id then
    ls_handle_method_response(ls, response)
  else
    ls_handle_notification(ls, response)
  end
end

-- Parse the data send by the language server
-- Note the chunks received may not end with the end of a message.
-- In the worst case a data chunk contains two partial messages on at the beginning
-- and one at the end
local function ls_recv_data(ls, data)
  -- new message received
  if ls.partial_response.len == 0 then
    lspc.log('LSPC: parse new message')
    local header = data:match('^Content%-Length: %d+')
    ls.partial_response.exp_len = tonumber(header:match('%d+'))
    local _, content_start = data:find('\r\n\r\n')

    ls.partial_response.msg = data:sub(content_start + 1)
    ls.partial_response.len = string.len(ls.partial_response.msg)

  else -- try to complete partial received message
    lspc.log('LSPC: parse message continuation')
    ls.partial_response.msg = ls.partial_response.msg .. data
    ls.partial_response.len = ls.partial_response.len + string.len(data)
  end

  -- received message not complete yet
  if ls.partial_response.len < ls.partial_response.exp_len then
    return
  end

  local complete_msg = ls.partial_response.msg:sub(1,
                                                   ls.partial_response.exp_len)

  lspc.log('LSPC: handling complete message: ' .. complete_msg)
  local resp = json.decode(complete_msg)
  ls_handle_msg(ls, resp)

  local leftover = ls.partial_response.len - ls.partial_response.exp_len

  if leftover > 0 then
    local leftover_data = ls.partial_response.msg:sub(
                              ls.partial_response.exp_len + 1)
    lspc.log('LSPC: parse leftover: "' .. leftover_data .. '"')

    ls.partial_response.exp_len = 0
    ls.partial_response.len = 0
    ls_recv_data(ls, leftover_data)
  end

  ls.partial_response.exp_len = 0
  ls.partial_response.len = 0
end

-- check if a language server is running and initialized
local function lspc_get_usable_ls(syntax)
  if not ls then
    return nil, 'Error: No language server running for ' .. syntax
  end

  if not ls.initialized then
    return nil, 'Error: Language server for ' .. syntax ..
               ' not initialized yet. Please try again'
  end

  return ls
end

local function lspc_close(ls, file)
  if not ls.open_files[file.path] then
    return 'Error: ' .. file.path .. ' not open'
  end
  ls_send_notification(ls, 'textDocument/didClose',
                       {textDocument = {uri = path_to_uri(file.path)}})
  ls.open_files[file.path] = nil
end

-- register a file as open with a language server and setup a close and save event handlers
-- A file must be opened before any textDocument functions can be used with it.
local function lspc_open(ls, win, file)
  -- already opened
  if ls.open_files[file.path] then
    return 'Error: ' .. file.path .. ' already open'
  end

  local params = {
    textDocument = {
      uri = 'file://' .. file.path,
      languageId = win.syntax,
      version = 0,
      text = file:content(0, file.size),
    },
  }

  ls.open_files[file.path] = {file = file, version = 0}
  ls_send_notification(ls, 'textDocument/didOpen', params)

  vis.events.subscribe(vis.events.FILE_CLOSE, function(file)
    for _, ls in pairs(lspc.running) do
      if ls.open_files[file.path] then
        lspc_close(ls, file)
      end
    end
  end)

  -- the server is interested in didSave notifications
  if ls.capabilities.textDocumentSync.save then
    vis.events.subscribe(vis.events.FILE_SAVE_POST, function(file, path)
      for _, ls in pairs(lspc.running) do
        if ls.open_files[file.path] then
          local params = {textDocument = {uri = path_to_uri(path)}}
          ls_send_notification(ls, 'textDocument/didSave', params)
        end
      end
    end)
  end

end

-- Initiate the shutdown of a language server
-- Sending the exit notification and closing the file handle are done in
-- the shutdown response handler.
local function ls_shutdown_server(ls)
  ls_call_method(ls, 'shutdown')
end

local function ls_start_server(syntax)
  if lspc.running[syntax] then
    return nil, 'Error: Already a language server running for ' .. syntax
  end

  local ls_conf = lspc.ls_map[syntax]
  if not ls_conf then
    return nil, 'Error: No language server available for ' .. syntax
  end

  local ls = {
    name = ls_conf.name,
    initialized = false,
    id = 0,
    inflight = {},
    open_files = {},
    partial_response = {exp_len = 0, len = 0, response = nil},
  }

  ls.fd = vis:communicate(ls_conf.name, ls_conf.cmd)

  lspc.running[syntax] = ls

  -- register the response handler
  vis.events.subscribe(vis.events.PROCESS_RESPONSE, function(name, msg, event)
    if name ~= ls.name then
      return
    end

    if event == 'EXIT' or event == 'SIGNAL' then
      if event == 'EXIT' then
        vis:info('language server exited with: ' .. msg)
      else
        vis:info('language server received signal: ' .. msg)
      end

      lspc.running[syntax] = nil
      return
    end

    lspc.log('LS response(' .. event .. '): ' .. msg)
    if event == 'STDERR' then
      return
    end

    ls_recv_data(ls, msg)
  end)

  local params = {
    processID = vis_pid,
    client = {name = lspc.name, version = lspc.version},
    rootUri = nil,
    capabilities = {},
  }

  ls_call_method(ls, 'initialize', params)

  return ls
end

-- generic stub implementation for all textDocument methods taking
-- a textDocumentPositionParams parameter
local function lspc_method_doc_pos(ls, method, win, argv)
  -- check if the language server has a provider for this method
  if not ls.capabilities[method .. 'Provider'] then
    return 'LPSC Error: language server ' .. ls.name .. ' does not provide ' ..
               method
  end

  if not ls.open_files[win.file.path] then
    lspc_open(ls, win, win.file)
  end

  local params = vis_doc_pos_to_lsp(vis_get_doc_pos(win))

  ls_call_text_document_method(ls, method, params, win, argv)
end

local lspc_goto_location_methods = {
  declaration = function(ls, win, open_cmd)
    return lspc_method_doc_pos(ls, 'declaration', win, open_cmd)
  end,
  definition = function(ls, win, open_cmd)
    return lspc_method_doc_pos(ls, 'definition', win, open_cmd)
  end,
  typeDefinition = function(ls, win, open_cmd)
    return lspc_method_doc_pos(ls, 'typeDefinition', win, open_cmd)
  end,
  implementation = function(ls, win, open_cmd)
    return lspc_method_doc_pos(ls, 'implementation', win, open_cmd)
  end,
  references = function(ls, win, open_cmd)
    return lspc_method_doc_pos(ls, 'references', win, open_cmd)
  end,
}

-- vis-lspc commands

vis:command_register('lspc-back', function()
  local err = vis_pop_doc_pos()
  if err then
    vis:info(err)
  end
end)

for name, func in pairs(lspc_goto_location_methods) do
  vis:command_register('lspc-' .. name, function(argv, _, win)
    local ls, err = lspc_get_usable_ls(win.syntax)
    if err then
      vis:info(err)
      return
    end

    -- vis cmd how to open the new location
    -- 'e' (default): in same window
    -- 'vsplit': in a vertical split window
    -- 'hsplit': in a horizontal split window
    local open_cmd = argv[1] or 'e'
    err = func(ls, win, open_cmd)
    if err then
      vis:info(err)
    end
  end)
end

vis:command_register('lspc-completion', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    vis:info(err)
    return
  end

  err = lspc_method_doc_pos(ls, 'completion', win)
  if err then
    vis:info(err)
  end
end)

vis:command_register('lspc-start-server', function(argv, _, win)
  local _, err = ls_start_server(argv[1] or win.syntax)
  if err then
    vis:info(err)
  end
end)

vis:command_register('lspc-shutdown-server', function(argv, _, win)
  local ls, err = lspc_get_usable_ls(argv[1] or win.syntax)
  if err then
    vis:info(err)
    vis:info('Error: no language server running')
    return
  end

  ls_shutdown_server(ls)
end)

vis:command_register('lspc-close', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    vis:info(err)
    return
  end

  lspc_close(ls, win.file)
end)

vis:command_register('lspc-open', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    vis:info(err)
    return
  end

  lspc_open(ls, win, win.file)
end)

-- vis-lspc event hooks

vis.events.subscribe(vis.events.WIN_OPEN, function(win)
  if lspc.autostart then
    ls_start_server(win.syntax, true)
  end
end)

vis.events.subscribe(vis.events.FILE_OPEN, function(file)
  local win = vis.win
  -- the only window we can access is not our window
  if not win or win.file ~= file then
    return
  end

  local ls = lspc_get_usable_ls(win.syntax)

  lspc_open(ls, win, file)
end)

-- vis-lspc default bindings

vis:map(vis.modes.NORMAL, '<F2>', function()
  vis:command('lspc-start-server')
end)

vis:map(vis.modes.NORMAL, '<F3>', function()
  vis:command('lspc-open')
end)

vis:map(vis.modes.NORMAL, '<C-]>', function()
  vis:command('lspc-definition')
end)

vis:map(vis.modes.NORMAL, '<C-t>', function()
  vis:command('lspc-back')
end)

vis:map(vis.modes.NORMAL, '<C- >', function()
  vis:command('lspc-completion')
end)

vis:map(vis.modes.INSERT, '<C- >', function()
  vis:command('lspc-completion')
  vis.mode = vis.modes.INSERT
end)

return lspc
