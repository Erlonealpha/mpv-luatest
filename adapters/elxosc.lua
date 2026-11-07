-- Only elxosc-specific setup belongs here; no project test files are loaded.
-- Supply --path .. --path ../elxlib to load the sibling elxlib source modules
-- without its native init.lua, exactly as the original offline bootstrap does.
local mp_stub = require 'mpv_test.mp_stub'
-- The unchanged host tests rely on their old stub retaining mouse position
-- across resets. New projects get a cleared mouse by default.
mp_stub.configure({ input_section = 'elxosc-input', preserve_mouse = true })

-- Normally supplied by elxlib init.lua, which the offline suite does not run.
---@diagnostic disable-next-line: global-in-non-module
_G.debug_msg = _G.debug_msg or function()
end
