-- Copyright (c) 2021 Florian Fischer. All rights reserved.
-- Use of this source code is governed by a MIT license found in the LICENSE file.
-- vis-lspc default bindings
vis:map(vis.modes.NORMAL, '<F2>', function()
  vis:command('lspc-start-server')
end, 'lspc: start lsp server')

vis:map(vis.modes.NORMAL, '<F3>', function()
  vis:command('lspc-open')
end, 'lspc: open current file')

vis:map(vis.modes.NORMAL, '<C-]>', function()
  vis:command('lspc-definition')
end, 'lspc: jump to definition')

vis:map(vis.modes.NORMAL, '<C-t>', function()
  vis:command('lspc-back')
end, 'lspc: go back position stack')

vis:map(vis.modes.NORMAL, '<C- >', function()
  vis:command('lspc-completion')
end, 'lspc: completion')

vis:map(vis.modes.INSERT, '<C- >', function()
  vis:command('lspc-completion')
  vis.mode = vis.modes.INSERT
end, 'lspc: completion')

-- bindings inspired by nvim
-- https://github.com/neovim/nvim-lspconfig
vis:map(vis.modes.NORMAL, 'gD', function()
  vis:command('lspc-declaration')
end, 'lspc: jump to declaration')

vis:map(vis.modes.NORMAL, 'gd', function()
  vis:command('lspc-definition')
end, 'lspc: jump to definition')

vis:map(vis.modes.NORMAL, 'gi', function()
  vis:command('lspc-implementation')
end, 'lspc: jump to implementation')

vis:map(vis.modes.NORMAL, 'gr', function()
  vis:command('lspc-references')
end, 'lspc: show references')

vis:map(vis.modes.NORMAL, ' D', function()
  vis:command('lspc-typeDefinition')
end, 'lspc: jump to type definition')

vis:map(vis.modes.NORMAL, ' e', function()
  vis:command('lspc-show-diagnostics')
end, 'lspc: show diagnostic of current line')

vis:map(vis.modes.NORMAL, 'K', function()
  vis:command('lspc-hover')
end, 'lspc: hover over current position')

vis:map(vis.modes.NORMAL, '<C-K>', function()
  vis:command('lspc-signature-help')
end, 'lspc: signature help')
