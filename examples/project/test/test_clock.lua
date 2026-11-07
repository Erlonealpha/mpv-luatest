local F = require 'mpv_luatest.framework'
local mp_stub = require 'mpv_luatest.mp_stub'
mp_stub.install()
local script = require 'my_script'

F.section('example: host clock')
F.test('a captured host reads the current fake clock', function()
    mp_stub.reset()
    mp_stub.fake.time = 2.5
    F.eq(script.seconds(), 2.5, 'current fake time')
    mp_stub.reset()
    F.eq(script.seconds(), 0, 'captured mp reference survives reset')
end)
