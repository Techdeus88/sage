---@private
---@return Sage.Spec[], string[]
local function get_specs_and_names()
    local config = require("sage.config")
    local plugin_fpaths = vim.fn.glob(config.opts.config_path .. config.opts.plugins_rpath .. "*.lua", true, true) ---@type string[]
    local specs, names = {}, {} ---@type Sage.Spec[], string[]

    for _, plugin_fpath in ipairs(plugin_fpaths) do
        local plugin_name = vim.fn.fnamemodify(plugin_fpath, ":t:r")
        local success, spec = pcall(require, "plugins." .. plugin_name) ---@type boolean, UnPack.Spec

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
        local delete_ok, _ = pcall(vim.pack.del, spec_names)
        if not delete_ok then
            return
        end
    end)
end

---@param spec_names string[]
local function handle_update(spec_names, opts)
    vim.schedule(function()
        local update_ok, _ = pcall(vim.pack.update, spec_names, { force = opts.force })
        if not update_ok then
            return
        end
    end)
end

local function handle_build(spec, path)
    if
        type(spec.src) ~= "string"
        or type(spec.data) ~= "table"
        or type(spec.data.build) ~= "string"
        or spec.data.build:is_empty_or_whitespace()
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
        local response = vim.system(vim.split(spec.data.build, " "), { cwd = path }):wait()
        vim.notify(
            ("Build %s for %s"):format(response.code ~= 0 and "failed" or "successful", package_name),
            response.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.INFO
        )
    end)
end

local M = {}

M.build = function(spec, path)
    handle_build(spec, path)    
end

---@param spec_names string[]
M.update = function(spec_names, all)
    if not all then
        for _, spec_name in ipairs(spec_names) do
            handle_update({ spec_name })
        end
    else
        handle_update(spec_names)
    end
end

M.delete = function(spec_names, all)
    if not all then
        for _, spec_name in ipairs(spec_names) do
            handle_delete({ spec_name })
        end
    else
        handle_delete(spec_names)
    end
end

return M
