-- ============================================================================
-- file: pack_ops.lua (or wherever you want this)
-- High-level helpers to build / load / update / delete packs
-- ============================================================================

local Container = require("sage.core.container").get_instance

---@private
---@return Sage.Spec[], string[]
local function get_specs_and_names()
    local config = require("sage.config")
    local plugin_fpaths = vim.fn.glob(config.opts.config_path .. config.opts.plugins_rpath .. "*.lua", true, true) ---@type string[]
    local specs, names = {}, {} ---@type Sage.Spec[], string[]

    for _, plugin_fpath in ipairs(plugin_fpaths) do
        local plugin_name = vim.fn.fnamemodify(plugin_fpath, ":t:r")
        local success, spec = pcall(require, "plugins." .. plugin_name)

        if not success then
            vim.schedule(function()
                vim.notify(("Failed to load plugin spec for %s"):format(plugin_name), vim.log.levels.ERROR)
            end)
        elseif type(spec) ~= "table" then
            vim.schedule(function()
                vim.notify(("Invalid spec for %s, not a table"):format(plugin_name), vim.log.levels.ERROR)
            end)
        else
            if spec.depends and type(spec.depends) == "table" then
                for _, dep in ipairs(spec.depends) do
                    if dep.src and type(dep.src) == "string" then
                        specs[#specs + 1] = dep
                        names[#names + 1] = vim.fn.fnamemodify(dep.src, ":t")
                    else
                        vim.schedule(function()
                            vim.notify(
                                ("Invalid dependency for %s, missing src"):format(plugin_name),
                                vim.log.levels.ERROR
                            )
                        end)
                    end
                end
            end

            if spec.src and type(spec.src) == "string" then
                specs[#specs + 1] = spec
                names[#names + 1] = vim.fn.fnamemodify(spec.src, ":t")
            else
                vim.schedule(function()
                    vim.notify(("Invalid spec for %s, missing src"):format(plugin_name), vim.log.levels.ERROR)
                end)
            end
        end
    end

    return specs, names
end

---@private
---@return string[]
local function get_package_names()
    local config = require("sage.config")
    local package_fpaths = vim.fn.glob(config.opts.data_path .. config.opts.packages_rpath .. "*/", false, true) ---@type string[]
    local package_names = {} ---@type string[]

    for _, package_fpath in ipairs(package_fpaths) do
        local package_name = vim.fn.fnamemodify(package_fpath:sub(1, -2), ":t")
        package_names[#package_names + 1] = package_name
    end

    return package_names
end

---@param spec_names string[]
local function handle_delete(spec_names)
    vim.schedule(function()
        local ok, err = pcall(vim.pack.del, spec_names)
        if not ok then
            vim.notify(("Failed to delete %s: %s"):format(table.concat(spec_names, ", "), err), vim.log.levels.ERROR)
        end
    end)
end

---@param spec_names string[]
---@param opts? { force?: boolean }
local function handle_update(spec_names, opts)
    opts = opts or {}
    vim.schedule(function()
        local ok, err = pcall(vim.pack.update, spec_names, { force = opts.force or false })
        if not ok then
            vim.notify(("Failed to update %s: %s"):format(table.concat(spec_names, ", "), err), vim.log.levels.ERROR)
        end
    end)
end

local function is_blank(str)
    return not str or str:match("^%s*$") ~= nil
end

---@param spec Sage.Spec
---@param path string
local function handle_build(spec, path)
    if
        type(spec.src) ~= "string"
        or type(spec.data) ~= "table"
        or type(spec.data.build) ~= "string"
        or is_blank(spec.data.build)
    then
        return
    end

    local config = require("sage.config")
    local package_name = vim.fn.fnamemodify(spec.src, ":t")
    local package_fpath = config.opts.data_path .. config.opts.packages_rpath .. package_name
    local stat = vim.uv.fs_stat(package_fpath)
    if not stat or stat.type ~= "directory" then
        return
    end

    vim.schedule(function()
        vim.notify(("Building %s..."):format(package_name), vim.log.levels.WARN)
        local cmd = vim.split(spec.data.build, " ")
        local response = vim.system(cmd, { cwd = path }):wait()
        vim.notify(
            ("Build %s for %s"):format(response.code ~= 0 and "failed" or "successful", package_name),
            response.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.INFO
        )
    end)
end

-- ============================================================================
-- Load packs
-- ============================================================================

---@param pack Sage.Pack
---@return boolean, string|nil
local function handle_load(pack)
    local container = Container()
    local loader = container:resolve("loader")
    local name = pack.name or (pack.src and vim.fn.fnamemodify(pack.src, ":t")) or "<unknown>"

    vim.notify(("Loading %s..."):format(name), vim.log.levels.INFO)

    local ok, err = pcall(function()
        loader:load_pack_safe(pack)
    end)

    if not ok then
        vim.notify(("Load failed for %s: %s"):format(name, err), vim.log.levels.ERROR)
        return false, err
    end

    vim.notify(("Load successful for %s"):format(name), vim.log.levels.INFO)
    return true, nil
end

local M = {}

M.build = function(spec, path)
    handle_build(spec, path)
end

---Load one or more packs by name, or all packs.
---@param spec_names string[]|nil
---@param all boolean|nil
---@return boolean, table|nil  # success, errors
M.load = function(spec_names, all)
    local container = Container()
    local manager = container:resolve("manager")
    local errors = {}
    local success = true

    if all then
        -- Load all known packs
        for name, pack in pairs(manager.packs or {}) do
            if pack.installed and not pack.active then
                local ok, err = handle_load(pack)
                if not ok then
                    success = false
                    errors[name] = err
                end
            end
        end
        return success, errors
    end

    spec_names = spec_names or {}

    for _, name in ipairs(spec_names) do
        local pack = manager.packs[name]
        if not pack then
            vim.notify(("Unknown pack: %s"):format(name), vim.log.levels.WARN)
            success = false
            errors[name] = "unknown pack"
        elseif not pack.installed then
            vim.notify(("Pack not installed: %s"):format(name), vim.log.levels.WARN)
            success = false
            errors[name] = "not installed"
        else
            local ok, err = handle_load(pack)
            if not ok then
                success = false
                errors[name] = err
            end
        end
    end

    return success, errors
end

---@param spec_names string[]
---@param all boolean|nil
---@param opts? { force?: boolean }
M.update = function(spec_names, all, opts)
    opts = opts or {}
    if all then
        -- If all is true, fetch all known spec names
        local _, names = get_specs_and_names()
        handle_update(names, opts)
    else
        handle_update(spec_names or {}, opts)
    end
end

---@param spec_names string[]
---@param all boolean|nil
M.delete = function(spec_names, all)
    if all then
        local names = get_package_names()
        handle_delete(names)
    else
        handle_delete(spec_names or {})
    end
end

return M
