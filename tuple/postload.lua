local ffi = require('ffi')

-- Gracefully handle hotreload. If the `tuple_keydef` is already
-- declared in FFI, then it's the hotreload case.
-- ffi.metatype() cannot be called twice on the same type.
if pcall(ffi.typeof, 'struct tuple_keydef') then
    return
end

--
-- Tarantool has built-in key_def Lua module since
-- 2.2.0-255-g22db9c264, which already calls
-- ffi.metatype() on <struct key_def>. We should use
-- another name within the external module.
ffi.cdef('struct tuple_keydef;')

local tuple_keydef = require('tuple.keydef')
local tuple_keydef_t = ffi.typeof('struct tuple_keydef')

local methods = {
    ['extract_key'] = tuple_keydef.extract_key,
    ['compare'] = tuple_keydef.compare,
    ['compare_with_key'] = tuple_keydef.compare_with_key,
    ['merge'] = tuple_keydef.merge,
    ['totable'] = tuple_keydef.totable,
    ['__serialize'] = tuple_keydef.totable,
}

ffi.metatype(tuple_keydef_t, {
    __index = function(self, key)
        return methods[key]
    end,
    __tostring = function(self) return '<struct tuple_keydef *>' end,
})
