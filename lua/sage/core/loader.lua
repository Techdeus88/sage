-- ============================================================================
-- SAGE LOADER (FIXED - Drop-in Ready)
-- ============================================================================

local Loader = {}
Loader.__index = Loader

function Loader.new(container, opts)
    local self = setmetatable({}, Loader)

    self.opts = opts

    self.bus = container:resolve("bus")
    self.utils = container:resolve("utils")

    self.timers = {}
    self.autocmds = {} -- ✅ FIXED: Initialize autocmds table

    return self
end

-- ============================================================================
-- CORRECT: Loader calls packadd and emits events for task system
-- ============================================================================

function Loader:load_pack_safe(pack, reason)
    local name = pack:get_name()
    local stage = pack:get_stage()
    local delay = 100
    local index = math.random(5, 10)

    -- Set loading status
    pack:set_status("loading")

    -- Emit loading start event the Dashboard actually listens to
    
        vim.schedule(function()
            self.bus.emit("pack:load:start", {
                name = name,
                status = pack:get_status(),
                stage = stage,
                message = reason or ("Loading " .. name .. "..."),
                pack = pack,
            })
        end)
    
    pack.times = pack.times or {}
    local load_start = vim.loop.hrtime()

    local ok, err = pcall(function()
        self:load_pack(pack)
    end)

    local load_ms = (vim.loop.hrtime() - load_start) / 1e6
    pack.times.load_duration = string.format("%.2f", load_ms)

    if not ok then
        pack:set_status("failed")
        self.utils.safe_notify(string.format("Pack '%s' failed to load: %s", name, tostring(err)), vim.log.levels.ERROR)

        vim.schedule(function()
            self.bus.emit("pack:failed", {
                name = name,
                pack = pack,
                error = err,
                phase = "load",
            })
        end)

        return false
    end

    -- ✅ Tell Dashboard that loading finished
    vim.schedule(function()
        self.bus.emit("pack:load:complete", {
            name = name,
            pack = pack,
            stage = stage,
            status = pack:get_status(),
            load_duration = load_ms,
            message = "Loaded " .. name,
        })
    end)

    return true
end

function Loader:configure_pack(pack, on_complete)
    local Bus = self.bus
    local name = pack:get_name()
    local spec = pack.specs.normalize or {}
    local data = spec.data or {}
    local index = math.random(1, 10)

    pack.times = pack.times or {}

    -- No config function: mark ready & emit a finish event with 0ms
    if not data.config then
        pack:set_status("ready")
        pack.times.config_duration = pack.times.config_duration or "0.00"

        vim.schedule(function()
            Bus.emit("pack:config:finish", {
                name = name,
                pack = pack,
                status = pack:get_status(),
                config_duration = 0,
                message = "No config for " .. name,
            })
        end)

        if on_complete then
            on_complete(true)
        end
        return
    end

    pack:set_status("configuring")

    vim.schedule(function()
        Bus.emit("pack:config:start", {
            name = name,
            pack = pack,
            status = pack:get_status(),
            message = "Configuring " .. name .. "...",
        })
    end)

    local config_start = vim.loop.hrtime()
    local ok, err = pcall(data.config)
    local config_duration = (vim.loop.hrtime() - config_start) / 1e6

    pack.times.config_duration = string.format("%.2f", config_duration)

    if not ok then
        pack:set_status("failed")
        pack.error = err

        vim.schedule(function()
            Bus.emit("pack:failed", {
                name = name,
                pack = pack,
                error = err,
                phase = "config",
            })
        end)

        if on_complete then
            on_complete(false)
        end
        return
    end

    pack:set_status("ready")

    vim.schedule(function()
        Bus.emit("pack:config:finish", {
            name = name,
            pack = pack,
            status = pack:get_status(),
            message = "Configured " .. name,
            config_duration = config_duration,
        })
    end)

    if on_complete then
        on_complete(true)
    end
end

-- ============================================================================
-- LOADER: Stage-Based Loading (YOUR CURRENT LOGIC - ENHANCED)
-- ============================================================================
function Loader:load_stage(stage_name, packs, on_complete)
    local Bus = self.bus
    if #packs == 0 then
        if on_complete then
            on_complete()
        end
        return
    end

    local stage_start = vim.loop.hrtime()

    Bus.emit("stage:start", {
        stage = stage_name,
        count = #packs,
    })

    -- Route to appropriate stage handler
    if stage_name == "now" then
        self:load_now_stage(packs, function()
            self:finalize_stage(stage_name, packs, stage_start, on_complete)
        end)
    elseif stage_name == "lazy" then
        self:load_lazy_stage(packs, function()
            self:finalize_stage(stage_name, packs, stage_start, on_complete)
        end)
    elseif stage_name == "later" then
        self:load_later_stage(packs, function()
            self:finalize_stage(stage_name, packs, stage_start, on_complete)
        end)
    elseif stage_name == "disabled" then
        self:load_disabled_stage(packs, function()
            self:finalize_stage(stage_name, packs, stage_start, on_complete)
        end)
    end
end

function Loader:finalize_stage(stage_name, packs, start_time, on_complete)
    local duration = (vim.loop.hrtime() - start_time) / 1e6
    local Bus = self.bus

    Bus.emit("stage:complete", {
        stage = stage_name,
        count = #packs,
        duration = duration,
    })

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- NOW STAGE: Load immediately and synchronously
-- ============================================================================
function Loader:load_now_stage(packs, on_complete)
    local total = #packs
    local completed = 0

    for _, pack in ipairs(packs) do
        self:load_pack_immediate(pack, function(success)
            completed = completed + 1

            if completed >= total and on_complete then
                on_complete()
            end
        end)
    end
end

function Loader:load_pack(pack)
    local name = pack:get_name()

    -- Validation
    if not pack.installed then
        return false, "Pack not installed"
    end

    if pack:get_status() == "loaded" then
        return true -- Already loaded
    end

    -- Set loading state
    pack:set_status("loading")
    vim.schedule(function()
        self.bus.emit("pack:loading", { name = name, pack = pack }) -- ✅ Fixed
    end)
    -- Execute packadd
    local ok, err = pcall(vim.cmd.packadd, name)

    if not ok then
        pack:set_status("failed")
        pack.error = err

        self.bus.emit("pack:failed", { name = name, pack = pack, error = err }) -- ✅ Fixed
        return false, err
    end

    -- Mark as loaded
    pack.loaded = true
    pack:set_status("loaded")
    vim.schedule(function()
        self.bus.emit("pack:loaded", { name = name, pack = pack }) -- ✅ Fixed
    end)
    -- Trigger configuration phase
    self:configure_pack(pack)

    return true
end

-- Line 117 - Fix Bus reference throughout load_pack_immediate
function Loader:load_pack_immediate(pack, on_complete)
    local name = pack:get_name()

    if not pack.installed then
        pack:set_status("failed")
        pack.error = "Cannot load: not installed"
        if on_complete then
            on_complete(false)
        end
        return
    end

    if pack.loaded then
        if on_complete then
            on_complete(true)
        end
        return
    end

    pack:set_status("loading")
    vim.schedule(function()
        self.bus.emit("pack:loading", { name = name, pack = pack, stage = "now" }) -- ✅ Fixed
    end)
    local load_start = vim.loop.hrtime()
    local ok, err = pcall(vim.cmd.packadd, name)
    local load_duration = (vim.loop.hrtime() - load_start) / 1e6

    if not ok then
        pack:set_status("failed")
        pack.error = err
        vim.schedule(function()
            self.bus.emit("pack:failed", { name = name, pack = pack, error = err }) -- ✅ Fixed
        end)
        if on_complete then
            on_complete(false)
        end
        return
    end

    pack.loaded = true
    pack.times.load_duration = string.format("%.2f", load_duration)
    pack:set_status("loaded")
    vim.schedule(function()
        self.bus.emit("pack:loaded", { -- ✅ Fixed
            name = name,
            pack = pack,
            load_duration = load_duration,
        })
    end)

    self:configure_pack(pack, function(config_success)
        if on_complete then
            on_complete(config_success)
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
    local Bus = self.bus
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

function Loader:load_disabled(packs)
    -- Mark as disabled, don't load
    for _, pack in ipairs(packs) do
        pack:set_status("disabled")
    end
end

-- ============================================================================
-- LAZY STAGE: Setup triggers, don't load yet
-- =====================F=======================================================
function Loader:load_lazy_stage(packs, on_complete)
    local Bus = self.bus

    for _, pack in ipairs(packs) do
        pack:set_status("lazy")

        local spec = pack.specs.normalize
        local triggers = spec.data.on or {}

        -- Setup command triggers
        if triggers.cmds or triggers.cmd then
            self:setup_cmd_triggers(pack, triggers.cmds or triggers.cmd)
        end

        -- Setup keymap triggers
        if triggers.keys then
            self:setup_key_triggers(pack, triggers.keys)
        end

        -- Setup event triggers
        if triggers.events or triggers.event then
            self:setup_event_triggers(pack, triggers.events or triggers.event)
        end

        -- Setup filetype triggers
        if triggers.fts or triggers.ft then
            self:setup_filetype_triggers(pack, triggers.fts or triggers.ft)
        end

        vim.schedule(function()
            Bus.emit("pack:lazy", {
                name = pack:get_name(),
                pack = pack,
                triggers = triggers,
            })
        end)
    end

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- LATER STAGE: Deferred loading strategies (KEEP YOUR LOGIC!)
-- ============================================================================
function Loader:load_later_stage(packs, on_complete)
    local strategy = (self.opts and self.opts.strategy) or "vimenter"

    if strategy == "vimenter" then
        self:_strategy_vimenter(packs, on_complete)
    elseif strategy == "delay" then
        self:_strategy_delay(packs, on_complete)
    elseif strategy == "idle" then
        self:_strategy_idle(packs, on_complete)
    else
        vim.notify("Unknown strategy: " .. strategy, vim.log.levels.WARN)
        if on_complete then
            on_complete()
        end
    end
end

-- ============================================================================
-- DISABLED STAGE: Mark as disabled, don't load
-- ============================================================================
function Loader:load_disabled_stage(packs, on_complete)
    local Bus = self.bus
    for _, pack in ipairs(packs) do
        pack:set_status("disabled")
        vim.schedule(function()
            Bus.emit("pack:disabled", {
                name = pack:get_name(),
                pack = pack,
            })
        end)
    end

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- TRIGGER SETUP (Keep your existing logic)
-- ============================================================================
function Loader:setup_cmd_triggers(pack, cmds)
    local commands = type(cmds) == "string" and { cmds } or cmds

    for _, cmd in ipairs(commands) do
        vim.api.nvim_create_user_command(cmd, function(opts)
            -- Remove command
            pcall(vim.api.nvim_del_user_command, cmd)

            -- Load pack
            self:load_pack_immediate(pack, function()
                -- Re-execute command
                vim.schedule(function()
                    local args = opts.args or ""
                    vim.cmd(cmd .. " " .. args)
                end)
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
            -- Remove keymap
            pcall(vim.keymap.del, mode, lhs)

            -- Load pack
            self:load_pack_immediate(pack, function()
                -- Re-trigger key
                vim.schedule(function()
                    local keys_to_send = vim.api.nvim_replace_termcodes(lhs, true, false, true)
                    vim.api.nvim_feedkeys(keys_to_send, "m", false)
                end)
            end)
        end, { desc = "Lazy load " .. pack:get_name() })
    end
end

function Loader:setup_event_triggers(pack, events)
    local event_list = type(events) == "string" and { events } or events
    local group = vim.api.nvim_create_augroup("LazyLoad_" .. pack:get_name(), { clear = true })

    local autocmd_id = vim.api.nvim_create_autocmd(event_list, {
        group = group,
        once = true,
        callback = function()
            pcall(vim.api.nvim_del_augroup_by_id, group)
            self:load_pack_immediate(pack)
        end,
    })

    table.insert(self.autocmds, autocmd_id)
end

function Loader:setup_filetype_triggers(pack, filetypes)
    local ft_list = type(filetypes) == "string" and { filetypes } or filetypes
    local group = vim.api.nvim_create_augroup("LazyLoadFT_" .. pack:get_name(), { clear = true })

    local autocmd_id = vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = ft_list,
        once = true,
        callback = function()
            pcall(vim.api.nvim_del_augroup_by_id, group)
            self:load_pack_immediate(pack)
        end,
    })

    table.insert(self.autocmds, autocmd_id)
end

-- ============================================================================
-- Loading Strategies
-- ============================================================================
function Loader:_strategy_vimenter(packs, on_complete)
    local has_run = false

    local function load_all()
        if has_run then
            return
        end
        has_run = true

        local total = #packs
        local completed = 0

        for _, pack in ipairs(packs) do
            self:load_pack_immediate(pack, function()
                completed = completed + 1
                if completed >= total and on_complete then
                    on_complete()
                end
            end)
        end
    end

    if vim.fn.has("vim_starting") == 1 then
        local autocmd_id = vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = load_all,
            desc = "Load 'later' stage packs on VimEnter",
        })
        table.insert(self.autocmds, autocmd_id)
    else
        -- VimEnter already fired
        load_all()
    end
end

function Loader:_strategy_delay(packs, on_complete)
    local delay_ms = (self.opts and self.opts.delay_ms) or 2000
    local timer = vim.uv.new_timer()
    table.insert(self.timers, timer)

    timer:start(
        delay_ms,
        0,
        vim.schedule_wrap(function()
            timer:close()

            local total = #packs
            local completed = 0

            for _, pack in ipairs(packs) do
                self:load_pack_immediate(pack, function()
                    completed = completed + 1
                    if completed >= total and on_complete then
                        on_complete()
                    end
                end)
            end
        end)
    )
end

function Loader:_strategy_idle(packs, on_complete)
    local idle_time_ms = (self.opts and self.opts.idle_time_ms) or 2000
    local check_interval = (self.opts and self.opts.check_interval) or 500
    local last_input_time = vim.loop.hrtime()
    local has_started = false

    local function check_idle()
        local current_time = vim.loop.hrtime()
        local time_since_input = (current_time - last_input_time) / 1e6

        if time_since_input >= idle_time_ms and not has_started then
            has_started = true

            local total = #packs
            local completed = 0

            for _, pack in ipairs(packs) do
                self:load_pack_immediate(pack, function()
                    completed = completed + 1
                    if completed >= total and on_complete then
                        on_complete()
                    end
                end)
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
        desc = "Track idle time for lazy loader",
    })
    table.insert(self.autocmds, autocmd_id)

    -- Start idle timer
    local timer = vim.uv.new_timer()
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
-- Cleanup (FIXED)
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
        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmds = {}

    -- Note: Commands and keymaps would need separate tracking to clean up
    -- For now, they'll be cleaned up when Neovim exits
end

return Loader
