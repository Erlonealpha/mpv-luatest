local F = require 'mpv_luatest.framework'
local mp_stub = require 'mpv_luatest.mp_stub'

F.section('offline mp lifecycle')

F.test('host references survive reset and test state is cleared', function()
    local mp = mp_stub.install()
    local fake = mp_stub.fake
    fake.mouse = { x = 9, y = 8 }
    mp.set_property('volume', 42)
    mp.commandv('seek', 5)
    mp.register_script_message('hello', function()
    end)
    mp.create_osd_overlay('ass-events')
    mp_stub.reset()
    -- Compare both references deliberately to guard the reset identity contract.
    ---@diagnostic disable-next-line: preferred-local-alias
    F.eq(mp_stub.fake, fake, 'shared state identity')
    F.eq(package.loaded['mp'], mp, 'host keeps installed mp')
    F.eq(fake.mouse, nil, 'mouse does not leak between tests')
    F.eq(next(fake.props), nil, 'properties cleared')
    F.eq(#fake.commands, 0, 'commands cleared')
    F.eq(next(fake.log), nil, 'callbacks cleared')
    F.eq(#fake.overlays, 0, 'overlay history cleared')
    F.eq(fake.osd_width, 1280, 'default width initialized')
    mp.set_property_native('pause', true)
    F.eq(fake.props.pause, true, 'captured host writes to fresh state')
    local replacement = mp_stub.install()
    F.eq(package.loaded['mp'], replacement, 'reinstall publishes replacement')
    F.ok(replacement ~= mp, 'install provides a fresh API table')
    mp.commandv('stop')
    F.eq(replacement.get_time(), fake.time, 'both API tables share state')
    F.eq(assert(fake.commands[1])[1], 'stop', 'old reference still records commands')
end)

F.test('pump runs one queued frame, preserves order and skips killed timers', function()
    mp_stub.reset()
    local mp = mp_stub.install()
    local order = {}
    mp.add_timeout(0, function()
        order[#order + 1] = 'first'
        mp.add_timeout(0, function()
            order[#order + 1] = 'next frame'
        end)
    end)
    local canceled = mp.add_timeout(0, function()
        error('killed callback ran')
    end)
    canceled:kill()
    mp.add_timeout(0, function()
        order[#order + 1] = 'second'
    end)
    mp_stub.pump()
    F.eq(table.concat(order, ','), 'first,second', 'ordered current frame')
    F.eq(#mp_stub.fake.timeouts, 1, 'new timer waits for next pump')
    mp_stub.pump()
    F.eq(order[3], 'next frame', 'next frame executes')
end)

F.test('properties, messages and observers can drive a project host', function()
    mp_stub.reset()
    local mp = mp_stub.install()
    local fake = mp_stub.fake
    fake.native_props.pause = false
    fake.fps = 144
    fake.time = 2.5
    F.eq(mp.get_property_native('pause'), false, 'false native property retained')
    F.eq(mp.get_property_native('missing'), 'native:missing', 'legacy fallback')
    F.eq(mp.get_property_number('display-fps'), 144, 'fake display rate')
    F.eq(mp.get_time(), 2.5, 'deterministic clock')
    local observed
    local function observer(_, value)
        observed = value
    end
    mp.observe_property('pause', 'bool', observer)
    assert(fake.events[1]).cb('pause', true)
    F.eq(observed, true, 'explicit observer dispatch')
    mp.unobserve_property(observer)
    F.eq(fake.unobserved[1], observer, 'observer cleanup recorded')
    mp.register_script_message('ping', function(value)
        observed = value
    end)
    fake.log.ping('pong')
    F.eq(observed, 'pong', 'script message dispatch')
    mp.unregister_script_message('ping')
    F.eq(fake.log.ping, nil, 'script message removed')
    mp.register_event('shutdown', observer)
    mp.unregister_event(observer)
    F.eq(fake.log['event:shutdown'], nil, 'event callback removed')
    mp.msg.warn('warning', 3)
    local message = assert(fake.messages[1])
    F.eq(message[1], 'warn', 'message severity')
    F.eq(message[3], 3, 'message arguments preserved')
end)

F.test('overlays and named sections work without a project-specific name', function()
    mp_stub.reset()
    mp_stub.configure()
    local mp = mp_stub.install()
    local fake = mp_stub.fake
    local first = mp.create_osd_overlay('ass-events')
    local second = mp.create_osd_overlay('ass-events')
    first:update()
    first:remove()
    F.eq(fake.overlays[1], first, 'first overlay retained')
    F.eq(fake.overlay, second, 'latest overlay compatibility view')
    F.eq(first.updates, 1, 'updates recorded')
    F.eq(first.removes, 1, 'removals recorded')
    local bindings = { { 'SPACE', function()
    end } }
    mp.set_key_bindings(bindings, 'other-project', 'force')
    F.eq(fake.binding_sections['other-project'].list, bindings, 'arbitrary section')
    F.eq(assert(fake.bindings).section, 'other-project', 'default compatibility view')
    mp_stub.configure({ input_section = 'primary' })
    mp.set_key_bindings(bindings, 'primary', 'force')
    mp.set_key_bindings({}, 'secondary', 'force')
    F.eq(assert(fake.bindings).section, 'primary', 'configured primary section')
    F.ok(fake.binding_sections.secondary ~= nil, 'all sections recorded')
    mp.set_mouse_area(1, 2, 3, 4, 'primary')
    mp.enable_key_bindings('primary', 'allow-vo-dragging')
    mp.disable_key_bindings('primary')
    F.eq(assert(fake.mouse_areas.primary[1]).x0, 1, 'mouse area recorded')
    F.eq(fake.enable_history[1], 'primary', 'enable order recorded')
    F.eq(fake.disable_history[1], 'primary', 'disable order recorded')
    F.eq(fake.bindings_enabled_sections.primary, nil, 'section disabled')
    mp_stub.configure()
end)

F.test('legacy mouse persistence is explicit and does not mutate options', function()
    local options = { preserve_mouse = true }
    mp_stub.configure(options)
    options.preserve_mouse = false
    local mouse = { x = 11, y = 12 }
    mp_stub.fake.mouse = mouse
    mp_stub.reset()
    F.eq(mp_stub.fake.mouse, mouse, 'configured persistence is copied')
    mp_stub.configure()
    mp_stub.reset()
    F.eq(mp_stub.fake.mouse, nil, 'default reset clears legacy state')
end)
