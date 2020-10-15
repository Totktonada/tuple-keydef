local ffi = require('ffi')
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
