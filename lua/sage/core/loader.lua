-- ============================================================================
-- UNIVERSAL LOADER WITH SUB CLASSES
-- ============================================================================
local Event = require("sage.core.bus")

-- ============================================================================
-- CORE LOAD PACK FUNCTION
-- ============================================================================
local function load_pack(pack, config_start)
    local n_spec = pack.specs.normalize
    local config = n_spec.data.config

    -- Execute config (before/after now handled by tasks)
    if type(config) == "function" then
        local ok, err = pcall(config)
        if not ok then
            pack.failed = true
            local msg = string.format("[%s] Config failed: %s", n_spec.name, err)
            vim.notify(msg, vim.log.levels.ERROR)
            return false, err
        end
    end

    pack.times = pack.times or {}
    pack.times.config_duration = string.format("%.2f", (vim.loop.hrtime() - config_start) / 1e6)

    return true, "success"
end

-- ============================================================================
-- DEPENDENCY RESOLUTION
-- ============================================================================
local function resolve_dependency_chain(target_pack, manager, visited, path)
    visited = visited or {}
    path = path or {}

    local name = target_pack.specs.normalize.name

    -- Circular dependency check
    if vim.tbl_contains(path, name) then
        local cycle = table.concat(path, " -> ") .. " -> " .. name
        vim.notify(string.format("⚠ Circular dependency: %s", cycle), vim.log.levels.WARN)
        return {}, true
    end

    if visited[name] then
        return {}, false
    end

    visited[name] = true
    table.insert(path, name)

    local chain = {}
    local spec = target_pack.specs.normalize
    local on = spec.data.on or {}

    if on.after then
        local after_plugins = type(on.after) == "table" and on.after or { on.after }

        for _, dep_name in ipairs(after_plugins) do
            local dep_pack = manager.packs[dep_name]

            if dep_pack then
                local sub_chain, has_cycle = resolve_dependency_chain(dep_pack, manager, visited, vim.deepcopy(path))

                if has_cycle then
                    return {}, true
                end

                vim.list_extend(chain, sub_chain)

                if not vim.tbl_contains(chain, dep_name) then
                    table.insert(chain, dep_name)
                end
            else
                vim.notify(string.format("⚠ Dependency '%s' not found for '%s'", dep_name, name), vim.log.levels.WARN)
            end
        end
    end

    return chain, false
end

-- ============================================================================
-- BaseLoader (Abstract)
-- ============================================================================
local BaseLoader = {}
BaseLoader.__index = BaseLoader

function BaseLoader.new()
    local self = setmetatable({}, BaseLoader)
    self.loading_queue = {}
    self.timers = {} -- Track all timers for cleanup
    self.autocmds = {} -- Track autocmds for cleanup
    self.user_commands = {} -- Track user commands for cleanup
    return self
end

function BaseLoader:is_loading(pack)
    return self.loading_queue[pack.specs.normalize.name] ~= nil
end

function BaseLoader:is_pack_ready(pack)
    if not pack then
        return false
    end
    return pack.loaded or self:is_loading(pack)
end

function BaseLoader:update_pack(pack_name, manager, to_force)
    to_force = to_force or false
    local pack = manager.packs[pack_name]
    if pack then
        local ok, err = pcall(vim.pack.update, { pack_name }, { force = to_force })
        if not ok then
            local msg = string.format("[%s] Update failed: %s", pack_name, err)
            vim.notify(msg, vim.log.levels.ERROR)
            return false, err
        end
        return true, "success"
    end
    return false, "pack not found"
end

-- Safe loading with proper state management
function BaseLoader:load_pack_safe(pack, reason, delay_ms)
    if not pack or not pack.specs or not pack.specs.normalize then
        return false, "invalid pack"
    end

    local name = pack.specs.normalize.name
    delay_ms = delay_ms or 0

    -- Already loaded or loading
    if pack.loaded or self:is_loading(pack) then
        return true, "already loaded or loading"
    end

    -- Mark as loading
    self.loading_queue[name] = true
    pack:set_status("loading")

    -- Emit start event
    vim.schedule(function()
        vim.defer_fn(function()
            Event.emit("pack:config:start", {
                name = name,
                status = pack:get_status(),
                message = reason or "Loading pack",
                pack = pack,
            })
        end, delay_ms)
    end)

    -- Execute load
    local config_start = vim.loop.hrtime()
    local ok, err = pcall(load_pack, pack, config_start)

    -- Update state
    self.loading_queue[name] = nil

    if ok then
        pack.loaded = true
        pack:set_status("loaded")

        -- Emit finish event
        vim.schedule(function()
            vim.defer_fn(function()
                Event.emit("pack:config:finish", {
                    name = name,
                    status = pack:get_status(),
                    message = "Ready",
                    config_duration = pack.times.config_duration,
                    pack = pack,
                })
            end, delay_ms)
        end)

        return true, "success"
    else
        pack.failed = true
        pack:set_status("failed")

        Event.emit("pack:failed", {
            name = name,
            status = pack:get_status(),
            reason = tostring(err),
            message = "Load failed",
        })

        return false, err
    end
end

function BaseLoader:start(packs, manager, opts)
    error("BaseLoader:start() must be overridden by subclasses")
end

function BaseLoader:close()
    -- Close all timers
    for _, timer in ipairs(self.timers) do
        if timer and not timer:is_closing() then
            timer:close()
        end
    end
    self.timers = {}

    -- Delete autocmds
    for _, id in ipairs(self.autocmds) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmds = {}

    -- Delete user commands
    for _, cmd_name in ipairs(self.user_commands) do
        pcall(vim.api.nvim_del_user_command, cmd_name)
    end
    self.user_commands = {}

    self.loading_queue = {}
end

-- ============================================================================
-- EagerLoader (now stage)
-- ============================================================================
local EagerLoader = setmetatable({}, { __index = BaseLoader })
EagerLoader.__index = EagerLoader

function EagerLoader.new()
    return setmetatable(BaseLoader.new(), EagerLoader)
end

function EagerLoader:start(packs, manager, opts)
    for i, pack in ipairs(packs or {}) do
        local delay = (i - 1) * 50
        -- Set initial status
        pack:set_status("loading")
        -- Load immediately
        self:load_pack_safe(pack, "Eager load", delay)
    end
end

-- ============================================================================
-- LaterLoader (later stage with strategies)
-- ============================================================================
local LaterLoader = setmetatable({}, { __index = BaseLoader })
LaterLoader.__index = LaterLoader

function LaterLoader.new()
    return setmetatable(BaseLoader.new(), LaterLoader)
end

function LaterLoader:start(packs, manager, opts)
    -- Set initial status for all later packs BEFORE applying strategy
    for _, pack in ipairs(packs or {}) do
        pack:set_status("pending")
        Event.emit("pack:config:start", {
            name = pack.specs.normalize.name,
            status = "pending",
            message = "Waiting for later stage trigger",
            pack = pack,
        })
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

-- Strategy vimenter: loads all lazy packs on VimEnter
function LaterLoader:_strategy_vimenter(packs, opts)
    local has_run = false

    local function load_all()
        if has_run then
            return
        end
        has_run = true

        for i, pack in ipairs(packs) do
            local delay = (i - 1) * 50
            vim.defer_fn(function()
                self:load_pack_safe(pack, "VimEnter strategy", delay)
            end, delay)
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
function LaterLoader:_strategy_delay(packs, opts)
    local delay_ms = (opts and opts.delay_ms) or 500
    local timer = vim.loop.new_timer()
    table.insert(self.timers, timer)

    timer:start(
        delay_ms,
        0,
        vim.schedule_wrap(function()
            timer:close()
            for i, pack in ipairs(packs) do
                local stagger = (i - 1) * 50
                self:load_pack_safe(pack, "Delay strategy", stagger)
            end
        end)
    )
end

-- Strategy idle: loads all lazy packs when user is idle for a set amount of seconds (default 4000)
function LaterLoader:_strategy_idle(packs, opts)
    local idle_time_ms = (opts and opts.idle_time_ms) or 4000
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
                self:load_pack_safe(pack, "Idle strategy", delay)
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
-- LazyLoader (lazy stage with triggers and dependencies)
-- ============================================================================
local LazyLoader = setmetatable({}, { __index = BaseLoader })
LazyLoader.__index = LazyLoader

function LazyLoader.new()
    local self = setmetatable(BaseLoader.new(), LazyLoader)
    self.dependency_timers = {}
    self.event_listeners = {}
    return self
end

function LazyLoader:start(packs, manager, opts)
    for _, pack in ipairs(packs or {}) do
        local spec = pack.specs.normalize
        local on = spec.data.on or {}
        local name = spec.name

        -- Check for dependency chain
        local dep_chain, has_cycle = resolve_dependency_chain(pack, manager)
        if has_cycle then
            vim.notify(string.format("✗ Skipping '%s': circular dependency", name), vim.log.levels.ERROR)
            pack:set_status("failed")
        elseif #dep_chain > 0 then
            pack:set_status("lazy")
            self:setup_dependency_loading(pack, manager, dep_chain)
        elseif on.before then
            pack:set_status("lazy")
            local before_list = type(on.before) == "table" and on.before or { on.before }
            self:setup_before_blocking(pack, manager, before_list)
        elseif on.after then
            pack:set_status("lazy")
            local after_list = type(on.after) == "table" and on.after or { on.after }
            self:setup_after_blocking(pack, manager, after_list)
        else
            -- setup_standard_triggers sets the status itself
            self:setup_standard_triggers(pack, on)
        end
    end
end

function LazyLoader:close()
    -- Close dependency timers
    for _, timer in pairs(self.dependency_timers) do
        if timer and not timer:is_closing() then
            timer:close()
        end
    end
    self.dependency_timers = {}

    -- Remove event listeners properly
    for pack_name, listener_ids in pairs(self.event_listeners) do
        for _, listener_id in ipairs(listener_ids) do
            pcall(Event.off, listener_id)
        end
    end
    self.event_listeners = {}

    -- Call parent close
    BaseLoader.close(self)
end

-- Setup dependency-based loading
function LazyLoader:setup_dependency_loading(pack, manager, dep_chain)
    local name = pack.specs.normalize.name
    local loaded_deps = {}
    local has_attempted = false

    -- Timeout after 30 seconds
    local timeout = vim.loop.new_timer()
    self.dependency_timers[name] = timeout

    timeout:start(
        30000,
        0,
        vim.schedule_wrap(function()
            if not pack.loaded and not has_attempted then
                vim.notify(
                    string.format("⏱ Timeout waiting for: %s", table.concat(dep_chain, ", ")),
                    vim.log.levels.WARN
                )
            end
            timeout:close()
        end)
    )

    -- Check and load when all deps ready
    local function check_and_load()
        if has_attempted or pack.loaded or self:is_loading(pack) then
            return
        end

        local all_loaded = true
        local missing = {}

        for _, dep_name in ipairs(dep_chain) do
            local dep_pack = manager.packs[dep_name]
            if not dep_pack or not dep_pack.loaded then
                all_loaded = false
                table.insert(missing, dep_name)
            end
        end

        if all_loaded then
            has_attempted = true
            timeout:close()

            vim.schedule(function()
                local ok =
                    self:load_pack_safe(pack, string.format("Dependencies ready: %s", table.concat(dep_chain, ", ")))

                if ok then
                    vim.notify(
                        string.format("✓ '%s' loaded after: %s", name, table.concat(dep_chain, ", ")),
                        vim.log.levels.INFO
                    )
                end
            end)
        else
            pack:set_status("lazy")
            Event.emit("pack:lazy:waiting", {
                name = name,
                status = pack:get_status(),
                message = string.format("Waiting for: %s", table.concat(missing, ", ")),
                dependencies = missing,
                pack = pack,
            })
        end
    end

    -- Listen for dependencies
    self.event_listeners[name] = self.event_listeners[name] or {}

    for _, dep_name in ipairs(dep_chain) do
        local dep_pack = manager.packs[dep_name]
        if dep_pack and dep_pack.loaded then
            loaded_deps[dep_name] = true
        else
            local listener_id = Event.on("pack:config:finish", function(data)
                if data.name == dep_name and not has_attempted then
                    loaded_deps[dep_name] = true
                    check_and_load()
                end
            end)
            table.insert(self.event_listeners[name], listener_id)
        end
    end

    vim.schedule(check_and_load)
end

-- Setup before loading
function LazyLoader:setup_before_blocking(pack, manager, before_list)
    local name = pack.specs.normalize.name
    local has_loaded = false

    for _, dep_name in ipairs(before_list) do
        local listener_id = Event.on("pack:install:finish", function(data)
            if data.name == dep_name and not has_loaded and not pack.loaded then
                has_loaded = true
                vim.schedule(function()
                    local ok = self:load_pack_safe(pack, string.format("Loading before '%s'", dep_name))
                    if ok then
                        vim.notify(string.format("✓ '%s' loaded before '%s'", name, dep_name), vim.log.levels.INFO)
                    end
                end)
            end
        end)
        table.insert(self.event_listeners[name], listener_id)
    end
end

-- Setup after loading
function LazyLoader:setup_after_blocking(pack, manager, after_list)
    local name = pack.specs.normalize.name
    local has_loaded = false

    for _, dep_name in ipairs(after_list) do
        local listener_id = Event.on("pack:install:finish", function(data)
            if data.name == dep_name and not has_loaded and not pack.loaded then
                has_loaded = true
                vim.schedule(function()
                    local ok = self:load_pack_safe(pack, string.format("Loading after '%s'", dep_name))
                    if ok then
                        vim.notify(string.format("✓ '%s' loaded after '%s'", name, dep_name), vim.log.levels.INFO)
                    end
                end)
            end
        end)
        table.insert(self.event_listeners[name], listener_id)
    end
end

-- Setup standard triggers
function LazyLoader:setup_standard_triggers(pack, on_config)
    if not pack or not pack.specs or not pack.specs.normalize then
        return false
    end

    local name = pack.specs.normalize.name
    local has_triggered = false

    local function trigger_load(trigger_type, detail)
        if has_triggered or (pack and pack.loaded) then
            return
        end
        has_triggered = true

        vim.schedule(function()
            self:load_pack_safe(pack, string.format("Triggered: %s (%s)", trigger_type, detail or ""))
        end)
    end

    -- Events
    local events = on_config.events or on_config.event
    if events then
        local evts = type(events) == "table" and events or { events }
        for _, evt in ipairs(evts) do
            local autocmd_id = vim.api.nvim_create_autocmd(evt, {
                callback = function()
                    trigger_load("event", evt)
                    return true
                end,
                desc = string.format("Load %s on %s", name, evt),
            })
            table.insert(self.autocmds, autocmd_id)
        end

        pack:set_status("lazy")
        Event.emit("pack:lazy", {
            name = name,
            status = pack:get_status(),
            message = "Waiting for events",
            trigger = { type = "events", value = events },
        })
        return true
    end

    -- Filetypes
    local fts = on_config.fts or on_config.ft
    if fts then
        local filetypes = type(fts) == "table" and fts or { fts }
        for _, ft in ipairs(filetypes) do
            local autocmd_id = vim.api.nvim_create_autocmd("FileType", {
                pattern = ft,
                callback = function(evt)
                    if vim.bo[evt.buf].filetype == ft then
                        trigger_load("filetype", ft)
                        return true
                    end
                end,
                desc = string.format("Load %s on filetype %s", name, ft),
            })
            table.insert(self.autocmds, autocmd_id)
        end

        pack:set_status("lazy")
        Event.emit("pack:lazy", {
            name = name,
            status = pack:get_status(),
            message = "Waiting for filetype",
            trigger = { type = "fts", value = filetypes },
        })
        return true
    end

    -- Commands
    local cmds = on_config.cmds or on_config.cmd
    if cmds then
        local commands = type(cmds) == "table" and cmds or { cmds }
        for _, cmd in ipairs(commands) do
            vim.api.nvim_create_user_command(cmd, function(args)
                trigger_load("command", cmd)
                -- Delete the placeholder command
                pcall(vim.api.nvim_del_user_command, cmd)
                vim.schedule(function()
                    vim.cmd(cmd .. " " .. args.args)
                end)
            end, {
                nargs = "*",
                desc = string.format("Load %s and run %s", name, cmd),
            })
            table.insert(self.user_commands, cmd)
        end

        pack:set_status("lazy")
        Event.emit("pack:lazy", {
            name = name,
            status = pack:get_status(),
            message = "Waiting for command",
            trigger = { type = "cmds", value = commands },
        })
        return true
    end

    -- Keys
    local keys = on_config.keys
    if keys then
        local ks = type(keys) == "table" and keys or { keys }
        local created_keymaps = {}

        for _, key in ipairs(ks) do
            local mode = key.mode or "n"
            local lhs = type(key) == "string" and key or key[1]

            vim.keymap.set(mode, lhs, function()
                trigger_load("keymap", lhs)
                -- Remove the lazy-load keymap
                pcall(vim.keymap.del, mode, lhs)
                vim.schedule(function()
                    local feedkey = vim.api.nvim_replace_termcodes(lhs, true, false, true)
                    vim.api.nvim_feedkeys(feedkey, "m", false)
                end)
            end, {
                desc = key.desc or string.format("Load %s on %s", name, lhs),
            })

            table.insert(created_keymaps, { mode = mode, lhs = lhs })
        end

        pack:set_status("lazy")
        Event.emit("pack:lazy", {
            name = name,
            status = pack:get_status(),
            message = "Waiting for keymap",
            trigger = { type = "keys", value = ks },
        })
        return true
    end

    return false
end

-- ============================================================================
-- DisabledLoader (disabled stage)
-- ============================================================================
local DisabledLoader = setmetatable({}, { __index = BaseLoader })
DisabledLoader.__index = DisabledLoader

function DisabledLoader.new()
    return setmetatable(BaseLoader.new(), DisabledLoader)
end

function DisabledLoader:start(packs, manager, opts)
    for i, pack in ipairs(packs or {}) do
        if not pack.loaded and pack.enabled == false then
            local config_start = vim.loop.hrtime()
            local name = pack.specs.normalize.name
            local delay = (i - 1) * 50

            pack:set_status("disabling")

            vim.schedule(function()
                vim.defer_fn(function()
                    Event.emit("pack:config:start", {
                        name = name,
                        status = "disabling",
                        message = "Setting to disabled",
                        pack = pack,
                    })
                end, delay)
            end)

            pack:set_status("disabled")
            pack.loaded = false
            pack.times = pack.times or {}
            pack.times.config_duration = string.format("%.2f", (vim.loop.hrtime() - config_start) / 1e6)

            vim.schedule(function()
                vim.defer_fn(function()
                    Event.emit("pack:config:finish", {
                        name = name,
                        status = "disabled",
                        message = "Pack disabled",
                        config_duration = pack.times.config_duration,
                        pack = pack,
                    })
                end, delay + 50)
            end)
        end
    end
end

-- ============================================================================
-- Unified Interface
-- ============================================================================
local Loader = {
    Eager = EagerLoader.new(),
    Later = LaterLoader.new(),
    Lazy = LazyLoader.new(),
    Disabled = DisabledLoader.new(),
}

function Loader.run(stage, packs, manager, opts)
    local stage_map = {
        now = Loader.Eager,
        later = Loader.Later,
        lazy = Loader.Lazy,
        disabled = Loader.Disabled,
    }

    local impl = stage_map[stage]
    if impl then
        impl:start(packs or {}, manager, opts or {})
    else
        vim.notify("⚠ Unknown loader stage: " .. tostring(stage), vim.log.levels.WARN)
    end
end

function Loader:close_all()
    for _, loader in pairs(self) do
        if type(loader.close) == "function" then
            pcall(function()
                loader:close()
            end)
        end
    end
end

return Loader
