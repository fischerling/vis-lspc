.PHONY: check format check-luacheck check-format

LUA_FILES := $(shell find -name "*.lua" -not -path "./json.lua")

TEST_FILES := $(shell find -name "*_test.lua")

check: check-luacheck check-format

check-luacheck:
	luacheck --globals=vis -- $(LUA_FILES)

check-format:
	for lf in $(LUA_FILES); do tools/check-format "$${lf}"; done

format:
	lua-format -i $(LUA_FILES)

test:
	for tf in $(TEST_FILES); do "$$tf"; done
