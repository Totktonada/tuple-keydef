/*
 * Copyright 2010-2020, Tarantool AUTHORS, please see AUTHORS file.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <assert.h>
#include <stdint.h>
#include <lua.h>
#include <lauxlib.h>
#include <tarantool/module.h>
#include "util.h"

/*
 * Verify that <box_key_part_def_t> has the same size when
 * compiled within tarantool and within the module.
 *
 * It is important, because the module allocates an array of key
 * parts and passes it to <box_key_def_new_ex>() tarantool
 * function.
 */
static_assert(sizeof(box_key_part_def_t) == BOX_KEY_PART_DEF_T_SIZE,
	      "sizeof(box_key_part_def_t)");

enum { TUPLE_INDEX_BASE = 1 };

static uint32_t CTID_STRUCT_KEY_DEF_REF = 0;
static bool JSON_PATH_IS_SUPPORTED = false;

/*
 * Buffer for the part of the module written in Lua.
 *
 * Note: It is prefixed with the project name to don't clash with
 * tarantool symbol.
 */
extern char key_def_key_def_lua[];

/* {{{ Helpers */

void
execute_key_def_lua(struct lua_State *L)
{
	int top = lua_gettop(L);

	const char *modname = "key_def";
	const char *modsrc = key_def_key_def_lua;
	const char *modfile = "@key_def/key_def.lua";

	if (luaL_loadbuffer(L, modsrc, strlen(modsrc), modfile) != 0)
		luaL_error(L, "Unable to load @key_def/key_def.lua");
	lua_pushstring(L, modname);
	lua_call(L, 1, 1);

	/* Ignore Lua return value. */
	lua_settop(L, top);
}

/**
 * part->path accessors.
 *
 * <box_key_part_def_t> on 1.10 does not have 'path' field, but
 * it is convenient to provide ability to build the module using
 * tarantool-1.10 headers.
 *
 * This hack assumes that pointers are 64 bit.
 */
#define JSON_PATH_PTR(part_ptr) ((const char **)((char *)(part_ptr) + 24))
#define JSON_PATH(part_ptr) (*JSON_PATH_PTR(part_ptr))
#define JSON_PATH_SET(part_ptr, value) do {		\
	const char **p = JSON_PATH_PTR(part_ptr);	\
	*p = (value);					\
} while(0)

/**
 * MULTIKEY_NONE contant is not provided by tarantool-1.10
 * headers, so we define our own.
 */
enum { KEY_DEF_MULTIKEY_NONE = -1 };

const char *field_type_blacklist[] = {
	"any",
	"array",
	"map",
	"*",     /* alias for 'any' */
};

/**
 * Whether a field type is supported by the module.
 *
 * It uses a black list to report an unsupported field type:
 * an unknown field type will be reported as supported.
 *
 * FIXME: Such blacklisting on the module side should be taken
 * as a temporary solution. Future implementation should lean on
 * tarantool provided information regarding supported key_def
 * actions: whether particular key_def / key_def_part can be used
 * to compare a tuple with a tuple / a key, to extract a key from
 * a tuple.
 */
static bool
field_type_is_supported(const char *field_type, size_t len)
{
	int max = lengthof(field_type_blacklist);
	int rc = strnindex(field_type_blacklist, field_type, len, max);
	return rc == max;
}

/**
 * Whether a JSON path is 'multikey path'.
 *
 * The function may be used on an invalid JSON path and may
 * report such path either as 'multikey path' or the opposite.
 *
 * FIXME: Future implementation should support 'multikey path'
 * key_defs, so it would not be worthful to expose relevant
 * functions from tarantool (and take care of backward
 * compatibility). Tarantool side limitations around such key_defs
 * should be reflected in the module API: whether it is possible
 * to do <...> using particular key_def.
 */
static bool
json_path_is_multikey(const char *path)
{
	return strstr(path, "[*]") != NULL;
}

/**
 * Runtime check whether JSON path is supported.
 */
static bool
json_path_is_supported(void)
{
	bool res = false;

	/* Create a key_def with JSON path. */
	box_key_part_def_t part;
	box_key_part_def_create(&part);
	part.fieldno = 0;
	part.field_type = "unsigned";
	JSON_PATH_SET(&part, "[1]");
	box_key_def_t *key_def = box_key_def_new_ex(&part, 1);

	/* Dump parts and look whether JSON path is dumped. */
	size_t region_svp = box_region_used();
	uint32_t part_count = 0;
	box_key_part_def_t *parts = box_key_def_dump_parts(key_def,
							   &part_count);
	assert(parts != NULL);
	res = JSON_PATH(&parts[0]) != NULL;
	box_region_truncate(region_svp);

	/* Delete the key_def. */
	box_key_def_delete(key_def);

	return res;
}

#define DIAG_SET_ER_ILLEGAL_PARAMS(...) do {			\
	box_error_set(__FILE__, __LINE__, ER_ILLEGAL_PARAMS,	\
		      ##__VA_ARGS__);				\
} while (0)

#define DIAG_SET_ER_MEMORY_ISSUE(...) do {				\
	box_error_set(__FILE__, __LINE__, ER_MEMORY_ISSUE,		\
		      "Failed to allocate %u bytes in %s for %s",	\
		      ##__VA_ARGS__);					\
} while (0)

#define diag_set(box_error_code, ...) do {	\
	DIAG_SET_##box_error_code(__VA_ARGS__);	\
} while(0)

/* }}} Helpers */

static void
luaT_key_def_to_table(struct lua_State *L, const box_key_def_t *key_def)
{
	size_t region_svp = box_region_used();
	uint32_t part_count = 0;
	box_key_part_def_t *parts = box_key_def_dump_parts(key_def,
							   &part_count);
	if (parts == NULL)
		luaT_error(L);

	lua_createtable(L, part_count, 0);
	for (uint32_t i = 0; i < part_count; ++i) {
		box_key_part_def_t *part = &parts[i];
		lua_newtable(L);

		lua_pushnumber(L, part->fieldno + TUPLE_INDEX_BASE);
		lua_setfield(L, -2, "fieldno");

		lua_pushstring(L, part->field_type);
		lua_setfield(L, -2, "type");

		bool is_nullable = (part->flags &
			BOX_KEY_PART_DEF_IS_NULLABLE_MASK) ==
			BOX_KEY_PART_DEF_IS_NULLABLE_MASK;
		if (is_nullable) {
			lua_pushboolean(L, is_nullable);
			lua_setfield(L, -2, "is_nullable");
		}

		if (part->collation != NULL) {
			lua_pushstring(L, part->collation);
			lua_setfield(L, -2, "collation");
		}

		if (JSON_PATH(part) != NULL) {
			lua_pushstring(L, JSON_PATH(part));
			lua_setfield(L, -2, "path");
		}

		lua_rawseti(L, -2, i + 1);
	}

	box_region_truncate(region_svp);
}

/**
 * Set key_part_def from a table on top of a Lua stack.
 *
 * A temporary storage for a JSON path is allocated on the box
 * region when it is necessary.
 *
 * When successful return 0, otherwise return -1 and set a diag.
 */
static int
luaT_key_def_set_part(struct lua_State *L, box_key_part_def_t *part)
{
	box_key_part_def_create(part);

	/* FIXME: Verify Lua type of each field. */

	/* Set part->fieldno. */
	lua_getfield(L, -1, "fieldno");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		/*
		 * 'field' is an alias for fieldno to support the
		 * same parts format as is used in
		 * <space_object>.create_index() in Lua.
		 */
		lua_getfield(L, -1, "field");
		if (lua_isnil(L, -1)) {
			diag_set(ER_ILLEGAL_PARAMS,
				 "fieldno or field must not be nil");
			return -1;
		}
	} else {
		lua_getfield(L, -2, "field");
		if (! lua_isnil(L, -1)) {
			diag_set(ER_ILLEGAL_PARAMS,
				 "Conflicting options: fieldno and field");
			return -1;
		}
		lua_pop(L, 1);
	}
	/*
	 * Transform one-based Lua fieldno to zero-based
	 * fieldno to use in box_key_def_new_ex().
	 */
	part->fieldno = lua_tointeger(L, -1) - TUPLE_INDEX_BASE;
	lua_pop(L, 1);

	/* Set part->type. */
	lua_getfield(L, -1, "type");
	if (lua_isnil(L, -1)) {
		diag_set(ER_ILLEGAL_PARAMS, "type must not be nil");
		return -1;
	}
	size_t field_type_len;
	part->field_type = lua_tolstring(L, -1, &field_type_len);
	lua_pop(L, 1);

	/*
	 * Verify field type.
	 *
	 * There are no comparators for 'any', 'array', 'map'
	 * fields in tarantool, so creation of such key_def have
	 * no practical application.
	 *
	 * FIXME: In future implementation we should obtain
	 * information about comparators and key extractors
	 * availability using the module API. See also
	 * <field_type_is_supported>().
	 */
	if (! field_type_is_supported(part->field_type, field_type_len)) {
		diag_set(ER_ILLEGAL_PARAMS, "Unsupported field type: %s",
			 part->field_type);
		return -1;
	}

	/* Set part->is_nullable. */
	lua_getfield(L, -1, "is_nullable");
	if (! lua_isnil(L, -1) && lua_toboolean(L, -1) != 0)
		part->flags |= BOX_KEY_PART_DEF_IS_NULLABLE_MASK;
	lua_pop(L, 1);

	/* FIXME: Bring back collation_id support. */

	/* Set part->collation. */
	lua_getfield(L, -1, "collation");
	if (! lua_isnil(L, -1))
		part->collation = lua_tostring(L, -1);
	lua_pop(L, 1);

	/* Set part->path (JSON path). */
	lua_getfield(L, -1, "path");
	if (! lua_isnil(L, -1)) {
		if (! JSON_PATH_IS_SUPPORTED) {
			diag_set(ER_ILLEGAL_PARAMS, "JSON path is not "
				 "supported on given tarantool version");
			return -1;
		}
		size_t path_len;
		const char *path = lua_tolstring(L, -1, &path_len);

		/*
		 * JSON path will be validated in
		 * box_key_def_new_ex().
		 */

		if (json_path_is_multikey(path)) {
			diag_set(ER_ILLEGAL_PARAMS,
				 "Multikey JSON path is not supported");
			return -1;
		}

		/*
		 * FIXME: Revisit this part and think whether we
		 * actually need to copy JSON paths.
		 */
		char *tmp = box_region_alloc(path_len + 1);
		if (tmp == NULL) {
			diag_set(ER_MEMORY_ISSUE, path_len + 1, "box_region",
				 "path");
			return -1;
		}
		/*
		 * lua_tolstring() guarantees that a string have
		 * trailing '\0'.
		 */
		memcpy(tmp, path, path_len + 1);
		JSON_PATH_SET(part, tmp);
	}
	lua_pop(L, 1);

	return 0;
}

/**
 * Check an existent tuple pointer in Lua stack by specified
 * index or attempt to construct it by Lua table.
 * Increase tuple's reference counter.
 * Returns not NULL tuple pointer on success, NULL otherwise.
 */
static struct tuple *
luaT_key_def_check_tuple(struct lua_State *L, box_key_def_t *key_def, int idx)
{
	struct tuple *tuple = luaT_istuple(L, idx);
	if (tuple == NULL)
		tuple = luaT_tuple_new(L, idx, box_tuple_format_default());
	if (tuple == NULL || box_tuple_validate_key_parts(key_def, tuple) != 0)
		return NULL;
	box_tuple_ref(tuple);
	return tuple;
}

static box_key_def_t *
luaT_check_key_def(struct lua_State *L, int idx)
{
	if (! luaL_iscdata(L, idx))
		return NULL;

	uint32_t cdata_type;
	box_key_def_t **key_def_ptr = luaL_checkcdata(L, idx, &cdata_type);
	if (key_def_ptr == NULL || cdata_type != CTID_STRUCT_KEY_DEF_REF)
		return NULL;
	return *key_def_ptr;
}

/**
 * Free a key_def from a Lua code.
 */
static int
lbox_key_def_gc(struct lua_State *L)
{
	box_key_def_t *key_def = luaT_check_key_def(L, 1);
	assert(key_def != NULL);
	box_key_def_delete(key_def);
	return 0;
}

/**
 * Extract key from tuple by given key definition and return
 * tuple representing this key.
 * Push the new key tuple as cdata to a Lua stack on success.
 * Raise error otherwise.
 */
static int
lbox_key_def_extract_key(struct lua_State *L)
{
	box_key_def_t *key_def;
	if (lua_gettop(L) != 2 || (key_def = luaT_check_key_def(L, 1)) == NULL)
		return luaL_error(L, "Usage: key_def:extract_key(tuple)");

	struct tuple *tuple;
	if ((tuple = luaT_key_def_check_tuple(L, key_def, 2)) == NULL)
		return luaT_error(L);

	size_t region_svp = box_region_used();
	uint32_t key_size;
	char *key = box_tuple_extract_key_ex(tuple, key_def,
					     KEY_DEF_MULTIKEY_NONE, &key_size);
	box_tuple_unref(tuple);
	if (key == NULL)
		return luaT_error(L);

	struct tuple *ret =
		box_tuple_new(box_tuple_format_default(), key, key + key_size);
	box_region_truncate(region_svp);
	if (ret == NULL)
		return luaT_error(L);
	luaT_pushtuple(L, ret);
	return 1;
}

/**
 * Compare tuples using the key definition.
 * Push 0  if key_fields(tuple_a) == key_fields(tuple_b)
 *      <0 if key_fields(tuple_a) < key_fields(tuple_b)
 *      >0 if key_fields(tuple_a) > key_fields(tuple_b)
 * integer to a Lua stack on success.
 * Raise error otherwise.
 */
static int
lbox_key_def_compare(struct lua_State *L)
{
	box_key_def_t *key_def;
	if (lua_gettop(L) != 3 ||
	    (key_def = luaT_check_key_def(L, 1)) == NULL) {
		return luaL_error(L, "Usage: key_def:"
				     "compare(tuple_a, tuple_b)");
	}

	struct tuple *tuple_a, *tuple_b;
	if ((tuple_a = luaT_key_def_check_tuple(L, key_def, 2)) == NULL)
		return luaT_error(L);
	if ((tuple_b = luaT_key_def_check_tuple(L, key_def, 3)) == NULL) {
		box_tuple_unref(tuple_a);
		return luaT_error(L);
	}

	int rc = box_tuple_compare(tuple_a, tuple_b, key_def);
	box_tuple_unref(tuple_a);
	box_tuple_unref(tuple_b);
	lua_pushinteger(L, rc);
	return 1;
}

/**
 * Compare tuple with key using the key definition.
 * Push 0  if key_fields(tuple) == parts(key)
 *      <0 if key_fields(tuple) < parts(key)
 *      >0 if key_fields(tuple) > parts(key)
 * integer to a Lua stack on success.
 * Raise error otherwise.
 */
static int
lbox_key_def_compare_with_key(struct lua_State *L)
{
	box_key_def_t *key_def;
	if (lua_gettop(L) != 3 ||
	    (key_def = luaT_check_key_def(L, 1)) == NULL) {
		return luaL_error(L, "Usage: key_def:"
				     "compare_with_key(tuple, key)");
	}

	struct tuple *tuple = luaT_key_def_check_tuple(L, key_def, 2);
	if (tuple == NULL)
		return luaT_error(L);

	size_t region_svp = box_region_used();
	const char *key = luaT_tuple_encode(L, 3, NULL);
	if (key == NULL) {
		box_region_truncate(region_svp);
		box_tuple_unref(tuple);
		return luaT_error(L);
	}

	if (box_key_def_validate_key(key_def, key, true) != 0) {
		box_region_truncate(region_svp);
		box_tuple_unref(tuple);
		return luaT_error(L);
	}

	int rc = box_tuple_compare_with_key(tuple, key, key_def);
	box_region_truncate(region_svp);
	box_tuple_unref(tuple);
	lua_pushinteger(L, rc);
	return 1;
}

/**
 * Construct and export to Lua a new key definition with a set
 * union of key parts from first and second key defs. Parts of
 * the new key_def consist of the first key_def's parts and those
 * parts of the second key_def that were not among the first
 * parts.
 * Push the new key_def as cdata to a Lua stack on success.
 * Raise error otherwise.
 */
static int
lbox_key_def_merge(struct lua_State *L)
{
	box_key_def_t *key_def_a, *key_def_b;
	if (lua_gettop(L) != 2 ||
	    (key_def_a = luaT_check_key_def(L, 1)) == NULL ||
	    (key_def_b = luaT_check_key_def(L, 2)) == NULL)
		return luaL_error(L, "Usage: key_def:merge(second_key_def)");

	box_key_def_t *new_key_def = box_key_def_merge(key_def_a, key_def_b);
	if (new_key_def == NULL)
		return luaT_error(L);

	*(box_key_def_t **) luaL_pushcdata(L, CTID_STRUCT_KEY_DEF_REF) =
		new_key_def;
	lua_pushcfunction(L, lbox_key_def_gc);
	luaL_setcdatagc(L, -2);
	return 1;
}

/**
 * Push a new table representing a key_def to a Lua stack.
 */
static int
lbox_key_def_to_table(struct lua_State *L)
{
	box_key_def_t *key_def;
	if (lua_gettop(L) != 1 || (key_def = luaT_check_key_def(L, 1)) == NULL)
		return luaL_error(L, "Usage: key_def:totable()");

	luaT_key_def_to_table(L, key_def);
	return 1;
}

/**
 * Create a new key_def from a Lua table.
 *
 * Expected a table of key parts on the Lua stack. The format is
 * the same as box.space.<...>.index.<...>.parts or corresponding
 * net.box's one.
 *
 * Push the new key_def as cdata to a Lua stack.
 */
static int
lbox_key_def_new(struct lua_State *L)
{
	if (lua_gettop(L) != 1 || lua_istable(L, 1) != 1)
		return luaL_error(L, "Bad params, use: key_def.new({"
				  "{fieldno = fieldno, type = type"
				  "[, is_nullable = <boolean>]"
				  "[, path = <string>]"
				  "[, collation = <string>]}, ...}");

	uint32_t part_count = lua_objlen(L, 1);

	size_t region_svp = box_region_used();
	size_t size = sizeof(box_key_part_def_t) * part_count;
	box_key_part_def_t *parts = box_region_aligned_alloc(
		size, alignof(box_key_part_def_t));
	if (parts == NULL) {
		diag_set(ER_MEMORY_ISSUE, size, "box_region_aligned_alloc",
			 "parts");
		return luaT_error(L);
	}
	if (part_count == 0) {
		diag_set(ER_ILLEGAL_PARAMS,
			 "At least one key part is required");
		return luaT_error(L);
	}

	for (uint32_t i = 0; i < part_count; ++i) {
		lua_rawgeti(L, 1, i + 1);
		if (luaT_key_def_set_part(L, &parts[i]) != 0) {
			box_region_truncate(region_svp);
			return luaT_error(L);
		}
		lua_pop(L, 1);
	}

	box_key_def_t *key_def = box_key_def_new_ex(parts, part_count);
	box_region_truncate(region_svp);
	if (key_def == NULL)
		return luaT_error(L);

	*(box_key_def_t **) luaL_pushcdata(L, CTID_STRUCT_KEY_DEF_REF) =
		key_def;
	lua_pushcfunction(L, lbox_key_def_gc);
	luaL_setcdatagc(L, -2);

	return 1;
}

/* {{{ Public API of the module */

/**
 * Register the module.
 */
LUA_API int
luaopen_key_def(struct lua_State *L)
{
	/*
	 * ffi.metatype() cannot be called twice on the same type.
	 *
	 * Tarantool has built-in key_def Lua module since
	 * 2.2.0-255-g22db9c264, which already calls
	 * ffi.metatype() on <struct key_def>. We should use
	 * another name within the external module.
	 */
	luaL_cdef(L, "struct key_def_key_def;");
	CTID_STRUCT_KEY_DEF_REF = luaL_ctypeid(L, "struct key_def_key_def *");

	JSON_PATH_IS_SUPPORTED = json_path_is_supported();

	/* Export C functions to Lua. */
	static const struct luaL_Reg meta[] = {
		{"new", lbox_key_def_new},
		{"extract_key", lbox_key_def_extract_key},
		{"compare", lbox_key_def_compare},
		{"compare_with_key", lbox_key_def_compare_with_key},
		{"merge", lbox_key_def_merge},
		{"totable", lbox_key_def_to_table},
		{NULL, NULL}
	};
	luaL_register(L, "key_def", meta);

	/* Execute Lua part of the module. */
	execute_key_def_lua(L);

	return 1;
}

/* }}} Public API of the module */
