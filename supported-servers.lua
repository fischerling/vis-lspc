-- Copyright (c) 2022 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- List of supported and preconfigured language server implementations
local source_str = debug.getinfo(1, 'S').source:sub(2)
local source_path = source_str:match('(.*/)')

local lspc = dofile(source_path .. 'lspc.lua')

local clangd = {name = 'clangd', cmd = 'clangd'}
local typescript = {
  name = 'typescript',
  cmd = 'typescript-language-server --stdio',
}

return {
  cpp = clangd,
  ansi_c = clangd,
  -- pylsp (python-lsp-server) language server configuration
  -- https://github.com/python-lsp/python-lsp-server
  python = {name = 'python-lsp-server', cmd = 'pylsp'},
  -- lua (lua-language-server) language server configuration
  -- https://github.com/sumneko/lua-language-server
  lua = {name = 'lua-language-server', cmd = 'lua-language-server'},
  -- typescript (typescript-language-server) language server configuration
  -- https://github.com/typescript-language-server/typescript-language-server
  javascript = typescript,
  typescript = typescript,
  -- dart language server configuration
  -- https://github.com/dart-lang/sdk/blob/master/pkg/analysis_server/tool/lsp_spec/README.md
  dart = {
    name = 'dart',
    cmd = 'dart language-server --client-id vis-lspc --client-version ' .. lspc.version,
  },
  -- haskell (haskell-language-server)
  -- https://github.com/haskell/haskell-language-server
  haskell = {name = 'haskell', cmd = 'haskell-language-server-wrapper --lsp'},

  -- ocaml (ocaml-language-server)
  -- https://github.com/ocaml/ocaml-lsp
  caml = {name = 'ocaml', cmd = 'ocamllsp'},
}
