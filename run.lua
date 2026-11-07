-- Standalone runner for any LuaJIT/mpv project. Paths are relative to --root.
local entry = (arg and arg[0] or 'run.lua'):gsub('\\', '/')
local directory = entry:match('^(.*)/[^/]+$') or '.'
package.path = directory .. '/src/?.lua;' .. package.path

local framework = require 'mpv_test.framework'
local runner = require 'mpv_test.runner'
local support = require 'mpv_test.support'
local mp_stub = require 'mpv_test.mp_stub'

local options, argument_error = runner.parse_args(arg or {})
if not options then
    framework.fail(tostring(argument_error))
    framework.summary()
    os.exit(1)
end
---@cast options MpvTestOptions
if options.help then
    print('Usage: luajit <mpv-test>/run.lua [options] [group/file filter]')
    print('  --root DIR       Project root (default: current directory)')
    print('  --test-dir DIR   Test directory relative to root (default: test)')
    print('  --path DIR       Additional module root; may be repeated')
    print('  --bootstrap FILE Project setup file relative to root (optional)')
    print('  -v               Show files, sections and successful tests')
    print('  -h, --help       Show this help')
    os.exit(0)
end

framework.set_verbose(options.verbose)
-- Existing suites keep their bare imports, even when their test directory
-- contains older copies. Namespaced and compatibility imports share identity.
package.loaded['framework'] = framework
package.loaded['runner'] = runner
package.loaded['mp_stub'] = mp_stub

local ready, test_directory = pcall(support.bootstrap, options)
if not ready then
    framework.fail('bootstrap failed: ' .. tostring(test_directory))
    framework.summary()
    os.exit(1)
end
---@cast test_directory string
if options.verbose then
    print('mpv-test suite (' .. _VERSION .. ', ' .. (jit and jit.version or 'no jit') .. ')')
end

local discovered, files = pcall(runner.discover, test_directory)
if not discovered then
    framework.fail(tostring(files))
    framework.summary()
    os.exit(1)
end
---@cast files string[]

local ran = 0
for _, name in ipairs(files) do
    if runner.matches(name, options.filter) then
        ran = ran + 1
        framework.file(name)
        local ok, err = pcall(dofile, test_directory .. '/' .. name)
        if not ok then
            framework.fail(name .. ' crashed: ' .. tostring(err):gsub('\n', ' | '))
        end
    end
end
if ran == 0 then
    framework.fail("no test file matched filter '" .. tostring(options.filter) .. "'")
end
os.exit(framework.summary() and 0 or 1)
