# key_def

It is WIP. Beware, I'll force-push.

## Differences from the built-in module

- Key feature: support tarantool-1.10.
- Support of 'varbinary' field type.
- `<collation_id>` option is removed, use `<collation>` instead.
- A bit different error messages.
- ClientError (with an appropriate code) is used to raise an error instead of
  internal errors: IllegalParams and OutOfMemory.
- `<key_def>` instance serializetion: `<is_nullable>` and `<collation>` are not
  shown when its value is default one (it is so only for `<path>` in the
  built-in module).

## TODO

- Adjust repository URLs in the rocspec before fork to tarantool organization.
