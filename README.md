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
* `textDocument/hover`
* `textDocument/rename`
* `textDocument/formatting`
* `[Diagnostics]`

## Whats not working

Everything else.

To my knowledge there is currently no good way to detect file changes via the Lua API.
But this is essential to support [Text Synchronization](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textSynchronization) which is required by the
LSP protocol.

A dirty workaround we currently use is to send the whole file content in a `textDocument/didChange`
method call before calling any other method.
If someone can come up with an idea how to solve this I would appreciate contributions.

Communicating with language-servers via other channels than stdin/stdout.

Currently only a handful of language server are configured by default.
Their configuration can be found in [`supported_servers.lua`](https://gitlab.com/muhq/vis-lspc/-/blob/main/supported-servers.lua).

## Requirements

* vis must be compiled with the Lua [communicate API](https://github.com/martanne/vis/pull/675).
* The language server you want to use. [Microsoft's list of implementations](https://microsoft.github.io/language-server-protocol/implementors/servers/)
* Optional: the json implementation of your choice
	* must provide `encode` and `decode` methods
	* vis-lspc tries to find a suitable json implementation using those candidates:
		* json
		* cjson
		* dkjson
		* bundled fallback (no utf8 support)

## Installation

1. Clone this repository into your vis plugins directory
2. Load the plugin in your `visrc.lua` with `require('plugins/vis-lspc')`

## Easy vis-lspc installation with GuixRUs

The [GuixRUs](https://git.sr.ht/~whereiseveryone/guixrus) channel provides a fork of `vis` with the [communicate](https://github.com/martanne/vis/pull/675) API patches applied. Additionally, `vis-lspc` is bundled for convenience.

After [adding GuixRUs](https://git.sr.ht/~whereiseveryone/guixrus#permanent) to your [channels.scm](https://guix.gnu.org/manual/en/html_node/Using-a-Custom-Guix-Channel.html), run the following command to build and install `vis-lsp`:

`guix install vis-lsp`

Alternatively, you can clone GuixRUs and install from a local git checkout:

`git clone https://git.sr.ht/~whereiseveryone/guixrus`

`cd guixrus`

`guix install -L . vis-lsp`

## Usage

vis-lspc is in a early state, but if you are brave there are some default key bindings:

### Default Bindings

	Normal mode:
	<F2> - start a language server for win.syntax
	<F3> - open win.file with a running language server
	<C-]> | <gd> - jump to the definition of the symbol under the main cursor
	<gD> - jump to declaration
	<gd> - jump to definition
	<gi> - jump to implementation
	<gr> - show references
	< D> - jump to type definition
	<C-t> - go back in the jump history
	< e> - show diagnostics of current line
	<K> - hover over current position
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

	# workspace edits
	lspc-rename <new name> - rename the identifier under the cursor to <new name>
	lspc-format - format the file in the current window

	# development support
	lspc-hover - hover over the current line
	lspc-show-diagnostics - show the available diagnostics of the current line

### Available configuration options

The module table returned by `require('plugins/vis-lspc')` can be use to configure
some aspects of vis-lspc.

Available options are:

* `name = 'vis-lspc'` - the name vis-lspc introduces itself to a language server
* `logging = false` - enable logging only useful for debugging vis-lspc
* `log_file = nil` - nil, filename or function returning a filename
  * If `log_file` is `nil` vis-lspc will create a new file in `$XDG_DATA_HOME/vis-lspc`
* `autostart = true` - try to start a language server in WIN_OPEN
* `menu_cmd = 'fzf' or 'vis-menu'` - program to prompt for user choices
* `confirm_cmd = 'vis-menu'` - program to prompt for user confirmation
* `ls_map` - a table mapping vis syntax names to language server configurations
* `highlight_diagnostics = false` - highlight available diagnostics
* `diagnostic_style = 'back:#e3514f'` - style used to highlight diagnostics

#### Configure your own Language Server

If vis-lspc has no language server configuration for your desired language or server
you have to create a language server configuration and insert it into the `ls_map`
table.
Please have a look at #2 and share your configuration with everyone else.

A language server configuration is a Lua table containing a at least a `name` field
which is used to manage the language server and a `cmd` field which is used to
start the language server.

**Note:** the language server must communicate with vis-lspc via stdio.
Your language server probably supports stdio but maybe requires a [special
command line flag](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#implementationConsiderations).

Additional fields are:

* `settings` - a table of arbitrary possibly nested data. It is sent in a `workspace/didChangeConfiguration` to the language server after initialization. It is also used to lookup configuration for the `workspace/configuratio` method call.
* `init_options` - table of arbitrary possibly nested data. It is send to the server as `initializationOptions` in the parameters of the `initialize` method call.

**Example:** The language server configuration entry in the  `ls_map` for lua-language-server

```lua
ls_map.lua = {
  name = 'lua-language-server',
  cmd = 'lua-language-server',
  settings = {
    Lua = {diagnostics = {globals = {'vis'}}, telemetry = {enable = false}},
  },
},
```

Language servers configured in vis-lspc can be found in `supported_servers.lua`.

## License

All code except otherwise noted is licensed under the term of GPL-3.
See the LICENSE file for more details.
Our fallback json implementation in json.lua is NOT licensed under GPL-3.
It is taken from [here](https://gist.github.com/tylerneylon/59f4bcf316be525b30ab)
and is put into public domain by [Tyler Neylon](https://github.com/tylerneylon).
