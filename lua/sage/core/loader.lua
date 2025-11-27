-- ============================================================================
-- Example Loader Implementation with Task System Integration
-- ============================================================================

local Loader = {}
Loader.__index = Loader

function Loader.new(container, opts)
    local self = setmetatable({}, Loader)
    self.opts = opts
    self.bus = container:resolve("bus")
    self.utils = container:resolve("utils")
    self.timers = {}
    self.autocmds = {} -- ✅ CRITICAL: This was missing!
    return self
end

-- ============================================================================
-- CORRECT: Loader triggers tasks, doesn't run config directly
-- ============================================================================

function Loader:load_pack_safe(pack, reason)
    local name = pack:get_name()
    local stage = pack:get_stage()
    local delay_load = 200

    -- Set loading status
    pack:set_status("loading")

    -- Emit loading start event
    vim.schedule(function()
        vim.defer_fn(function()
            self.bus.emit("pack:load:start", {
                name = name,
                status = pack:get_status(),
                stage = stage,
                message = "Loading",
                pack = pack,
            })
        end, delay_load)
    end)

    local ok, err = pcall(function()
        self:load_pack(pack, delay_load)
    end)

    if not ok then
        pack:set_status("failed")
        self.utils.safe_notify(string.format("Pack '%s' failed to load: %s", name, tostring(err)), vim.log.levels.ERROR)
        return false
    end

    return true
end

function Loader:load_pack(pack, delay_load)
    local name = pack:get_name()
    pack:set_status("configuring")

    -- IMPORTANT: The Loader does NOT call config() directly
    -- Instead, it signals the task system to run the config task

    -- Emit event to signal configuration should start
    vim.schedule(function()
        vim.defer_fn(function()
            self.bus.emit("pack:config:start", {
                name = name,
                status = pack:get_status(),
                message = "Adding configuration",
                pack = pack,
            })
        end, delay_load + 25)
    end)

    -- Trigger the task lifecycle to continue
    -- This will run any pending tasks (config, after_hook)
    vim.schedule(function()
        if pack.lifecycle then
            local ok, err = pack.lifecycle:run_next()

            if not ok and err ~= "no more tasks" then
                self.utils.safe_notify(
                    string.format("Pack '%s' task execution failed: %s", name, tostring(err)),
                    vim.log.levels.ERROR
                )
                pack:set_status("failed")
                return
            end
            if ok then
                pack:set_status("configured")
                vim.schedule(function()
                    vim.defer_fn(function()
                        self.bus.emit("pack:config:finish", {
                            name = name,
                            status = pack:get_status(),
                            message = "Config added",
                            pack = pack,
                        })
                    end, delay_load + 50)
                end)
            end

            -- After tasks complete successfully, mark as loaded
            if pack.lifecycle.completed then
                pack:set_status("loaded")

                vim.schedule(function()
                    vim.defer_fn(function()
                        self.bus.emit("pack:load:complete", {
                            name = name,
                            status = pack:get_status(),
                            message = "Loading complete",
                            pack = pack,
                        })
                    end, delay_load + 100)
                end)
            end
        else
            -- No lifecycle (shouldn't happen with task system)
            self.utils.safe_notify(string.format("Pack '%s' has no lifecycle", name), vim.log.levels.WARN)
            pack:set_status("loaded")
        end
    end)
end

-- ============================================================================
-- Stage-specific loaders
-- ============================================================================

function Loader:run(stage_name, packs, manager, opts)
    if stage_name == "now" then
        self:load_now(packs)
    elseif stage_name == "lazy" then
        self:load_lazy(packs)
    elseif stage_name == "later" then
        self:load_later(packs)
    elseif stage_name == "disabled" then
        self:load_disabled(packs)
    end
end

function Loader:load_now(packs)
    -- Load immediately
    for _, pack in ipairs(packs) do
        vim.schedule(function()
            self:load_pack_safe(pack)
        end)
    end
end

function Loader:load_lazy(packs)
    -- Set up lazy loading triggers
    for _, pack in ipairs(packs) do
        pack:set_status("lazy")

        local spec = pack.specs.normalize

        -- Setup triggers (commands, keys, events, etc.)
        local commands = spec.data.cmds or spec.data.cmd
        if commands then
            self:setup_cmd_triggers(pack, commands)
        end

        local keys = spec.data.keys
        if keys then
            self:setup_key_triggers(pack, keys)
        end

        local events = spec.data.events or spec.data.event
        if events then
            self:setup_event_triggers(pack, events)
        end

        local fts = spec.data.fts or spec.data.ft
        if fts then
            self:setup_filetype_triggers(pack, fts)
        end
    end
end

function Loader:load_later(packs)
    local opts = self.opts
    -- Set initial status for all later packs BEFORE applying strategy
    for i, pack in ipairs(packs or {}) do
        pack:set_status("pending")
    end

    local strategy = (opts and opts.strategy) or "vimenter"
    if strategy == "vimenter" then
        self:_strategy_vimenter(packs, opts)
    elseif strategy == "delay" then
        self:_strategy_delay(packs, opts)
    elseif strategy == "idle" then
        self:_strategy_idle(packs, opts)
    else
        vim.notify("Unknown strategy: " .. tostring(strategy), vim.log.levels.WARN)
    end
end

function Loader:load_disabled(packs)
    -- Mark as disabled, don't load
    for _, pack in ipairs(packs) do
        pack:set_status("disabled")
    end
end

-- ============================================================================
-- Trigger Setup (for lazy loading)
-- ============================================================================

function Loader:setup_cmd_triggers(pack, cmds)
    local commands = type(cmds) == "string" and { cmds } or cmds

    for _, cmd in ipairs(commands) do
        vim.api.nvim_create_user_command(cmd, function(opts)
            -- Remove the command before loading
            pcall(vim.api.nvim_del_user_command, cmd)

            -- Load the pack (which triggers task system)
            self:load_pack_safe(pack)

            -- Re-execute the command
            vim.schedule(function()
                local args = opts.args or ""
                vim.cmd(cmd .. " " .. args)
            end)
        end, { nargs = "*", force = true })
    end
end

function Loader:setup_key_triggers(pack, keys)
    local mappings = type(keys) == "string" and { keys } or keys

    for _, mapping in ipairs(mappings) do
        local mode = mapping.mode or "n"
        local lhs = mapping[1] or mapping.lhs

        vim.keymap.set(mode, lhs, function()
            -- Remove the keymap before loading
            pcall(vim.keymap.del, mode, lhs)

            -- Load the pack
            self:load_pack_safe(pack)

            -- Re-trigger the key
            vim.schedule(function()
                local keys_to_send = vim.api.nvim_replace_termcodes(lhs, true, false, true)
                vim.api.nvim_feedkeys(keys_to_send, "m", false)
            end)
        end, { desc = "Lazy load " .. pack:get_name() })
    end
end

function Loader:setup_event_triggers(pack, events)
    local event_list = type(events) == "string" and { events } or events

    local group = vim.api.nvim_create_augroup("LazyLoad_" .. pack:get_name(), { clear = true })

    vim.api.nvim_create_autocmd(event_list, {
        group = group,
        once = true,
        callback = function()
            -- Delete the autocmd group
            pcall(vim.api.nvim_del_augroup_by_id, group)

            -- Load the pack
            self:load_pack_safe(pack)
        end,
    })
end

function Loader:setup_filetype_triggers(pack, filetypes)
    local ft_list = type(filetypes) == "string" and { filetypes } or filetypes

    local group = vim.api.nvim_create_augroup("LazyLoadFT_" .. pack:get_name(), { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = ft_list,
        once = true,
        callback = function()
            -- Delete the autocmd group
            pcall(vim.api.nvim_del_augroup_by_id, group)

            -- Load the pack
            self:load_pack_safe(pack)
        end,
    })
end

-- Strategy vimenter: loads all lazy packs on VimEnter
function Loader:_strategy_vimenter(packs, opts)
    local has_run = false

    local function load_all()
        if has_run then
            return
        end
        has_run = true

        for i, pack in ipairs(packs) do
            self:load_pack_safe(pack, "VimEnter strategy")
        end
    end

    if vim.fn.has("vim_starting") == 1 then
        local autocmd_id = vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = load_all,
            desc = "Load later-stage plugins on VimEnter",
        })
        table.insert(self.autocmds, autocmd_id)
    else
        load_all()
    end
end

-- Strategy delay: delays loading of all lazy packs
function Loader:_strategy_delay(packs, opts)
    local delay_ms = (opts and opts.delay_ms) or 2000
    local timer = vim.loop.new_timer()
    table.insert(self.timers, timer)

    timer:start(
        delay_ms,
        0,
        vim.schedule_wrap(function()
            timer:close()
            for i, pack in ipairs(packs) do
                self:load_pack_safe(pack, "Delay strategy")
            end
        end)
    )
end

-- Strategy idle: loads all lazy packs when user is idle for a set amount of seconds (default 4000)
function Loader:_strategy_idle(packs, opts)
    local idle_time_ms = (opts and opts.idle_time_ms) or 2000
    local check_interval = (opts and opts.check_interval) or 500
    local last_input_time = vim.loop.hrtime()
    local has_started = false

    local function check_idle()
        local current_time = vim.loop.hrtime()
        local time_since_input = (current_time - last_input_time) / 1e6

        if time_since_input >= idle_time_ms and not has_started then
            has_started = true
            for i, pack in ipairs(packs) do
                local delay = (i - 1) * 50
                self:load_pack_safe(pack, "Idle strategy")
            end
            return false -- Stop checking
        end

        return true -- Continue checking
    end

    -- Track user input
    local autocmd_id = vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI", "CmdlineEnter" }, {
        callback = function()
            last_input_time = vim.loop.hrtime()
        end,
        desc = "Track idle loader input",
    })
    table.insert(self.autocmds, autocmd_id)

    -- Start idle timer
    local timer = vim.loop.new_timer()
    table.insert(self.timers, timer)

    timer:start(
        check_interval,
        check_interval,
        vim.schedule_wrap(function()
            if not check_idle() then
                timer:close()
            end
        end)
    )
end

-- ============================================================================
-- Cleanup
-- ============================================================================

function Loader:close_all()
    -- Close all timers
    for _, timer in ipairs(self.timers or {}) do
        if timer and not timer:is_closing() then
            pcall(function()
                timer:close()
            end)
        end
    end
    self.timers = {}

    -- Remove all autocmds
    for _, id in ipairs(self.autocmds or {}) do
        function Loader:iclose_all()
            -- Clean up any remaining triggers
            -- This would need tracking of created commands/keymaps/autocmds
        end

        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmds = {}

    -- Note: Command/keymap cleanup would need tracking similar to autocmds
    vim.notify("Loader cleaned up", vim.log.levels.DEBUG)
end

return Loader
