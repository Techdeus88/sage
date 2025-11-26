-- ============================================================================
-- sage/ui/dashboard_manager.lua
-- Intelligent Dashboard Display Logic
-- ============================================================================

local DashboardManager = {}
DashboardManager.__index = DashboardManager

function DashboardManager.new(opts)
    local self = setmetatable({}, DashboardManager)

    -- Configuration
    self.mode = opts.dashboard or "smart"
    self.auto_close_delay = opts.dashboard_auto_close or 3000 -- ms
    self.show_threshold = opts.dashboard_threshold or 500 -- ms
    self.state_file = vim.fn.stdpath("data") .. "/sage_dashboard_state.json"

    -- Dashboard reference (set by Manager)
    self.dashboard = nil

    -- State tracking
    self.shown_this_session = false
    self.first_run = nil
    self.start_time = nil
    self.has_errors = false
    self.auto_close_timer = nil

    -- Load persistent state
    self:load_state()

    return self
end

-- ============================================================================
-- State Persistence
-- ============================================================================

function DashboardManager:load_state()
    local ok, content = pcall(vim.fn.readfile, self.state_file)
    if ok and #content > 0 then
        local state = vim.fn.json_decode(table.concat(content))
        self.first_run = state.first_run == nil or state.first_run
    else
        -- First time ever
        self.first_run = true
        self:save_state({ first_run = false })
    end
end

function DashboardManager:save_state(data)
    pcall(function()
        vim.fn.writefile({ vim.fn.json_encode(data) }, self.state_file)
    end)
end

-- ============================================================================
-- Decision Logic
-- ============================================================================

function DashboardManager:should_show(context)
    context = context or {}

    -- Never show
    if self.mode == "never" then
        return false, "mode:never"
    end

    -- Manual only
    if self.mode == "manual" then
        return false, "mode:manual"
    end

    -- Always show
    if self.mode == "always" then
        return true, "mode:always"
    end

    -- Show once per session
    if self.mode == "startup" then
        if not self.shown_this_session then
            self.shown_this_session = true
            return true, "mode:startup"
        end
        return false, "already shown this session"
    end

    -- Show on first run or new packs
    if self.mode == "first" then
        if self.first_run then
            return true, "mode:first (first run)"
        end
        if context.new_packs and #context.new_packs > 0 then
            return true, string.format("mode:first (new: %d)", #context.new_packs)
        end
        return false, "not first run, no new packs"
    end

    -- Show only on errors
    if self.mode == "errors" then
        if context.failed_packs and #context.failed_packs > 0 then
            self.has_errors = true
            return true, string.format("mode:errors (failures: %d)", #context.failed_packs)
        end
        return false, "no errors detected"
    end

    -- Smart mode (multiple conditions)
    if self.mode == "smart" then
        return self:smart_decision(context)
    end

    return false, "unknown mode: " .. tostring(self.mode)
end

function DashboardManager:smart_decision(context)
    -- 1. First run detection
    if self.first_run then
        return true, "smart:first_run"
    end

    -- 2. New packs detected
    if context.new_packs and #context.new_packs > 0 then
        return true, string.format("smart:new_packs (%d)", #context.new_packs)
    end

    -- 3. Failures detected
    if context.failed_packs and #context.failed_packs > 0 then
        self.has_errors = true
        return true, string.format("smart:failures (%d)", #context.failed_packs)
    end

    -- 4. Startup taking too long
    if context.elapsed_ms and context.elapsed_ms > self.show_threshold then
        return true, string.format("smart:slow (%.0fms)", context.elapsed_ms)
    end

    -- 5. Large number of packs
    if context.packs and #context.packs > 30 then
        return true, string.format("smart:many_packs (%d)", #context.packs)
    end

    -- 6. Uninstalled packs detected
    if context.uninstalled_count and context.uninstalled_count > 0 then
        return true, string.format("smart:uninstalled (%d)", context.uninstalled_count)
    end

    -- Everything looks good
    return false, "smart:all_ok"
end

-- ============================================================================
-- Display Strategies
-- ============================================================================

function DashboardManager:show_immediately(context)
    local should_show, reason = self:should_show(context)

    if should_show and self.dashboard then
        vim.defer_fn(function()
            if not self.dashboard.is_open then
                self.dashboard:open()
                self:log(string.format("Dashboard shown: %s", reason))
            end
        end, 100)
    else
        self:log(string.format("Dashboard not shown: %s", reason))
    end

    return should_show
end

function DashboardManager:show_delayed(context, delay)
    self.start_time = vim.loop.hrtime()

    vim.defer_fn(function()
        local elapsed = (vim.loop.hrtime() - self.start_time) / 1e6
        context.elapsed_ms = elapsed

        local should_show, reason = self:should_show(context)

        if should_show and self.dashboard and not self.dashboard.is_open then
            self.dashboard:open()
            self:log(string.format("Dashboard shown (delayed): %s", reason))
        end
    end, delay or 500)
end

function DashboardManager:show_on_condition(condition_fn, context)
    if condition_fn() then
        local should_show, reason = self:should_show(context)

        if should_show and self.dashboard and not self.dashboard.is_open then
            vim.schedule(function()
                self.dashboard:open()
                self:log(string.format("Dashboard shown (conditional): %s", reason))
            end)
        end
    end
end

-- ============================================================================
-- Auto-close Logic
-- ============================================================================

function DashboardManager:setup_auto_close()
    if not self.dashboard or not self.dashboard.is_open then
        return
    end

    -- Don't auto-close if there are errors
    if self.has_errors then
        self:log("Auto-close skipped: errors present")
        return
    end

    -- Don't auto-close in certain modes
    if self.mode == "always" or self.mode == "manual" then
        self:log("Auto-close skipped: mode prevents it")
        return
    end

    -- User explicitly disabled auto-close
    if self.auto_close_delay == false or self.auto_close_delay == 0 then
        self:log("Auto-close disabled by config")
        return
    end

    -- Cancel existing timer
    if self.auto_close_timer then
        if not self.auto_close_timer:is_closing() then
            self.auto_close_timer:close()
        end
    end

    -- Schedule auto-close
    self.auto_close_timer = vim.loop.new_timer()
    self.auto_close_timer:start(
        self.auto_close_delay,
        0,
        vim.schedule_wrap(function()
            if self.dashboard and self.dashboard.is_open then
                self.dashboard:close()
                self:log(string.format("Dashboard auto-closed after %dms", self.auto_close_delay))
            end
            if self.auto_close_timer and not self.auto_close_timer:is_closing() then
                self.auto_close_timer:close()
            end
        end)
    )
end

function DashboardManager:cancel_auto_close()
    if self.auto_close_timer and not self.auto_close_timer:is_closing() then
        self.auto_close_timer:close()
        self.auto_close_timer = nil
        self:log("Auto-close cancelled")
    end
end

-- ============================================================================
-- Context Builders (Helpers for Manager)
-- ============================================================================

function DashboardManager:build_context(specs, packs)
    local context = {
        specs = specs or {},
        packs = packs or {},
        new_packs = {},
        uninstalled_count = 0,
        failed_packs = {},
    }

    -- Detect new/uninstalled packs
    if specs then
        for _, spec in ipairs(specs) do
            local pack_name = spec.name
            local pack_path = vim.fn.stdpath("data") .. "/site/pack/sage/opt/" .. pack_name

            if vim.fn.isdirectory(pack_path) == 0 then
                table.insert(context.new_packs, pack_name)
                context.uninstalled_count = context.uninstalled_count + 1
            end
        end
    end

    return context
end

function DashboardManager:update_context_with_results(context, result)
    if result then
        context.failed_packs = result.failed_packs or {}
        context.installed_count = result.installed_count or 0
        context.elapsed_ms = result.elapsed_ms or 0
    end
    return context
end

-- ============================================================================
-- Manual Controls
-- ============================================================================

function DashboardManager:force_open()
    if self.dashboard then
        self.dashboard:open()
        self:log("Dashboard force opened")
    end
end

function DashboardManager:force_close()
    if self.dashboard then
        self.dashboard:close()
        self:cancel_auto_close()
        self:log("Dashboard force closed")
    end
end

function DashboardManager:toggle()
    if self.dashboard then
        if self.dashboard.is_open then
            self:force_close()
        else
            self:force_open()
        end
    end
end

-- ============================================================================
-- Utilities
-- ============================================================================

function DashboardManager:log(message)
    if vim.g.sage_debug then
        print(string.format("[DashboardManager] %s", message))
    end
end

function DashboardManager:cleanup()
    self:cancel_auto_close()
    if self.dashboard then
        self.dashboard:close()
    end
end

return DashboardManager
