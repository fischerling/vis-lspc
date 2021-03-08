.PHONY: check format check-luacheck check-format

# bash's process substitution is used for check-format
SHELL := /bin/bash

check: check-luacheck check-format

check-luacheck:
	luacheck --globals=vis -- init.lua

check-format:
	diff init.lua <(lua-format init.lua) >/dev/null

format:
	lua-format -i init.lua
