-- Copyright (c) 2021-2023 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- State of our language server client
local lspc = {
  -- mapping language server names to their state tables
  running = {},
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
  highlight_diagnostics = false,
  -- style id used by lspc to register the style used to highlight diagnostics
  diagnostic_style_id = 43,
  -- style used by lspc to highlight the diagnostic range
  -- 60% solarized red
  diagnostic_style = 'back:#e3514f',

  -- message level to show in the UI when receiving messages from the server
  -- Error = 1, Warning = 2, Info = 3, Log = 4
  message_level = 3,
}

--
--- ClientCapabilities we tell the language server when calling "initialize"
--
local supported_markup_kind = {'plaintext'}

local goto_methods_capabilities = {
  linkSupport = true,
  dynamicRegistration = false,
}

local client_capabilites = {
  workspace = {
    configuration = true,
    didChangeConfiguration = {dynamicRegistration = false},
  },
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

lspc.client_capabilites = client_capabilites

return lspc
