# vis-lspc

A language server protocol client for the [vis editor](https://github.com/martanne/vis).

## Whats working

vis-lspc currently supports:
* `textDocument/completion`
* `textDocument/declaration`
* `textDocument/definition`
* `textDocument/references`
* `textDocument/typeDefinition`
* `textDocument/implementation`
* `[Diagnostics]`

## Whats not working

Everything else.

To my knowledge there is currently no good way to detect file changes via the Lua API.
But this is essential to support [Text Synchronization](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textSynchronization) which is required by the
LSP protocol.

A dirty workaround we currently use is to send the whole file content in a `textDocument/didChange`
method call before calling any other method.
If someone can come up with an idea how to solve this I would appreciate contributions.

We never send any client capabilities.

Communicating with language-servers via other channels than stdin/stdout.

Currently only clangd and pyls are configured by default and somewhat tested.

## Requirements

* vis must be compiled with the Lua [communicate API](https://github.com/martanne/vis/pull/675).
* The language server you want to use. [Microsoft's list of implementations](https://microsoft.github.io/language-server-protocol/implementors/servers/)
* Optional: the json implementation of your choice
	* must be usable by calling `require('json')`
	* must provide `json.encode, json.decode`

## Installation

1. Clone this repository into your vis plugins directory
2. Load the plugin in your `visrc.lua` with `require('plugins/vis-lspc')`

## Usage

vis-lspc is in a early state, but if you are brave there are some default key bindings:

### Default Bindings

	Normal mode:
	<F2> - start a language server for win.syntax
	<F3> - open win.file with a running language server
	<C-]> - jump to the definition of the symbol under the main cursor
	<C-t> - go back in the jump history
	Normal and Insert mode:
	<C- > - get completions


### Available commands

	# language-server management:
	lspc-start-server [syntax] - start a language server for syntax or win.syntax
	lspc-stop-server [syntax] - stop the language server for syntax or win.syntax

	# file registration:
	lspc-open - register the file in the current window
	lspc-close - unregister the file in the current window

	# navigation commands (they all operate on the symbol under the main cursor):
	lspc-completion - syntax completion
	lspc-references [e | vsplit | hsplit] - select and open a reference
	lspc-declaration [e | vsplit | hsplit] - select and open a declaration
	lspc-definition [e | vsplit | hsplit] - open the definition
	lspc-typeDeclaration [e | vsplit | hsplit] - select and open a type declaration
	lspc-implementation [e | vsplit | hsplit] - I actually have no idea what this does

	lspc-back - navigate back in the goto history

### Available configuration fields

The module table returned by `require('plugins/vis-lspc')` can be use to configure
some aspects of vis-lspc.

Available fields are:

* `name = 'vis-lspc'` - the name vis-lspc introduces itself to a language server
* `logging = false` - enable logging only useful for debugging vis-lspc
* `log_file = 'vis-lspc.log'` - file vis-lspc writes all log messages to
* `autostart = true` - try to start a language server in WIN_OPEN
* `menu_cmd = 'fzf' or 'vis-menu'` - program to prompt for user choices
* `ls_map` - a table mapping vis syntax names to language server configurations

#### Configure your own Language Server

If vis-lspc has no language server configuration for your desired language or server
you have to create a language server configuration and insert it into the `ls_map`
table.
Please have a look at #2 and share your configuration with everyone else.

A language server configuration is a Lua table containing a `name` field which is
used to manage the language server.
And a `cmd` field which is used to start the language server.

**Note:** the language server must communicate with vis-lspc via stdio.
Your language server probably supports stdio but maybe requires a [special
command line flag](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#implementationConsiderations).

**Example:** The language server configuration for clangd and its entries in `ls_map`

	-- clangd language server configuration
	local clangd = {name = 'clangd', cmd = 'clangd'}

	-- map of known language servers per syntax
	lspc.ls_map = {cpp = clangd, ansi_c = clangd}

## License

All code except otherwise noted is licensed under the term of GPL-3.
See the LICENSE file for more details.
Our fallback json implementation in json.lua is NOT licensed under GPL-3.
It is taken from [here](https://gist.github.com/tylerneylon/59f4bcf316be525b30ab)
and is put into public domain by [Tyler Neylon](https://github.com/tylerneylon).
