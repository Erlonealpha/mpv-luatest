-- Public suite API. The caller owns process exit and project configuration.
local framework = require 'mpv_luatest.framework'
local runner = require 'mpv_luatest.runner'
local support = require 'mpv_luatest.support'
local mp_stub = require 'mpv_luatest.mp_stub'

local M = {}

--- Bind legacy imports to the canonical modules; never load project copies.
function M.install_aliases()
    package.loaded['framework'] = framework
    package.loaded['runner'] = runner
    package.loaded['mp_stub'] = mp_stub
end

---@param options MpvLuaTestOptions
---@return integer exit_code
function M.run(options)
    framework.reset()
    framework.set_verbose(options.verbose)
    M.install_aliases()

    local ready, test_directory = pcall(support.bootstrap, options)
    if not ready then
        framework.fail('bootstrap failed: ' .. tostring(test_directory))
        framework.summary()
        return 1
    end
    ---@cast test_directory string
    if options.verbose then
        print((options.suite_name or 'mpv-luatest suite') .. ' (' .. _VERSION
            .. ', ' .. (jit and jit.version or 'no jit') .. ')')
    end
    local discovered, files = pcall(runner.discover, test_directory)
    if not discovered then
        framework.fail(tostring(files))
        framework.summary()
        return 1
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
    return framework.summary() and 0 or 1
end

---@param args string[]
---@param defaults? MpvLuaTestOptions
---@return integer exit_code
function M.main(args, defaults)
    local options, argument_error = runner.parse_args(args, defaults)
    if not options then
        framework.reset()
        framework.fail(tostring(argument_error))
        framework.summary()
        return 1
    end
    ---@cast options MpvLuaTestOptions
    if options.help then
        print('Usage: luajit <mpv-luatest>/run.lua [options] [group/file filter]')
        print('  --root DIR       Project root (default: current directory)')
        print('  --test-dir DIR   Test directory relative to root (default: test)')
        print('  --path DIR       Additional module root; may be repeated')
        print('  --bootstrap FILE Project setup file relative to root (optional)')
        print('  -v               Show files, sections and successful tests')
        print('  -h, --help       Show this help')
        return 0
    end
    return M.run(options)
end

return M
