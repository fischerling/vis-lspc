-- Copyright (c) 2021 Florian Fischer. All rights reserved.
--
-- This file is part of vis-lspc.
--
-- vis-lspc is free software: you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later
-- version.
--
-- vis-lspc is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
-- FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- vis-lspc found in the LICENSE file. If not, see <https://www.gnu.org/licenses/>.
--
-- Parse the data send by a language server
-- Note the chunks received may not end with the end of a message.
-- In the worst case a data chunk contains two partial messages on at the beginning
-- and one at the end
local function add(p, data)
  p.data = p.data .. data

  -- we have not seen a complete header in data yet
  if not p.exp_len then
    -- search for the end of a header
    -- LSP message format: 'header\r\n\r\nbody'
    local header_end, content_start = p.data:find('\r\n\r\n')

    -- header is not complete yet -> save data and wait for more
    if not header_end then
      return
    end

    -- got a complete header
    local header = p.data:sub(1, header_end)

    -- extract content length from the header
    p.exp_len = tonumber(header:match('%d+'))
    if not p.exp_len then
      return 'invalid header in data: ' .. p.data
    end

    -- consume header from data
    p.data = p.data:sub(content_start + 1)
  end

  local data_avail = string.len(p.data)
  -- we have no complete message yet -> await more data
  if p.exp_len > data_avail then
    return
  end

  local complete_msg = p.data:sub(1, p.exp_len)
  table.insert(p.msgs, complete_msg)

  -- consume complete_msg from data
  p.data = p.data:sub(p.exp_len + 1)

  local leftover = data_avail - p.exp_len

  -- reset exp_len to search for a new header
  p.exp_len = nil

  if leftover > 0 then
    return p:add('')
  end
end

local function get_msgs(p)
  local msgs = p.msgs
  p.msgs = {}
  return msgs
end

local function Parser()
  local parser = {
    add = add,
    get_msgs = get_msgs,
    exp_len = nil,
    data = '',
    msgs = {},
  }
  return parser
end

return {Parser = Parser}
