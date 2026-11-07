-- A minimal mpv script whose host clock can be tested offline.
-- mp is supplied by the host or the test stub, with no external metadata needed.
---@diagnostic disable-next-line: unresolved-require
local mp = require 'mp'
local M = {}

---@return number
function M.seconds()
    return mp.get_time()
end

return M
