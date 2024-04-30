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

--
--- ClientCapabilities we tell the language server when calling "initialize"
--
local supported_markup_kind = {'markdown'}

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

return lspc
