--- Stateful parser for the data send by a language server.
-- Note the chunks received may not end with the end of a message.
-- In the worst case a data chunk contains two partial messages one
-- at the beginning and one at the end.
-- @module parser
-- @author Florian Fischer
-- @license GPL-3
-- @copyright Florian Fischer 2021-2024
local parser = {}

local Parser = {}

function parser.new()
  local self = {exp_len = nil, data = '', msgs = {}}

  setmetatable(self, {__index = Parser})
  return self
end

function Parser:add(data)
  self.data = self.data .. data

  -- we have not seen a complete header in data yet
  if not self.exp_len then
    -- search for the end of a header
    -- LSP message format: 'header\r\n\r\nbody'
    local header_end, content_start = self.data:find('\r\n\r\n')

    -- header is not complete yet -> save data and wait for more
    if not header_end then
      return
    end

    -- got a complete header
    local header = self.data:sub(1, header_end)

    -- extract content length from the header
    self.exp_len = tonumber(header:match('%d+'))
    if not self.exp_len then
      return 'invalid header in data: ' .. self.data
    end

    -- consume header from data
    self.data = self.data:sub(content_start + 1)
  end

  local data_avail = string.len(self.data)
  -- we have no complete message yet -> await more data
  if self.exp_len > data_avail then
    return
  end

  local complete_msg = self.data:sub(1, self.exp_len)
  table.insert(self.msgs, complete_msg)

  -- consume complete_msg from data
  self.data = self.data:sub(self.exp_len + 1)

  local leftover = data_avail - self.exp_len

  -- reset exp_len to search for a new header
  self.exp_len = nil

  if leftover > 0 then
    return self:add('')
  end
end

function Parser:get_msgs()
  local msgs = self.msgs
  self.msgs = {}
  return msgs
end

return parser
