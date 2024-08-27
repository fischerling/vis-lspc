--- State and methods of the language server client.
-- This module table is returned when requiring the vis-lspc plugin.
-- @module lspc
-- @author Florian Fischer
-- @license GPL-3
-- @copyright Florian Fischer 2021-2024
--- Initial state of the client.
-- This includes the default configuration that can be modified in
-- your visrc.lua file.
local lspc = {
  -- mapping language server names to their state tables
  running = {},
  open_files = {},
  name = 'vis-lspc',
  version = '0.1.8',
  -- write log messages to lspc.log_file
  logging = false,
  log_file = nil,
  -- automatically start a language server when a new window is opened
  autostart = true,
  -- program used to let the user make choices
  -- The available choices are pass to <menu_cmd> on stdin separated by '\n'
  menu_cmd = 'vis-menu -l 10',
  -- program used to ask the user for confirmation
  confirm_cmd = 'vis-menu',

  -- should diagnostics be highlighted if available
  highlight_diagnostics = 'line',
  -- style id used by lspc to register the style used to highlight diagnostics
  -- by default win.STYLE_LEXER_MAX is used (the last style id available for the lexer styles). See vis/ui.h.
  diagnostic_style_id = nil,
  -- styles used by lspc to highlight the diagnostic range
  -- must be set by the user
  diagnostic_styles = {
    error = 'fore:red,italics,reverse',
    warning = 'fore:yellow,italics,reverse',
    information = 'fore:yellow,italics,reverse',
    hint = 'fore:yellow,italics,reverse',
  },

  -- restore the position of the primary curser after applying a workspace edit
  workspace_edit_remember_cursor = true,

  -- message level to show in the UI when receiving messages from the server
  -- Error = 1, Warning = 2, Info = 3, Log = 4
  message_level = 3,

  -- How to present messages to the user.
  -- 'message': use vis:message; 'open': use a new split window allowing for syntax highlighting
  show_message = 'message',

  -- events
  events = {
    LS_INITIALIZED = 'LspcEvent::LS_INITIALIZED',
    LS_DID_OPEN = 'LspcEvent::LS_DID_OPEN',
  },
}

-- check if fzf is available and use fzf instead of vis-menu per default
if os.execute('type fzf >/dev/null 2>/dev/null') then
  lspc.menu_cmd = 'fzf'
end

local supported_markup_kind = {'markdown'}

local goto_methods_capabilities = {
  linkSupport = true,
  dynamicRegistration = false,
}

--- ClientCapabilities we tell the language server when calling "initialize".
local client_capabilites = {
  workspace = {
    configuration = true,
    didChangeConfiguration = {dynamicRegistration = false},
  },
  textDocument = {
    synchronization = {dynamicRegistration = false, didSave = true},
    -- ask the server to send us only markdown completionItems
    completion = {
      dynamicRegistration = false,
      completionItem = {documentationFormat = supported_markup_kind},
    },
    -- ask the server to send us only markdown hover results
    hover = {dynamicRegistration = false, contentFormat = supported_markup_kind},
    -- ask the server to send us only markdown signatureHelp results
    signatureHelp = {
      dynamicRegistration = false,
      signatureInformation = {documentationFormat = supported_markup_kind},
    },
    declaration = {dynamicRegistration = false, linkSupport = true},
    definition = goto_methods_capabilities,
    publishDiagnostics = {relatedInformation = false},
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

lspc.client_capabilites = client_capabilites

local Lspc = {}

--- Log a message.
-- @string: the message to log
function Lspc:log(msg)
  self.logger:log(msg)
end

--- Present a warning to the user.
-- @string: the warning message
function Lspc:warn(msg)
  local warning = 'LSPC Warning: ' .. msg
  self.logger:log(warning)
  vis:info(warning)
end

--- Present an error to the user.
-- @string: the error message
function Lspc:err(msg)
  local warning = 'LSPC Error: ' .. msg
  self.logger:log(warning)
  vis:info(warning)
end

setmetatable(lspc, {__index = Lspc})

return lspc
