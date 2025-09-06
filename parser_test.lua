#!/usr/bin/env lua5.4

local parser = require('parser')

local function build_msg(body)
  return 'Content-Length: ' .. tostring(string.len(body)) .. '\r\n\r\n' .. body
end

local lunatest = require('lunatest')

-- Actual LSP message in the wild.
function test_msg_with_content_type() -- luacheck: ignore 111
  local msg = 'Content-Type: application/vscode-jsonrpc; charset=utf8\r\n' ..
                  'Content-Length: 1996\r\n\r\n' ..
                  [[{"jsonrpc":"2.0","id":0,"result":{"capabilities":{"textDocumentSync":1,"completionProvider":{"triggerCharacters":[":",">","$","[","@","(","'","\"","\\"],"resolveProvider":true},"hoverProvider":true,"signatureHelpProvider":{"triggerCharacters":["(",",","@"]},"definitionProvider":true,"typeDefinitionProvider":true,"implementationProvider":true,"referencesProvider":true,"documentHighlightProvider":true,"documentSymbolProvider":true,"codeActionProvider":{"codeActionKinds":["refactor.class.simplify","quickfix.import_class","quickfix.promote_constructor","quickfix.remove_unused_imports","quickfix.promote_constructor_public","quickfix.complete_constructor","quickfix.fill.object","quickfix.here_doc_provider","quickfix.complete_constructor_public","refactor.extract.constant","refactor.extract.method","quickfix.generate_member","quickfix.create_class","quickfix.add_missing_return_types","quickfix.add_missing_params","quickfix.add_missing_docblocks_return","quickfix.fix_namespace_class_name","refactor.extract.expression","quickfix.fill.matchArms","quickfix.correct_variable_name","quickfix.create_unresolable_class","quickfix.generate_decorator","refactor","quickfix.generate_mutators","quickfix.add_missing_properties","quickfix.implement_contracts","quickfix.add_missing_class_generic","quickfix.generate_accessors","quickfix.override_method"]},"workspaceSymbolProvider":true,"renameProvider":{"prepareProvider":true},"selectionRangeProvider":true,"executeCommandProvider":{"commands":["name_import","transform","create_class","generate_member","extract_method","replace_qualifier_with_import","extract_constant","generate_accessors","generate_mutators","import_all_unresolved_names","extract_expression","generate_decorator","override_method"]},"inlineValueProvider":true,"workspace":{"fileOperations":{"willRename":{"filters":[{"pattern":{"glob":"**\/*.php"}}]}}},"experimental":{"xevaluatableExpressionProvider":true}},"serverInfo":{"name":"phpactor\/phpactor","version":"dev-master"}}}]] -- luacheck: ignore 631

  local p = parser.new()
  local err = p:add(msg)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_not_nil(msgs[1])
end

function test_complete_msg() -- luacheck: ignore 111
  local msg = build_msg('foo')
  local p = parser.new()
  local err = p:add(msg)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
end

function test_two_complete_msgs() -- luacheck: ignore 111
  local p = parser.new()
  local data = build_msg('foo')
  local err = p:add(data)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')

  data = build_msg('bar')
  err = p:add(data)
  lunatest.assert_nil(err)
  msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'bar')
end

function test_two_complete_msgs_at_once() -- luacheck: ignore 111
  local data = build_msg('foo') .. build_msg('bar')
  local p = parser.new()
  local err = p:add(data)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(2, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
  lunatest.assert_equal(msgs[2], 'bar')
end

function test_split_msg() -- luacheck: ignore 111
  local msg = build_msg('foo')
  local part1 = msg:sub(1, -3)
  local part2 = msg:sub(-2)
  local p = parser.new()
  local err = p:add(part1)
  lunatest.assert_nil(err)

  err = p:add(part2)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
end

function test_complete_and_split_msg() -- luacheck: ignore 111
  local msg = build_msg('foo') .. build_msg('bar')
  local part1 = msg:sub(1, -3)
  local part2 = msg:sub(-2)
  local p = parser.new()
  local err = p:add(part1)
  lunatest.assert_nil(err)

  err = p:add(part2)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(2, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
  lunatest.assert_equal(msgs[2], 'bar')
end

function test_split_hdr() -- luacheck: ignore 111
  local msg = build_msg('foo')
  local part1 = msg:sub(1, 3)
  local part2 = msg:sub(4)
  local p = parser.new()
  local err = p:add(part1)
  lunatest.assert_nil(err)

  err = p:add(part2)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
end

function test_split_hdr_body_sep() -- luacheck: ignore 111
  local msg = build_msg('foo')
  local part1 = msg:sub(1, 19)
  local part2 = msg:sub(20)
  local p = parser.new()
  local err = p:add(part1)
  lunatest.assert_nil(err)

  err = p:add(part2)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
end

lunatest.run()
