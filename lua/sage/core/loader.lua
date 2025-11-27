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
    self.autocmds = {}  -- ✅ FIXED: Initialize autocmds table

    return self
end

-- ============================================================================
-- CORRECT: Loader calls packadd and emits events for task system
-- ============================================================================

function Loader:load_pack_safe(pack, reason)
    local name = pack:get_name()
    local stage = pack:get_stage()

    -- Set loading status
    pack:set_status("loading")

    -- Emit loading start event
    vim.schedule(function()
        self.bus.emit("pack:load:start", {
            name = name,
            status = pack:get_status(),
            stage = stage,
            message = "Loading",
            pack = pack,
        })
    end)

    local ok, err = pcall(function()
        self:load_pack(pack)
    end)

    if not ok then
        pack:set_status("failed")
        self.utils.safe_notify(string.format("Pack '%s' failed to load: %s", name, tostring(err)), vim.log.levels.ERROR)
        return false
    end

    return true
end

function Loader:load_pack(pack)
    local name = pack:get_name()
    
    -- ✅ CRITICAL: Call packadd here (pack was installed but not loaded yet)
    local packadd_ok, packadd_err = pcall(vim.cmd, "packadd " .. name)
    if not packadd_ok then
        self.utils.safe_notify(
            string.format("Failed to packadd '%s': %s", name, tostring(packadd_err)),
            vim.log.levels.ERROR
        )
        pack:set_status("failed")
        return
    end

    pack:set_status("configuring")

    -- Emit event to signal configuration should start
    vim.schedule(function()
        self.bus.emit("pack:config:start", {
            name = name,
            status = pack:get_status(),
            message = "Configuring",
            pack = pack,
        })
    end)

    -- ✅ The config task in the lifecycle will run the actual config function
    -- We just need to wait for it to complete
    
    -- If pack has lifecycle, it's already running from pack:install:finish event
    -- The config task will execute and emit pack:config:finish when done
    
    -- For packs without config, mark as configured immediately
    if pack.specs.normalize.data.config == nil then
        pack:set_status("configured")
        vim.schedule(function()
            self.bus.emit("pack:config:finish", {
                name = name,
                status = pack:get_status(),
                message = "No config needed",
                pack = pack,
                config_duration = "0.00",
            })
        end)
    end

    -- Mark as loaded (config task will run separately via lifecycle)
    pack:set_status("loaded")
    
    vim.schedule(function()
        self.bus.emit("pack:load:complete", {
            name = name,
            status = pack:get_status(),
            message = "Loading complete",
            pack = pack,
        })
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

    local autocmd_id = vim.api.nvim_create_autocmd(event_list, {
        group = group,
        once = true,
        callback = function()
            -- Delete the autocmd group
            pcall(vim.api.nvim_del_augroup_by_id, group)

            -- Load the pack
            self:load_pack_safe(pack)
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
            -- Delete the autocmd group
            pcall(vim.api.nvim_del_augroup_by_id, group)

            -- Load the pack
            self:load_pack_safe(pack)
        end,
    })
    
    table.insert(self.autocmds, autocmd_id)
end

-- ============================================================================
-- Loading Strategies
-- ============================================================================

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