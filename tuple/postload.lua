-- This script is NOT a regular module file.
--
-- It is bundled into the .so / .dylib file.
--
-- It is executed only on the first load of the module.
--
-- It is NOT executed after hot reload (when the package.loaded
-- entry is removed and require is called once again).
--
-- The tuple.keydef module table is accessible as `...`.

local ffi = require('ffi')
local tuple_keydef = ...
local tuple_keydef_t = ffi.typeof('struct tuple_keydef')

local methods = {
    ['extract_key'] = tuple_keydef.extract_key,
    ['compare'] = tuple_keydef.compare,
    ['compare_with_key'] = tuple_keydef.compare_with_key,
    ['merge'] = tuple_keydef.merge,
    ['totable'] = tuple_keydef.totable,
    ['__serialize'] = tuple_keydef.totable,
}

-- ffi.metatype() succeeds only when called the first time.
-- Next calls on the same type will raise 'cannot change a
-- protected metatable' error.
ffi.metatype(tuple_keydef_t, {
    __index = function(self, key)
        return methods[key]
    end,
    __tostring = function(self) return '<struct tuple_keydef *>' end,
})
