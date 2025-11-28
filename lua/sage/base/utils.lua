local U = {}

function U.safe_notify(msg, level)
    vim.schedule(function()
        vim.notify(msg, level)
    end)
end

function U.count_pack_directories(pack_path)
    local items = vim.split(vim.fn.glob(pack_path .. "/*"), "\n", { trimempty = true })
    local count = 0

    for _, item in ipairs(items) do
        if vim.fn.isdirectory(item) ~= 0 then
            count = count + 1
        end
    end

    return count
end

function U.format_table(tbl, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    local lines = {}

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            table.insert(lines, prefix .. key .. " = {")
            table.insert(lines, table.concat(value, " "))
            table.insert(lines, prefix .. "}")
        else
            local val_str = type(value) == "string" and string.format('"%s"', value) or tostring(value)
            table.insert(lines, prefix .. key .. " = " .. val_str)
        end
    end

    return table.concat(lines, "\n")
end

function U.is_not_enabled(pack)
    return pack.enabled == false
end

function U.packs_to_names(packs)
    local names = {}
    for name, pack in pairs(packs) do
        table.insert(names, name)
    end
    return names
end

function U.names_to_packs(names, Packs)
    local packs = {}
    for _, name in ipairs(names) do
        packs[name] = Packs[name]
    end
    return packs
end

function U.sort_packs(packs)
    local by_stage = {}
    for _, pack in ipairs(packs) do
        local stage = pack.specs.normalize.data.on.stage
        -- Fix #1: ensure valid stage
        local stage = type(stage) == "string" and stage or "default"
        by_stage[stage] = by_stage[stage] or {}
        table.insert(by_stage[stage], pack)
    end

    local sorted = {}

    for stage, group in pairs(by_stage) do
        local lookup = {}
        for _, p in ipairs(group) do
            -- Fix #2: safe spec normalization
            local n_spec = (p.specs and p.specs.normalize) or {}
            local name = n_spec.name or p.name

            if type(name) == "string" then
                lookup[name] = p
                -- normalize field so deps code can read it later
                p.name = name
                p.deps = n_spec.data.depends or {}
                p.priority = n_spec.data.priority or 0
            else
                vim.notify("Warning: pack missing name in stage " .. tostring(stage), vim.log.levels.WARN)
            end
        end

        table.sort(group, function(a, b)
            return (a.priority or 0) > (b.priority or 0)
        end)

        local ordered, seen = {}, {}

        local function add_with_deps(pkg)
            if not pkg or not pkg.name or seen[pkg.name] then
                return
            end
            seen[pkg.name] = true
            for _, dep in ipairs(pkg.deps or {}) do
                if type(dep) == "string" then
                    local dep_pkg = lookup[dep]
                    if dep_pkg then
                        add_with_deps(dep_pkg)
                    end
                end
            end
            table.insert(ordered, pkg)
        end

        for _, pkg in ipairs(group) do
            add_with_deps(pkg)
        end

        sorted[stage] = ordered
    end

    return sorted
end

---Utility: extract normalized pack/plugin name from a spec or source string
---@param input any String or table spec
---@return string|nil name Normalized plugin name (e.g. "mason.nvim")
function U.extract_name(input)
    if not input then
        return nil
    end

    -- Case 1: simple string source, e.g. "williamboman/mason.nvim"
    if type(input) == "string" then
        return input:match("([^/]+)$")
    end

    -- Case 2: table with explicit name
    if type(input) == "table" then
        if input.name then
            return input.name
        end

        -- table with src key or array form, e.g. { src = "williamboman/mason.nvim" } or { "williamboman/mason.nvim" }
        local source = input.src or input[1]
        if type(source) == "string" then
            return source:match("([^/]+)$")
        end
    end

    -- Fallback
    return nil
end

function U.get_lua_files_recursive_opts(directory, opts)
    opts = opts or {}
    local exclude_dirs = opts.exclude_dirs or {}
    local exclude_files = opts.exclude_files or {}
    local exclude_patterns = opts.exclude_patterns or {}

    local function should_exclude(name, path)
        -- check directory exclusions
        for _, dir in ipairs(exclude_dirs) do
            if path:match("/" .. vim.pesc(dir) .. "/") or path:match("/" .. vim.pesc(dir) .. "$") then
                return true
            end
        end

        -- check exact filename exclusions
        for _, file in ipairs(exclude_files) do
            if name == file then
                return true
            end
        end

        -- check pattern exclusions
        for _, pattern in ipairs(exclude_patterns) do
            if path:match(pattern) then
                return true
            end
        end

        return false
    end

    return vim.fs.find(function(name, path)
        return name:match("%.lua$") and not should_exclude(name, path)
    end, {
        path = directory,
        type = "file",
        limit = math.huge,
    })
end

U.get_module = function(name)
    local module = name:match("^[^.]+")
    return module
end

U.get_dep_names = function(deps)
    local names = {}
    for _, dep in ipairs(deps) do
        if type(dep) == "string" then
            table.insert(names, U.extract_name(dep))
        else
            local name = type(dep[1]) == "string" and dep[1] or dep.name or dep.src
            table.insert(names, U.extract_name(name))
        end
    end
    return names
end

return U
