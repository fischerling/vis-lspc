.PHONY: check format check-luacheck check-format

LUA_FILES := $(shell find -name "*.lua" -not -path "./json.lua")

# bash's process substitution is used for check-format
SHELL := /bin/bash

check: check-luacheck check-format

check-luacheck:
	luacheck --globals=vis -- $(LUA_FILES)

check-format:
	for lf in $(LUA_FILES); do diff $$lf <(lua-format $$lf) >/dev/null; done

format:
	lua-format -i $(LUA_FILES)
