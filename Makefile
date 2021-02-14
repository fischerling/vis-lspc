.PHONY: check format

check:
	luacheck --globals=vis -- init.lua

format:
	lua-format -i init.lua
