--- Simple logging module for vis-lspc.
-- @module log
-- @author Florian Fischer
-- @license GPL-3
-- @copyright 2024 Florian Fischer
local log = {}

--- Logger class metatable.
local Logger = {}
function Logger:log(msg)
  self.log_fd:write(msg)
  self.log_fd:write('\n')
  self.log_fd:flush()
end
function Logger:close()
  self.log_fd:close()
end

--- Dummy logger class metatable using NOP log functions.
local DummyLogger = {}
function DummyLogger.log()
end
function DummyLogger.close()
end

--- Logger that initialises itself on first use
local LazyInitLogger = {}
function LazyInitLogger:log(first_msg)
  self.logger = log.new(self.name, self.conf.logging, self.conf.log_file)
  self.log = function(lazyLogger, msg)
    lazyLogger.logger:log(msg)
  end
  self.logger:log(first_msg)
end
function LazyInitLogger:close()
  self.logger:close()
end

--- Create a new lazily initializing logger
--
-- The created logger will initialize itself using log.new on first use.
-- The logging and log_file fields of the conf table are passed to log.new.
-- @param name The name of the logger
-- @param conf Table containing logging and log_file members
function log.lazyNew(name, conf)
  local logger = {name = name, conf = conf}
  setmetatable(logger, {__index = LazyInitLogger})
  return logger
end

--- Create a new named logger
-- @param name The name of the logger
-- @param logging Is logging enabled
-- @param log_file File path to the log file to use
function log.new(name, logging, log_file)
  local logger = {name = name, log_fd = nil}

  if not logging then
    setmetatable(logger, {__index = DummyLogger})
    return logger
  end

  setmetatable(logger, {__index = Logger})

  -- open the default log file in $XDG_DATA_HOME/vis-lspc
  if not log_file then
    local xdg_data = os.getenv('XDG_DATA_HOME') or os.getenv('HOME') .. '/.local/share'
    local log_dir = xdg_data .. '/vis-lspc'

    -- ensure the direcoty exists
    os.execute('mkdir -p ' .. log_dir)

    -- log file format: {timestamp}-{basename-cwd}.log
    local log_file_fmt = log_dir .. '/%s-%s.log'
    local timestamp = os.date('%Y-%m-%dT%H:%M:%S')
    local proc = assert(io.popen('basename "${PWD}"', 'r'))
    local basename_cwd = assert(proc:read('*a')):match('^%s*(.-)%s*$')
    local success, _, status = proc:close()
    if not success then
      local err = 'getting the basename of CWD failed with exit code: ' .. status
      vis:info('LSPC Error: ' .. err)
    end
    log_file = log_file_fmt:format(timestamp, basename_cwd)

  elseif type(log_file) == 'function' then
    log_file = log_file()
  end

  logger.log_fd = assert(io.open(log_file, 'w'))
  return logger
end

return log
