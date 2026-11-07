-- Project-independent module search paths and optional setup hook.
local M = {}

---@param root string
---@param path string
---@return string
function M.resolve(root, path)
    path = path:gsub('\\', '/')
    if path:match('^%a:/') or path:sub(1, 1) == '/' then
        return path
    end
    if root == '.' then
        return path
    end
    return root:gsub('\\', '/') .. '/' .. path
end

---@param options MpvLuaTestOptions
---@return string test_directory
function M.bootstrap(options)
    local test_directory = M.resolve(options.root, options.test_dir)
    local roots = { test_directory, options.root }
    for _, path in ipairs(options.paths) do
        roots[#roots + 1] = M.resolve(options.root, path)
    end
    local patterns = {}
    for _, root in ipairs(roots) do
        patterns[#patterns + 1] = root .. '/?.lua'
        patterns[#patterns + 1] = root .. '/?/init.lua'
    end
    patterns[#patterns + 1] = package.path
    package.path = table.concat(patterns, ';')

    if options.bootstrap then
        local setup = assert(loadfile(M.resolve(options.root, options.bootstrap)))
        setup(options.root, test_directory)
    end
    return test_directory
end

return M
