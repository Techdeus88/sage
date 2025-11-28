-- ============================================================================
-- SAGE LOADER (PRODUCTION READY)
-- ============================================================================

local Loader = {}
Loader.__index = Loader

function Loader.new(container, opts)
    local self = setmetatable({}, Loader)

    self.opts = opts
    self.bus = container:resolve("bus")
    self.utils = container:resolve("utils")

    self.timers = {}
    self.autocmds = {}

    return self
end

-- ============================================================================
-- Pack Loading
-- ============================================================================

function Loader:load_pack(pack)
    local name = pack:get_name()

    if not pack.installed then
        return false, "Pack not installed"
    end

    if pack:get_status() == "loaded" then
        return true
    end

    pack:set_status("loading")

    self.bus.emit("pack:loading", { name = name, pack = pack })

    local ok, err = pcall(vim.cmd.packadd, name)

    if not ok then
        pack:set_status("failed")
        pack.error = err

        self.bus.emit("pack:failed", { name = name, pack = pack, error = err })

        return false, err
    end

    pack.loaded = true
    pack:set_status("loaded")

    self.bus.emit("pack:loaded", { name = name, pack = pack })

    self:configure_pack(pack)

    return true
end

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

    self.bus.emit("pack:loading", { name = name, pack = pack })

    local load_start = vim.loop.hrtime()
    local ok, err = pcall(vim.cmd.packadd, name)
    local load_duration = (vim.loop.hrtime() - load_start) / 1e6

    if not ok then
        pack:set_status("failed")
        pack.error = err

        self.bus.emit("pack:failed", { name = name, pack = pack, error = err })

        if on_complete then
            on_complete(false)
        end
        return
    end

    pack.loaded = true
    pack.times = pack.times or {}
    pack.times.load_duration = string.format("%.2f", load_duration)
    pack:set_status("loaded")

    self.bus.emit("pack:loaded", {
        name = name,
        pack = pack,
        load_duration = load_duration,
    })

    self:configure_pack(pack, function(config_success)
        if on_complete then
            on_complete(config_success)
        end
    end)
end

-- ============================================================================
-- Pack Configuration
-- ============================================================================

function Loader:configure_pack(pack, on_complete)
    local name = pack:get_name()
    local spec = pack.specs.normalize or {}
    local data = spec.data or {}

    pack.times = pack.times or {}

    if not data.config then
        pack:set_status("ready")
        pack.times.config_duration = "0.00"

        self.bus.emit("pack:config:finish", {
            name = name,
            pack = pack,
            status = pack:get_status(),
            config_duration = 0,
            message = "No config for " .. name,
        })

        if on_complete then
            on_complete(true)
        end
        return
    end

    pack:set_status("configuring")

    self.bus.emit("pack:config:start", {
        name = name,
        pack = pack,
        status = pack:get_status(),
        message = "Configuring " .. name .. "...",
    })

    local config_start = vim.loop.hrtime()
    local ok, err = pcall(data.config)
    local config_duration = (vim.loop.hrtime() - config_start) / 1e6

    pack.times.config_duration = string.format("%.2f", config_duration)

    if not ok then
        pack:set_status("failed")
        pack.error = err

        self.bus.emit("pack:failed", {
            name = name,
            pack = pack,
            error = err,
            phase = "config",
        })

        if on_complete then
            on_complete(false)
        end
        return
    end

    pack:set_status("ready")

    self.bus.emit("pack:config:finish", {
        name = name,
        pack = pack,
        status = pack:get_status(),
        message = "Configured " .. name,
        config_duration = config_duration,
    })

    if on_complete then
        on_complete(true)
    end
end

-- ============================================================================
-- Stage-Based Loading
-- ============================================================================

function Loader:load_stage(stage_name, packs, on_complete)
    if #packs == 0 then
        if on_complete then
            on_complete()
        end
        return
    end

    local stage_start = vim.loop.hrtime()

    self.bus.emit("stage:start", {
        stage = stage_name,
        count = #packs,
    })

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

    self.bus.emit("stage:complete", {
        stage = stage_name,
        count = #packs,
        duration = duration,
    })

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- NOW STAGE: Load immediately
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

-- ============================================================================
-- LAZY STAGE: Setup triggers
-- ============================================================================

function Loader:load_lazy_stage(packs, on_complete)
    for _, pack in ipairs(packs) do
        pack:set_status("lazy")

        local spec = pack.specs.normalize
        local triggers = spec.data.on or {}

        if triggers.cmds or triggers.cmd then
            self:setup_cmd_triggers(pack, triggers.cmds or triggers.cmd)
        end

        if triggers.keys then
            self:setup_key_triggers(pack, triggers.keys)
        end

        if triggers.events or triggers.event then
            self:setup_event_triggers(pack, triggers.events or triggers.event)
        end

        if triggers.fts or triggers.ft then
            self:setup_filetype_triggers(pack, triggers.fts or triggers.ft)
        end

        self.bus.emit("pack:lazy", {
            name = pack:get_name(),
            pack = pack,
            triggers = triggers,
        })
    end

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- LATER STAGE: Deferred loading
-- ============================================================================

function Loader:load_later_stage(packs, on_complete)
    local strategy = (self.opts and self.opts.strategy) or "vimenter"

    if strategy == "vimenter" then
        self:strategy_vimenter(packs, on_complete)
    elseif strategy == "delay" then
        self:strategy_delay(packs, on_complete)
    elseif strategy == "idle" then
        self:strategy_idle(packs, on_complete)
    else
        vim.notify("Unknown strategy: " .. strategy, vim.log.levels.WARN)
        if on_complete then
            on_complete()
        end
    end
end

function Loader:strategy_vimenter(packs, on_complete)
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
        load_all()
    end
end

function Loader:strategy_delay(packs, on_complete)
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

function Loader:strategy_idle(packs, on_complete)
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

            return false
        end

        return true
    end

    local autocmd_id = vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI", "CmdlineEnter" }, {
        callback = function()
            last_input_time = vim.loop.hrtime()
        end,
        desc = "Track idle time for lazy loader",
    })
    table.insert(self.autocmds, autocmd_id)

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
-- DISABLED STAGE: Mark as disabled
-- ============================================================================

function Loader:load_disabled_stage(packs, on_complete)
    for _, pack in ipairs(packs) do
        pack:set_status("disabled")

        self.bus.emit("pack:disabled", {
            name = pack:get_name(),
            pack = pack,
        })
    end

    if on_complete then
        vim.schedule(on_complete)
    end
end

-- ============================================================================
-- Trigger Setup
-- ============================================================================

function Loader:setup_cmd_triggers(pack, cmds)
    local commands = type(cmds) == "string" and { cmds } or cmds

    for _, cmd in ipairs(commands) do
        vim.api.nvim_create_user_command(cmd, function(opts)
            pcall(vim.api.nvim_del_user_command, cmd)

            self:load_pack_immediate(pack, function()
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
            pcall(vim.keymap.del, mode, lhs)

            self:load_pack_immediate(pack, function()
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
-- Cleanup
-- ============================================================================

function Loader:close_all()
    for _, timer in ipairs(self.timers or {}) do
        if timer and not timer:is_closing() then
            pcall(function()
                timer:close()
            end)
        end
    end
    self.timers = {}

    for _, id in ipairs(self.autocmds or {}) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmds = {}
end

return Loader
