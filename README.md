# tuple.keydef

## Overview

The module provides ability to use Tarantool's tuple comparators and key
extraction functions.

## API

It is the same as the [built-in][website_doc] `key_def` module, but should be
required as `tuple.keydef`.

## Compatibility

Supported tarantool versions:

- 1.10 since 1.10.7-85-g840c13293.
- 2.4 since 2.4.2-126-g883eac6a7.
- 2.5 since 2.5.1-145-geea90d7ce.
- 2.6 since 2.6.0-188-g4a12985f1.
- All 2.7+.

The older tarantool versions are not supported, because they lack of necessary
C APIs.

The module built against one tarantool version works fine on another: it
performs runtime checks of supported features (like JSON paths).

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
- `<keydef>` instance serialization: `<is_nullable>` and `<collation>` are not
  shown when its value is default one (it is so only for `<path>` in the
  built-in module).

### Differences to the bad side

Let's name it backlog :)

- Don't support extraction of a key with a composite type. Let's backport
  [gh-4538][gh-4538] fix.
- `<collation_id>` option is removed, use `<collation>` instead.

[gh-4538]: https://github.com/tarantool/tarantool/issues/4538
[website_doc]: https://www.tarantool.io/en/doc/latest/reference/reference_lua/key_def/
