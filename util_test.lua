#!/usr/bin/env lua5.4

-- mock vis global
vis = {} -- luacheck: ignore 111
local util = require('util')

local lunatest = require('lunatest')

function test_dirname() -- luacheck: ignore 111
  lunatest.assert_equal('/usr', util.dirname('/usr/lib'))
  lunatest.assert_equal('/', util.dirname('/usr/'))
  lunatest.assert_equal('.', util.dirname('usr'))
  lunatest.assert_equal('.', util.dirname('.'))
  lunatest.assert_equal('..', util.dirname('..'))
  lunatest.assert_equal('/', util.dirname('/'))
end

function test_visual_chars_in_line() -- luacheck: ignore 111
  local win = {options = {tabwidth = 4}} -- win mock
  local s = '\tfo' -- visual chars == 6
  lunatest.assert_equal(util.visual_chars_in_line(win, s, #s), 6)

  s = 'f\tfo' -- visual chars == 6
  lunatest.assert_equal(util.visual_chars_in_line(win, s, #s), 6)

  s = 'fo\tfo' -- visual chars == 6
  lunatest.assert_equal(util.visual_chars_in_line(win, s, #s), 6)

  s = 'foo\tfo' -- visual chars == 6
  lunatest.assert_equal(util.visual_chars_in_line(win, s, #s), 6)
end

function test_table_deep_copy() -- luacheck: ignore 111
  local t = {1, 2, 3, foo = {4, 5, bar = 'bar'}}
  local cpy = util.table.deep_copy(t)

  lunatest.assert_table(cpy)
  lunatest.assert_len(3, cpy)
  lunatest.assert_table(cpy.foo)
  lunatest.assert_len(2, cpy.foo)
  for i, v in ipairs(t) do
    lunatest.assert_equal(v, cpy[i])
  end

  t[2] = 12
  lunatest.assert_not_equal(t[2], cpy[2])
  t.foo[2] = 13
  lunatest.assert_not_equal(t.foo[2], cpy.foo[2])
end

function test_table_merge() -- luacheck: ignore 111
  local t = {1, 2, foo = {bar = {nose = 'nose'}}}
  local t2 = {3, foo = {4, 5, bar = {bar = 'bar'}}}
  lunatest.assert_table(t)
  lunatest.assert_table(t2)

  util.table.merge(t, t2)

  lunatest.assert_table(t)
  lunatest.assert_len(3, t)

  lunatest.assert_equal(1, t[1])
  lunatest.assert_equal(2, t[2])
  lunatest.assert_equal(3, t[3])

  lunatest.assert_table(t.foo)
  lunatest.assert_len(2, t.foo)

  lunatest.assert_equal(t[3], t2[1])
  lunatest.assert_equal(t[2], 2)

  lunatest.assert_equal(t.foo.bar.bar, 'bar')
  lunatest.assert_equal(t.foo.bar.nose, 'nose')
end

lunatest.run()
