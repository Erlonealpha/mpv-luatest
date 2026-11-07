-- Standalone CLI. Embedded users call mpv_luatest.suite.main directly.
local entry = (arg and arg[0] or 'run.lua'):gsub('\\', '/')
local directory = entry:match('^(.*)/[^/]+$') or '.'
package.path = directory .. '/src/?.lua;' .. directory .. '/src/?/init.lua;' .. package.path

local suite = require 'mpv_luatest.suite'
os.exit(suite.main(arg or {}))
