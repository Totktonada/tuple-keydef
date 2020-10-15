#!/usr/bin/env tarantool

-- Prefer the module from the repository.
local cur_dir = require('fio').abspath(debug.getinfo(1).source:match("@?(.*/)")
    :gsub('/%./', '/'):gsub('/+$', ''))
local soext = jit.os == 'OSX' and 'dylib' or 'so'
package.cpath = ('%s/../keydef/?.%s;%s'):format(cur_dir, soext, package.cpath)

-- {{{ Compatibility layer between different tarantool versions

local function parse_tarantool_version(component)
    local pattern = '^(%d+).(%d+).(%d+)-(%d+)-g[0-9a-f]+$'
    return tonumber((select(component, _TARANTOOL:match(pattern))))
end

local _TARANTOOL_MAJOR = parse_tarantool_version(1)
local _TARANTOOL_MINOR = parse_tarantool_version(2)
local _TARANTOOL_PATCH = parse_tarantool_version(3)
local _TARANTOOL_REV = parse_tarantool_version(4)

local function tarantool_version_at_least(major, minor, patch, rev)
    local major = major or 0
    local minor = minor or 0
    local patch = patch or 0
    local rev = rev or 0

    if _TARANTOOL_MAJOR < major then return false end
    if _TARANTOOL_MAJOR > major then return true end

    if _TARANTOOL_MINOR < minor then return false end
    if _TARANTOOL_MINOR > minor then return true end

    if _TARANTOOL_PATCH < patch then return false end
    if _TARANTOOL_PATCH > patch then return true end

    if _TARANTOOL_REV < rev then return false end
    if _TARANTOOL_REV > rev then return true end

    return true
end

-- FIXME: Check against exact version where JSON path support
-- appears.
local json_path_is_supported = tarantool_version_at_least(2)

-- }}} Compatibility layer between different tarantool versions

local tap = require('tap')
local ffi = require('ffi')
local json = require('json')
local fun = require('fun')

-- XXX fix for gh-4252: to prevent invalid trace assembling (see
-- https://github.com/LuaJIT/LuaJIT/issues/584) disable JIT for
-- <fun.chain> iterator (i.e. <chain_gen_r1>). Since the function
-- is local, the dummy chain generator is created to obtain the
-- function GC object.
jit.off(fun.chain({}).gen)

local tuple_keydef = require('keydef')

local usage_error = 'Bad params, use: tuple_keydef.new({' ..
                    '{fieldno = fieldno, type = type' ..
                    '[, is_nullable = <boolean>]' ..
                    '[, path = <string>]' ..
                    '[, collation = <string>]}, ...}'

local function coll_not_found(fieldno, collation)
    --[[ FIXME: Bring collation_id support back.
    if type(collation) == 'number' then
        return ('Wrong index options (field %d): ' ..
               'collation was not found by ID'):format(fieldno)
    end
    ]]--
    return ('Unknown collation: "%s"'):format(collation)
end

local function normalize_key_parts(parts)
    local res = {}
    for i, part in ipairs(parts) do
        res[i] = table.copy(part)
        if res[i].is_nullable == false then
            res[i].is_nullable = nil
        end
    end
    return res
end

local tuple_keydef_new_cases = {
    -- Cases to call before box.cfg{}.
    {
        'Pass no key parts',
        parts = {},
        exp_err = 'At least one key part is required',
    },
    {
        "Pass a garbage instead of key parts",
        parts = {fieldno = 1, type = 'unsigned'},
        exp_err = 'At least one key part is required',
    },
    {
        'Pass a field on an unknown type',
        parts = {{
            fieldno = 2,
            type = 'unknown',
        }},
        exp_err = 'Unknown field type: "unknown"',
    },
    --[[ FIXME: Bring collation_id support back.
    {
        'Try to use collation_id before box.cfg{}',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 2,
        }},
        exp_err = coll_not_found(1, 2),
    },
    ]]--
    {
        'Try to use collation before box.cfg{}',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation = 'unicode_ci',
        }},
        exp_err = coll_not_found(1, 'unicode_ci'),
    },
    function()
        -- For collations.
        box.cfg{}
    end,
    -- Cases to call after box.cfg{}.
    --[[ FIXME: Bring collation_id support back.
    {
        'Try to use both collation_id and collation',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 2,
            collation = 'unicode_ci',
        }},
        exp_err = 'Conflicting options: collation_id and collation',
    },
    {
        'Unknown collation_id',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 999,
        }},
        exp_err = coll_not_found(1, 999),
    },
    ]]--
    {
        'Unknown collation name',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation = 'unknown',
        }},
        exp_err = 'Unknown collation: "unknown"',
    },
    {
        'Bad parts parameter type',
        parts = 1,
        exp_err = usage_error,
    },
    {
        'No parameters',
        params = {},
        exp_err = usage_error,
    },
    {
        'Two parameters',
        params = {{}, {}},
        exp_err = usage_error,
    },
    {
        'Invalid JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[3[',
        }},
        exp_err = 'Invalid JSON path: "[3["',
        require_json_path = true,
    },
    {
        'Multikey JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[*]',
        }},
        exp_err = 'Multikey JSON path is not supported',
        require_json_path = true,
    },
    {
        'Success case; one part',
        parts = {{
            fieldno = 1,
            type = 'string',
        }},
        exp_err = nil,
    },
    {
        'Success case; one part with a JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[3]',
        }},
        exp_err = nil,
        require_json_path = true,
    },
    --
    -- gh-4519: tuple.keydef should allow the same options as
    -- <space_object>.create_index(). That is, a field number
    -- should be allowed to be specified as `field`, not only
    -- `fieldno`.
    --
    {
        'Success case; `field` is alias to `fieldno`',
        parts = {{
            field = 1,
            type = 'unsigned'
        }},
        exp_err = nil,
    },
    {
        'Field and fieldno can not be set both',
        parts = {{
            field = 1,
            fieldno = 1,
            type = 'unsigned'
        }},
        exp_err = 'Conflicting options: fieldno and field',
    }
}

local test = tap.test('tuple.keydef')

test:plan(#tuple_keydef_new_cases - 1 + 8)
for _, case in ipairs(tuple_keydef_new_cases) do
    if type(case) == 'function' then
        case()
    elseif case.require_json_path and not json_path_is_supported then
        test:skip(case[1])
    else
        local ok, res
        if case.params then
            ok, res = pcall(tuple_keydef.new, unpack(case.params))
        else
            ok, res = pcall(tuple_keydef.new, case.parts)
        end
        if case.exp_err == nil then
            ok = ok and type(res) == 'cdata' and
                ffi.istype('struct tuple_keydef', res)
            test:ok(ok, case[1])
        else
            local err = tostring(res) -- cdata -> string
            test:is_deeply({ok, err}, {false, case.exp_err}, case[1])
        end
    end
end

-- Prepare source data for test cases.

-- Case: extract_key().
test:test('extract_key()', function(test)
    test:plan(13)

    local keydef_a = tuple_keydef.new({
        {type = 'unsigned', fieldno = 1},
    })
    local keydef_b = tuple_keydef.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local keydef_c = tuple_keydef.new({
        {type = 'scalar', fieldno = 2},
        {type = 'scalar', fieldno = 1},
        {type = 'string', fieldno = 4, is_nullable = true},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    test:is_deeply(keydef_a:extract_key(tuple_a):totable(), {1}, 'case 1')
    test:is_deeply(keydef_b:extract_key(tuple_a):totable(), {1, 22}, 'case 2')

    -- JSON path.
    if json_path_is_supported then
        local res = tuple_keydef.new({
            {type = 'string', fieldno = 1, path = 'a.b'},
        }):extract_key(box.tuple.new({{a = {b = 'foo'}}})):totable()
        test:is_deeply(res, {'foo'}, 'JSON path (tuple argument)')

        local res = tuple_keydef.new({
            {type = 'string', fieldno = 1, path = 'a.b'},
        }):extract_key({{a = {b = 'foo'}}}):totable()
        test:is_deeply(res, {'foo'}, 'JSON path (table argument)')
    else
        test:skip('JSON path (tuple argument)')
        test:skip('JSON path (table argument)')
    end

    -- A key def has a **nullable** part with a field that is over
    -- a tuple size.
    --
    -- The key def options are:
    --
    -- * is_nullable = true;
    -- * has_optional_parts = true.
    test:is_deeply(keydef_c:extract_key(tuple_a):totable(), {1, 1, box.NULL},
        'short tuple with a nullable part')

    -- A key def has a **non-nullable** part with a field that is
    -- over a tuple size.
    --
    -- The key def options are:
    --
    -- * is_nullable = false;
    -- * has_optional_parts = false.
    local exp_err
    if tarantool_version_at_least(2) then
        exp_err = 'Tuple field [2] required by space format is missing'
    else
        exp_err = 'Field 2 was not found in the tuple'
    end
    local keydef = tuple_keydef.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
    })
    local ok, err = pcall(keydef.extract_key, keydef,
        box.tuple.new({'foo'}))
    test:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 1)')

    -- Same as before, but a max fieldno is over tuple:len() + 1.
    local exp_err
    if tarantool_version_at_least(2) then
        exp_err = 'Tuple field [2] required by space format is missing'
    else
        exp_err = 'Field 2 was not found in the tuple'
    end
    local keydef = tuple_keydef.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
        {type = 'string', fieldno = 3},
    })
    local ok, err = pcall(keydef.extract_key, keydef,
        box.tuple.new({'foo'}))
    test:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 2)')

    -- Same as before, but with another key def options:
    --
    -- * is_nullable = true;
    -- * has_optional_parts = false.
    local exp_err
    if tarantool_version_at_least(2) then
        exp_err = 'Tuple field [2] required by space format is missing'
    else
        exp_err = 'Field 2 was not found in the tuple'
    end
    local keydef = tuple_keydef.new({
        {type = 'string', fieldno = 1, is_nullable = true},
        {type = 'string', fieldno = 2},
    })
    local ok, err = pcall(keydef.extract_key, keydef,
        box.tuple.new({'foo'}))
    test:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 3)')

    -- A tuple has a field that does not match corresponding key
    -- part type.
    if tarantool_version_at_least(2) then
        exp_err = 'Supplied key type of part 2 does not match index ' ..
                  'part type: expected string'
    else
        exp_err = 'Tuple field 2 type does not match one required by ' ..
                  'operation: expected string'
    end
    local keydef = tuple_keydef.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
        {type = 'string', fieldno = 3},
    })
    local ok, err = pcall(keydef.extract_key, keydef, {'one', 'two', 3})
    test:is_deeply({ok, tostring(err)}, {false, exp_err},
        'wrong field type')

    if json_path_is_supported then
        local keydef = tuple_keydef.new({
            {type = 'number', fieldno = 1, path='a'},
            {type = 'number', fieldno = 1, path='b'},
            {type = 'number', fieldno = 1, path='c', is_nullable=true},
            {type = 'number', fieldno = 3, is_nullable=true},
        })
        local ok, err = pcall(keydef.extract_key, keydef,
                              box.tuple.new({1, 1, 22}))
        local exp_err = 'Tuple field [1]a required by space format is missing'
        test:is_deeply({ok, tostring(err)}, {false, exp_err},
                       'invalid JSON structure')
        test:is_deeply(keydef:extract_key({{a=1, b=2}, 1}):totable(),
                       {1, 2, box.NULL, box.NULL},
                       'tuple with optional parts - case 1')
        test:is_deeply(keydef:extract_key({{a=1, b=2, c=3}, 1}):totable(),
                       {1, 2, 3, box.NULL},
                       'tuple with optional parts - case 2')
        test:is_deeply(keydef:extract_key({{a=1, b=2}, 1, 3}):totable(),
                       {1, 2, box.NULL, 3},
                       'tuple with optional parts - case 3')
    else
        test:skip('invalid JSON structure')
        test:skip('tuple with optional parts - case 1')
        test:skip('tuple with optional parts - case 2')
        test:skip('tuple with optional parts - case 3')
    end
end)

-- Case: compare().
test:test('compare()', function(test)
    test:plan(8)

    local keydef_a = tuple_keydef.new({
        {type = 'unsigned', fieldno = 1},
    })
    local keydef_b = tuple_keydef.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local tuple_a = box.tuple.new({1, 1, 22})
    local tuple_b = box.tuple.new({2, 1, 11})
    local tuple_c = box.tuple.new({3, 1, 22})

    test:is(keydef_a:compare(tuple_b, tuple_a), 1,
            'case 1: great (tuple argument)')
    test:is(keydef_a:compare(tuple_b, tuple_c), -1,
            'case 2: less (tuple argument)')
    test:is(keydef_b:compare(tuple_b, tuple_a), -1,
            'case 3: less (tuple argument)')
    test:is(keydef_b:compare(tuple_a, tuple_c), 0,
            'case 4: equal (tuple argument)')

    test:is(keydef_a:compare(tuple_b:totable(), tuple_a:totable()), 1,
            'case 1: great (table argument)')
    test:is(keydef_a:compare(tuple_b:totable(), tuple_c:totable()), -1,
            'case 2: less (table argument)')
    test:is(keydef_b:compare(tuple_b:totable(), tuple_a:totable()), -1,
            'case 3: less (table argument)')
    test:is(keydef_b:compare(tuple_a:totable(), tuple_c:totable()), 0,
            'case 4: equal (table argument)')
end)

-- Case: compare_with_key().
test:test('compare_with_key()', function(test)
    test:plan(3)

    local keydef_b = tuple_keydef.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    local key = {1, 22}
    test:is(keydef_b:compare_with_key(tuple_a:totable(), key), 0, 'table')

    local key = box.tuple.new({1, 22})
    test:is(keydef_b:compare_with_key(tuple_a, key), 0, 'tuple')

    -- Unserializable key.
    local exp_err = "unsupported Lua type 'function'"
    local key = {function() end}
    local ok, err = pcall(keydef_b.compare_with_key, keydef_b, tuple_a, key)
    test:is_deeply({ok, tostring(err)}, {false, exp_err}, 'unserializable key')
end)

-- Case: totable().
test:test('totable()', function(test)
    test:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local keydef_a = tuple_keydef.new(parts_a)
    local keydef_b = tuple_keydef.new(parts_b)

    local exp = normalize_key_parts(parts_a)
    test:is_deeply(keydef_a:totable(), exp, 'case 1')

    local exp = normalize_key_parts(parts_b)
    test:is_deeply(keydef_b:totable(), exp, 'case 2')
end)

-- Case: __serialize().
test:test('__serialize()', function(test)
    test:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local keydef_a = tuple_keydef.new(parts_a)
    local keydef_b = tuple_keydef.new(parts_b)

    local exp = normalize_key_parts(parts_a)
    local got = json.decode(json.encode(keydef_a))
    test:is_deeply(got, exp, 'case 1')

    local exp = normalize_key_parts(parts_b)
    local got = json.decode(json.encode(keydef_b))
    test:is_deeply(got, exp, 'case 2')
end)

-- Case: tostring().
test:test('tostring()', function(test)
    test:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local keydef_a = tuple_keydef.new(parts_a)
    local keydef_b = tuple_keydef.new(parts_b)

    local exp = '<struct tuple_keydef *>'
    test:is(tostring(keydef_a), exp, 'case 1')
    test:is(tostring(keydef_b), exp, 'case 2')
end)

-- Case: merge().
test:test('merge()', function(test)
    test:plan(6)

    local keydef_a = tuple_keydef.new({
        {type = 'unsigned', fieldno = 1},
    })
    local keydef_b = tuple_keydef.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local keydef_c = tuple_keydef.new({
        {type = 'scalar', fieldno = 2},
        {type = 'scalar', fieldno = 1},
        {type = 'string', fieldno = 4, is_nullable = true},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    local keydef_ab = keydef_a:merge(keydef_b)
    local exp_parts = fun.iter(keydef_a:totable())
        :chain(fun.iter(keydef_b:totable())):totable()
    test:is_deeply(keydef_ab:totable(), exp_parts,
        'case 1: verify with :totable()')
    test:is_deeply(keydef_ab:extract_key(tuple_a):totable(), {1, 1, 22},
        'case 1: verify with :extract_key()')

    local keydef_ba = keydef_b:merge(keydef_a)
    local exp_parts = fun.iter(keydef_b:totable())
        :chain(fun.iter(keydef_a:totable())):totable()
    test:is_deeply(keydef_ba:totable(), exp_parts,
        'case 2: verify with :totable()')
    test:is_deeply(keydef_ba:extract_key(tuple_a):totable(), {1, 22, 1},
        'case 2: verify with :extract_key()')

    -- Intersecting parts + NULL parts.
    local keydef_cb = keydef_c:merge(keydef_b)
    local exp_parts = keydef_c:totable()
    exp_parts[#exp_parts + 1] = {type = 'number', fieldno = 3}
    test:is_deeply(keydef_cb:totable(), exp_parts,
        'case 3: verify with :totable()')
    test:is_deeply(keydef_cb:extract_key(tuple_a):totable(),
        {1, 1, box.NULL, 22}, 'case 3: verify with :extract_key()')
end)

test:test('JSON path is not supported error', function(test)
    test:plan(1)

    if json_path_is_supported then
        test:skip('verify error message')
        return
    end

    local parts = {
        {
            fieldno = 1,
            type = 'string',
            path = '[3]',
        },
    }
    local exp_err = 'JSON path is not supported on given tarantool version'
    local ok, err = pcall(tuple_keydef.new, parts)
    test:is_deeply({ok, tostring(err)}, {false, exp_err},
                   'verify error message')
end)

os.exit(test:check() and 0 or 1)
