#!/usr/bin/env tarantool

local tap = require('tap')
local ffi = require('ffi')

-- Presence of the methods confirms that correct metatype is set
-- for the <struct tuple_keydef> ctype.
--
-- Here we don't verify how the methods work.
local function test_instance_methods_presence(test, tuple_keydef)
        local methods = {
            'extract_key',
            'compare',
            'compare_with_key',
            'merge',
            'totable',
            '__serialize',
        }
        test:plan(#methods)

        local kd = tuple_keydef.new({{fieldno = 1, type = 'unsigned'}})
        for _, m in ipairs(methods) do
            test:ok(kd[m] ~= nil, ('%s is present'):format(m))
        end
end

-- gh-9: verify hot reload.
--
-- https://github.com/tarantool/tuple-keydef/issues/9
local test = tap.test('hot reload')

test:plan(3)

-- Verify the case, when <struct tuple_keydef> is declared via
-- LuaJIT's FFI before a first load of the module.
--
-- This case looks strange on the first glance, but someone may
-- declare <struct tuple_keydef> to use ffi.istype(). So it may
-- be the valid usage.
--
-- Important: keep this test case first, don't require the module
-- before it (otherwise it'll not test anything).
test:test('declared_ctype', function(test)
    test:plan(4)

    -- Declare the ctype before first loading of the module.
    ffi.cdef('struct tuple_keydef')

    -- Verify the first load.
    local ok, tuple_keydef = pcall(require, 'tuple.keydef')
    test:ok(ok, 'first load succeeds')
    test:test('methods presense', test_instance_methods_presence, tuple_keydef)

    -- Verify reload just in case.
    package.loaded['tuple.keydef'] = nil
    local ok, tuple_keydef = pcall(require, 'tuple.keydef')
    test:ok(ok, 'reload succeeds')
    test:test('methods presense', test_instance_methods_presence, tuple_keydef)
end)

-- Verify the case, when there are alive links to the previous
-- module table.
test:test('hot_reload_keep_old_table', function(test)
    test:plan(3)

    -- Reload.
    local tuple_keydef_old = require('tuple.keydef')
    package.loaded['tuple.keydef'] = nil
    local ok, tuple_keydef_new = pcall(require, 'tuple.keydef')

    -- Verify.
    --
    -- It does not matter, whether the module table is the same or
    -- a new one.
    test:ok(ok, 'reload succeeds')
    test:istable(tuple_keydef_new, 'the module is a table (just in case)')

    -- Fake usage of tuple_keydef_old. Just to hide it from
    -- LuaJIT's optimizer. I don't know whether it may eliminate
    -- the variable in this particular case (without the fake
    -- usage). But in some cases the optimizer is powerful enough:
    --
    -- https://gist.github.com/mejedi/d61752c5fd582d2507360d375513c6b8
    test:istable(tuple_keydef_old, 'fake usage of the old module table')
end)

-- Collect the old module table before load the module again.
test:test('hot_reload_after_gc', function(test)
    test:plan(4)

    require('tuple.keydef')

    -- Forget all links to the module table.
    --
    -- rawset() is to don't be hit by the 'strict mode'. When
    -- tarantool is built as Debug, it behaves like after
    -- `require('strict').on()` by default.
    rawset(_G, 'tuple', nil)
    package.loaded['tuple.keydef'] = nil

    -- Ensure the module table is garbage collected.
    --
    -- There is opinion that collectgarbage() should be called
    -- twice to actually collect everything.
    --
    -- https://stackoverflow.com/a/28320364/1598057
    collectgarbage()
    collectgarbage()

    local ok, tuple_keydef = pcall(require, 'tuple.keydef')
    test:ok(ok, 'reload succeeds')
    test:istable(tuple_keydef, 'the module is a table (just in case)')
    test:istable(_G.tuple, '_G.tuple is present')
    test:istable(_G.tuple.keydef, '_G.tuple.keydef is present')
end)

os.exit(test:check() and 0 or 1)
