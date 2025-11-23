-- SAGE PACK MANAGER - FIXED & OPTIMIZED
-- ============================================================================
-- ============================================================================
local utils = require("sage.base.utils")

local Manager = {}
Manager.__index = Manager
Manager._singleton = nil

-- ============================================================================
-- Singleton Pattern (FIXED)
-- ============================================================================
function Manager:get_singleton()
    if Manager._singleton == nil then
        Manager._singleton = Manager.new()
    end
    return Manager._singleton
end

function Manager.new()
    local self = setmetatable({}, Manager)
    self.packs = {}
    self.install_times = {}
    self.delay_time = 100
    return self
end

-- ============================================================================
-- Pack Creation
-- ============================================================================
function Manager:create_pack(spec)
    local pack = require("sage.core.pack")
    local Pack = pack.new(spec)
    local TaskSystem = require("sage.core.tasks.system")
    -- Wire the task system
    TaskSystem.wire_pack(Pack)
    return Pack
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
-- Batch Installation with Callback-Based Tracking (FIXED)
-- ============================================================================
function Manager:install_activate_batch(pack_groups, on_complete)
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
        if on_complete then
            vim.schedule(function()
                on_complete(true, {})
            end)
        end
        return true
    end

    -- Build normalized specs
    local n_specs = vim.tbl_map(function(p)
        return p.specs.normalize
    end, all_packs)

    local total_to_install = #all_packs
    local install_finish_count = 0
    local failed_packs = {}
    local delay_start = 50

    -- Emit install:start events
    for i, pack in ipairs(all_packs) do
        local name = pack.specs.normalize.name
        pack:set_status("installing")

        vim.schedule(function()
            Event.emit("pack:install:start", {
                name = name,
                status = "installing",
                message = "Installation starting",
                pack = pack,
            })
        end)
    end

    local global_start = vim.loop.hrtime()

    -- Single batch installation with callback tracking
    local ok, err = pcall(vim.pack.add, n_specs, {
        confirm = false,
        load = function(data)
            local pack_name = data.spec.name
            local pack = self.packs[pack_name]

            if not pack then
                utils.safe_notify(string.format("Pack '%s' not found in manager", pack_name), vim.log.levels.WARN)
                table.insert(failed_packs, pack_name)
                install_finish_count = install_finish_count + 1

                -- Check if all done
                if install_finish_count == total_to_install then
                    if on_complete then
                        vim.schedule(function()
                            on_complete(true, {
                                installed_count = total_to_install - #failed_packs,
                                failed_count = #failed_packs,
                                failed_packs = failed_packs,
                            })
                        end)
                    end
                end
                return
            end

            pack.installed = true

            -- Load the pack
            vim.cmd("packadd " .. pack_name)

            -- Record timing
            local individual_time = vim.loop.hrtime() - global_start
            pack.times = pack.times or {}
            pack.times.install_duration = string.format("%.2f", individual_time / 1e6)

            -- Emit install:finish event WITHOUT vim.schedule (keep in load callback)
            vim.schedule(function()
                Event.emit("pack:install:finish", {
                    name = pack_name,
                    status = "installed",
                    message = "Installation complete",
                    install_duration = pack.times.install_duration,
                    pack = pack,
                })
            end)

            pack:set_active(data)
            pack:set_path(data.path)

            -- NOTE: Do NOT set any status here
            -- The Loaders will set the appropriate status for each stage:
            -- - "now" stage: will set to "loading" then "loaded"
            -- - "later" stage: will set to "pending" then trigger to "loading"/"loaded"
            -- - "lazy" stage: will set to "lazy" then trigger to "loading"/"loaded"
            -- - "disabled" stage: will set to "disabled"

            -- Increment counter
            install_finish_count = install_finish_count + 1

            -- Check if all packs have been installed
            if install_finish_count == total_to_install then
                if on_complete then
                    vim.schedule(function()
                        on_complete(true, {
                            installed_count = total_to_install - #failed_packs,
                            failed_count = #failed_packs,
                            failed_packs = failed_packs,
                        })
                    end)
                end
            end
        end,
    })

    if not ok then
        vim.schedule(function()
            utils.safe_notify(string.format("Batch installation failed: %s", tostring(err)), vim.log.levels.ERROR)
        end)

        -- Mark all as failed
        for _, pack in ipairs(all_packs) do
            pack.installed = false
            pack:set_status("failed")
        end

        vim.schedule(function()
            Event.emit("pack:install:failed", {
                count = #all_packs,
                message = "Batch installation failed",
                error = tostring(err),
            })
        end)

        if on_complete then
            vim.schedule(function()
                on_complete(false, {
                    error = tostring(err),
                    failed_count = #all_packs,
                })
            end)
        end

        return false
    end

    -- Schedule build commands to run after all packs are loaded
    -- vim.schedule(function()
    --     vim.defer_fn(function()
    --         for _, pack in ipairs(all_packs) do
    --             local original_spec = pack.specs.normalize
    --             if original_spec.data.build then
    --                 local name = original_spec.name
    --                 print(string.format("[BUILD] Running build for %s", name))
    --
    --                 local ok_build, err_build = pcall(function()
    --                     if type(original_spec.build) == "string" then
    --                         -- It's a command
    --                         vim.cmd(original_spec.build)
    --                     elseif type(original_spec.build) == "function" then
    --                         -- It's a function
    --                         original_spec.build()
    --                     end
    --                 end)
    --
    --                 if not ok_build then
    --                     utils.safe_notify(
    --                         string.format("[%s] Build failed: %s", name, tostring(err_build)),
    --                         vim.log.levels.WARN
    --                     )
    --                     print(string.format("[BUILD] ERROR for %s: %s", name, tostring(err_build)))
    --                 else
    --                     print(string.format("[BUILD] Success for %s", name))
    --                 end
    --             end
    --         end
    --     end, 500)  -- Defer build by 500ms to ensure everything is loaded
    -- end)

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
        -- pack:set_status("installing")

        vim.schedule(function()
            vim.defer_fn(function()
                Event.emit("pack:install:start", {
                    name = name,
                    status = pack:get_status(),
                    message = "Installation starting",
                    pack = pack,
                })
            end, delay_start * i)
        end)
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
        vim.schedule(function()
            utils.safe_notify(string.format("Installation failed: %s", tostring(err)), vim.log.levels.ERROR)
        end)

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
-- Load Pack Specs from Directory
-- ============================================================================
function Manager:load_specs(specs_dir)
    local all_specs = {}
    local seen_names = {}
    local pre_path = vim.fn.stdpath("config") .. "/lua"
    local specs_path = pre_path .. (specs_dir or "/packs")

    -- Check if directory exists
    if vim.fn.isdirectory(specs_path) == 0 then
        utils.safe_notify(string.format("Specs directory not found: %s", specs_path), vim.log.levels.WARN)
        return all_specs
    end

    -- Get spec files
    local spec_files = utils.get_lua_files_recursive_opts(specs_path, {
        exclude_dirs = { "configs", "tests", "spec", "node_modules", ".git" },
    })

    if #spec_files == 0 then
        utils.safe_notify(string.format("No spec files found in: %s", specs_path), vim.log.levels.INFO)
        return all_specs
    end

    -- Load and parse specs
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
                    utils.safe_notify(string.format("Duplicate spec: %s (skipping)", name), vim.log.levels.WARN)
                end
            end
        elseif not success then
            utils.safe_notify(
                string.format("Failed to load spec file: %s - %s", file, tostring(file_specs)),
                vim.log.levels.ERROR
            )
        end
    end

    if #all_specs == 0 then
        utils.safe_notify("No pack specs found", vim.log.levels.INFO)
        return all_specs
    end

    return all_specs
end

-- ============================================================================
-- Main Entry Point: run_packs method
-- ============================================================================
function Manager:run_packs(opts)
    opts = opts or {}
    local Event = require("sage.core.bus")
    local Loader = require("sage.core.loader")

    -- Load specs
    local all_specs = self:load_specs(opts.directory)
    if #all_specs == 0 then
        return all_specs
    end

    local all_packs = {}
    local delay = 75
    local total_to_create = #all_specs
    local created_count = 0

    -- Show dashboard if needed
    if opts.dashboard == "smart" and should_show_dashboard(all_specs) then
        local ok, Dashboard = pcall(require, "sage.ui.dashboard")
        if ok then
            Dashboard:open()
        end
    elseif opts.dashboard == "simple" then
        local ok, Dashboard = pcall(require, "sage.ui.dashboard")
        if ok then
            Dashboard:open()
        end
    end

    local function process_stages(by_stage)
        local function process_stage(stage_name, packs)
            if #packs == 0 then
                utils.safe_notify(string.format("[STAGE] %s: 0 packs, skipping", stage_name), vim.log.levels.DEBUG, {})
                return
            end

            local ok, err = pcall(Loader.run, stage_name, packs, self, opts)
            if not ok then
                utils.safe_notify(
                    string.format("Stage '%s' loading failed: %s", stage_name, tostring(err)),
                    vim.log.levels.ERROR
                )
            end
        end

        process_stage("now", by_stage.now)
        process_stage("lazy", by_stage.lazy)
        process_stage("later", by_stage.later)
        process_stage("disabled", by_stage.disabled)

        vim.schedule(function()
            Event.emit("pack:complete", {
                duration = 0,
                num_packs = #all_packs,
                by_stage = {
                    now = #by_stage.now,
                    later = #by_stage.later,
                    lazy = #by_stage.lazy,
                    disabled = #by_stage.disabled,
                },
            })
        end)
    end

    local function process_packs()
        local sorted = utils.sort_packs(all_packs)
        local by_stage = {
            now = sorted["now"] or {},
            later = sorted["later"] or {},
            lazy = sorted["lazy"] or {},
            disabled = sorted["disabled"] or {},
        }

        -- Start batch installation with callback
        -- The callback will fire when ALL packs have called their load() function
        self:install_activate_batch(by_stage, function(success, result)
            if not success then
                utils.safe_notify(string.format("Installation failed: %s", result.error), vim.log.levels.ERROR)
                return
            end

            if success then
                -- NOW process stages (only after all installs are done)
                process_stages(by_stage)
            end
        end)
    end

    for i, spec in ipairs(all_specs) do
        local Pack = self:create_pack(spec)
        local name = Pack.specs.normalize.name

        Pack:set_status("created")
        self.packs[name] = Pack
        table.insert(all_packs, Pack)

        -- Capture pack_index and name at loop time (closure fix)
        local pack_index = i
        local pack_name = name
        local pack_stage = Pack:get_stage()
        local pack_status = Pack:get_status()

        vim.schedule(function()
            vim.defer_fn(function()
                Event.emit("pack:created", {
                    name = pack_name,
                    stage = pack_stage,
                    status = pack_status,
                    pack = Pack,
                    message = "Creating pack",
                })
                created_count = created_count + 1
                if created_count == total_to_create then
                    Event.emit("pack:all_created", { num_packs = total_to_create })
                    process_packs()
                end
            end, delay * pack_index)
        end)
    end
    return all_packs
end

-- ============================================================================
-- Cleanup on shutdown
-- ============================================================================
function Manager:cleanup()
    local Loader = require("sage.core.loader")
    Loader:close_all()
    self.packs = {}
end

return Manager:get_singleton()
