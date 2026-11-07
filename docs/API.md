# API

Add `src/?.lua` and `src/?/init.lua` from this checkout to `package.path` to use
these modules directly. `require 'mpv_luatest'` exports `version`, `framework`,
`runner`, `support`, `mp_stub`, and `suite`. Aggregate fields are the same objects
returned by the corresponding `mpv_luatest.*` modules.

## Suites

`suite.main(args, defaults?)` parses CLI arguments and returns an integer exit
code. `suite.run(options)` runs already parsed options. Neither exits the process.
The standalone `run.lua` passes this result to `os.exit`.

Options:

| Field | Default | Meaning |
| --- | --- | --- |
| `root` | `.` | Project root, relative to the working directory |
| `test_dir` | `test` | Directory searched for test files |
| `paths` | `{}` | Additional module roots, in search order |
| `bootstrap` | absent | Lua setup file executed before discovery |
| `verbose` | `false` | Print files, sections and successful test bodies |
| `filter` | absent | Slash-separated group/file substring filter |
| `suite_name` | `mpv-luatest suite` | Name printed in verbose mode |

`test_dir`, `paths`, and `bootstrap` resolve relative to `root`, with absolute
paths accepted. The bootstrap chunk receives `(root, test_directory)` through
`...`. It may set globals or configure the stub. Bootstrap failures stop the run.

`runner.parse_args(args, defaults?)` returns `(options, nil)` or `(nil, message)`.
It copies the defaults and their paths; caller tables remain unchanged. CLI flags
override defaults. `--path` appends and may be repeated. Supported flags are
`--root`, `--test-dir`, `--path`, `--bootstrap`, `-v`, `-h`, and `--help`.

`runner.discover(root)` finds root-level `test_*.lua` and recursively enters only
directories starting with `test`. Files are sorted by relative path. Discovery
uses the system shell (`cmd` on Windows, `find` on POSIX); no Lua filesystem
library is required. Windows paths containing quotes, percent/exclamation marks,
or line breaks are rejected because they cannot be passed safely through `cmd`.

`runner.matches(path, filter?)` matches consecutive path components as literal
substrings, stripping an optional `test_` prefix and `.lua` suffix. A single
component can select a group or file at any depth. Backslashes are normalized.

`suite.install_aliases()` binds bare `framework`, `runner`, and `mp_stub` imports
to their canonical modules. Suites install these aliases automatically, before
the bootstrap and tests. The test directory still supplies project helpers.

Each suite resets assertion counts. It continues after failed assertions or
crashed files and returns 1 for failures, invalid arguments, bootstrap/discovery
errors or zero matching files; success/help returns 0. Suites do not reload
required application modules, clear arbitrary globals, or automatically install
`mp`. Use separate Lua processes when full module isolation is required.

## Assertions

| Function | Behavior |
| --- | --- |
| `section(name)` | Set the current report section |
| `test(name, body)` | Catch a body exception and attribute it to this test |
| `ok(condition, message)` | Assert truthiness |
| `eq(actual, expected, message)` | Assert Lua equality |
| `contains(value, substring, message)` | Match a literal substring after `tostring` |
| `close(actual, expected, message, epsilon?)` | Numeric tolerance, default `1e-9` |
| `raises(body, substring, message)` | Require an error whose text contains the substring |
| `fail(message)` | Record a failure explicitly |
| `results()` | Return failed count, passed count, and failure messages |
| `summary()` | Print the report and return whether it passed |
| `reset()` | Clear assertion/report context without replacing the module |
| `file(name)`, `set_verbose(boolean)` | Set file context and verbosity |

Counts describe assertions, not test bodies. Assertions return a boolean and
continue running; they do not throw. A failing assertion prevents its enclosing
test body from being printed as successful. Error text is reported unchanged
apart from converting line breaks for the one-line failure output.

## mp stub

`mp_stub.install()` creates a new API table and publishes it as
`package.loaded['mp']`. Install it before requiring application modules that use
`mp`. Every installed table closes over the same `mp_stub.fake` state table.

`reset()` replaces recorded collections and restores time 0, OSD 1280×720 and
display FPS 60. Captured `mp` references remain usable. `pump()` runs queued,
uncanceled timeouts in registration order; timers created by their callbacks wait
for the next pump. Delays are recorded as a queued frame, not real elapsed time.

| API subset | State/control |
| --- | --- |
| `get_time`, `get_osd_size`, display-fps numeric properties | `time`, `osd_width`, `osd_height`, `fps` |
| Native properties and mouse-pos | `native_props`, `mouse` |
| `set_property`, `set_property_native` | `props` records writes |
| `commandv`, `msg.info/warn/error` | `commands`, `messages` |
| Property observers and removal | `events`, `unobserved` |
| Script messages and host events | `log[name]`, `log['event:' .. name]` |
| `add_timeout` and timer `kill()` | `timeouts`, driven by `pump()` |
| OSD overlay create/update/remove | `overlays`, latest `overlay`, operation counts |
| Key binding and mouse areas | Section maps plus enable/disable order histories |

Callbacks are dispatched explicitly through the fake state; property writes do
not trigger observers. Unconfigured native properties return `'native:' .. name`;
numeric property reads only recognize display-fps/estimated-display-fps. Overlays
record operations but do not render or calculate bounds.

`configure({ input_section?, preserve_mouse? })` copies compatibility settings.
With an input section, `fake.bindings` tracks that primary section; otherwise it
tracks the latest registration. All sections remain in `binding_sections`.
The default reset clears mouse position; `preserve_mouse=true` retains it.
`configure()` restores defaults. Resetting fake state does not reset configuration
or restore API fields a test has overridden.

This stub implements a focused API subset. It does not emulate libass, JSON IPC,
native async commands, `mp.utils`, or `mp.assdraw`. Tests can explicitly replace
fields on their installed API table for additional behavior. Real host tests
belong to the consuming project and should use isolated processes/configuration.
