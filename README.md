# vis-lspc - language server protocol client for the vis editor

## Whats working

vis-lspc currently supports:
* `textDocument/completion`
* `textDocument/declaration`
* `textDocument/definition`
* `textDocument/typeDefinition`
* `textDocument/implementation`

## Whats not working

Everything else.

Especially `textDocument/didChange` must be implemented before vis-lspc is somewhat usable.
To my knowledge the is currently no good way to detect file changes vis the Lua API.
But this is essential to support [Text Synchronization](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textSynchronization) which is required by the
LSP protocol.

A dirty workaround could be to send the whole file content in a `textDocument/didChange`
method call before calling any other method.
If someone can come up with an idea how to solve this I would appreciate contributions.

We never send any client capabilities.

Communicating with language-servers via other channels than stdin/stdout.

Currently only clangd is available and somewhat tested.

There should be a mapping between vis syntax/lexer names and LSP [languageId](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentItem).
For example the syntax for C code in vis is called 'ansi_c' and in LSP 'c'.

## Usage

Note that till `textDocument/didChange` is implemented vis-lspc is hardly usable.
But if you are brave there are some default key bindings:

	Normal mode:
	<F2> - start a language server for win.syntax
	<F3> - open win.file with a running language server
	<C-]> - jump to the definition of the symbol under the main cursor
	<C-t> - go back in the jump history
	Normal and Insert mode:
	<C- > - get completions

## Requirements

* vis must be compiled with the Lua [communicate API](https://github.com/martanne/vis/pull/675).
* Optional: the json implementation of your choice
	* must be usable by calling `require('json')`
	* must provide `json.encode, json.decode`

## Installation

1. Clone this repository into your vis plugins directory
2. Load the plugin in your `visrc.lua` with `require('plugins/vis-lspc')`

## License

All code except otherwise noted is licensed under the term of GPL-3.
See the LICENSE file for more details.
Our fallback json implementation in json.lua is NOT licensed under GPL-3.
It is taken from [here](https://gist.github.com/tylerneylon/59f4bcf316be525b30ab)
and is put into public domain by [Tyler Neylon](https://github.com/tylerneylon).
