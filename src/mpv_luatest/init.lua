-- Canonical aggregate; all fields share identity with their direct modules.
local framework = require 'mpv_luatest.framework'
local runner = require 'mpv_luatest.runner'
local support = require 'mpv_luatest.support'
local mp_stub = require 'mpv_luatest.mp_stub'
local suite = require 'mpv_luatest.suite'

return {
    version = '0.1.0',
    framework = framework,
    runner = runner,
    support = support,
    mp_stub = mp_stub,
    suite = suite,
}
