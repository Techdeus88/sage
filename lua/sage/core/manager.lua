-- ============================================================================
-- SAGE PACK MANAGER (FIXED - Drop-in Ready)
-- ============================================================================
local Manager = {}
Manager.__index = Manager

function Manager.new(container, opts)
    local self = setmetatable({}, Manager)

    self.container = container
    self.opts = opts

    self.bus = self.container:resolve("bus")
    self.utils = self.container:resolve("utils")
    self.loader = nil

    self.packs = {}
    self.install_times = {}

    -- Track installation state
    self.installation_complete = false
    self.installation_success = false
    self.installation_result = nil

    return self
end

-- ============================================================================
-- Load Pack Specs (Now uses pre-normalized specs from config)
-- ============================================================================
function Manager:load_specs()
    local Utils = self.utils
    local config = require("sage.config")

    -- Specs are already loaded and normalized by config.setup()
    local all_specs = config.get_all_specs()

    if #all_specs == 0 then
        Utils.safe_notify("No pack specs found", vim.log.levels.INFO)
        return {}
    end

    Utils.safe_notify(
        string.format("Using %d pre-normalized specs from config", #all_specs),
        vim.log.levels.DEBUG
    )

    return all_specs
end

-- ============================================================================
-- Dashboard Detection
-- ============================================================================
local function should_show_dashboard(all_specs, opts)
    if opts.dashboard == "smart" then
        for _, spec in ipairs(all_specs) do
            if not spec.installed or spec.status == "failed" or spec.status == "installing" then
                return true
            end
        end
    elseif opts.dashboard == "simple" then
        return true
    end

    return false
end

-- ============================================================================
-- Pack Creation
-- ============================================================================
function Manager:create_pack(spec)
    local pack = self.container:resolve("pack")
    -- local TaskSystem = self.container:resolve("task_system")

    local Pack = pack.new(spec)

    -- ✅ CRITICAL: Mark as NOT installed yet
    Pack.installed = false
    Pack.loaded = false

    -- ✅ Wire the task system (sets up lifecycle, doesn't run it)
    -- TaskSystem.wire_pack(Pack)

    return Pack
end

function Manager:get_packs()
    return self.packs
end

function Manager:get_pack(name)
    return self.packs[name]
end

function Manager:update_pack(name, updated_pack)
    local pack = self.packs[name]
    if pack then
        self.packs[name] = updated_pack
        updated_pack:set_status("updated")
    end
    return self.packs[name]
end

-- ============================================================================
-- Flatten pack groups into a single array
-- ============================================================================
function Manager:flatten_pack_groups(pack_groups)
    local all_packs = {}
    local stages_to_install = { "now", "lazy", "later", "disabled" }

    for _, stage in ipairs(stages_to_install) do
        if pack_groups[stage] and type(pack_groups[stage]) == "table" then
            for _, pack in ipairs(pack_groups[stage]) do
                if pack then
                    pack._install_stage = stage
                    table.insert(all_packs, pack)
                end
            end
        end
    end

    return all_packs
end

-- ============================================================================
-- Create all packs from specs
-- ============================================================================
function Manager:create_all_packs(specs)
    local Utils = self.utils
    local Bus = self.bus
    local delay = 115

    if #specs == 0 then
        Utils.safe_notify("No pack specs to create", vim.log.levels.INFO)
        return {}
    end

    local packs = {}
    local seen_names = {}
    local create_start = vim.loop.hrtime()

    for i, spec in ipairs(specs) do
        local pack_create_start = vim.loop.hrtime()

        local pack = self:create_pack(spec)
        local name = pack.name

        if seen_names[name] then
            Utils.safe_notify(string.format("Duplicate pack '%s' found (skipping)", name), vim.log.levels.WARN)
            goto continue
        end

        seen_names[name] = true
        pack:set_status("created")

        pack.times = pack.times or {}
        pack.times.create_duration = string.format("%.2f", (vim.loop.hrtime() - pack_create_start) / 1e6)

        self.packs[name] = pack
        table.insert(packs, pack)

        -- ✅ RESTORED: Emit pack:created event for each pack
        -- This allows dashboard to track individual pack creation
        vim.schedule(function()
                vim.defer_fn(function()
            Bus.emit("pack:created", {
                name = name,
                stage = pack:get_stage(),
                status = "created",
                message = "Pack created",
                pack = pack,
            })
            end, delay * i)
        end)

        ::continue::
    end

    local total_create_time = (vim.loop.hrtime() - create_start) / 1e6

    -- Emit batch creation complete event
    vim.schedule(function()
        Bus.emit("pack:all_created", {
            num_packs = #packs,
            packs = packs,
            create_duration = string.format("%.2f", total_create_time),
        })
    end)

    return packs
end

-- ============================================================================
-- MANAGER: Installation + Stage Classification
-- ============================================================================
function Manager:install_and_classify_batch(packs)
    -- 1. Classify packs by stage BEFORE installation
    local by_stage = {
        now = {},
        lazy = {},
        later = {},
        disabled = {}
    }
    
    for _, pack in ipairs(packs) do
        local stage = pack:get_stage()
        table.insert(by_stage[stage], pack)
    end
    
    -- 2. Install ALL packs (stage doesn't affect installation)
    local all_packs = vim.iter(vim.tbl_values(by_stage)):flatten()
    self:install_batch(all_packs, function(success)
        if success then
            -- 3. After install completes, pass to Loader by stage
            self:initiate_stage_loading(by_stage)
        end
    end)
end

function Manager:install_batch(packs, on_complete)
    local pack_names = {}
    
    for _, pack in ipairs(packs) do
        pack:set_status("installing")
        Bus.emit("pack:installing", { name = pack.name, pack = pack })
        table.insert(pack_names, pack.specs.normalize)
    end
    
    -- Submit to vim.pack.add (all at once for efficiency)
    vim.pack.add(pack_names, { load = false })
    
    -- Poll for completion
    self:poll_installation_complete(packs, on_complete)
end

function Manager:poll_installation_complete(packs, on_complete)
    local timer = vim.uv.new_timer()
    local check_interval = 100 -- ms
    local max_attempts = 100 -- 10 seconds total
    local attempts = 0
    
    timer:start(check_interval, check_interval, vim.schedule_wrap(function()
        attempts = attempts + 1
        local all_done = true
        
        for _, pack in ipairs(packs) do
            if pack:get_status() == "installing" then
                local pack_info = vim.pack.get({ pack.name })
                
                if pack_info and pack_info.path then
                    -- ✅ Installation confirmed
                    pack.installed = true
                    pack:set_path(pack_info.path)
                    pack:set_status("installed")
                    
                    Bus.emit("pack:installed", {
                        name = pack.name,
                        pack = pack,
                        stage = pack:get_stage()
                    })
                else
                    all_done = false
                end
            end
        end
        
        if all_done or attempts >= max_attempts then
            timer:close()
            
            -- Handle timeouts
            if attempts >= max_attempts then
                for _, pack in ipairs(packs) do
                    if pack:get_status() == "installing" then
                        pack:set_status("failed")
                        pack.error = "Installation timeout"
                    end
                end
            end
            
            if on_complete then
                on_complete(all_done)
            end
        end
    end))
end

function Manager:initiate_stage_loading(by_stage)
    local Bus = self.bus
    local Loader = self.container:resolve("loader")
    
    -- Load stages in order: now → lazy → later → disabled
    Loader:load_stage("now", by_stage.now, function()
        Loader:load_stage("lazy", by_stage.lazy, function()
            Loader:load_stage("later", by_stage.later, function()
                Loader:load_stage("disabled", by_stage.disabled, function()
                    Bus.emit("pack:all_stages_complete")
                end)
            end)
        end)
    end)
end

-- ============================================================================
-- Process stages after installation completes
-- ============================================================================
function Manager:process_stages(by_stage)
    local Utils = self.utils
    local Bus = self.bus
    local Loader = self.container:resolve("loader")

    local stages_start = vim.loop.hrtime()
    local stage_results = {}

    local function process_stage(stage_name, packs)
        if #packs == 0 then
            Utils.safe_notify(string.format("[STAGE] %s: 0 packs, skipping", stage_name), vim.log.levels.DEBUG)
            stage_results[stage_name] = { success = true, count = 0, duration = 0 }
            return true
        end

        local stage_start = vim.loop.hrtime()
        local pack_names = vim.tbl_map(function(p)
            return p.specs.normalize.name
        end, packs)

        Utils.safe_notify(
            string.format("[STAGE] %s: Processing %d packs: %s", stage_name, #packs, table.concat(pack_names, ", ")),
            vim.log.levels.DEBUG
        )

        local ok, err = pcall(function()
            Loader:run(stage_name, packs, self, self.opts)
        end)

        local stage_duration = (vim.loop.hrtime() - stage_start) / 1e6

        if not ok then
            Utils.safe_notify(
                string.format(
                    "[STAGE] %s FAILED after %.2fms with %d packs\nPacks: %s\nError: %s",
                    stage_name,
                    stage_duration,
                    #packs,
                    table.concat(pack_names, ", "),
                    tostring(err)
                ),
                vim.log.levels.ERROR
            )

            for _, pack in ipairs(packs) do
                pack:set_status("failed")
            end

            stage_results[stage_name] = {
                success = false,
                count = #packs,
                duration = stage_duration,
                error = tostring(err),
            }

            return false
        end

        Utils.safe_notify(
            string.format("[STAGE] %s: Completed %d packs in %.2fms", stage_name, #packs, stage_duration),
            vim.log.levels.DEBUG
        )

        stage_results[stage_name] = {
            success = true,
            count = #packs,
            duration = stage_duration,
        }

        return true
    end

    local now_ok = process_stage("now", by_stage.now)
    local lazy_ok = process_stage("lazy", by_stage.lazy)
    local later_ok = process_stage("later", by_stage.later)
    local disabled_ok = process_stage("disabled", by_stage.disabled)

    local total_duration = (vim.loop.hrtime() - stages_start) / 1e6
    local all_success = now_ok and lazy_ok and later_ok and disabled_ok

    vim.schedule(function()
        Bus.emit("pack:complete", {
            duration = string.format("%.2f", total_duration),
            num_packs = #by_stage.now + #by_stage.lazy + #by_stage.later + #by_stage.disabled,
            by_stage = {
                now = #by_stage.now,
                lazy = #by_stage.lazy,
                later = #by_stage.later,
                disabled = #by_stage.disabled,
            },
            stage_results = stage_results,
            all_stages_success = all_success,
        })
    end)

    return all_success
end

-- ============================================================================
-- Main Entry Point: run_packs method
-- ============================================================================
function Manager:run_packs()
    local Utils = self.utils
    local Bus = self.bus
    local Dashboard = self.container:resolve("dashboard")

    local run_start = vim.loop.hrtime()

    -- Load pre-normalized specs from config
    local all_specs = self:load_specs()

    if #all_specs == 0 then
        Utils.safe_notify("No pack specs found, nothing to do", vim.log.levels.INFO)
        return {}
    end

    Utils.safe_notify(
        string.format("Processing %d pre-normalized pack specs", #all_specs),
        vim.log.levels.INFO
    )

    local show_dashboard = should_show_dashboard(all_specs, self.opts)

    if show_dashboard then
        vim.defer_fn(function()
            Dashboard:open()
        end, 500)
    end

    local all_packs = self:create_all_packs(all_specs)
    
    if #all_packs == 0 then
        Utils.safe_notify("No packs created successfully", vim.log.levels.WARN)
        return {}
    end

    Utils.safe_notify(
        string.format(
            "Pack distribution - now: %d, lazy: %d, later: %d, disabled: %d",
            #by_stage.now,
            #by_stage.lazy,
            #by_stage.later,
            #by_stage.disabled
        ),
        vim.log.levels.INFO
    )

    local install_ok = self:install_and_classify_batch(all_packs)
    
    if not install_ok then
        Utils.safe_notify("Failed to start batch installation", vim.log.levels.ERROR)
        return {}
    end

    return all_packs
end

-- ============================================================================
-- Cleanup (same as before - no changes needed)
-- ============================================================================
function Manager:cleanup()
    local Utils = self.utils
    local Bus = self.bus
    local cleanup_start = vim.loop.hrtime()

    Utils.safe_notify("Starting manager cleanup...", vim.log.levels.DEBUG)

    local Loader = self.container:resolve("loader")
    local TaskSystem = self.container:resolve("task_system")

    local stats = {
        packs_cleaned = 0,
        loaders_closed = 0,
        timers_closed = 0,
        tasks_unwired = 0,
        errors = {},
    }

    if Loader and type(Loader.close_all) == "function" then
        local ok, err = pcall(function()
            Loader:close_all()
            stats.loaders_closed = 1
        end)
        if not ok then
            table.insert(stats.errors, string.format("Loader cleanup failed: %s", tostring(err)))
            Utils.safe_notify(string.format("Failed to close loaders: %s", tostring(err)), vim.log.levels.WARN)
        end
    end

    for name, pack in pairs(self.packs) do
        local pack_ok, pack_err = pcall(function()
            if TaskSystem and type(TaskSystem.unwire_pack) == "function" then
                TaskSystem.unwire_pack(pack)
                stats.tasks_unwired = stats.tasks_unwired + 1
            end

            if pack.cleanup and type(pack.cleanup) == "function" then
                pack:cleanup()
            end

            if pack.timers then
                for timer_name, timer in pairs(pack.timers) do
                    if timer and type(timer) == "table" and timer.close then
                        if not timer:is_closing() then
                            pcall(function()
                                timer:close()
                                stats.timers_closed = stats.timers_closed + 1
                            end)
                        end
                    end
                end
                pack.timers = nil
            end

            pack.installed = nil
            pack.loaded = nil
            pack.times = nil
            pack._install_stage = nil
            pack.lifecycle = nil
            pack._task_event_listeners = nil

            stats.packs_cleaned = stats.packs_cleaned + 1
        end)

        if not pack_ok then
            table.insert(stats.errors, string.format("Pack '%s' cleanup failed: %s", name, tostring(pack_err)))
        end
    end

    self.packs = {}
    self.install_times = {}
    self.installation_complete = false
    self.installation_success = false
    self.installation_result = nil

    local cleanup_duration = (vim.loop.hrtime() - cleanup_start) / 1e6

    vim.schedule(function()
        Bus.emit("manager:cleanup", {
            duration = string.format("%.2f", cleanup_duration),
            stats = stats,
            success = #stats.errors == 0,
        })
    end)

    if #stats.errors > 0 then
        Utils.safe_notify(
            string.format(
                "Manager cleanup completed with %d errors in %.2fms:\n%s",
                #stats.errors,
                cleanup_duration,
                table.concat(stats.errors, "\n")
            ),
            vim.log.levels.WARN
        )
    else
        Utils.safe_notify(
            string.format(
                "Manager cleanup successful: %d packs, %d tasks unwired, %d timers (%.2fms)",
                stats.packs_cleaned,
                stats.tasks_unwired,
                stats.timers_closed,
                cleanup_duration
            ),
            vim.log.levels.DEBUG
        )
    end

    return stats
end

return Manager
