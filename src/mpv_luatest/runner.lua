---@diagnostic disable: duplicate-type, duplicate-doc-field

-- Discovery and selection for standalone Lua suites. No project dependency.
local M = {}

---@class MpvLuaTestOptions
---@field verbose boolean
---@field help? boolean
---@field filter? string
---@field root string
---@field test_dir string
---@field paths string[]
---@field bootstrap? string
---@field suite_name? string

---@param args string[]
---@param defaults? MpvLuaTestOptions
---@return MpvLuaTestOptions? options
---@return string? error
function M.parse_args(args, defaults)
    defaults = defaults or { verbose = false, root = '.', test_dir = 'test', paths = {} }
    ---@type MpvLuaTestOptions
    local options = {
        verbose = defaults.verbose,
        root = defaults.root,
        test_dir = defaults.test_dir,
        bootstrap = defaults.bootstrap,
        suite_name = defaults.suite_name,
        paths = {},
    }
    for _, path in ipairs(defaults.paths) do
        options.paths[#options.paths + 1] = path
    end
    local index = 1
    while index <= #args do
        local value = assert(args[index])
        if value == '-v' then
            options.verbose = true
        elseif value == '-h' or value == '--help' then
            options.help = true
        elseif value == '--root' or value == '--test-dir' or value == '--path'
            or value == '--bootstrap' then
            index = index + 1
            local path = args[index]
            if not path or path == '' or path:sub(1, 1) == '-' then
                return nil, value .. ' requires a nonempty path'
            end
            path = path:gsub('\\', '/')
            if value == '--root' then
                options.root = path
            elseif value == '--test-dir' then
                options.test_dir = path
            elseif value == '--bootstrap' then
                options.bootstrap = path
            else
                options.paths[#options.paths + 1] = path
            end
        elseif value:sub(1, 1) == '-' then
            return nil, 'unknown option: ' .. value
        elseif options.filter then
            return nil, 'expected at most one test filter'
        elseif value == '' then
            return nil, 'test filter must not be empty'
        else
            options.filter = value:gsub('\\', '/')
        end
        index = index + 1
    end
    return options
end

---@param path string
---@return string[]
local function components(path)
    local parts = {}
    for part in path:gsub('\\', '/'):gmatch('[^/]+') do
        parts[#parts + 1] = part:gsub('%.lua$', ''):gsub('^test_?', '')
    end
    return parts
end

--- Each filter component is a literal substring of the corresponding path
--- component. A single component also selects a group at any depth.
---@param path string
---@param filter string?
---@return boolean
function M.matches(path, filter)
    if not filter then
        return true
    end
    local parts, wanted = components(path), components(filter)
    if #wanted == 0 then
        return false
    end
    for start = 1, #parts - #wanted + 1 do
        local matched = true
        for index, needle in ipairs(wanted) do
            local part = parts[start + index - 1]
            if not needle or needle == '' or not part or not part:find(needle, 1, true) then
                matched = false
                break
            end
        end
        if matched then
            return true
        end
    end
    return false
end

---@param path string
---@return boolean
local function is_test_path(path)
    local parts = {}
    for part in path:gmatch('[^/]+') do
        parts[#parts + 1] = part
    end
    for index = 1, #parts - 1 do
        if not parts[index]:match('^test') then
            return false
        end
    end
    return #parts > 0 and parts[#parts]:match('^test_.*%.lua$') ~= nil
end

---@param root string
---@return string[] files relative to root, in deterministic order
function M.discover(root)
    local windows = package.config:sub(1, 1) == '\\'
    local command
    if windows then
        -- cmd expands percent/exclamation marks even inside quoted paths.
        if root:find('["%%!\r\n]') then
            error('unsupported characters in Windows test directory: ' .. root)
        end
        -- cmd's directory stack also resolves relative and UNC checkout paths.
        command = 'pushd "' .. root:gsub('/', '\\') .. '" && cd && dir /b /s /a-d *.lua'
    else
        local quoted = "'" .. root:gsub("'", "'\\''") .. "'"
        command = 'cd ' .. quoted .. ' && pwd && find . -type f -name "*.lua"'
    end
    local handle = io.popen(command)
    if not handle then
        error('cannot discover test files')
    end
    local base = handle:read('*l')
    if not base then
        handle:close()
        error('cannot read test directory: ' .. root)
    end
    base = base:gsub('\\', '/'):gsub('/$', '') .. '/'
    local files = {}
    for line in handle:lines() do
        ---@cast line string
        local path = line:gsub('\\', '/')
        if windows then
            path = path:sub(#base + 1)
        else
            path = path:gsub('^%./', '')
        end
        if is_test_path(path) then
            files[#files + 1] = path
        end
    end
    handle:close()
    table.sort(files)
    return files
end

return M
