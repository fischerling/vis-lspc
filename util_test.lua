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

lunatest.run()
