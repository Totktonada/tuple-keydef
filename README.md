# tuple.keydef

It is WIP. Beware, I'll force-push.

## API

It is the same as the [built-in][website_doc] `key_def` module, but should be
required as `tuple.keydef`.

## Differences from the built-in module

### Key differences

- May be updated separately from tarantool.
- Supports tarantool-1.10.
- Support of 'varbinary' field type (but it was fixed in [gh-4538][gh-4538] in
  the built-in module).

### Subtle differences

- A bit different error messages.
- ClientError (with an appropriate code) is used to raise an error instead of
  internal errors: IllegalParams and OutOfMemory.
- `<key_def>` instance serializetion: `<is_nullable>` and `<collation>` are not
  shown when its value is default one (it is so only for `<path>` in the
  built-in module).

### Differences to the bad side

Let's name it backlog :)

- Don't support extraction of a key with a composite type. Let's backport
  [gh-4538][gh-4538] fix.
- `<collation_id>` option is removed, use `<collation>` instead.

[gh-4538]: https://github.com/tarantool/tarantool/issues/4538
[website_doc]: https://www.tarantool.io/en/doc/latest/reference/reference_lua/key_def/
