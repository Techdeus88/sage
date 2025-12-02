-- ============================================================================
-- sage/config.lua
-- Early normalization and validation of user specs
-- ============================================================================

---@class Sage.Config.UserOpts
---@field config_path string
---@field data_path string
---@field packages_rpath string
---@field sage_rpath string
---@field plugins_rpath string
---@field exclude_dirs string[]
---@field add_opts table
---@field update_opts table
---@field strategy string
---@field check_interval number
---@field delay_time_ms number
---@field idle_time_ms number
---@field dashboard string
---@field dashboard_auto_close number
---@field dashboard_threshold number
---@field lock_windows boolean
---@field auto_focus boolean
---@field level string
---@field max_log number
---@field install_timeout number

local M = {} ---@class Sage.Config

M.opts = { ---@class Sage.Config.Opts
    config_path = vim.fn.stdpath("config"),
    data_path = vim.fn.stdpath("data"),
    packages_rpath = "/site/pack/core/opt/",
    sage_rpath = "/site/pack/core/start/sage/",
    plugins_rpath = "/lua/packs/", -- Directory to load pack specs from
    exclude_dirs = { "configs", "tests", "spec", "node_modules", ".git" },
    add_opts = { confirm = false }, ---@type vim.pack.keyset.add
    update_opts = { force = true }, ---@type vim.pack.keyset.update
    strategy = "vimenter", -- "vimenter", "delay", or "idle"
    check_interval = 100, -- How often the timer checks idle time
    delay_time_ms = 1000, -- Delay before loading later-stage packs
    idle_time_ms = 1000, -- How long user must be idle before loading
    dashboard = "smart", -- "never", "manual", "errors", "first", "smart", "startup", "always"
    dashboard_auto_close = 2000,
    dashboard_threshold = 500,
    lock_windows = true,
    auto_focus = true,
    level = "INFO",
    max_log = 1000,
    install_timeout = 60000,
}

M.stages = {
    NOW = "now",
    LATER = "later",
    LAZY = "lazy",
    DISABLED = "disabled",
}

M.specs = nil -- Will hold normalized specs after setup()

-- ============================================================================
-- Validation Tables
-- ============================================================================

-- User-level spec keys (before normalization)
local VALID_SPEC_KEYS = {
    src = true,
    name = true,
    priority = true,
    enabled = true,
    version = true,
    config = true,
    depends = true,
    build = true,
    init = true,
    post = true,
    on = true,
    [1] = true, -- Allow array-style { "user/repo" }
}

-- Normalized pack spec keys (after normalization)
local VALID_PACK_SPEC_KEYS = {
    src = true,
    name = true,
    version = true,
    data = true,
}

-- spec.data keys
local VALID_PACK_DATA_KEYS = {
    depends = true,
    build = true,
    config = true,
    init = true,
    post = true,
    on = true,
    source = true,
    stage = true,
    enabled = true,
    priority = true,
}

-- spec.data.on keys
local VALID_ON_KEYS = {
    before = true,
    after = true,
    events = true,
    event = true,
    fts = true,
    ft = true,
    cmds = true,
    cmd = true,
    keys = true,
}

-- ============================================================================
-- Validation Functions
-- ============================================================================

--- Validate user spec key (before normalization)
---@param key string
---@return boolean
local function validate_spec_key(key)
    return VALID_SPEC_KEYS[key] == true
end

--- Validate normalized pack spec key
---@param key string
---@return boolean
local function validate_pack_spec_key(key)
    return VALID_PACK_SPEC_KEYS[key] == true
end

--- Validate spec.data key
---@param key string
---@return boolean
local function validate_pack_data_key(key)
    return VALID_PACK_DATA_KEYS[key] == true
end

--- Validate spec.data.on key
---@param key string
---@return boolean
local function validate_on_key(key)
    return VALID_ON_KEYS[key] == true
end

--- Validate a user spec table before normalization
---@param spec table
---@return boolean ok, string[] errors
local function validate_spec_fields(spec)
    local errors = {}
    if type(spec) ~= "table" then
        return false, { "spec is not a table" }
    end

    -- Check user-level keys
    for key, _ in pairs(spec) do
        if not validate_spec_key(key) then
            errors[#errors + 1] = ("Invalid top-level key: '%s'"):format(key)
        end
    end

    -- Basic required fields
    local src = spec.src or spec[1]
    if not src or type(src) ~= "string" then
        errors[#errors + 1] = "spec.src or spec[1] is required and must be a string"
    end

    return #errors == 0, errors
end

--- Validate a normalized pack spec
---@param spec table
---@return boolean ok, string[] errors
local function validate_pack_fields(spec)
    local errors = {}
    if type(spec) ~= "table" then
        return false, { "spec is not a table" }
    end

    -- 1. top-level keys
    for key, _ in pairs(spec) do
        if not validate_pack_spec_key(key) then
            errors[#errors + 1] = ("Invalid top-level key: '%s'"):format(key)
        end
    end

    -- 2. spec.data keys
    local data = spec.data
    if data ~= nil then
        if type(data) ~= "table" then
            errors[#errors + 1] = "spec.data must be a table"
        else
            for key, _ in pairs(data) do
                if not validate_pack_data_key(key) then
                    errors[#errors + 1] = ("Invalid data key: 'data.%s'"):format(key)
                end
            end

            -- 3. spec.data.on keys
            local on = data.on
            if on ~= nil then
                if type(on) ~= "table" then
                    errors[#errors + 1] = "spec.data.on must be a table"
                else
                    for key, _ in pairs(on) do
                        if not validate_on_key(key) then
                            errors[#errors + 1] = ("Invalid on key: 'data.on.%s'"):format(key)
                        end
                    end
                end
            end
        end
    end

    return #errors == 0, errors
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

---Utility: extract normalized pack/plugin name from a spec or source string
---@param input any String or table spec
---@return string|nil name Normalized plugin name (e.g. "mason.nvim")
local function extract_name(input)
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
        -- table with src key or array form
        local source = input.src or input[1]
        if type(source) == "string" then
            return source:match("([^/]+)$")
        end
    end
    return nil
end

---Get all .lua files recursively from a directory
---@param exclude_dirs? table
---@param path string
---@return string[]
local function get_lua_files_recursive_opts(path, exclude_dirs)
    exclude_dirs = exclude_dirs or {}
    local files = {}

    local function is_excluded(dir_name)
        for _, excluded in ipairs(exclude_dirs) do
            if dir_name == excluded then
                return true
            end
        end
        return false
    end

    local function scan_dir(dir)
        local handle = vim.loop.fs_scandir(dir)
        if not handle then
            return
        end

        while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then
                break
            end

            local full_path = dir .. "/" .. name

            if type == "directory" then
                if not is_excluded(name) then
                    scan_dir(full_path)
                end
            elseif type == "file" and name:match("%.lua$") then
                table.insert(files, full_path)
            end
        end
    end

    scan_dir(path)
    return files
end

-- ============================================================================
-- Spec Normalization
-- ============================================================================
local function determine_stage(spec)
    local stage = ""
    local disabled = spec.enabled ~= nil and spec.enabled == false
    if disabled then
        stage = M.stages["DISABLED"]
        return stage
    end

    local on = spec.on
    if
        on ~= nil
        and (
            on.before ~= nil
            or on.after ~= nil
            or on.events ~= nil
            or on.event ~= nil
            or on.fts ~= nil
            or on.ft ~= nil
            or on.cmds ~= nil
            or on.cmd ~= nil
            or on.keys ~= nil
        )
    then
        stage = M.stages["LAZY"]
        return stage
    end

    if on ~= nil and on.stage == "now" then
        stage = M.stages["NOW"]
        return stage
    end

    stage = M.stages["LATER"]
    return stage
end

---Normalize a user spec into the standard pack format
---@param spec table User spec
---@return table|nil normalized_spec Normalized spec ready for vim.pack.add
local function normalize_spec(spec)
    if type(spec) ~= "table" then
        return nil
    end

    local prefix = "https://github.com/"
    local source = spec.src or spec[1]
    local name = spec.name or extract_name(source)
    local version = spec.version
    local disabled = not not (spec.enabled ~= nil and spec.enabled == false)
    local stage = determine_stage(spec)
    local priority = spec.priority or 100

    local n_spec = {}

    -- Required fields
    n_spec["src"] = prefix .. source
    n_spec["name"] = name
    n_spec["version"] = version

    -- Initialize data container (arbitrary data)
    n_spec["data"] = {}
    n_spec["data"]["on"] = {}

    n_spec.data.enabled = not disabled
    -- Move config-related fields into data
    if source then
        n_spec.data.source = source
    end

    if spec.priority then
        n_spec.data.priority = spec.priority
    end

    if spec.build then
        n_spec.data.build = spec.build
    end

    if spec.config then
        n_spec.data.config = spec.config
    end

    if spec.init then
        n_spec.data.init = spec.init
    end

    if spec.post then
        n_spec.data.post = spec.post
    end

    if spec.depends then
        n_spec.data.depends = spec.depends
    end

    if stage then
        n_spec.data.stage = stage
    end

    if spec.on then
        n_spec.data.on.events = spec.on.events or spec.on.event
        n_spec.data.on.fts = spec.on.fts or spec.on.ft
        n_spec.data.on.cmds = spec.on.cmds or spec.on.cmd
        n_spec.data.on.keys = spec.on.keys
        n_spec.data.on.before = spec.on.before
        n_spec.data.on.after = spec.on.after
    end

    return n_spec
end

-- ============================================================================
-- Spec Loading
-- ============================================================================

---Load and normalize all specs from the plugins directory
---@param specs_dir string Relative path to specs directory
---@return table[] normalized_specs Array of normalized specs
local function load_specs(opts)
    local all_specs = {}
    local seen_names = {}
    local pre_path = vim.fn.stdpath("config")
    local specs_dir = opts.plugins_rpath or "/lua/packs"
    local specs_path = pre_path .. specs_dir

    if vim.fn.isdirectory(specs_path) == 0 then
        vim.notify(string.format("Specs directory not found: %s", specs_path), vim.log.levels.WARN)
        return all_specs
    end

    local spec_files = get_lua_files_recursive_opts(specs_path, opts.exclude_dirs)

    if #spec_files == 0 then
        vim.notify(string.format("No spec files found in: %s", specs_path), vim.log.levels.INFO)
        return all_specs
    end

    for _, file in ipairs(spec_files) do
        local success, file_specs = pcall(dofile, file)

        if success and file_specs and type(file_specs) == "table" then
            for _, spec in ipairs(file_specs) do
                -- Validate user spec
                local is_valid, errors = validate_spec_fields(spec)

                if not is_valid then
                    vim.notify(
                        string.format("Invalid user spec in %s:\n%s", file, table.concat(errors, "\n")),
                        vim.log.levels.ERROR
                    )
                    goto continue
                end

                -- Normalize spec
                local n_spec = normalize_spec(spec)

                if not n_spec then
                    vim.notify(string.format("Failed to normalize spec from %s", file), vim.log.levels.ERROR)
                    goto continue
                end

                -- Validate normalized spec
                local is_valid_normalized, norm_errors = validate_pack_fields(n_spec)

                if not is_valid_normalized then
                    vim.notify(
                        string.format(
                            "Invalid normalized spec for %s:\n%s",
                            n_spec.name,
                            table.concat(norm_errors, "\n")
                        ),
                        vim.log.levels.ERROR
                    )
                    goto continue
                end

                -- Check for duplicates
                local name = n_spec.name
                if not seen_names[name] then
                    seen_names[name] = true
                    table.insert(all_specs, n_spec)
                else
                    vim.notify(string.format("Duplicate spec: %s (skipping)", name), vim.log.levels.WARN)
                end

                ::continue::
            end
        elseif not success then
            vim.notify(
                string.format("Failed to load spec file: %s - %s", file, tostring(file_specs)),
                vim.log.levels.ERROR
            )
        end
    end

    if #all_specs == 0 then
        vim.notify("No pack specs found", vim.log.levels.DEBUG)
        return all_specs
    end

    vim.notify(string.format("Loaded and normalized %d pack specs", #all_specs), vim.log.levels.DEBUG)

    return all_specs
end

-- ============================================================================
-- Public API
-- ============================================================================

---Setup configuration and load/normalize specs
---@param opts? Sage.Config.UserOpts User configuration options
function M.setup(opts)
    -- Merge user opts with defaults
    M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})

    -- Load and normalize all specs
    M.specs = load_specs(M.opts)

    -- Store spec count for later use
    M.count = #M.specs
end

---Get a specific normalized spec by name
---@param name string Pack name
---@return table|nil spec Normalized spec or nil
function M.get_spec(name)
    if not M.specs then
        return nil
    end

    for _, spec in ipairs(M.specs) do
        if spec.name == name then
            return spec
        end
    end

    return nil
end

---Get all normalized specs
---@return table[] specs Array of normalized specs
function M.get_all_specs()
    return M.specs or {}
end

---Validate a single spec (useful for runtime validation)
---@param spec table Spec to validate
---@param normalized? boolean Whether spec is already normalized
---@return boolean ok, string[] errors
function M.validate(spec, normalized)
    if normalized then
        return validate_pack_fields(spec)
    else
        return validate_spec_fields(spec)
    end
end

return M
