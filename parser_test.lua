#!/usr/bin/env lua

local parser = require('parser')

local function build_msg(body)
  return 'Content-Length: ' .. tostring(string.len(body)) .. '\r\n\r\n' .. body
end

local lunatest = require('lunatest')

function test_complete_msg() -- luacheck: ignore 111
  local msg = build_msg('foo')
  local p = parser.Parser()
  local err = p:add(msg)
  lunatest.assert_nil(err)

  local msgs = p:get_msgs()
  lunatest.assert_table(msgs)
  lunatest.assert_len(1, msgs)
  lunatest.assert_equal(msgs[1], 'foo')
end

function test_two_complete_msgs() -- luacheck: ignore 111
  local p = parser.Parser()
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
  local p = parser.Parser()
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
  local p = parser.Parser()
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
  local p = parser.Parser()
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
  local p = parser.Parser()
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
  local p = parser.Parser()
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
