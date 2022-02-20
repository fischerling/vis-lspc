-- Copyright (c) 2021 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- We require vis compiled with the communicate patch
local source_str = debug.getinfo(1, 'S').source:sub(2)
local source_path = source_str:match('(.*/)')

local parser = dofile(source_path .. 'parser.lua')

if not vis.communicate then
  vis:info('LSPC Error: language server support requires vis communicate patch')
  return {}
end

local json
local json_impls = {'json', 'cjson', 'dkjson'}

-- find a suitable json implementation
for _, json_impl in ipairs(json_impls) do
  if vis:module_exist(json_impl) then
    json = require(json_impl)
    if not json.encode or not json.decode then
      json = nil
    end

    -- found a usable json implementation
    if json then
      break
    end
  end
end

-- We found no suitable implementation in json_impls -> use our fallback
if not json then
  json = dofile(source_path .. 'json.lua')
end

local jsonrpc = {}
jsonrpc.error_codes = {
  -- json rpc errors
  ParseError = -32700,
  InvalidRequest = -32600,
  MethodNotFound = -32601,
  InvalidParams = -32602,
  InternalError = -32603,

  ServerNotInitialized = -32002,
  UnknownErrorCode = -32001,

  -- lsp errors
  ContentModified = -32801,
  RequestCancelled = -32800,
}

-- state of our language server client
local lspc = {
  -- mapping language server names to their state tables
  running = {},
  name = 'vis-lspc',
  version = '0.1.4',
  -- write log messages to lspc.log_file
  logging = false,
  log_file = nil,
  -- automatically start a language server when a new window is opened
  autostart = true,
  -- program used to let the user make choices
  -- The available choices are pass to <menu_cmd> on stdin separated by '\n'
  menu_cmd = 'vis-menu',
  -- program used to ask the user for confirmation
  confirm_cmd = 'vis-menu',

  -- should diagnostics be highlighted if available
  highlight_diagnostics = false,
  -- style id used by lspc to register the style used to highlight diagnostics
  diagnostic_style_id = 43,
  -- style used by lspc to highlight the diagnostic range
  -- 60% solarized red
  diagnostic_style = 'back:#e3514f',
}

-- Forward declaration of lspc_err to use it in capture_cmd
local lspc_err

-- Helper to execute a command and capture its output
local function capture_cmd(cmd)
  local p = assert(io.popen(cmd, 'r'))
  local s = assert(p:read('*a'))
  local success, _, status = p:close()
  if not success then
    local err = cmd .. ' failed with exit code: ' .. status
    if lspc_err then
      lspc_err(err)
    else
      vis:info('LSPC Error: ' .. err)
    end
  end
  return s
end

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

    local log_file = lspc.log_file

    -- open the default log file in $XDG_DATA_HOME/vis-lspc
    if not log_file then
      local xdg_data = os.getenv('XDG_DATA_HOME') or os.getenv('HOME') ..
                           '/.local/share'
      local log_dir = xdg_data .. '/vis-lspc'

      -- ensure the direcoty exists
      os.execute('mkdir -p ' .. log_dir)

      -- log file format: {time-stamp}-{basename-cwd}.log
      local log_file_fmt = log_dir .. '/%s-%s.log'
      local timestamp = os.date('%Y-%m-%dT%H:%M:%S')
      local cwd = capture_cmd('pwd')
      local basename_cwd = capture_cmd('basename ' .. cwd):match('^%s*(.-)%s*$')
      log_file = log_file_fmt:format(timestamp, basename_cwd)

    elseif type(log_file) == 'function' then
      log_file = log_file()
    end

    log_fd = assert(io.open(log_file, 'w'))
    lspc.log = log

    log(msg)
  end
end
lspc.log = init_logging

local function lspc_warn(msg)
  local warning = 'LSPC Warning: ' .. msg
  lspc.log(warning)
  vis:info(warning)
end

lspc_err = function(msg)
  local err = 'LSPC Error: ' .. msg
  lspc.log(err)
  vis:info(err)
end

-- get vis's pid to pass it to the language servers
local vis_pid
do
  local vis_proc_file = io.open('/proc/self/stat', 'r')
  if vis_proc_file then
    vis_pid = vis_proc_file:read('*n')
    vis_proc_file:close()

  else -- fallback if /proc/self/stat
    local out = capture_cmd('sh -c "echo $PPID"')
    vis_pid = tonumber(out)
  end
end
assert(vis_pid)

--
--- ClientCapabilities we tell the language server when calling "initialize"
--
local supported_markup_kind = {'plaintext'}

local goto_methods_capabilities = {
  linkSupport = true,
  dynamicRegistration = false,
}

local client_capabilites = {
  workspace = {configuration = false},
  textDocument = {
    synchronization = {dynamicRegistration = false, didSave = true},
    -- ask the server to send us only plaintext completionItems
    completion = {
      dynamicRegistration = false,
      completionItem = {documentationFormat = supported_markup_kind},
    },
    -- ask the server to send us only plaintext hover results
    hover = {dynamicRegistration = false, contentFormat = supported_markup_kind},
    -- ask the server to send us only plaintext signatureHelp results
    signatureHelp = {
      dynamicRegistration = false,
      signatureInformation = {documentationFormat = supported_markup_kind},
    },
    declaration = {dynamicRegistration = false, linkSupport = true},
    definition = goto_methods_capabilities,
    typeDefinition = goto_methods_capabilities,
    implementation = goto_methods_capabilities,
    references = {dynamicRegistration = false},
    rename = {
      dynamicRegistration = false,
      prepareSupport = false,
      honorsChangeAnnotations = false,
    },
  },
  window = {workDoneProgress = false, showDocument = {support = false}},
}

-- check if fzf is available and use fzf instead of vis-menu per default
if os.execute('type fzf >/dev/null 2>/dev/null') then
  lspc.menu_cmd = 'fzf'
end

-- mapping function between vis lexer names and LSP languageIds
local function syntax_to_languageId(syntax)
  if syntax == 'ansi_c' then
    return 'c'
  end
  return syntax
end

-- clangd language server configuration
local clangd = {name = 'clangd', cmd = 'clangd'}

-- map of known language servers per syntax
lspc.ls_map = {
  cpp = clangd,
  ansi_c = clangd,
  -- pylsp (python-lsp-server) language server configuration
  -- https://github.com/python-lsp/python-lsp-server
  python = {name = 'python-lsp-sever', cmd = 'pylsp'},
  -- lua (lua-language-server) language server configuration
  -- https://github.com/sumneko/lua-language-server
  lua = {name = 'lua-language-server', cmd = 'lua-language-server'},
}

-- return the name of the language server for this syntax
local function get_ls_name_for_syntax(syntax)
  local ls_def = lspc.ls_map[syntax]
  if not ls_def then
    return nil, 'No language server available for ' .. syntax
  end
  return ls_def.name
end

-- Document position code
-- https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentPositionParams

-- We use the following position/location/file related types in  vis-lspc:
-- pos - like in vis a 0-based byte offset into the file.
-- path - posix path used by vis
-- uri - file uri used by LSP

-- lsp_position - 0-based tuple (line, character)
-- lsp_document_position - aka. LSP TextDocumentPosition, tuple of (uri, lsp_position)

-- vis_selection - 1-based tuple (line, cul) (character)
--              Can be used with with Selection:to
-- vis_document_position - 1-based tuple of (path, line, cul)

-- vis_range - tuple of 0-based byte offsets (finish, start)
-- lsp_range - aka. Range, tuple of two lsp_positions (start, end)

-- There exist helper function to convert from one type into another
-- aswell as helper to retrieve the current primary selection from a vis.window

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

-- get the vis_selection from current primary selection
local function get_selection(win)
  return {line = win.selection.line, col = win.selection.col}
end

-- get the 0-based byte offset from a selection
-- ATTENTION: this function modifies the primary selection so it is not
-- safe to call it for example during WIN_HIGHLIGHT events
local function vis_sel_to_pos(win, selection)
  local old_selection = get_selection(win)
  -- move primary selection
  win.selection:to(selection.line, selection.col)
  local pos = win.selection.pos
  -- restore old primary selection
  win.selection:to(old_selection.line, old_selection.col)
  return pos
end

-- get the line and column from a 0-based byte offset
-- ATTENTION: this function modifies the primary selection so it is not
-- safe to call it for example during WIN_HIGHLIGHT events
local function vis_pos_to_sel(win, pos)
  local old_selection = get_selection(win)
  -- move primary selection
  win.selection.pos = pos
  local sel = get_selection(win)
  -- restore old primary selection
  win.selection:to(old_selection.line, old_selection.col)
  return sel
end

-- convert lsp_position to vis_selection
local function lsp_pos_to_vis_sel(pos)
  return {line = pos.line + 1, col = pos.character + 1}
end

-- convert vis_selection to lsp_position
local function vis_sel_to_lsp_pos(pos)
  return {line = pos.line - 1, character = pos.col - 1}
end

-- convert our vis_document_position to lsp_document_position aka. TextDocumentPosition
local function vis_doc_pos_to_lsp(doc_pos)
  return {
    textDocument = {uri = path_to_uri(doc_pos.file)},
    position = vis_sel_to_lsp_pos({line = doc_pos.line, col = doc_pos.col}),
  }
end

-- convert lsp_document_position to vis_document_position
local function lsp_doc_pos_to_vis(doc_pos)
  local pos = lsp_pos_to_vis_sel(doc_pos.position)
  return {
    file = uri_to_path(doc_pos.textDocument.uri),
    line = pos.line,
    col = pos.col,
  }
end

-- get document position of the main curser
local function vis_get_doc_pos(win)
  return {
    file = win.file.path,
    line = win.selection.line,
    col = win.selection.col,
  }
end

-- convert a lsp_range to a vis_range
-- ATTENTION: this function modifies the primary selection so it is not
-- safe to call it for example during WIN_HIGHLIGHT events
local function lsp_range_to_vis_range(win, lsp_range)
  local start = lsp_pos_to_vis_sel(lsp_range.start)
  local start_pos = vis_sel_to_pos(win, start)

  local finish = lsp_pos_to_vis_sel(lsp_range['end'])
  local finish_pos = vis_sel_to_pos(win, finish)

  return {start = start_pos, finish = finish_pos}
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
    vis_push_doc_pos(vis.win)
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

  local start_pos = lsp_pos_to_vis_sel(textEdit.range.start)
  local end_pos = lsp_pos_to_vis_sel(textEdit.range['end'])

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
    local path = uri_to_path(location.uri or location.targetUri)
    local range = location.range or location.targetSelectionRange
    local position = lsp_pos_to_vis_sel(range.start)
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

-- get a user confirmation
-- return true if user selected yes, false otherwise
local function lspc_confirm(prompt)
  local choices = 'no\nyes'

  local cmd = 'printf "' .. choices .. '" | ' .. lspc.confirm_cmd

  if prompt then
    cmd = cmd .. ' -p \'' .. prompt .. '\''
  end

  lspc.log('get confirmation using: ' .. cmd)
  -- local menu = io.popen(cmd)
  -- local output = menu:read('*a')
  -- local _, _, status = menu:close()

  local choice = nil
  local status, output = vis:pipe(vis.win.file, {start = 0, finish = 0}, cmd)
  if status == 0 then
    -- trim newline from selection
    if output:sub(-1) == '\n' then
      choice = output:sub(1, -2)
    else
      choice = output
    end
  end

  vis:redraw()
  return choice == 'yes'
end

-- apply a WorkspaceEdit received from the language server
local function vis_apply_workspaceEdit(_, _, workspaceEdit)
  local file_edits = workspaceEdit.changes
  assert(file_edits)

  -- generate change summary
  local summary = '--- workspace edit summary ---\n'
  for uri, edits in pairs(file_edits) do
    local path = uri_to_path(uri)
    summary = summary .. path .. ':\n'
    for i, edit in ipairs(edits) do
      summary = summary .. '\t' .. i .. '.: ' .. json.encode(edit) .. '\n'
    end
  end

  vis:message(summary)
  vis:redraw()

  -- get user confirmation
  local confirmation = lspc_confirm('apply changes:')

  -- close summary window
  vis:command('q')

  if not confirmation then
    return
  end

  -- apply changes to open files
  for uri, edits in pairs(file_edits) do
    local path = uri_to_path(uri)

    -- search all open windows for this uri
    local win_with_file
    for win in vis:windows() do
      if win.file and win.file.path == path then
        win_with_file = win
        break
      end
    end

    -- It is not open currently -> open it
    local opened
    if not win_with_file then
      vis:command('o ' .. path)
      win_with_file = vis.win
      opened = true
    end

    for _, edit in ipairs(edits) do
      vis_apply_textEdit(win_with_file, win_with_file.file, edit)
    end

    -- save changes and close the opened window
    if opened then
      vis:command('wq')
    end
  end
end

local function lspc_highlight_diagnostics(win, diagnostics)
  for _, diagnostic in ipairs(diagnostics) do
    local range = diagnostic.vis_range
    -- make sure to highlight only ranges which actually contain the diagnostic
    if diagnostic.content == win.file:content(range) then
      win:style(lspc.diagnostic_style_id, range.start, range.finish - 1)
    end
  end
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

local function lspc_handle_goto_method_response(req, result)
  if not result or next(result) == nil then
    lspc_warn(req.method .. ' found no results')
    return
  end

  local location
  -- result actually a list of results
  if type(result) == 'table' then
    location = lspc_select_location(result)
    if not location then
      return
    end
  else
    location = result
  end
  assert(location)

  -- location is a Location
  local lsp_doc_pos
  if location.uri then
    lspc.log('Handle location: ' .. json.encode(location))
    lsp_doc_pos = {
      textDocument = {uri = location.uri},
      position = {
        line = location.range.start.line,
        character = location.range.start.character,
      },
    }
    -- location is a LocationLink
  elseif location.targetUri then
    lspc.log('Handle locationLink: ' .. json.encode(location))
    lsp_doc_pos = {
      textDocument = {uri = location.targetUri},
      position = {
        line = location.targetSelectionRange.start.line,
        character = location.targetSelectionRange.start.character,
      },
    }
  else
    lspc_warn('Unknown location type: ' .. json.encode(location))
  end

  local doc_pos = lsp_doc_pos_to_vis(lsp_doc_pos)
  vis_open_new_doc_pos(doc_pos, req.ctx)
end

local function lspc_handle_completion_method_response(win, result, old_pos)
  if not result or not result.items then
    lspc_warn('no completion available')
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

  if completion.textEdit then
    vis_apply_textEdit(win, win.file, completion.textEdit)
    return
  end

  if completion.insertText or completion.label then
    -- Does our current state correspont to the state when the completion method
    -- was called.
    -- Otherwise we don't have a good way to apply the 'insertText' completion
    if win.selection.pos ~= old_pos then
      lspc_warn('can not apply textInsert because the cursor position changed')
    end

    local new_word = completion.insertText or completion.label
    local old_word_range = win.file:text_object_word(old_pos)
    local old_word = win.file:content(old_word_range)

    lspc.log(string.format(
                 'Completion old_pos=%d, old_range={start=%d, finish=%d}, old_word=%s',
                 old_pos, old_word_range.start, old_word_range.finish,
                 old_word:gsub('\n', '\\n')))

    -- update old_word_range and old_word and return if old_word is a prefix of the completion
    local function does_completion_apply_to_pos(pos)
      old_word_range = win.file:text_object_word(pos)
      old_word = win.file:content(old_word_range)

      local is_prefix = new_word:sub(1, string.len(old_word)) == old_word
      return is_prefix
    end

    -- search for a possible completion token which we should replace with this insertText
    local matches = does_completion_apply_to_pos(old_pos)
    if not matches then
      lspc.log('Cursor looks like its not on the completion token')

      -- try the common case the cursor is behind its completion token: fooba┃
      local next_pos_candidate = old_pos - 1
      matches = does_completion_apply_to_pos(next_pos_candidate)
      if matches then
        old_pos = next_pos_candidate
      end
    end

    local completion_start
    -- we found a completion token -> replace it
    if matches then
      lspc.log('replace the token: ' .. old_word ..
                   '  we found being a prefix of the completion')
      win.file:delete(old_word_range)
      completion_start = old_word_range.start
    else
      completion_start = old_pos
    end
    -- apply insertText
    win.file:insert(completion_start, new_word)
    win.selection.pos = completion_start + string.len(new_word)
    win:draw()
    return
  end

  -- neither insertText nor textEdit where present
  lspc_err('Unsupported completion')
end

local function lspc_handle_hover_method_response(win, result, old_pos)
  if not result or not result.contents then
    lspc_warn('no hover available')
    return
  end

  local sel = vis_pos_to_sel(win, old_pos)
  local hover_header =
      '--- hover: ' .. (win.file.path or '') .. ':' .. sel.line .. ', ' ..
          sel.col .. ' ---'

  local hover_msg = ''
  -- result is MarkedString[]
  if type(result.contents) == 'table' then
    lspc.log('hover returned list of length ' .. #result.contents)
    for i, v in ipairs(result.contents) do
      if i == 1 then
        hover_msg = v.value or v
      else
        hover_msg = hover_msg .. '\n---\n' .. (v.value or v)
      end
    end
    -- result is either MarkedString or MarkupContent
  else
    hover_msg = result.contents.value or result.contents
  end
  vis:message(hover_header .. '\n' .. hover_msg)
end

local function lspc_handle_signature_help_method_response(win, result, call_pos)
  if not result or not result.signatures or #result.signatures == 0 then
    lspc_warn('no signature help available')
    return
  end

  local signatures = result.signatures

  local sel = vis_pos_to_sel(win, call_pos)
  local help_header = '--- signature help: ' .. (win.file.path or '') .. ':' ..
                          sel.line .. ', ' .. sel.col .. ' ---'

  -- local help_msg = json.encode(result)
  local help_msg = ''
  for _, signature in ipairs(signatures) do
    local sig_msg = signature.label
    if signature.documentation then
      local doc = signature.documentation.value or signature.documentation
      sig_msg = sig_msg .. '\n\tdocumentation: ' .. doc
    end
    help_msg = help_msg .. '\n' .. sig_msg
  end
  vis:message(help_header .. help_msg)
end

local function lspc_handle_rename_method_response(win, result)
  -- result must always be valid because otherwise we would caught the error
  -- in ls_handle_method_response
  vis_apply_workspaceEdit(win, win.file, result)
end

-- method response dispatcher
local function ls_handle_method_response(ls, method_response, req)
  local win = req.win

  local method = req.method

  local err = method_response.error
  if err then
    local err_msg = err.message
    local err_code = err.code
    lspc_err(err_msg .. ' (' .. err_code .. ') occurred during ' .. method)
    -- Don't try to handle error responses any further
    return
  end

  local result = method_response.result

  -- LuaFormatter off
  if method == 'textDocument/definition' or
     method == 'textDocument/declaration' or
     method == 'textDocument/typeDefinition' or
     method == 'textDocument/implementation' or
     method == 'textDocument/references' then
    -- LuaFormatter on
    lspc_handle_goto_method_response(req, result)

  elseif method == 'initialize' then
    ls.initialized = true
    ls.capabilities = result.capabilities
    ls_send_notification(ls, 'initialized')

  elseif method == 'textDocument/completion' then
    lspc_handle_completion_method_response(win, result, req.ctx)

  elseif method == 'textDocument/hover' then
    lspc_handle_hover_method_response(win, result, req.ctx)

  elseif method == 'textDocument/signatureHelp' then
    lspc_handle_signature_help_method_response(win, result, req.ctx)

  elseif method == 'textDocument/rename' then
    lspc_handle_rename_method_response(win, result, req.ctx)

  elseif method == 'shutdown' then
    ls_send_notification(ls, 'exit')
    ls.fd:close()

    -- remove the ls from lspc.running
    for ls_name, rls in pairs(lspc.running) do
      if ls == rls then
        lspc.running[ls_name] = nil
        break
      end
    end
  else
    lspc_warn('received unknown method ' .. method)
  end

  ls.inflight[method_response.id] = nil
end

local function ls_handle_method_call(ls, method_call)
  local method = method_call.method
  lspc.log('Unknown method call ' .. method)
  local response = {id = method_call.id}
  response['error'] = {
    code = jsonrpc.error_codes.MethodNotFound,
    message = method .. ' not implemented',
  }
  ls_rpc(ls, response)
end

-- save the diagnostics received for a file uri
local function lspc_handle_publish_diagnostics(ls, uri, diagnostics)
  local file_path = uri_to_path(uri)
  local file = ls.open_files[file_path]
  if file and file_path == vis.win.file.path then
    for _, diagnostic in ipairs(diagnostics) do
      -- We convert the lsp_range to a vis_range here to do it only once.
      -- And because we can't do it during a WIN_HIGHLIGHT events because
      -- lsp_range_to_vis_range modifies the primary selection
      diagnostic.vis_range = lsp_range_to_vis_range(vis.win, diagnostic.range)
      -- Remember the content of the diagnostic to only highlight it if the content
      -- did not change
      diagnostic.content = vis.win.file:content(diagnostic.vis_range)
    end

    file.diagnostics = diagnostics

    lspc.log('remember diagnostics for ' .. file_path)
  end
end

local function ls_handle_notification(ls, notification) -- luacheck: no unused args
  local method = notification.method
  if method == 'textDocument/publishDiagnostics' then
    lspc_handle_publish_diagnostics(ls, notification.params.uri,
                                    notification.params.diagnostics)
  end
end

-- dispatch between a method call and a message response
-- for a message response we have a req remembered in the inflight table
local function ls_handle_method(ls, method)
  local req = ls.inflight[method.id]
  if req then
    ls_handle_method_response(ls, method, req)
  else
    ls_handle_method_call(ls, method)
  end
end

-- dispatch between a method call/response and a notification from the server
local function ls_handle_msg(ls, response)
  if response.id then
    ls_handle_method(ls, response)
  else
    ls_handle_notification(ls, response)
  end
end

-- Parse the data send by the language server
-- Note the chunks received may not end with the end of a message.
-- In the worst case a data chunk contains two partial messages on at the beginning
-- and one at the end
local function ls_recv_data(ls, data)
  local err = ls.parser:add(data)
  if err then
    lspc_err(err)
    return
  end

  local msgs = ls.parser:get_msgs()
  if not msgs then
    return
  end

  for _, msg in ipairs(msgs) do
    local resp = json.decode(msg)
    ls_handle_msg(ls, resp)
  end
end

-- check if a language server is running and initialized
local function lspc_get_usable_ls(syntax)
  if not syntax then
    return nil, 'No syntax provided'
  end

  local ls_name, err = get_ls_name_for_syntax(syntax)
  if err then
    return nil, err
  end

  local ls = lspc.running[ls_name]
  if not ls then
    return nil, 'No language server running for ' .. syntax
  end

  if not ls.initialized then
    return nil, 'Language server for ' .. syntax ..
               ' not initialized yet. Please try again'
  end

  return ls
end

local function lspc_close(ls, file)
  if not ls.open_files[file.path] then
    return file.path .. ' not open'
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
    return file.path .. ' already open'
  end

  local params = {
    textDocument = {
      uri = 'file://' .. file.path,
      languageId = syntax_to_languageId(win.syntax),
      version = 0,
      text = file:content(0, file.size),
    },
  }

  ls.open_files[file.path] = {file = file, version = 0, diagnostics = {}}
  ls_send_notification(ls, 'textDocument/didOpen', params)

  vis.events.subscribe(vis.events.FILE_CLOSE,
                       function(file) -- luacheck: ignore file
    for _, ls in pairs(lspc.running) do -- luacheck: ignore ls
      if ls.open_files[file.path] then
        lspc_close(ls, file)
      end
    end
  end)

  -- the server is interested in didSave notifications
  if ls.capabilities.textDocumentSync.save then
    vis.events.subscribe(vis.events.FILE_SAVE_POST,
                         function(file, path) -- luacheck: ignore file
      for _, ls in pairs(lspc.running) do -- luacheck: ignore ls
        if ls.open_files[file.path] then
          local params = {textDocument = {uri = path_to_uri(path)}} -- luacheck: ignore params
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
  local ls_conf = lspc.ls_map[syntax]
  if not ls_conf then
    return nil, 'No language server available for ' .. syntax
  end

  local exe = ls_conf.cmd:gmatch('%S+')()
  if not os.execute('type ' .. exe .. '>/dev/null 2>/dev/null') then
    -- remove the configured language server
    lspc.ls_map[syntax] = nil
    local msg = string.format(
                    'Language server for %s configured but %s not found',
                    syntax, exe)
    -- the warning will be visual if the language server was automatically startet
    -- if the user tried to start teh server manually they will see msg as error
    lspc_warn(msg)
    return nil, msg

  end

  if lspc.running[ls_conf.name] then
    return nil, 'Already a language server running for ' .. syntax
  end

  local ls = {
    name = ls_conf.name,
    initialized = false,
    id = 0,
    inflight = {},
    open_files = {},
    parser = parser.Parser(),
  }

  ls.fd = vis:communicate(ls_conf.name, ls_conf.cmd)

  lspc.running[ls_conf.name] = ls

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

      lspc.running[ls.name] = nil
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
    capabilities = client_capabilites,
  }

  ls_call_method(ls, 'initialize', params)

  return ls
end

-- generic stub implementation for all textDocument methods taking
-- a textDocumentPositionParams parameter
local function lspc_method_doc_pos(ls, method, win, argv)
  -- check if the language server has a provider for this method
  if not ls.capabilities[method .. 'Provider'] then
    return 'language server ' .. ls.name .. ' does not provide ' .. method
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

local function lspc_show_diagnostic(ls, win, line)
  if not ls.open_files[win.file.path] then
    lspc_open(ls, win, win.file)
  end

  local open_file = ls.open_files[win.file.path]

  local diagnostics = open_file.diagnostics
  if not diagnostics then
    return win.file.path .. ' has no diagnostics available'
  end

  line = line or get_selection(win).line
  lspc.log('Show diagnostics for ' .. line)
  local diagnostics_to_show = {}
  for _, diagnostic in ipairs(diagnostics) do
    local start = lsp_pos_to_vis_sel(diagnostic.range.start)
    if start.line == line then
      diagnostic.start = start
      table.insert(diagnostics_to_show, diagnostic)
    end
  end

  local diagnostics_fmt = '%d:%d %s:%s\n'
  local diagnostics_msg = ''
  for _, diagnostic in ipairs(diagnostics_to_show) do
    diagnostics_msg = diagnostics_msg ..
                          string.format(diagnostics_fmt, diagnostic.start.line,
                                        diagnostic.start.col, diagnostic.code,
                                        diagnostic.message)
  end

  if diagnostics_msg ~= '' then
    vis:message(diagnostics_msg)
  else
    lspc_warn('No diagnostics available for line: ' .. line)
  end
end

-- vis-lspc commands

vis:command_register('lspc-back', function()
  local err = vis_pop_doc_pos()
  if err then
    lspc_err(err)
  end
end)

for name, func in pairs(lspc_goto_location_methods) do
  vis:command_register('lspc-' .. name, function(argv, _, win)
    local ls, err = lspc_get_usable_ls(win.syntax)
    if err then
      lspc_err(err)
      return
    end

    -- vis cmd how to open the new location
    -- 'e' (default): in same window
    -- 'vsplit': in a vertical split window
    -- 'hsplit': in a horizontal split window
    local open_cmd = argv[1] or 'e'
    err = func(ls, win, open_cmd)
    if err then
      lspc_err(err)
    end
  end)
end

vis:command_register('lspc-hover', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  -- remember the position where hover was called
  err = lspc_method_doc_pos(ls, 'hover', win, win.selection.pos)
  if err then
    lspc_err(err)
  end
end)

vis:command_register('lspc-signature-help', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  -- remember the position where signatureHelp was called
  err = lspc_method_doc_pos(ls, 'signatureHelp', win, win.selection.pos)
  if err then
    lspc_err(err)
  end
end)

vis:command_register('lspc-rename', function(argv, _, win)
  local new_name = argv[1]
  if not new_name then
    lspc_err('lspc-rename usage: <new name>')
    return
  end

  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  -- check if the language server has a provider for this method
  if not ls.capabilities['renameProvider'] then
    lspc_err('language server ' .. ls.name .. ' does not provide rename')
    return
  end

  if not ls.open_files[win.file.path] then
    lspc_open(ls, win, win.file)
  end

  local params = vis_doc_pos_to_lsp(vis_get_doc_pos(win))
  params.newName = new_name

  ls_call_text_document_method(ls, 'rename', params, win)
end)

vis:command_register('lspc-completion', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  -- remember the position where completions were requested
  -- to apply insertText completions
  err = lspc_method_doc_pos(ls, 'completion', win, win.selection.pos)
  if err then
    lspc_err(err)
  end
end)

vis:command_register('lspc-start-server', function(argv, _, win)
  local syntax = argv[1] or win.syntax
  if not syntax then
    lspc_err('no language specified')
  end

  local _, err = ls_start_server(syntax)
  if err then
    lspc_err(err)
  end
end)

vis:command_register('lspc-shutdown-server', function(argv, _, win)
  local ls, err = lspc_get_usable_ls(argv[1] or win.syntax)
  if err then
    lspc_err('no language server running: ' .. err)
    return
  end

  ls_shutdown_server(ls)
end)

vis:command_register('lspc-close', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  lspc_close(ls, win.file)
end)

vis:command_register('lspc-open', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  lspc_open(ls, win, win.file)
end)

vis:command_register('lspc-show-diagnostics', function(argv, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  err = lspc_show_diagnostic(ls, win, argv[1])
  if err then
    lspc_err(err)
  end
end)

vis:command_register('lspc-open', function(_, _, win)
  local ls, err = lspc_get_usable_ls(win.syntax)
  if err then
    lspc_err(err)
    return
  end

  lspc_open(ls, win, win.file)
end)

-- vis-lspc event hooks

vis.events.subscribe(vis.events.WIN_OPEN, function(win)
  if lspc.autostart and win.syntax then
    ls_start_server(win.syntax)
  end

  assert(win:style_define(lspc.diagnostic_style_id, lspc.diagnostic_style))
end)

vis.events.subscribe(vis.events.WIN_HIGHLIGHT, function(win)
  local ls = lspc_get_usable_ls(win.syntax)
  if not ls then
    return
  end

  if not win.file then
    return
  end

  local open_file = ls.open_files[win.file.path]
  if open_file and open_file.diagnostics and lspc.highlight_diagnostics then
    lspc_highlight_diagnostics(win, open_file.diagnostics)
  end
end)

vis.events.subscribe(vis.events.FILE_OPEN, function(file)
  local win = vis.win
  -- the only window we can access is not our window
  if not win or win.file ~= file then
    return
  end

  local ls = lspc_get_usable_ls(win.syntax)
  if not ls then
    return
  end

  lspc_open(ls, win, file)
end)

vis:option_register('lspc-highlight-diagnostics', 'bool', function(value)
  lspc.highlight_diagnostics = value
  return true
end, 'Should lspc highlight diagnostics if available')

vis:option_register('lspc-menu-cmd', 'string', function(value)
  lspc.menu_cmd = value
  return true
end, 'External tool vis-lspc uses to present choices in a menu')

vis:option_register('lspc-confirm-cmd', 'string', function(value)
  lspc.confirm_cmd = value
  return true
end, 'External tool vis-lspc uses to ask the user for confirmation')

dofile(source_path .. 'bindings.lua')
return lspc
