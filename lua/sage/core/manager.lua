-- ============================================================================
-- SAGE PACK MANAGER
-- ============================================================================
local Manager = {}
Manager.__index = Manager

function Manager.new(container, opts)
    local self = setmetatable({}, Manager)

    self.container = container
    self.opts = opts ---@class SageConfig.Opts

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
-- Load Pack Specs from Directory
-- ============================================================================
function Manager:load_specs(specs_dir)
    local Utils = self.utils
    local all_specs = {}
    local seen_names = {}
    local pre_path = vim.fn.stdpath("config")
    local specs_path = pre_path .. (specs_dir or "/lua/packs")

    if vim.fn.isdirectory(specs_path) == 0 then
        Utils.safe_notify(string.format("Specs directory not found: %s", specs_path), vim.log.levels.WARN)
        return all_specs
    end

    local spec_files = Utils.get_lua_files_recursive_opts(specs_path, {
        exclude_dirs = { "configs", "tests", "spec", "node_modules", ".git" },
    })

    if #spec_files == 0 then
        Utils.safe_notify(string.format("No spec files found in: %s", specs_path), vim.log.levels.INFO)
        return all_specs
    end

    for _, file in ipairs(spec_files) do
        local success, file_specs = pcall(dofile, file)
        if success and file_specs and type(file_specs) == "table" then
            for _, spec in ipairs(file_specs) do
                local src = spec.src or spec[1]
                local name = spec.name or Utils.extract_name(src)
                if not seen_names[name] then
                    seen_names[name] = true
                    table.insert(all_specs, spec)
                else
                    Utils.safe_notify(string.format("Duplicate spec: %s (skipping)", name), vim.log.levels.WARN)
                end
            end
        elseif not success then
            Utils.safe_notify(
                string.format("Failed to load spec file: %s - %s", file, tostring(file_specs)),
                vim.log.levels.ERROR
            )
        end
    end

    if #all_specs == 0 then
        Utils.safe_notify("No pack specs found", vim.log.levels.INFO)
        return all_specs
    end

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
    local TaskSystem = self.container:resolve("task_system")

    local Pack = pack.new(spec)
    TaskSystem.wire_pack(Pack)

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

-- ==========================================================================
-- Flatten pack groups into a single array
-- ==========================================================================
function Manager:flatten_pack_groups(pack_groups)
    local all_packs = {}
    local stages_to_install = { "now", "lazy", "later", "disabled" }

    for _, stage in ipairs(stages_to_install) do
        if pack_groups[stage] and type(pack_groups[stage]) == "table" then
            for _, pack in ipairs(pack_groups[stage]) do
                -- Ensure pack has stage info for later reference
                if pack then
                    pack._install_stage = stage
                    table.insert(all_packs, pack)
                end
            end
        end
    end

    return all_packs
end

-- ==========================================================================
-- Create a timeout timer with proper cleanup
-- ==========================================================================
function Manager:create_timeout_timer(state, on_complete)
    local Utils = self.utils

    local timer = vim.loop.new_timer()
    local timeout_ms = self.opts.install_timeout or 30000 -- 30 seconds default

    timer:start(
        timeout_ms,
        0,
        vim.schedule_wrap(function()
            if state.completed < state.total then
                local timeout_msg = string.format(
                    "Installation timeout: %d/%d packs completed after %dms",
                    state.completed,
                    state.total,
                    timeout_ms
                )

                Utils.safe_notify(timeout_msg, vim.log.levels.WARN)

                -- Mark remaining packs as failed
                for name, pack in pairs(self.packs) do
                    if not pack.installed then
                        pack:set_status("failed")
                        table.insert(state.failed, name)
                    end
                end

                -- Calculate actual elapsed time
                local elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6

                -- Call completion callback with timeout error
                if on_complete then
                    on_complete(false, {
                        installed_count = state.completed,
                        failed_count = state.total - state.completed,
                        failed_packs = state.failed,
                        error = "Installation timeout",
                        elapsed_ms = elapsed_ms,
                        timeout = true,
                    })
                end
            end

            -- Clean up timer
            if timer and not timer:is_closing() then
                pcall(function()
                    timer:close()
                end)
            end
        end)
    )

    return timer
end

function Manager:handle_pack_load(data, state, on_complete)
    local Utils = self.utils
    local Bus = self.bus

    local pack_name = data.spec.name
    local pack = self.packs[pack_name]

    -- Validate pack exists
    if not pack then
        Utils.safe_notify(
            string.format("Pack '%s' not found in manager during load callback", pack_name),
            vim.log.levels.WARN
        )
        table.insert(state.failed, pack_name)
        state.completed = state.completed + 1
        self:check_installation_complete(state, on_complete)
        return
    end

    -- ✅ CRITICAL: Mark installed IMMEDIATELY (synchronously)
    pack.installed = true
    
    -- ✅ CRITICAL: Set metadata IMMEDIATELY
    pack:set_active(data)
    pack:set_path(data.path)

    -- ✅ CRITICAL: Record timing IMMEDIATELY
    pack.times = pack.times or {}
    pack.times.install_duration = "0.00" -- Will be updated later

    -- ✅ CRITICAL: Increment counter IMMEDIATELY
    state.completed = state.completed + 1

    -- ✅ NOW schedule the heavy work AFTER this callback returns
    vim.schedule(function()
        local pack_start_time = vim.loop.hrtime()
        
        -- 1. Packadd (can be slow)
        local packadd_ok, packadd_err = pcall(vim.cmd, "packadd " .. pack_name)
        if not packadd_ok then
            Utils.safe_notify(
                string.format("Failed to packadd '%s': %s", pack_name, tostring(packadd_err)),
                vim.log.levels.WARN
            )
        end

        -- 2. Update timing
        local install_duration_ms = (vim.loop.hrtime() - pack_start_time) / 1e6
        pack.times.install_duration = string.format("%.2f", install_duration_ms)

        -- 3. Emit event
        Bus.emit("pack:install:finish", {
            name = pack_name,
            status = "installed",
            message = "Installation complete",
            install_duration = pack.times.install_duration,
            pack = pack,
            stage = pack._install_stage,
        })

        -- 4. Run task lifecycle
        if pack.lifecycle then
            local ok, err = pack.lifecycle:run_next()
            if not ok and err ~= "no more tasks" then
                Utils.safe_notify(
                    string.format("Pack '%s' task lifecycle error: %s", pack_name, tostring(err)),
                    vim.log.levels.WARN
                )
            end
        end
    end)

    -- ✅ CRITICAL: Check completion synchronously
    -- Don't wait for scheduled work to finish
    if state.completed >= state.total then
        -- Close timeout timer
        if state.timer and not state.timer:is_closing() then
            pcall(function()
                state.timer:close()
            end)
            state.timer = nil
        end

        -- Calculate elapsed time
        local total_elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6

        -- Build result
        local result = {
            installed_count = state.total - #state.failed,
            failed_count = #state.failed,
            failed_packs = state.failed,
            elapsed_ms = total_elapsed_ms,
            total_packs = state.total,
        }

        -- ✅ Schedule the completion callback
        if on_complete then
            vim.schedule(function()
                on_complete(true, result)
            end)
        end
    end
end

-- Check if installation is complete and trigger callback
function Manager:check_installation_complete(state, on_complete)
    if state.completed >= state.total then
        -- Close timeout timer
        if state.timer and not state.timer:is_closing() then
            pcall(function()
                state.timer:close()
            end)
            state.timer = nil
        end

        -- Calculate total elapsed time
        local total_elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6

        -- Build result object
        local result = {
            installed_count = state.total - #state.failed,
            failed_count = #state.failed,
            failed_packs = state.failed,
            elapsed_ms = total_elapsed_ms,
            total_packs = state.total,
        }

        -- Call completion callback
        if on_complete then
            vim.schedule(function()
                on_complete(true, result)
            end)
        end
    end
end

-- Handle catastrophic installation failure
function Manager:handle_install_failure(err, all_packs, state, on_complete)
    local Utils = self.utils
    local Bus = self.bus

    -- Close timer if exists
    if state.timer and not state.timer:is_closing() then
        pcall(function()
            state.timer:close()
        end)
        state.timer = nil
    end

    -- Log error
    vim.schedule(function()
        Utils.safe_notify(string.format("Batch installation failed: %s", tostring(err)), vim.log.levels.ERROR)
    end)

    -- Mark all packs as failed
    for _, pack in ipairs(all_packs) do
        pack.installed = false
        pack:set_status("failed")

        local pack_name = pack.specs.normalize.name
        table.insert(state.failed, pack_name)
    end

    -- Emit failure event
    vim.schedule(function()
        Bus.emit("pack:install:failed", {
            count = #all_packs,
            message = "Batch installation failed",
            error = tostring(err),
            failed_packs = state.failed,
        })
    end)

    -- Calculate elapsed time
    local elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6

    -- Call completion callback with error
    if on_complete then
        vim.schedule(function()
            on_complete(false, {
                error = tostring(err),
                failed_count = #all_packs,
                failed_packs = state.failed,
                elapsed_ms = elapsed_ms,
                total_packs = state.total,
            })
        end)
    end
end

-- ============================================================================
-- Batch installation with state management
-- ============================================================================
function Manager:install_activate_batch(pack_groups, on_complete)
    local Utils = self.utils
    local Bus = self.bus
    
    -- ✅ FIX: Get confirmation setting from config
    local should_confirm = self.opts.add_opts and self.opts.add_opts.confirm or false

    -- Flatten all pack groups into single array
    local all_packs = self:flatten_pack_groups(pack_groups)

    -- Handle empty case
    if #all_packs == 0 then
        if on_complete then
            vim.schedule(function()
                on_complete(true, {
                    installed_count = 0,
                    failed_count = 0,
                    failed_packs = {},
                    elapsed_ms = 0,
                    total_packs = 0,
                })
            end)
        end
        return true
    end

    -- Initialize installation state
    local state = {
        total = #all_packs,
        completed = 0,
        failed = {},
        timer = nil,
        start_time = vim.loop.hrtime(),
    }

    -- ✅ FIX: Remove nested vim.schedule + vim.defer_fn for install:start events
    for _, pack in ipairs(all_packs) do
        local name = pack.specs.normalize.name
        pack:set_status("installing")

        vim.schedule(function()
            Bus.emit("pack:install:start", {
                name = name,
                status = "installing",
                message = "Installing",
                pack = pack,
                stage = pack._install_stage,
            })
        end)
    end

    -- Build normalized specs for vim.pack.add
    local n_specs = vim.tbl_map(function(p)
        return p.specs.normalize
    end, all_packs)

    -- Create timeout timer
    state.timer = self:create_timeout_timer(state, on_complete)

    -- ✅ FIX: Execute batch installation with correct confirm setting
    local ok, err = pcall(vim.pack.add, n_specs, {
        confirm = should_confirm,  -- ✅ Use config value, not hardcoded false!
        load = function(data)
            self:handle_pack_load(data, state, on_complete)  -- ✅ Removed 4th param
        end,
    })

    -- Handle immediate failure
    if not ok then
        self:handle_install_failure(err, all_packs, state, on_complete)  -- ✅ Removed 5th param
        return false
    end

    return true
end


function Manager:install_activate_batch_v2(pack_groups, on_complete)
    local Utils = self.utils
    local Bus = self.bus
    local should_confirm = self.opts.add_opts and self.opts.add_opts.confirm or false

    local all_packs = self:flatten_pack_groups(pack_groups)

    if #all_packs == 0 then
        if on_complete then
            vim.schedule(function()
                on_complete(true, {
                    installed_count = 0,
                    failed_count = 0,
                    failed_packs = {},
                    elapsed_ms = 0,
                    total_packs = 0,
                })
            end)
        end
        return true
    end

    local state = {
        total = #all_packs,
        completed = 0,
        failed = {},
        start_time = vim.loop.hrtime(),
    }

    -- Emit events
    for _, pack in ipairs(all_packs) do
        local name = pack.specs.normalize.name
        pack:set_status("installing")
        vim.schedule(function()
            Bus.emit("pack:install:start", {
                name = name,
                status = "installing",
                message = "Installing",
                pack = pack,
                stage = pack._install_stage,
            })
        end)
    end

    local n_specs = vim.tbl_map(function(p)
        return p.specs.normalize
    end, all_packs)

    -- ✅ FIX: Call vim.pack.add WITHOUT load callback
    -- Then process packs after it completes
    local ok, err = pcall(function()
        vim.pack.add(n_specs, { confirm = should_confirm, load = false })
    end)

    if not ok then
        Utils.safe_notify(
            string.format("Batch installation failed: %s", tostring(err)),
            vim.log.levels.ERROR
        )
        self:handle_install_failure(err, all_packs, state, on_complete)
        return false
    end

    -- ✅ NOW process all packs after vim.pack.add completes
    vim.schedule(function()
        for _, pack in ipairs(all_packs) do
            local pack_name = pack.specs.normalize.name
            local pack_start_time = vim.loop.hrtime()

            -- Check if pack was actually installed
            local pack_info = vim.pack.get({ pack_name })[1]
            if not pack_info then
                Utils.safe_notify(
                    string.format("Pack '%s' not found after installation", pack_name),
                    vim.log.levels.WARN
                )
                table.insert(state.failed, pack_name)
                goto continue
            end

            -- Mark as installed
            pack.installed = true
            pack:set_active(pack_info)
            pack:set_path(pack_info.path)

            -- Packadd
            local packadd_ok, packadd_err = pcall(vim.cmd, "packadd " .. pack_name)
            if not packadd_ok then
                Utils.safe_notify(
                    string.format("Failed to packadd '%s': %s", pack_name, tostring(packadd_err)),
                    vim.log.levels.WARN
                )
            end

            -- Record timing
            local install_duration_ms = (vim.loop.hrtime() - pack_start_time) / 1e6
            pack.times = pack.times or {}
            pack.times.install_duration = string.format("%.2f", install_duration_ms)

            -- Emit event
            Bus.emit("pack:install:finish", {
                name = pack_name,
                status = "installed",
                message = "Installation complete",
                install_duration = pack.times.install_duration,
                pack = pack,
                stage = pack._install_stage,
            })

            -- Run task lifecycle
            if pack.lifecycle then
                local lifecycle_ok, lifecycle_err = pack.lifecycle:run_next()
                if not lifecycle_ok and lifecycle_err ~= "no more tasks" then
                    Utils.safe_notify(
                        string.format("Pack '%s' task lifecycle error: %s", pack_name, tostring(lifecycle_err)),
                        vim.log.levels.WARN
                    )
                end
            end

            ::continue::
        end

        -- Calculate elapsed time
        local total_elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6

        -- Build result
        local result = {
            installed_count = state.total - #state.failed,
            failed_count = #state.failed,
            failed_packs = state.failed,
            elapsed_ms = total_elapsed_ms,
            total_packs = state.total,
        }

        -- Call completion callback
        if on_complete then
            on_complete(true, result)
        end
    end)

    return true
end

function Manager:install_activate_sequential(pack_groups, on_complete)
    local Utils = self.utils
    local Bus = self.bus
    local should_confirm = self.opts.add_opts and self.opts.add_opts.confirm or false

    local all_packs = self:flatten_pack_groups(pack_groups)

    if #all_packs == 0 then
        if on_complete then
            vim.schedule(function()
                on_complete(true, {
                    installed_count = 0,
                    failed_count = 0,
                    failed_packs = {},
                    elapsed_ms = 0,
                    total_packs = 0,
                })
            end)
        end
        return true
    end

    local state = {
        total = #all_packs,
        completed = 0,
        failed = {},
        start_time = vim.loop.hrtime(),
    }

    -- Process packs one at a time (reliable but slower)
    local function process_next_pack(index)
        if index > #all_packs then
            -- All done
            local total_elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6
            local result = {
                installed_count = state.total - #state.failed,
                failed_count = #state.failed,
                failed_packs = state.failed,
                elapsed_ms = total_elapsed_ms,
                total_packs = state.total,
            }
            if on_complete then
                vim.schedule(function()
                    on_complete(true, result)
                end)
            end
            return
        end

        local pack = all_packs[index]
        local pack_name = pack.specs.normalize.name
        
        pack:set_status("installing")
        Bus.emit("pack:install:start", {
            name = pack_name,
            status = "installing",
            message = "Installing",
            pack = pack,
            stage = pack._install_stage,
        })

        -- Install this pack
        vim.schedule(function()
            local ok, err = pcall(function()
                vim.pack.add({ pack.specs.normalize }, { confirm = should_confirm })
            end)

            if not ok then
                Utils.safe_notify(
                    string.format("Failed to install '%s': %s", pack_name, tostring(err)),
                    vim.log.levels.WARN
                )
                table.insert(state.failed, pack_name)
                state.completed = state.completed + 1
                process_next_pack(index + 1)
                return
            end

            -- Pack installed successfully
            local pack_info = vim.pack.get(pack_name)
            if pack_info then
                pack.installed = true
                pack:set_active(pack_info)
                pack:set_path(pack_info.path)

                -- Packadd
                pcall(vim.cmd, "packadd " .. pack_name)

                -- Record timing
                pack.times = pack.times or {}
                pack.times.install_duration = "0.00"

                -- Emit event
                Bus.emit("pack:install:finish", {
                    name = pack_name,
                    status = "installed",
                    message = "Installation complete",
                    install_duration = pack.times.install_duration,
                    pack = pack,
                    stage = pack._install_stage,
                })

                -- Run lifecycle
                if pack.lifecycle then
                    pcall(pack.lifecycle.run_next, pack.lifecycle)
                end
            else
                table.insert(state.failed, pack_name)
            end

            state.completed = state.completed + 1
            
            -- Process next pack
            vim.schedule(function()
                process_next_pack(index + 1)
            end)
        end)
    end

    -- Start processing
    process_next_pack(1)
    return true
end

-- ============================================================================
-- Create all packs from specs (no artificial delays)
-- ============================================================================
function Manager:create_all_packs(specs)
    local Utils = self.utils
    local Bus = self.bus

    if #specs == 0 then
        Utils.safe_notify("No pack specs to create", vim.log.levels.INFO)
        return {}
    end

    local packs = {}
    local seen_names = {}
    local create_start = vim.loop.hrtime()

    -- Create all packs synchronously (no artificial delays)
    for i, spec in ipairs(specs) do
        local pack_create_start = vim.loop.hrtime()

        -- Create the pack
        local pack = self:create_pack(spec)
        local name = pack.specs.normalize.name

        -- Check for duplicates
        if seen_names[name] then
            Utils.safe_notify(string.format("Duplicate pack '%s' found (skipping)", name), vim.log.levels.WARN)
            goto continue
        end

        -- Mark as seen and created
        seen_names[name] = true
        pack:set_status("created")

        -- Track creation time
        pack.times = pack.times or {}
        pack.times.create_duration = string.format("%.2f", (vim.loop.hrtime() - pack_create_start) / 1e6)

        -- Store pack
        self.packs[name] = pack
        table.insert(packs, pack)

        vim.schedule(function()
            vim.defer_fn(function()
                Bus.emit("pack:created", {
                            name = name,
                            status = pack:get_status(),
                            stage = pack:get_stage(),
                            message = "Created",
                            pack = pack,
                })
            end, 25 * i)
        end)

        ::continue::
    end

    local total_create_time = (vim.loop.hrtime() - create_start) / 1e6

    -- Emit single batch creation event
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

            -- Mark all packs in this stage as failed
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

    -- Process stages in order
    -- Note: We continue even if a stage fails, but log it prominently
    local now_ok = process_stage("now", by_stage.now)
    local lazy_ok = process_stage("lazy", by_stage.lazy)
    local later_ok = process_stage("later", by_stage.later)
    local disabled_ok = process_stage("disabled", by_stage.disabled)

    local total_duration = (vim.loop.hrtime() - stages_start) / 1e6
    local all_success = now_ok and lazy_ok and later_ok and disabled_ok

    -- Emit completion event with detailed results
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
-- Main Entry Point: run_packs method (REFACTORED)
-- ============================================================================
function Manager:run_packs()
    local Utils = self.utils
    local Bus = self.bus
    local Dashboard = self.container:resolve("dashboard")

    local run_start = vim.loop.hrtime()

    -- Load specs from directory
    local all_specs = self:load_specs(self.opts.plugins_rpath)

    if #all_specs == 0 then
        Utils.safe_notify("No pack specs found, nothing to do", vim.log.levels.INFO)
        return {}
    end

    Utils.safe_notify(
        string.format("Loaded %d pack specs from %s", #all_specs, self.opts.directory or "/lua/packs"),
        vim.log.levels.INFO
    )

    -- Determine if we should show dashboard
    local show_dashboard = should_show_dashboard(all_specs, self.opts)

    if show_dashboard then
        vim.defer_fn(function()
            Dashboard:open()
        end, 500)
    end

    -- Create all packs (no artificial delays)
    local all_packs = self:create_all_packs(all_specs)

    if #all_packs == 0 then
        Utils.safe_notify("No packs created successfully", vim.log.levels.WARN)
        return {}
    end

    -- Sort packs by stage
    local sorted = Utils.sort_packs(all_packs)
    local by_stage = {
        now = sorted["now"] or {},
        lazy = sorted["lazy"] or {},
        later = sorted["later"] or {},
        disabled = sorted["disabled"] or {},
    }

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

    -- Start batch installation with callback
    -- The callback will fire when ALL packs have finished installing
    local install_ok = self:install_activate_batch_v2(by_stage, function(success, result)
        if not success then
            Utils.safe_notify(
                string.format(
                    "Installation failed: %s (elapsed: %.2fms)",
                    result.error or "unknown error",
                    result.elapsed_ms or 0
                ),
                vim.log.levels.ERROR
            )

            -- Emit failure event
            vim.schedule(function()
                Bus.emit("pack:run_complete", {
                    success = false,
                    error = result.error,
                    elapsed_ms = result.elapsed_ms,
                    installed_count = result.installed_count or 0,
                    failed_count = result.failed_count or #all_packs,
                })
            end)
            return
        end

        -- Show summary if there were any failures
        if result.failed_count and result.failed_count > 0 then
            Utils.safe_notify(
                string.format(
                    "Installation completed with %d failures (%.2fms): %s",
                    result.failed_count,
                    result.elapsed_ms,
                    table.concat(result.failed_packs or {}, ", ")
                ),
                vim.log.levels.WARN
            )
        else
            Utils.safe_notify(
                string.format("All %d packs installed successfully (%.2fms)", result.installed_count, result.elapsed_ms),
                vim.log.levels.INFO
            )
        end

        -- NOW process stages (only after all installs are done)
        local stages_ok = self:process_stages(by_stage)

        local total_elapsed = (vim.loop.hrtime() - run_start) / 1e6

        -- Emit final completion event
        vim.schedule(function()
            Bus.emit("pack:run_complete", {
                success = stages_ok,
                total_duration = string.format("%.2f", total_elapsed),
                installed_count = result.installed_count,
                failed_count = result.failed_count,
                failed_packs = result.failed_packs,
                by_stage = {
                    now = #by_stage.now,
                    lazy = #by_stage.lazy,
                    later = #by_stage.later,
                    disabled = #by_stage.disabled,
                },
            })
        end)
    end)

    if not install_ok then
        Utils.safe_notify("Failed to start batch installation", vim.log.levels.ERROR)
        return {}
    end

    return all_packs
end

-- ============================================================================
-- Cleanup on shutdown (IMPROVED)
-- ============================================================================
function Manager:cleanup()
    local Utils = self.utils
    local Bus = self.bus
    local cleanup_start = vim.loop.hrtime()

    Utils.safe_notify("Starting manager cleanup...", vim.log.levels.DEBUG)

    -- Resolve dependencies once
    local Loader = self.container:resolve("loader")
    local TaskSystem = self.container:resolve("task_system")

    -- Track cleanup statistics
    local stats = {
        packs_cleaned = 0,
        loaders_closed = 0,
        timers_closed = 0,
        tasks_unwired = 0,
        errors = {},
    }

    -- 1. Close all loaders first (this may have pack-specific cleanup)
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

    -- 2. Clean up individual packs
    for name, pack in pairs(self.packs) do
        local pack_ok, pack_err = pcall(function()
            -- Unwire task system listeners
            if TaskSystem and type(TaskSystem.unwire_pack) == "function" then
                TaskSystem.unwire_pack(pack)
                stats.tasks_unwired = stats.tasks_unwired + 1
            end

            -- Call pack-specific cleanup if available
            if pack.cleanup and type(pack.cleanup) == "function" then
                pack:cleanup()
            end

            -- Clean up pack timers if any exist
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

            -- Clear pack references
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

    -- 3. Clear the packs table
    self.packs = {}

    -- 4. Clean up manager-level state
    self.install_times = {}
    self.installation_complete = false
    self.installation_success = false
    self.installation_result = nil

    -- 5. Emit cleanup event
    local cleanup_duration = (vim.loop.hrtime() - cleanup_start) / 1e6

    vim.schedule(function()
        Bus.emit("manager:cleanup", {
            duration = string.format("%.2f", cleanup_duration),
            stats = stats,
            success = #stats.errors == 0,
        })
    end)

    -- 6. Log final cleanup status
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

-- ============================================================================
-- Force cleanup (emergency cleanup without errors)
-- ============================================================================
function Manager:force_cleanup()
    -- Silent cleanup that swallows all errors
    pcall(function()
        if self.container then
            local Loader = self.container:resolve("loader")
            if Loader and Loader.close_all then
                pcall(Loader.close_all, Loader)
            end
        end
    end)

    -- Force clear everything
    self.packs = {}
    self.install_times = {}
    self.installation_complete = false
    self.installation_success = false
    self.installation_result = nil

    return true
end

-- ============================================================================
-- Selective cleanup (cleanup specific packs)
-- ============================================================================
function Manager:cleanup_pack(pack_name)
    local Utils = self.utils
    local pack = self.packs[pack_name]

    if not pack then
        Utils.safe_notify(string.format("Pack '%s' not found for cleanup", pack_name), vim.log.levels.WARN)
        return false
    end

    local ok, err = pcall(function()
        -- Pack-specific cleanup
        if pack.cleanup and type(pack.cleanup) == "function" then
            pack:cleanup()
        end

        -- Clean up timers
        if pack.timers then
            for _, timer in pairs(pack.timers) do
                if timer and type(timer) == "table" and timer.close then
                    if not timer:is_closing() then
                        pcall(function()
                            timer:close()
                        end)
                    end
                end
            end
        end

        -- Remove from manager
        self.packs[pack_name] = nil

        Utils.safe_notify(string.format("Pack '%s' cleaned up successfully", pack_name), vim.log.levels.DEBUG)
    end)

    if not ok then
        Utils.safe_notify(
            string.format("Failed to cleanup pack '%s': %s", pack_name, tostring(err)),
            vim.log.levels.ERROR
        )
        return false
    end

    return true
end

-- ============================================================================
-- Get cleanup statistics (useful for debugging)
-- ============================================================================
function Manager:get_cleanup_stats()
    local stats = {
        total_packs = 0,
        packs_with_timers = 0,
        active_timers = 0,
        pack_list = {},
    }

    for name, pack in pairs(self.packs) do
        stats.total_packs = stats.total_packs + 1

        local pack_info = {
            name = name,
            status = pack:get_status(),
            stage = pack:get_stage(),
            installed = pack.installed or false,
            has_timers = false,
            active_timers = 0,
        }

        if pack.timers then
            pack_info.has_timers = true
            stats.packs_with_timers = stats.packs_with_timers + 1

            for timer_name, timer in pairs(pack.timers) do
                if timer and type(timer) == "table" and timer.close then
                    if not timer:is_closing() then
                        pack_info.active_timers = pack_info.active_timers + 1
                        stats.active_timers = stats.active_timers + 1
                    end
                end
            end
        end

        table.insert(stats.pack_list, pack_info)
    end

    return stats
end

return Manager
