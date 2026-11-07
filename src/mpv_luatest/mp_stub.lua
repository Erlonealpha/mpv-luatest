-- A tiny `mp` stub for the host-layer tests.
--
-- install() replaces require 'mp'. The fake state table stays stable across
-- reset(), including when host modules retain an installed mp table.

local S = {}
local input_section
local preserve_mouse = false

---@class MpStubOptions
---@field input_section? string Primary section for the fake.bindings view.
---@field preserve_mouse? boolean Retain mouse on reset for legacy suites.

---@class MpStubBinding
---@field list table[]
---@field section string
---@field flags? string

---@class MpStubState : table
---@field messages table[]
---@field props table<string, any>
---@field events { name: string, cb: function }[]
---@field commands table[]
---@field timeouts { cb: function, killed: boolean, kill: function }[]
---@field log table<string, function>
---@field time number
---@field osd_width number
---@field osd_height number
---@field fps number
---@field mouse? table
---@field overlay? table
---@field overlays table[]
---@field bindings? MpStubBinding
---@field bindings_enabled? { section: string, flags: string? }
---@field bindings_disabled? string
---@field mouse_areas table<string, table[]>
---@field binding_sections table<string, MpStubBinding>
---@field bindings_enabled_sections table<string, table?>
---@field enable_history string[]
---@field disable_history string[]
---@field unobserved function[]
---@field native_props table<string, any>

---@type MpStubState
local fake = {
    messages = {},
    props = {},
    events = {},
    commands = {},
    timeouts = {},
    log = {},
    time = 0,
    osd_width = 1280,
    osd_height = 720,
    fps = 60,
    overlays = {},
    mouse_areas = {},
    binding_sections = {},
    bindings_enabled_sections = {},
    enable_history = {},
    disable_history = {},
    unobserved = {},
    native_props = {},
}

S.fake = fake

--- Copy compatibility options for primary input and reset behavior.
--- All sections are always available through fake.binding_sections.
---@param options? MpStubOptions
function S.configure(options)
    options = options or {}
    input_section = options.input_section
    preserve_mouse = options.preserve_mouse == true
end

function S.reset()
    fake.messages, fake.props, fake.events = {}, {}, {}
    fake.commands, fake.timeouts, fake.log = {}, {}, {}
    fake.time = 0
    fake.osd_width, fake.osd_height = 1280, 720
    fake.fps = 60
    fake.overlay = nil
    fake.overlays = {}
    fake.bindings = nil
    fake.bindings_enabled = nil
    fake.bindings_disabled = nil
    fake.mouse_areas = {}
    fake.binding_sections = {}
    fake.bindings_enabled_sections = {}
    fake.enable_history = {}
    fake.disable_history = {}
    fake.unobserved = {}
    fake.native_props = {}
    if not preserve_mouse then
        fake.mouse = nil
    end
end

--- Run every timeout queued since the last call (one frame of the host loop).
function S.pump()
    local queued = fake.timeouts
    fake.timeouts = {}
    for _, timer in ipairs(queued) do
        if not timer.killed then
            timer.cb()
        end
    end
end

---@return table mp the stub, also installed as `package.loaded['mp']`
function S.install()
    local mp = {}

    mp.msg = {
        info = function(...)
            fake.messages[#fake.messages + 1] = { 'info', ... }
        end,
        warn = function(...)
            fake.messages[#fake.messages + 1] = { 'warn', ... }
        end,
        error = function(...)
            fake.messages[#fake.messages + 1] = { 'error', ... }
        end,
    }

    ---@param name string
    function mp.get_property_native(name)
        if name == 'mouse-pos' then
            return fake.mouse
        end
        if fake.native_props[name] ~= nil then
            return fake.native_props[name]
        end
        return 'native:' .. name
    end

    ---@param name string
    ---@param value any
    function mp.set_property_native(name, value)
        fake.props[name] = value
    end

    ---@param name string
    ---@param value any
    function mp.set_property(name, value)
        fake.props[name] = value
    end

    ---@param name string
    function mp.get_property_number(name)
        if name == 'display-fps' or name == 'estimated-display-fps' then
            return fake.fps
        end
        return nil
    end

    function mp.get_time()
        return fake.time
    end

    ---@param ... any
    function mp.commandv(...)
        fake.commands[#fake.commands + 1] = { ... }
    end

    ---@param name string
    ---@param _ string
    ---@param cb function
    function mp.observe_property(name, _, cb)
        fake.events[#fake.events + 1] = { name = name, cb = cb }
    end

    ---@param cb function
    function mp.unobserve_property(cb)
        fake.unobserved[#fake.unobserved + 1] = cb
    end

    ---@param name string
    ---@param cb function
    function mp.register_script_message(name, cb)
        fake.log[name] = cb
    end

    ---@param name string
    function mp.unregister_script_message(name)
        fake.log[name] = nil
    end

    ---@param name string
    ---@param cb function
    function mp.register_event(name, cb)
        fake.log['event:' .. name] = cb
    end

    ---@param callback function
    function mp.unregister_event(callback)
        for name, registered in pairs(fake.log) do
            if name:sub(1, 6) == 'event:' and registered == callback then
                fake.log[name] = nil
            end
        end
    end

    function mp.wait_event()
    end

    ---@param _ number
    ---@param cb function
    function mp.add_timeout(_, cb)
        local timer = { cb = cb, killed = false }
        function timer:kill()
            self.killed = true
        end
        fake.timeouts[#fake.timeouts + 1] = timer
        return timer
    end

    ---@param format string
    function mp.create_osd_overlay(format)
        fake.overlay = {
            format = format,
            z = 0,
            data = nil,
            res_x = nil,
            res_y = nil,
            updates = 0,
            removes = 0,
        }
        fake.overlay.update = function(self)
            self.updates = self.updates + 1
        end
        fake.overlay.remove = function(self)
            self.removes = self.removes + 1
        end
        fake.overlays[#fake.overlays + 1] = fake.overlay
        return fake.overlay
    end

    function mp.get_osd_size()
        return fake.osd_width, fake.osd_height
    end

    ---@param list table[]
    ---@param section string
    ---@param flags? string
    function mp.set_key_bindings(list, section, flags)
        local binding = { list = list, section = section, flags = flags }
        fake.binding_sections[section] = binding
        if input_section == nil or section == input_section then
            fake.bindings = binding
        end
    end

    ---@param section string
    ---@param flags? string
    function mp.enable_key_bindings(section, flags)
        local binding = { section = section, flags = flags }
        fake.bindings_enabled_sections[section] = binding
        fake.enable_history[#fake.enable_history + 1] = section
        fake.bindings_enabled = binding
    end

    ---@param section string
    function mp.disable_key_bindings(section)
        fake.bindings_enabled_sections[section] = nil
        fake.disable_history[#fake.disable_history + 1] = section
        fake.bindings_enabled = nil
        fake.bindings_disabled = section
    end

    ---@param x0 number
    ---@param y0 number
    ---@param x1 number
    ---@param y1 number
    ---@param section string
    function mp.set_mouse_area(x0, y0, x1, y1, section)
        local areas = fake.mouse_areas[section]
        if areas == nil then
            areas = {}
            fake.mouse_areas[section] = areas
        end
        areas[#areas + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
    end

    package.loaded['mp'] = mp
    return mp
end

S.reset()
return S
