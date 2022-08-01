-- Copyright (c) 2022 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- List of supported and preconfigured language server implementations
local clangd = {name = 'clangd', cmd = 'clangd'}

return {
  cpp = clangd,
  ansi_c = clangd,
  -- pylsp (python-lsp-server) language server configuration
  -- https://github.com/python-lsp/python-lsp-server
  python = {name = 'python-lsp-server', cmd = 'pylsp'},
  -- lua (lua-language-server) language server configuration
  -- https://github.com/sumneko/lua-language-server
  lua = {name = 'lua-language-server', cmd = 'lua-language-server'},
}
