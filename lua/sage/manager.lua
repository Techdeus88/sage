-- ============================================================================
-- SAGE PACK MANAGER - FIXED & OPTIMIZED
-- ============================================================================
local utils = require("sage.base.utils")

local Manager = {}
Manager.__index = Manager
Manager._singleton = nil

-- ============================================================================
-- Singleton Pattern (FIXED)
-- ============================================================================
function Manager:get_singleton()
    -- FIXED: Use Manager._singleton, not self._singleton
    if Manager._singleton == nil then
        Manager._singleton = Manager.new()
    end
    return Manager._singleton
end

function Manager.new()
    local self = setmetatable({}, Manager)
    self.packs = {}
    self.install_times = {}
    return self
end

-- ============================================================================
-- Pack Creation
-- ============================================================================
function Manager:create_pack(spec)
    local pack = require("sage.core.pack")
    local PackLifecycle = require("sage.core.lifecycle")

    local Pack = pack.new(spec)
    Pack.lifecycle = PackLifecycle.new(Pack)

    return Pack
end

-- ============================================================================
-- Wire Pack Tasks (Currently unused but kept for future)
-- ============================================================================
function Manager:wire_pack_tasks(pack)
    local Task = require("sage.core.task")
    local Event = require("sage.core.bus")
    local lc = pack.lifecycle

    lc:add_task(Task.new("install", function()
        Event.emit("pack:install:start", {
            name = pack.specs.normalize.name,
            status = "installing",
        })
        self:install_pack(pack)
        Event.emit("pack:install:finish", {
            name = pack.specs.normalize.name,
            status = "installed",
            install_duration = pack.times.install_duration,
        })
    end))

    lc:add_task(Task.new("config", function()
        Event.emit("pack:config:start", {
            name = pack.specs.normalize.name,
            status = "configuring",
        })
        self:configure_pack(pack)
        Event.emit("pack:config:finish", {
            name = pack.specs.normalize.name,
            status = "configured",
            config_duration = pack.times.config_duration,
        })
    end))
end

-- ============================================================================
-- Batch Installation (OPTIMIZED: Single vim.pack.add call)
-- ============================================================================
function Manager:install_activate_batch(pack_groups)
    local Event = require("sage.core.bus")

    -- Flatten all packs from all stages
    local all_packs = {}
    local stages_to_install = { "now", "lazy", "later", "disabled" }

    for _, stage in ipairs(stages_to_install) do
        if pack_groups[stage] then
            vim.list_extend(all_packs, pack_groups[stage])
        end
    end

    if #all_packs == 0 then
        return true
    end

    -- Build normalized specs
    local n_specs = vim.tbl_map(function(p)
        return p.specs.normalize
    end, all_packs)

    -- Emit install:start events
    local delay_start = 50
    for i, pack in ipairs(all_packs) do
        local name = pack.specs.normalize.name
        pack:set_status("installing")

        vim.defer_fn(function()
            Event.emit("pack:install:start", {
                name = name,
                status = "installing",
                message = "Installation starting",
                pack = pack,
            })
        end, delay_start * i)
    end

    -- Single batch installation
    local global_start = vim.loop.hrtime()

    local ok, err = pcall(vim.pack.add, n_specs, {
        confirm = false,
        load = function(data)
            local pack_name = data.spec.name
            local pack = self.packs[pack_name]

            if not pack then
                vim.notify(string.format("Pack '%s' not found in manager", pack_name), vim.log.levels.WARN)
                return
            end

            -- Load the pack
            vim.cmd("packadd " .. pack_name)

            -- Record timing (individual, not cumulative)
            local individual_time = vim.loop.hrtime() - global_start
            pack.times = pack.times or {}
            pack.times.install_duration = string.format("%.2f", individual_time / 1e6)

            pack:set_status("installed")
            pack.installed = true

            -- Emit install:finish event
            vim.schedule(function()
                Event.emit("pack:install:finish", {
                    name = pack_name,
                    status = "installed",
                    message = "Installation complete",
                    install_duration = pack.times.install_duration,
                    pack = pack,
                })
            end)
        end,
    })

    if not ok then
        vim.notify(string.format("Batch installation failed: %s", tostring(err)), vim.log.levels.ERROR)

        -- Mark all as failed
        for _, pack in ipairs(all_packs) do
            pack.installed = false
            pack:set_status("failed")
        end

        Event.emit("pack:install:failed", {
            count = #all_packs,
            message = "Batch installation failed",
            error = tostring(err),
        })

        return false
    end

    return true
end

-- ============================================================================
-- Individual Stage Installation (Legacy - kept for compatibility)
-- ============================================================================
function Manager:install_activate(packs)
    local Event = require("sage.core.bus")

    packs = packs or {}
    if #packs == 0 then
        return true
    end

    local n_specs = vim.tbl_map(function(p)
        return p.specs.normalize
    end, packs)

    local delay_start = 50
    local install_start = vim.loop.hrtime()

    -- Emit start events
    for i, pack in ipairs(packs) do
        local name = pack.specs.normalize.name
        pack:set_status("installing")

        vim.defer_fn(function()
            Event.emit("pack:install:start", {
                name = name,
                status = "installing",
                message = "Installation starting",
                pack = pack,
            })
        end, delay_start * i)
    end

    -- Install
    local ok, err = pcall(vim.pack.add, n_specs, {
        confirm = false,
        load = function(data)
            local pack_name = data.spec.name
            local pack = self.packs[pack_name]

            if pack then
                vim.cmd("packadd " .. pack_name)

                pack.times = pack.times or {}
                pack.times.install_duration = string.format("%.2f", (vim.loop.hrtime() - install_start) / 1e6)
                pack:set_status("installed")
                pack.installed = true

                vim.schedule(function()
                    Event.emit("pack:install:finish", {
                        name = pack_name,
                        status = "installed",
                        message = "Installation complete",
                        install_duration = pack.times.install_duration,
                        pack = pack,
                    })
                end)
            end
        end,
    })

    if not ok then
        vim.notify(string.format("Installation failed: %s", tostring(err)), vim.log.levels.ERROR)

        for _, pack in ipairs(packs) do
            pack.installed = false
            pack:set_status("failed")
        end

        Event.emit("pack:install:failed", {
            list = packs,
            count = #packs,
            message = "Installation failed",
            error = tostring(err),
        })

        return false
    end

    return true
end

-- ============================================================================
-- Dashboard Detection
-- ============================================================================
local function should_show_dashboard(all_specs)
    for _, spec in ipairs(all_specs) do
        if not spec.installed or spec.status == "failed" or spec.status == "installing" then
            return true
        end
    end
    return false
end

-- ============================================================================
-- Main Entry Point (FIXED: Removed debug statements)
-- ============================================================================
function Manager:run_packs(opts)
    opts = opts or {}

    -- Lazy-load dashboard to avoid circular dependency
    local Event = require("sage.core.bus")
    local Loader = require("sage.core.loader")

    local all_specs = {}
    local all_packs = {}
    local seen_names = {}

    -- Build paths
    local pre_path = vim.fn.stdpath("config") .. "/lua"
    print(pre_path)
    local specs_path = pre_path .. (opts.directory or "/packs")
    print(specs_path)

    -- Check if directory exists
    if vim.fn.isdirectory(specs_path) == 0 then
        vim.notify(string.format("Specs directory not found: %s", specs_path), vim.log.levels.WARN)
        return all_specs
    end

    -- Load spec files
    local spec_files = utils.get_lua_files_recursive_opts(specs_path, {
        exclude_dirs = { "configs", "tests", "spec", "node_modules", ".git" },
    })

    if #spec_files == 0 then
        vim.notify(string.format("No spec files found in: %s", specs_path), vim.log.levels.INFO)
        return all_specs
    end
    print(vim.inspect(spec_files))

    -- Parse specs
    for _, file in ipairs(spec_files) do
        local success, file_specs = pcall(dofile, file)

        if success and file_specs and type(file_specs) == "table" then
            for _, spec in ipairs(file_specs) do
                local src = spec.src or spec[1]
                local name = spec.name or utils.extract_name(src)

                if not seen_names[name] then
                    seen_names[name] = true
                    table.insert(all_specs, spec)
                else
                    vim.notify(string.format("Duplicate spec: %s (skipping)", name), vim.log.levels.WARN)
                end
            end
        elseif not success then
            vim.notify(
                string.format("Failed to load spec file: %s - %s", file, tostring(file_specs)),
                vim.log.levels.ERROR
            )
        end
    end

    if #all_specs == 0 then
        vim.notify("No pack specs found", vim.log.levels.INFO)
        print(vim.inspect(all_specs))
        return all_specs
    end

    -- Show dashboard if needed (lazy-load to avoid circular dep)
    if opts.dashboard == "smart" and should_show_dashboard(all_specs) then
        local ok, Dashboard = pcall(require, "sage.ui.dashboard")
        if ok then
            Dashboard:open()
        end
    elseif opts.dashboard == true then
        local ok, Dashboard = pcall(require, "sage.ui.dashboard")
        if ok then
            Dashboard:open()
        end
    end

    -- Create packs
    local delay = 75
    for i, spec in ipairs(all_specs) do
        local Pack = self:create_pack(spec)
        local name = Pack.specs.normalize.name

        Pack:set_status("created")
        self.packs[name] = Pack
        table.insert(all_packs, Pack)

        -- Emit pack created event
        vim.schedule(function()
            vim.defer_fn(function()
                Event.emit("pack:created", {
                    name = name,
                    stage = Pack:get_stage(),
                    status = Pack:get_status(),
                    pack = Pack,
                    message = "Creating pack",
                })
            end, delay * i)
        end)
    end

    -- Process packs after creation events
    vim.defer_fn(function()
        Event.emit("pack:all_created", { num_packs = #all_packs })

        -- Sort packs by stage
        local sorted = utils.sort_packs(all_packs)
        local by_stage = {
            now = sorted["now"] or {},
            later = sorted["later"] or {},
            lazy = sorted["lazy"] or {},
            disabled = sorted["disabled"] or {},
        }

        -- Stage-by-stage installation and loading
        local function process_stage(stage_name, packs, load_immediately)
            if #packs == 0 then
                return
            end

            local install_ok = self:install_activate(packs)
            if not install_ok then
                vim.notify(string.format("Stage '%s' installation failed", stage_name), vim.log.levels.ERROR)
                return
            end

            -- Load packs
            if load_immediately then
                local ok, err = pcall(Loader.run, stage_name, packs, self, opts)
                if not ok then
                    vim.notify(
                        string.format("Stage '%s' loading failed: %s", stage_name, tostring(err)),
                        vim.log.levels.ERROR
                    )
                end
            end
        end

        -- Process stages in order
        process_stage("now", by_stage.now, true)
        process_stage("lazy", by_stage.lazy, true)
        process_stage("later", by_stage.later, true)
        process_stage("disabled", by_stage.disabled, true)

        -- Emit completion
        vim.schedule(function()
            local total_duration = vim.loop.hrtime() - _G.sage.start
            Event.emit("pack:complete", {
                duration = total_duration,
                num_packs = #all_packs,
                by_stage = {
                    now = #by_stage.now,
                    later = #by_stage.later,
                    lazy = #by_stage.lazy,
                    disabled = #by_stage.disabled,
                },
            })
        end)
    end, delay * #all_specs + 100)
end

-- ============================================================================
-- Cleanup on shutdown
-- ============================================================================
function Manager:cleanup()
    local Loader = require("sage.core.loader")
    Loader.close_all()
    self.packs = {}
end

return Manager:get_singleton()
