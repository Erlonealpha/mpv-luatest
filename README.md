# mpv-luatest

A small LuaJIT test framework for mpv scripts and host-independent Lua modules.
The runner, assertions and fake `mp` module require only LuaJIT and the system
shell. They do not load mpv, native libraries, or another project's modules.

## Run a project

Clone [this repository](https://github.com/Erlonealpha/mpv-luatest) wherever you
keep development dependencies, then run from your project's root:

```sh
luajit /path/to/mpv-luatest/run.lua
luajit /path/to/mpv-luatest/run.lua -v player/layout
```

Tests default to `test/`. Project modules are loaded by their bare names from
the project root. Put additional code/dependency roots on the search path:

```sh
luajit /path/to/mpv-luatest/run.lua --root /path/to/project --test-dir tests --path src --path vendor
```

Quote paths containing spaces. Every `--path`, `--test-dir` and `--bootstrap`
is relative to `--root`, or may be absolute. Use `--bootstrap setup.lua` for
project globals and stub configuration; its chunk receives root/test directory
through `...`. See the [API reference](docs/API.md) for defaults and behavior.

A test can install the fake host before loading its application:

```lua
local F = require 'mpv_luatest.framework'
local stub = require 'mpv_luatest.mp_stub'
stub.install()
local script = require 'my_script'

F.section('clock')
F.test('reads fake time', function()
    stub.reset()
    stub.fake.time = 2.5
    F.eq(script.seconds(), 2.5, 'current host time')
end)
```

A complete runnable example is included:

```sh
luajit run.lua --root examples/project
```

The CLI also supports existing tests importing `framework`, `runner`, or
`mp_stub`: these names resolve to the same canonical module objects.

## Use as a development dependency

A project can pin this checkout as a Git submodule:

```sh
git submodule add https://github.com/Erlonealpha/mpv-luatest.git mpv-luatest
git submodule update --init --recursive
```

After cloning a consuming project, initialize its recorded submodule commit;
update that pointer deliberately after verifying a newer framework version.
This is a test dependency and contains no `main.lua` for mpv's directory loader.

To keep a project's existing entry command, write a small adapter that adds
the dependency's module roots and calls the public API:

```lua
package.path = 'mpv-luatest/src/?.lua;mpv-luatest/src/?/init.lua;' .. package.path
local suite = require 'mpv_luatest.suite'
os.exit(suite.main(arg or {}, {
    verbose = false,
    root = '.',
    test_dir = 'test',
    paths = { 'src' },
    bootstrap = 'test/bootstrap.lua',
    suite_name = 'my-project tests',
}))
```

`suite.main` and `suite.run` return status codes without exiting the process.
The canonical aggregate is `require 'mpv_luatest'`; it exports the same direct
module objects, plus the framework version.

## Discovery and results

Files named `test_*.lua` are discovered in sorted order at the test root and
below directories whose names start with `test`. Other directories, including
`fixtures` and `real_host`, are excluded. Filters match literal substrings in
consecutive slash-separated components; `test_` and `.lua` may be omitted.

Default output shows failures and assertion totals. `-v` includes file/section
and successful test names. Failed assertions and crashed files do not stop
remaining files. Exit code is 0 on success/help, 1 on errors or empty matches.

The fake host records timeouts, property observers, messages, overlays, commands,
key sections and mouse areas. Tests explicitly dispatch callbacks and pump fake
frames. It covers a documented API subset; use real mpv processes for rendering,
IPC and real input validation. Details are in [API.md](docs/API.md).

## Framework checks

From this repository alone:

```sh
luajit run.lua --test-dir tests
luajit run.lua --root examples/project
emmylua_check . --warnings-as-errors
uv run --group test python -m pytest -q
```

Python + pytest are development-only dependencies declared in
`pyproject.toml` and `uv.lock`. Existing Python/pytest may also run
`python -m pytest -q`. Set `MPV_LUATEST_LUAJIT` to select LuaJIT, otherwise PATH
is searched. CLI tests relocate the framework and create independent temporary
projects to verify use without a consumer checkout.

## Layout and license

| Path | Responsibility |
| --- | --- |
| `run.lua` | Standalone process entry |
| `src/mpv_luatest/` | Public modules, discovery, assertions and fake host |
| `docs/API.md` | Module contracts and stub boundaries |
| `examples/project/` | Runnable consumer example |
| `tests/` | Framework behavior and subprocess regressions |

Released under the [MIT license](LICENSE). The initial assertion/runner/stub
implementation was extracted from elxosc; all project-specific adapters and
validation records are maintained by their consuming projects.
