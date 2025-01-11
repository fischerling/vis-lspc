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

lunatest.run()
