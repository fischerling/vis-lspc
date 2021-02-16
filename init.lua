-- Copyright (c) 2021 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- We require vis compiled with the communicate patch
if not vis.communicate then
  vis:info('Error: language server support requires vis communicate patch')
  return nil
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
  version = '0.0.1',
  -- write log messages to lspc.log_file
  logging = true,
  log_file = 'vis-lspc.log',
  log = init_logging,
}

local clangd = {name = 'clangd', cmd = 'clangd'}

-- map of known language servers per syntax
lspc.ls_map = {cpp = clangd, ansi_c = clangd}

-- Document position code
-- https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentPositionParams

-- A document positions is defined by a file path and a (line, column) tuple
-- We use 1-based indices like vis and lua.
-- Note line and col numbers must be transformed into 0-based inices when communicating
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

-- Support jumping between document positions
-- Open a document position in the active window
local vis_push_doc_pos
-- Restore the last text position in the active window
local vis_pop_doc_pos
do
  -- stack of edited document positions
  local doc_pos_stack = {}

  local function vis_goto_doc_pos(doc_pos)
    vis:command('e ' .. doc_pos.file)
    vis.win.selection:to(doc_pos.line, doc_pos.col)
  end

  vis_push_doc_pos = function(doc_pos)
    local old_doc_pos = {}
    old_doc_pos.file = vis.win.file.path
    old_doc_pos.line = vis.win.selection.line
    old_doc_pos.col = vis.win.selection.col

    table.insert(doc_pos_stack, old_doc_pos)
    vis_goto_doc_pos(doc_pos)
  end

  vis_pop_doc_pos = function()
    local last_doc_pos = table.remove(doc_pos_stack)
    if not last_doc_pos then
      return
    end
    vis_goto_doc_pos(last_doc_pos)

    -- reopen possibly closed file
    vis:command('lspc-open')
  end
end

vis:command_register('lspc-back', function()
  vis_pop_doc_pos()
end)

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

-- send a rpc message to a language server
local function ls_rpc(ls, req)
  req.jsonrpc = '2.0'

  local content_part = json.encode(req)
  local content_len = string.len(content_part)

  local header_part = 'Content-Length: ' .. tostring(content_len)
  local msg = header_part .. '\r\n\r\n' .. content_part
  lspc.log('LSPC Sending: ' .. msg .. '\n')

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
local function ls_call_method(ls, method, params, win)
  local id = ls.id
  ls.id = ls.id + 1

  local req = {id = id, method = method, params = params}
  ls.inflight[id] = req

  ls_rpc(ls, req)
  -- remember the current window to apply the effects of a
  -- method call in the original window
  ls.inflight[id].win = win
end

-- call textDocument/<method> and send a didChange notification upfront
-- to make sure the server sees our current state.
-- This is not ideal since we are sending more data than needed and
-- the  server has less time to parse the new file content and do its work
-- resulting in longer stalls after method invocation.
local function ls_call_text_document_method(ls, method, params, win)
  ls_send_did_change(ls, win.file)
  ls_call_method(ls, 'textDocument/' .. method, params, win)
end

local function lspc_handle_goto_method_response(method, result)
  if not result or next(result) == nil then
    vis:info('LSPC Warning: ' .. method .. ' found no results')
    return
  end

  local location
  -- result is no plain Location -> it must be Location[]
  if not result.uri then
    -- Use the first result. TODO: smarter result selection
    location = result[1]
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

  vis_push_doc_pos(lsp_doc_pos_to_vis(lsp_doc_pos))
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

  local vis_menu_input = ''
  for _, completion in ipairs(completions) do
    vis_menu_input = vis_menu_input .. completion.label .. '\n'
  end

  -- select a completion
  local completion = nil
  local cmd = 'printf "' .. vis_menu_input .. '" | vis-menu'
  local status, selection = vis:pipe(win.file, {start = 0, finish = 0}, cmd)
  if status == 0 then
    -- trim newline from selection
    selection = selection:sub(1, -2)

    for _, item in ipairs(completions) do
      if selection == item.label then
        completion = item
        break
      end
    end

    assert(completion)

    vis_apply_textEdit(win, win.file, completion.textEdit)
  end
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
     method == 'textDocument/implementation' then
    -- LuaFormatter on
    lspc_handle_goto_method_response(method, result)

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

  lspc.log('LSPC: handling complete message:\n' .. complete_msg .. '\n')
  local resp = json.decode(complete_msg)
  ls_handle_msg(ls, resp)

  local leftover = ls.partial_response.len - ls.partial_response.exp_len

  if leftover > 0 then
    local leftover_data = ls.partial_response.msg:sub(
                              ls.partial_response.exp_len + 1)
    lspc.log('LSPC: parse leftover:\n"' .. leftover_data .. '"\n')

    ls.partial_response.exp_len = 0
    ls.partial_response.len = 0
    ls_recv_data(ls, leftover_data)
  end

  ls.partial_response.exp_len = 0
  ls.partial_response.len = 0
end

-- check if a language server is running and register file as open
local function lspc_get_usable_ls(syntax)
  local ls = lspc.running[syntax]
  if not ls then
    vis:info('Error: No language server running for ' .. syntax)
    return nil
  end

  if not ls.initialized then
    vis:info('Error: Language server not initialized yet. Please try again')
    return nil
  end

  return ls
end

local function lspc_close(ls, file)
  ls_send_notification(ls, 'textDocument/didClose',
                       {textDocument = {uri = path_to_uri(file.path)}})
  ls.open_files[file.path] = nil
end

vis:command_register('lspc-close', function(_, _, win)
  local ls = lspc_get_usable_ls(win.syntax)

  lspc_close(ls, win.file)
end)

-- register a file as open with a language server and setup a close and save event handlers
-- A file must be opened before any textDocument functions can be used with it.
local function lspc_open(ls, win, file)
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

  -- TODO: implement textDocument/didChange

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

vis:command_register('lspc-open', function(_, _, win)
  local ls = lspc_get_usable_ls(win.syntax)

  if ls.open_files[win.file.path] then
    return
  end

  lspc_open(ls, win, win.file)
end)

-- Initiate the shutdown of a language server
-- Sending the exit notification and closing the file handle are done in
-- the shutdown response handler.
local function ls_shutdown_server(ls)
  ls_call_method(ls, 'shutdown', nil)
end

vis:command_register('lspc-shutdown-server', function(argv, _, win)
  local ls = lspc_get_usable_ls(argv[1] or win.syntax)
  if not ls then
    return
  end

  ls_shutdown_server(ls)
end)

local function ls_start_server(syntax)
  if lspc.running[syntax] then
    vis:info('Error: Already a language server running for ' .. syntax)
    return
  end

  local ls_conf = lspc.ls_map[syntax]
  if not ls_conf then
    vis:info('Error: No language server available for ' .. syntax)
    return
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

      ls.running[syntax] = nil
      return
    end

    lspc.log('LS response(' .. event .. '): ' .. msg .. '\n')
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

vis:command_register('lspc-start-server', function(argv, _, win)
  ls_start_server(argv[1] or win.syntax)
end)

local function lspc_method_textDocumentPositionParams(ls, method, win)
  -- check if the language server has a provider for this method
  if not ls.capabilities[method .. 'Provider'] then
    vis:info(
        'LPSC Error: language server ' .. ls.name .. ' does not provide ' ..
            method)
    return
  end

  if not ls.open_files[win.file.path] then
    lspc_open(ls, win, win.file)
  end

  local params = vis_doc_pos_to_lsp(vis_get_doc_pos(win))

  ls_call_text_document_method(ls, method, params, win)
end

local function lspc_declaration(ls, win)
  lspc_method_textDocumentPositionParams(ls, 'declaration', win)
end

local function lspc_definition(ls, win)
  lspc_method_textDocumentPositionParams(ls, 'definition', win)
end

local function lspc_typeDefinition(ls, win)
  lspc_method_textDocumentPositionParams(ls, 'typeDefinition', win)
end

local function lspc_implementation(ls, win)
  lspc_method_textDocumentPositionParams(ls, 'implementation', win)
end

local function lspc_completion(ls, win)
  lspc_method_textDocumentPositionParams(ls, 'completion', win)
end

local lspc_methods = {
  declaration = lspc_declaration,
  definition = lspc_definition,
  typeDefinition = lspc_typeDefinition,
  implementation = lspc_implementation,
  completion = lspc_completion,
}

for name, func in pairs(lspc_methods) do
  vis:command_register('lspc-' .. name, function(_, _, win, selection)
    local ls = lspc_get_usable_ls(win.syntax, win.file)
    if not ls then
      return
    end

    func(ls, win, selection)
  end)
end

-- default bindings
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
