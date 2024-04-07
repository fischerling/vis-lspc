-- Copyright (c) 2021-2023 Florian Fischer. All rights reserved.
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
  diagnostic_style_id = 64, -- 64 is the last style id available for the lexer styles. See vis/ui.h.
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

return lspc
