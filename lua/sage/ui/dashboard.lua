local height_percentage = 0.8
local width_percentage = 0.8

local function center_text(text, width)
    local text_width = vim.fn.strdisplaywidth(text)
    local padding = math.floor((width - text_width) / 2)
    if padding < 0 then
        padding = 0
    end
    local pad = string.rep(" ", padding)
    return string.format("%s%s%s", pad, text, pad)
end

local function add_padding_to_line(line, padding)
    padding = padding or 1
    local pad = string.rep(" ", padding)
    return string.format("%s%s%s", pad, line, pad)
end

-- ============================================================================
-- Dashboard UI Controller - Three Pane Layout
-- ============================================================================
local Dashboard = {}
Dashboard.__index = Dashboard

-- ============================================================================
-- SINGLETON INSTANCE
-- ============================================================================
local _instance = nil

function Dashboard.get_instance()
    if not _instance then
        _instance = setmetatable({}, Dashboard)
        _instance:_init_defaults()
    end
    return _instance
end

function Dashboard.new()
    -- Redirect to singleton
    return Dashboard.get_instance()
end

-- ============================================================================
-- INITIALIZATION DEFAULTS
-- ============================================================================
function Dashboard:_init_defaults()
    self.is_open = false
    self.is_valid = false
    self.initialized = false

    -- Window/Buffer management
    self.header_buf = nil
    self.header_win = nil
    self.content_buf = nil
    self.content_win = nil
    self.footer_buf = nil
    self.footer_win = nil

    -- Tab system
    self.tabs = {}
    self.active_tab_index = 1

    -- Pack tracking
    self.rows = {}
    self.rows_by_name = {}
    self.pending_packs = nil

    -- Selection system
    self.selected_rows = {}
    self.selection_mode = false

    -- Rendering & updates
    self.pending_row_updates = {}
    self.debounce_timers = {}
    self.last_render_times = { footer = 0, rows = {} }
    self.update_batch = { queue = {}, processing = false }

    -- Dependencies (set during init)
    self.container = nil
    self.elements = nil
    self.icons = nil
    self.opts = {}
    self.config = {}
    self.bus = nil
    self.manager = nil
    self.utils = nil
    self.logger = nil

    -- Namespace references
    self.ns_rows = nil
    self.ns_content = nil
    self.ns_buttons = nil
    self.ns_ui = nil
    self.ns_footer = nil
    self.ns_background = nil
    self.ns_text = nil
    self.ns_overlay = nil
    self.ns_status = nil
    self.ns_selection = nil

    -- Dimensions
    self.header_height = 4
    self.footer_height = 6

    -- Misc state
    self.last_stats = nil
    self.autocmd_ids = {}
    self.window_check_timer = nil
    self.render_timer = nil
    self._footer_timer = nil
    self._footer_pending = false
end

-- ============================================================================
-- INITIALIZATION (CALL ONCE)
-- ============================================================================
function Dashboard:init(container, elements, icons, opts)
    -- Prevent double-initialization
    if self.initialized then
        self.logger:warn("Dashboard", "Already initialized, skipping init()")
        return
    end

    self.opts = opts or {}
    self.container = container
    self.elements = elements
    self.icons = icons

    -- Resolve dependencies
    self.bus = self.container:resolve("bus")
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")
    self.logger = self.container:resolve("logger")

    -- Initialize subsystems
    self:_init_selection()
    self:_init_smooth_updates()
    self:_init_config()
    self:_init_tabs()
    self:_init_namespaces()
    self:_setup_highlights()
    self:_setup_commands()

    self.initialized = true
    self:debug_log("Dashboard initialized as singleton")
end

-- ============================================================================
-- PRIVATE INITIALIZATION METHODS
-- ============================================================================

function Dashboard:_init_selection()
    self.selected_rows = {}
    self.selection_mode = false
end

function Dashboard:_init_smooth_updates()
    self.pending_row_updates = {}
    self.pending_footer_update = false

    self.debounce_timers = {
        footer = nil,
        batch = nil,
    }

    self.last_render_times = {
        footer = 0,
        rows = {},
    }

    self.update_batch = {
        queue = {},
        processing = false,
    }

    self.frame_limiter = {
        last_frame = 0,
        pending_renders = {},
    }
end

function Dashboard:_init_config()
    self.config = {
        lock_windows = self.opts.lock_windows ~= false,
        auto_focus = self.opts.auto_focus ~= false,
        debounce_ms = self.opts.debounce_ms or 200,
        footer_debounce_ms = 150,
        row_debounce_ms = 100,
        batch_debounce_ms = 200,
        batch_interval_ms = 50,
        max_batch_size = 10,
        min_render_interval_ms = 16,
    }
end

function Dashboard:_init_tabs()
    self.tabs = {
        { id = "all", label = "All" },
        { id = "loaded", label = "Loaded" },
        { id = "not_loaded", label = "Not Loaded" },
        { id = "lazy", label = "Lazy" },
        { id = "now", label = "Now" },
        { id = "later", label = "Later" },
        { id = "failed", label = "Failed" },
        { id = "disabled", label = "Disabled" },
    }
    self.active_tab_index = 1
end

function Dashboard:_init_namespaces()
    self.ns_rows = vim.api.nvim_create_namespace("SageDashboardRows")
    self.ns_content = vim.api.nvim_create_namespace("SageDashboardContent")
    self.ns_buttons = vim.api.nvim_create_namespace("SageDashboardButtons")
    self.ns_ui = vim.api.nvim_create_namespace("SageUI")
    self.ns_footer = vim.api.nvim_create_namespace("SageDashboardFooter")
    self.ns_background = vim.api.nvim_create_namespace("SageBackground")
    self.ns_text = vim.api.nvim_create_namespace("SageText")
    self.ns_overlay = vim.api.nvim_create_namespace("SageOverlay")
    self.ns_status = vim.api.nvim_create_namespace("SageStatus")
    self.ns_selection = vim.api.nvim_create_namespace("SageDashboardSelection")
end

function Dashboard:_setup_highlights()
    vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
    vim.api.nvim_set_hl(0, "SageHeaderBorder", { link = "FloatBorder", default = true })
    vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
    vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })
    vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
    vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
    vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
    vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })

    vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "*",
        callback = function()
            self:_setup_highlights()
        end,
        desc = "Reapply Sage dashboard highlights on colorscheme change",
    })
end

function Dashboard:_setup_commands()
    vim.api.nvim_create_user_command("SageOpen", function()
        local dashboard = Dashboard.get_instance()
        dashboard:open()
    end, { desc = "Open Sage dashboard" })

    vim.api.nvim_create_user_command("SageClose", function()
        local dashboard = Dashboard.get_instance()
        dashboard:close()
    end, { desc = "Close Sage dashboard" })

    vim.api.nvim_create_user_command("SageToggle", function()
        local dashboard = Dashboard.get_instance()
        if dashboard.is_open then
            dashboard:close()
        else
            dashboard:open()
        end
    end, { desc = "Toggle Sage dashboard" })
end

local STATUS_ORDER = {
    not_loaded = 1,
    loaded = 2,
    failed = 3,
    disabled = 4,
}

local STAGE_ORDER = {
    now = 1,
    later = 2,
    lazy = 3,
    disabled = 4,
}

Dashboard.UPDATE_CONFIG = {
    -- Debounce timing
    footer_debounce_ms = 150,
    row_debounce_ms = 100,
    batch_debounce_ms = 200,

    -- Batch processing
    batch_interval_ms = 50,
    max_batch_size = 10,

    -- Render throttling
    min_render_interval_ms = 16,
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

function Dashboard:adjust_color(color, factor)
    if type(color) == "string" then
        color = tonumber(color:sub(2), 16)
    end
    local function rshift(x, n)
        return math.floor(x / 2 ^ n)
    end

    local function band(x, y)
        return x % (2 ^ (math.floor(math.log(y) / math.log(2)) + 1))
    end

    local r = math.floor(rshift(color, 16) * (1 + factor))
    local g = math.floor(band(rshift(color, 8), 0xFF) * (1 + factor))
    local b = math.floor(band(color, 0xFF) * (1 + factor))

    r = math.min(255, math.max(0, r))
    g = math.min(255, math.max(0, g))
    b = math.min(255, math.max(0, b))

    return string.format("#%02x%02x%02x", r, g, b)
end

function Dashboard:debug_log(msg, sub_source)
    sub_source = sub_source or ""
    self.logger:debug("Dashboard-" .. sub_source, msg)
end

local function getTableValue(t, keys)
    local current = t
    for _, key in ipairs(keys) do
        if type(current) == "table" and current[key] ~= nil then
            current = current[key]
        else
            return nil
        end
    end
    return current
end

local function split_by_period(str)
    local result = {}
    for part in str:gmatch("([^.]*)") do
        if part ~= "" then
            table.insert(result, part)
        end
    end
    return result
end

-- ============================================================================
-- Window & Buffer Helpers
-- ============================================================================

function Dashboard:get_window(window_name)
    local name_map = { header = self.header_win, content = self.content_win, footer = self.footer_win }
    return name_map[window_name]
end

function Dashboard:bufline(row)
    if not row.mark_id then
        return nil
    end
    local pos = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, self.ns_rows, row.mark_id, {})
    if not pos or not pos[1] then
        return nil
    end
    return pos[1]
end

function Dashboard:_ensure_lines(to_line_inclusive)
    local lc = vim.api.nvim_buf_line_count(self.content_buf)
    if lc <= to_line_inclusive then
        local need = to_line_inclusive - lc + 1
        local blanks = {}
        for _ = 1, need do
            blanks[#blanks + 1] = ""
        end
        vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
        vim.api.nvim_buf_set_lines(self.content_buf, lc, lc, false, blanks)
        vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    end
end

function Dashboard:is_valid()
    return self.content_buf
        and vim.api.nvim_buf_is_valid(self.content_buf)
        and self.content_win
        and vim.api.nvim_win_is_valid(self.content_win)
end

function Dashboard:find(name)
    return self.rows_by_name[name]
end
-- ============================================================================
-- Three-Pane Window Layout
-- ============================================================================
function Dashboard:create_three_pane_layout()
    local width = vim.o.columns
    local height = vim.o.lines

    local win_height = math.floor(height * height_percentage)
    local win_width = math.floor(width * width_percentage)

    local row = math.floor((height - win_height) / 2)
    local col = math.floor((width - win_width) / 2)

    local content_height = win_height - self.header_height - self.footer_height

    self.header_buf = vim.api.nvim_create_buf(false, true)
    self.content_buf = vim.api.nvim_create_buf(false, true)
    self.footer_buf = vim.api.nvim_create_buf(false, true)

    -- Configure buffers to prevent premature closure
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("filetype", "sage", { buf = buf })
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
        vim.api.nvim_set_option_value("indentexpr", "", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

        pcall(vim.api.nvim_buf_set_var, buf, "miniindentscope_disable", true)
        pcall(vim.api.nvim_buf_set_var, buf, "indent_blankline_enabled", false)
        pcall(vim.api.nvim_buf_set_var, buf, "snacks_indent_disable", true)
    end

    self.header_win = vim.api.nvim_open_win(self.header_buf, false, {
        relative = "editor",
        width = win_width,
        height = self.header_height,
        row = row,
        col = col,
        style = "minimal",
        border = { "┌", "─", "┐", "│", "", "", "", "│" },
    })

    self.content_win = vim.api.nvim_open_win(self.content_buf, true, {
        relative = "editor",
        width = win_width,
        height = content_height,
        row = row + self.header_height,
        col = col,
        style = "minimal",
        border = { "", "", "", "│", "", "", "", "│" },
    })

    self.footer_win = vim.api.nvim_open_win(self.footer_buf, false, {
        relative = "editor",
        width = win_width,
        height = self.footer_height,
        row = row + self.header_height + content_height,
        col = col,
        style = "minimal",
        border = { "├", "─", "┤", "│", "└", "─", "┘", "│" },
    })

    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_option_value("winfixheight", true, { win = win })
            vim.api.nvim_set_option_value("winfixwidth", true, { win = win })
            vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = win })
        end
    end

    vim.api.nvim_set_option_value("cursorline", true, { win = self.content_win })
    vim.api.nvim_set_option_value("scrolloff", 3, { win = self.content_win })

    pcall(vim.api.nvim_set_current_win, self.content_win)

    self:lock_windows()
    self:setup_close_keymaps()
end

function Dashboard:lock_windows()
    if not self.config or self.config.lock_windows == false then
        return
    end

    local dashboard_windows = {
        header = self.header_win,
        content = self.content_win,
        footer = self.footer_win,
    }

    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            local winleave_id = vim.api.nvim_create_autocmd("WinLeave", {
                callback = function()
                    local current = vim.api.nvim_get_current_win()
                    local is_dashboard = current == self.header_win
                        or current == self.content_win
                        or current == self.footer_win

                    if not is_dashboard then
                        vim.schedule(function()
                            if self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                                pcall(vim.api.nvim_set_current_win, self.content_win)
                            else
                                self:close()
                            end
                        end)
                    end
                end,
            })
            table.insert(self.autocmd_ids, winleave_id)
        end
    end

    local close_guard_id = vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(args)
            local closed_win = tonumber(args.match)

            for name, win_id in pairs(dashboard_windows) do
                if closed_win == win_id then
                    vim.schedule(function()
                        if self.header_win or self.content_win or self.footer_win then
                            self:close()
                        end
                    end)
                    return
                end
            end
        end,
    })
    table.insert(self.autocmd_ids, close_guard_id)

    self.window_check_timer = vim.uv.new_timer()
    self.window_check_timer:start(
        1000,
        1000,
        vim.schedule_wrap(function()
            local header_valid = self.header_win and vim.api.nvim_win_is_valid(self.header_win)
            local content_valid = self.content_win and vim.api.nvim_win_is_valid(self.content_win)
            local footer_valid = self.footer_win and vim.api.nvim_win_is_valid(self.footer_win)

            if not (header_valid and content_valid and footer_valid) then
                self:close()
            end
        end)
    )
end

function Dashboard:setup_close_keymaps()
    local close_keys = { "q", "<Esc>" }
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        for _, key in ipairs(close_keys) do
            vim.keymap.set("n", key, function()
                self:close()
            end, {
                buffer = buf,
                noremap = true,
                silent = true,
                nowait = true,
                desc = "Close Sage dashboard",
            })
        end
    end
end

-- ============================================================================
-- Window Management
-- ============================================================================
function Dashboard:open()
    if
        self.header_win
        and vim.api.nvim_win_is_valid(self.header_win)
        and self.content_win
        and vim.api.nvim_win_is_valid(self.content_win)
    then
        self:focus_first_pack()
        return
    end
    self.is_open = true
    self.is_valid = true

    local ok, err = pcall(function()
        self:create_three_pane_layout()
    end)

    if not ok then
        vim.notify("Failed to open dashboard: " .. tostring(err), vim.log.levels.ERROR)
        self.is_open = false
        return
    end

    if self.pending_packs then
        for _, pack in ipairs(self.pending_packs) do
            self:debug_log("add_pack(): flushing queued pack", pack.name)
            self:add_pack(pack)
        end
        self.pending_packs = nil
    end

    self:debug_log(string.format("Rendering %d tracked packs", vim.tbl_count(self.rows_by_name)))
    self:rebuild_display()

    self:render_header()
    self:render_footer()
    self:setup_keymaps()
    self:setup_footer_debounced()
end

function Dashboard:close()
    self.is_open = false
    self.is_valid = false

    if self.window_check_timer and not self.window_check_timer:is_closing() then
        self.window_check_timer:close()
        self.window_check_timer = nil
    end

    if self.render_timer and not self.render_timer:is_closing() then
        self.render_timer:close()
        self.render_timer = nil
    end

    self.autocmd_ids = {}

    self:cleanup_smooth_updates()
    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end

    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        if buf and vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end

    self.header_win = nil
    self.content_win = nil
    self.footer_win = nil
    self.header_buf = nil
    self.content_buf = nil
    self.footer_buf = nil
    self.rows = {}
    self.rows_by_name = {}
    self.is_open = false
end

-- ============================================================================
-- Window Focus Management
-- ============================================================================
function Dashboard:focus_content_window()
    if not (self.content_win and vim.api.nvim_win_is_valid(self.content_win)) then
        return
    end
    pcall(vim.api.nvim_set_current_win, self.content_win)
    pcall(vim.api.nvim_win_set_cursor, self.content_win, { 1, 0 })
    vim.cmd("redraw")
end

function Dashboard:focus_first_pack()
    if not (self.content_win and vim.api.nvim_win_is_valid(self.content_win)) then
        return
    end
    local first_row = nil
    for _, row in ipairs(self.rows) do
        local line = self:bufline(row)
        if line then
            if not first_row or line < self:bufline(first_row) then
                first_row = row
            end
        end
    end

    if first_row then
        local line = self:bufline(first_row)
        pcall(vim.api.nvim_set_current_win, self.content_win)
        pcall(vim.api.nvim_win_set_cursor, self.content_win, { line + 1, 0 })
    else
        self:focus_content_window()
    end
end

-- ============================================================================
-- Enhanced Keymaps with Pack Operations
-- ============================================================================

function Dashboard:setup_keymaps()
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    -- Disable insert mode in all buffers
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.keymap.set("n", "i", "<Nop>", { buffer = buf, silent = true })
        vim.keymap.set("n", "a", "<Nop>", { buffer = buf, silent = true })
    end

    -- Tab navigation
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.keymap.set("n", "<Tab>", function()
            self.active_tab_index = (self.active_tab_index % #self.tabs) + 1
            self:refresh_for_tab()

            if self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                pcall(vim.api.nvim_set_current_win, self.content_win)
            end
        end, { buffer = buf, silent = true, desc = "Next tab" })

        vim.keymap.set("n", "<S-Tab>", function()
            self.active_tab_index = (self.active_tab_index - 2 + #self.tabs) % #self.tabs + 1
            self:refresh_for_tab()

            if self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                pcall(vim.api.nvim_set_current_win, self.content_win)
            end
        end, { buffer = buf, silent = true, desc = "Previous tab" })
    end

    -- Selection mode keymaps
    vim.keymap.set("n", "v", function()
        self:toggle_selection_mode()
        vim.notify(self.selection_mode and "Selection mode enabled" or "Selection mode disabled", vim.log.levels.INFO)
    end, { buffer = self.content_buf, silent = true, desc = "Toggle selection mode" })

    vim.keymap.set("n", "<Space>", function()
        if not self.selection_mode then
            vim.notify("Enable selection mode first (press 'v')", vim.log.levels.WARN)
            return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = self:get_row_at_line(cursor[1])

        if row then
            self:toggle_row_selection(row)
            local count = vim.tbl_count(self.selected_rows)
            vim.notify(string.format("%d pack(s) selected", count), vim.log.levels.INFO)
            self:render_selection_indicator()
        end
    end, { buffer = self.content_buf, silent = true, desc = "Toggle row selection" })

    vim.keymap.set("n", "<Esc>", function()
        if self.selection_mode then
            self:toggle_selection_mode()
            vim.notify("Selection cleared", vim.log.levels.INFO)
        end
    end, { buffer = self.content_buf, silent = true, desc = "Clear selection" })

    -- Delete pack(s)
    vim.keymap.set("n", "d", function()
        local pack_names = {}

        if self.selection_mode and vim.tbl_count(self.selected_rows) > 0 then
            pack_names = self:get_selected_pack_names()
        else
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = self:get_row_at_line(cursor[1])

            if not row then
                vim.notify("No pack under cursor", vim.log.levels.WARN)
                return
            end

            pack_names = { row.name }
        end

        self:delete_packs(pack_names)
    end, { buffer = self.content_buf, silent = true, desc = "Delete pack(s)" })

    -- Update pack(s)
    vim.keymap.set("n", "u", function()
        local pack_names = {}

        if self.selection_mode and vim.tbl_count(self.selected_rows) > 0 then
            pack_names = self:get_selected_pack_names()
        else
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = self:get_row_at_line(cursor[1])

            if not row then
                vim.notify("No pack under cursor", vim.log.levels.WARN)
                return
            end

            pack_names = { row.name }
        end

        self:update_packs(pack_names)
    end, { buffer = self.content_buf, silent = true, desc = "Update pack(s)" })

    -- Force update pack(s)
    vim.keymap.set("n", "U!", function()
        local pack_names = {}

        if self.selection_mode and vim.tbl_count(self.selected_rows) > 0 then
            pack_names = self:get_selected_pack_names()
        else
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = self:get_row_at_line(cursor[1])

            if not row then
                vim.notify("No pack under cursor", vim.log.levels.WARN)
                return
            end

            pack_names = { row.name }
        end

        self:update_packs(pack_names, { force = true })
    end, { buffer = self.content_buf, silent = true, desc = "Force update pack(s)" })

    -- Update ALL packs
    vim.keymap.set("n", "U", function()
        self:update_all_packs()
    end, { buffer = self.content_buf, silent = true, desc = "Update all packs" })

    -- Pack comparison
    vim.keymap.set("n", "<A-CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = self:get_row_at_line(cursor[1])

        if not row then
            vim.notify("No pack selected", vim.log.levels.WARN)
            return
        end

        self:display_pack_comparison(row.name)
    end, { buffer = self.content_buf, silent = true, desc = "Show pack comparison" })

    -- Refresh
    vim.keymap.set("n", "r", function()
        vim.notify("Refreshing dashboard...", vim.log.levels.INFO)
        vim.schedule(function()
            self:close()
            self:open()
        end)
    end, { buffer = self.content_buf, desc = "Refresh dashboard" })

    -- Toggle details
    vim.keymap.set("n", "<CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = self:get_row_at_line(cursor[1])

        if not row then
            vim.notify("No pack selected", vim.log.levels.WARN)
            return
        end

        if row.expanded then
            self:collapse_details(row)
        else
            self:expand_details(row)
        end
    end, { buffer = self.content_buf, desc = "Toggle pack details" })

    -- Help
    vim.keymap.set("n", "?", function()
        self:show_help()
    end, { buffer = self.content_buf, silent = true, desc = "Show help" })
end

-- ============================================================================
-- Help Display
-- ============================================================================

function Dashboard:show_help()
    local help_lines = {
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "                    SAGE DASHBOARD KEYBINDINGS                  ",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "",
        "Navigation:",
        "  <Tab>        Next tab",
        "  <S-Tab>      Previous tab",
        "  <CR>         Toggle pack details",
        "  r            Refresh dashboard",
        "",
        "Selection:",
        "  v            Toggle selection mode",
        "  <Space>      Toggle row selection (in selection mode)",
        "  <Esc>        Clear selection / Exit selection mode",
        "",
        "Pack Operations:",
        "  d            Delete selected pack(s) or pack under cursor",
        "  u            Update selected pack(s) or pack under cursor",
        "  U            Update ALL packs",
        "  U!           Force update (no confirmation)",
        "",
        "Information:",
        "  <A-CR>       Show pack comparison (Sage vs vim.pack)",
        "  ?            Show this help",
        "",
        "Close:",
        "  q            Close dashboard",
        "",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "",
        "Press any key to close this help...",
    }

    local buf = vim.api.nvim_create_buf(false, true)
    local width = 67
    local height = #help_lines

    local win_width = vim.o.columns
    local win_height = vim.o.lines
    local row = math.floor((win_height - height) / 2)
    local col = math.floor((win_width - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

    -- Close on any key
    vim.keymap.set("n", "<buffer>", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
end

-- ============================================================================
-- Header Rendering
-- ============================================================================
function Dashboard:render_header()
    if not (self.header_buf and vim.api.nvim_buf_is_valid(self.header_buf)) then
        return
    end

    local tab_line = {}
    for i, tab in ipairs(self.tabs) do
        if i == self.active_tab_index then
            table.insert(tab_line, string.format(" [%s] ", tab.label))
        else
            table.insert(tab_line, string.format("  %s  ", tab.label))
        end
    end

    local win_width = vim.api.nvim_win_get_width(self.header_win)
    local rendered_tabs = center_text(table.concat(tab_line, ""), win_width)

    local header_lines = { "", rendered_tabs, "", "" }

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.header_buf })
    vim.api.nvim_buf_set_lines(self.header_buf, 0, -1, false, header_lines)

    vim.api.nvim_buf_clear_namespace(self.header_buf, self.ns_ui, 0, -1)

    local col = 0
    local tab_text = table.concat(tab_line, "")
    local padding = math.floor((win_width - #tab_text) / 2)

    for i, tab in ipairs(self.tabs) do
        local text = (i == self.active_tab_index) and string.format(" [%s] ", tab.label)
            or string.format("  %s  ", tab.label)

        local hl = (i == self.active_tab_index) and "SageTabActive" or "SageTab"

        vim.api.nvim_buf_set_extmark(self.header_buf, self.ns_ui, 1, padding + col, {
            end_col = padding + col + #text,
            hl_group = hl,
            hl_mode = "combine",
            virt_text = {},
        })
        col = col + #text
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.header_buf })
end

-- ============================================================================
-- Footer Rendering with Extmarks (Multi-line Support)
-- ============================================================================

function Dashboard:render_footer()
    local footer_type = self.opts.footer_type or "primary"
    if footer_type == "primary" then
        self:render_footer_primary_extmarks()
    elseif footer_type == "alternative" then
        self:render_footer_alternative_extmarks()
    end
end

function Dashboard:render_footer_primary_extmarks()
    if not (self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf)) then
        return
    end
    if not (self.footer_win and vim.api.nvim_win_is_valid(self.footer_win)) then
        return
    end

    local win_width = vim.api.nvim_win_get_width(self.footer_win)
    local stats = self:get_stats()

    local ok, sage_metrics = pcall(require, "sage.metrics")
    local total_duration = 0
    if ok and sage_metrics and type(sage_metrics.get_event) == "function" then
        total_duration = sage_metrics:get_event("uienter") or 0
    end

    -- Calculate progress
    local progress_pct = stats.total > 0 and ((stats.loaded + stats.unloaded) / stats.total * 100) or 0
    local bar_width = math.floor(win_width * 0.6)
    local filled = math.floor(bar_width * (progress_pct / 100))
    local empty = bar_width - filled
    local progress_bar = string.rep("█", filled) .. string.rep("░", empty)

    -- Prepare buffer with proper line structure
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.footer_buf })
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, { "", "", "" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.footer_buf })

    -- Clear previous extmarks
    vim.api.nvim_buf_clear_namespace(self.footer_buf, self.ns_footer, 0, -1)

    -- LINE 0: Progress bar
    local progress_text = string.format(
        "[%d/%d] %s %.0f%%",
        stats.loaded + stats.unloaded,
        stats.total,
        progress_bar,
        progress_pct
    )
    local progress_centered = center_text(progress_text, win_width)

    vim.api.nvim_buf_set_extmark(self.footer_buf, self.ns_footer, 0, 0, {
        virt_text = { { progress_centered, "SageFooterProgress" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })

    -- LINE 1: Stats
    local stats_text = string.format(
        "Loaded: %d  •  Unloaded: %d  •  Lazy: %d  •  Failed: %d  •  Now: %d  •  Later: %d  •  Disabled: %d  •  Duration: %sms",
        stats.loaded,
        stats.unloaded,
        stats.lazy,
        stats.failed,
        stats.now,
        stats.later,
        stats.disabled,
        total_duration
    )
    local stats_centered = center_text(stats_text, win_width)

    vim.api.nvim_buf_set_extmark(self.footer_buf, self.ns_footer, 1, 0, {
        virt_text = { { stats_centered, "SageFooterStats" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })

    -- LINE 2: Help text
    local help_text =
        "Press 'r' to refresh  •  'q' to quit  •  '<CR>' to toggle details  •  '<Tab>' to switch tabs  •  '?' for help"
    local help_centered = center_text(help_text, win_width)

    vim.api.nvim_buf_set_extmark(self.footer_buf, self.ns_footer, 2, 0, {
        virt_text = { { help_centered, "SageFooterHelp" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })
end

function Dashboard:render_footer_alternative_extmarks()
    if not (self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf)) then
        return
    end
    if not (self.footer_win and vim.api.nvim_win_is_valid(self.footer_win)) then
        return
    end

    local stats = self:get_stats()

    -- Calculate progress percentage
    local pct = 0
    local loaded = math.min((stats.loaded), 100)
    if stats.total > 0 then
        pct = math.floor((loaded / stats.total) * 100)
    end

    -- Create progress bar (10 segments)
    local filled = math.floor(pct / 10)
    local empty = 10 - filled
    local bar = "[" .. string.rep("■", filled) .. string.rep("□", empty) .. "]"

    -- Prepare buffer
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.footer_buf })
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, { "", "" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.footer_buf })

    -- Clear previous extmarks
    vim.api.nvim_buf_clear_namespace(self.footer_buf, self.ns_footer, 0, -1)

    -- LINE 0: Progress bar with percentage
    local line0_segments = {
        { bar .. " ", "MoreMsg" },
        { string.format("%2d:%2d (%d%%)%3d packs", stats.loaded, stats.unloaded, pct, stats.total), "Number" },
    }

    vim.api.nvim_buf_set_extmark(self.footer_buf, self.ns_footer, 0, 0, {
        virt_text = line0_segments,
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })

    -- LINE 1: Detailed stats
    local statistics = string.format(
        "Total:%d  Loaded:%d  Unloaded:%d  Failed:%d  Now:%d  Later:%d  Lazy:%d  Disabled:%d",
        stats.total,
        stats.loaded,
        stats.unloaded,
        stats.failed,
        stats.now,
        stats.later,
        stats.lazy,
        stats.disabled
    )

    local line1_segments = {
        { statistics .. " ", "Comment" },
    }

    vim.api.nvim_buf_set_extmark(self.footer_buf, self.ns_footer, 1, 0, {
        virt_text = line1_segments,
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })
end

function Dashboard:setup_footer_debounced()
    self._footer_timer = nil
    self._footer_pending = false
end

function Dashboard:schedule_footer_update()
    -- Cancel existing timer
    if self.debounce_timers.footer then
        vim.fn.timer_stop(self.debounce_timers.footer)
        self.debounce_timers.footer = nil
    end

    -- Schedule new update
    self.debounce_timers.footer = vim.fn.timer_start(self.config.footer_debounce_ms, function()
        self:render_footer()
        self.last_render_times.footer = vim.loop.now()
        self.debounce_timers.footer = nil
    end)
end

-- ============================================================================
-- Statistics
-- ============================================================================
function Dashboard:get_stats()
    local stats = {
        total = 0,
        failed = 0,
        loaded = 0,
        unloaded = 0,
        now = 0,
        later = 0,
        lazy = 0,
        disabled = 0,
    }
    for _, row in ipairs(self.rows) do
        stats.total = stats.total + 1

        local s = row.elements.status and row.elements.status.value
        local st = row.elements.stage and row.elements.stage.value

        if s == "ready" or s == "configured" or s == "loaded" then
            stats.loaded = stats.loaded + 1
        end

        if s == "wait_to_load" or s == "configuring" or s == "disabled" then
            stats.unloaded = stats.unloaded + 1
        end

        if s == "failed" then
            stats.failed = stats.failed + 1
        end
        if st == "lazy" then
            stats.lazy = stats.lazy + 1
        end
        if st == "now" then
            stats.now = stats.now + 1
        end
        if st == "later" then
            stats.later = stats.later + 1
        end
        if st == "disabled" then
            stats.disabled = stats.disabled + 1
        end
    end

    return stats
end

-- ============================================================================
-- Row Rendering & Management
-- ============================================================================

function Dashboard:build_segments_for_row(row)
    local segments = {}
    -- Pad by 1 column so row does not touch the left border
    table.insert(segments, { " ", "Normal" })

    local elems = row.elements

    local render_order = {
        elems.status,
        elems.name,
        elems.stage,
        elems.install_duration,
        elems.config_duration,
        elems.deps,
        elems.lazy,
        elems.message,
        elems.path,
        elems.error,
    }

    for _, elem in ipairs(render_order) do
        if elem then
            -- Check if element has text property (simple elements)
            if elem.text and elem.text ~= "" then
                table.insert(segments, { elem.text, elem.hl_group or "Normal" })
                table.insert(segments, { " ", "Normal" })
            -- Check if element has render_with_hl method (complex elements)
            elseif elem.render_with_hl then
                local out = elem:render_with_hl()

                -- Handle array of segments (like LazyElement)
                if type(out) == "table" and out[1] and out[1].text then
                    for _, part in ipairs(out) do
                        local t = part.text
                        if type(t) ~= "string" then
                            t = tostring(t or "")
                        end
                        if t ~= "" then
                            local hl = part.hl_group or "Normal"
                            table.insert(segments, { t, hl })
                        end
                    end
                    table.insert(segments, { " ", "Normal" })
                -- Handle single segment object
                elseif type(out) == "table" and out.text and out.text ~= "" then
                    local t = out.text
                    if type(t) ~= "string" then
                        t = tostring(t or "")
                    end
                    table.insert(segments, { t, out.hl_group or "Normal" })
                    table.insert(segments, { " ", "Normal" })
                end
            end
        end
    end

    -- Remove trailing space
    if segments[#segments] and segments[#segments][1] == " " then
        table.remove(segments)
    end

    return segments
end

function Dashboard:render_row_at(line, row)
    -- Get segments from the row's build_segments function
    local segments = row.build_segments and row.build_segments() or {}
    -- Validate segments structure
    if type(segments) ~= "table" then
        self:debug_log("ERROR: build_segments() did not return a table for " .. (row.name or "unknown"))
        return
    end

    -- Place the extmark with virt_text
    vim.api.nvim_buf_set_extmark(self.content_buf, self.ns_content, line, 0, {
        virt_text = segments,
        virt_text_pos = "overlay",
        hl_mode = "combine",
    })
end

function Dashboard:clear_content()
    vim.api.nvim_buf_clear_namespace(self.content_buf, self.ns_content, 0, -1)
end

function Dashboard:refresh()
    self:clear_content()
    for _, row in ipairs(self.rows) do
        if row.mark_id then
            local pos = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, self.ns_rows, row.mark_id, {})
            if pos and pos[1] then
                self:render_row_at(pos[1], row)
            end
        end
    end
end

-- ============================================================================
-- Tab Filtering & Display
-- ============================================================================

function Dashboard:refresh_for_tab()
    if not self.content_buf or not vim.api.nvim_buf_is_valid(self.content_buf) then
        return
    end

    local filter_id = self.tabs[self.active_tab_index].id

    local function matches(row)
        local status = row.elements.status and row.elements.status.value
        local stage = row.elements.stage and row.elements.stage.value
        local pack = row.pack

        if filter_id == "all" then
            return true
        end
        if filter_id == "loaded" then
            return status == "loaded" or status == "ready" or status == "configured"
        end
        if filter_id == "not_loaded" then
            return (pack and not pack.loaded) or status == "installing" or status == "installed" or status == "created"
        end
        if filter_id == "lazy" then
            return stage == "lazy"
        end
        if filter_id == "failed" then
            return status == "failed"
        end
        if filter_id == "now" then
            return stage == "now"
        end
        if filter_id == "later" then
            return stage == "later"
        end
        if filter_id == "disabled" then
            return stage == "disabled"
        end

        return false
    end

    vim.api.nvim_buf_clear_namespace(self.content_buf, self.ns_rows, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.content_buf, self.ns_content, 0, -1)
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    local line = 0
    local any = false

    for _, row in ipairs(self.rows) do
        if matches(row) then
            any = true

            vim.api.nvim_buf_set_lines(self.content_buf, line, line, false, { "" })

            row.mark_id = vim.api.nvim_buf_set_extmark(
                self.content_buf,
                self.ns_rows,
                line,
                0,
                { id = row.mark_id, right_gravity = false }
            )

            self:render_row_at(line, row)

            if row.expanded and row.details then
                for _, det in ipairs(row.details) do
                    line = line + 1

                    vim.api.nvim_buf_set_lines(self.content_buf, line, line, false, { "" })

                    det.mark_id = vim.api.nvim_buf_set_extmark(
                        self.content_buf,
                        self.ns_rows,
                        line,
                        0,
                        { id = det.mark_id, right_gravity = false }
                    )

                    self:render_row_at(line, det)
                end
            end

            line = line + 1
        end
    end

    if not any then
        vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {
            "",
            "   No packs for filter: " .. filter_id,
            "",
        })
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:render_header()
    self:render_footer()
end

-- ============================================================================
-- Sorting & Display Rebuild
-- ============================================================================

function Dashboard:resort_rows()
    table.sort(self.rows, function(a, b)
        local status_a = a.elements.status.value or "not_loaded"
        local status_b = b.elements.status.value or "not_loaded"
        local sa = STATUS_ORDER[status_a] or 999
        local sb = STATUS_ORDER[status_b] or 999
        if sa ~= sb then
            return sa > sb
        end

        local stage_a = a.elements.stage.value or "now"
        local stage_b = b.elements.stage.value or "now"
        local sta = STAGE_ORDER[stage_a] or 999
        local stb = STAGE_ORDER[stage_b] or 999

        if sta ~= stb then
            return sta < stb
        end

        return a.name < b.name
    end)

    self:rebuild_display()
end

function Dashboard:rebuild_display()
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    for i, row in ipairs(self.rows) do
        local line = i - 1

        self:_ensure_lines(line)

        if row.mark_id then
            pcall(vim.api.nvim_buf_del_extmark, self.content_buf, self.ns_rows, row.mark_id)
        end

        row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, self.ns_rows, line, 0, {
            right_gravity = true,
        })

        self:render_row_at(line, row)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:render_header()
    self:render_footer()
end

-- ============================================================================
-- Pack Management
-- ============================================================================

function Dashboard:add_pack(pack)
    if not self.content_buf or not vim.api.nvim_buf_is_valid(self.content_buf) then
        self.pending_packs = self.pending_packs or {}
        table.insert(self.pending_packs, pack)
        self:debug_log("add_pack(): UI not ready, queued", pack.name)
        return
    end
    if self.rows_by_name[pack.name] then
        return
    end

    local row = {
        name = pack.name,
        pack = pack.pack,
        mark_id = nil,
        expanded = false,
        details = {},
        elements = self:build_elements_for_pack(pack),
    }

    row.build_segments = function()
        return self:build_segments_for_row(row)
    end

    self.rows_by_name[pack.name] = row
    table.insert(self.rows, row)

    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })

    local line = vim.api.nvim_buf_line_count(self.content_buf)
    vim.api.nvim_buf_set_lines(self.content_buf, line, line, false, { "" })

    row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, self.ns_rows, line, 0, {
        right_gravity = false,
    })

    self:render_row_at(line, row)

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })

    return row
end

function Dashboard:build_elements_for_pack(data)
    local icons = self.icons
    local elem = self.elements
    local utils = self.utils
    local name = data.name
    local stage = data.stage
    local status = data.status
    local message = data.message
    local path = data.path or ""

    local Pack = self.manager.packs[name]
    local n_spec = Pack.specs.normalize

    local trigger_data = (n_spec.data.on and next(n_spec.data.on)) and n_spec.data.on or nil

    local name_elem = elem.TextElement.new("name", name)
    local status_elem = elem.StatusElement.new("status", status, "icon")
    local status_elem_two = elem.StatusElement.new("status", status, "icon_text")
    local stage_elem = elem.StageElement.new("stage", stage, "icon")
    local stage_elem_two = elem.StageElement.new("stage", stage, "icon_text")
    local install_duration_elem = elem.DurationElement.new("install_duration", Pack.times.install_duration)
    local config_duration_elem = elem.DurationElement.new("config_duration", Pack.times.config_duration)
    local message_elem = elem.TextElement.new("message", message)
    local deps_elem = elem.ListElement.new("deps", utils.get_dep_names(n_spec.data.depends or {}))
    local lazy_elem = elem.LazyElement.new("lazy", trigger_data)
    local path_elem = elem.LinkElement.new("path", path)
    local error_elem = elem.ErrorElement.new("error", "")

    local row_elements = {
        name = name_elem,
        status = status_elem,
        status_two = status_elem_two,
        stage = stage_elem,
        stage_two = stage_elem_two,
        install_duration = install_duration_elem,
        config_duration = config_duration_elem,
        message = message_elem,
        deps = deps_elem,
        lazy = lazy_elem,
        path = path_elem,
        error = error_elem,
    }

    return row_elements
end

function Dashboard:sync_all_packs()
    if not self.manager or not self.manager.packs then
        return
    end
    for name, pack in pairs(self.manager.packs) do
        local row = self.rows_by_name[name]
        if not row then
            self:add_pack({
                name = name,
                pack = pack,
                stage = pack:get_stage(),
                status = pack:get_status(),
                message = "Idle",
            })
        end
    end

    self:resort_rows()
end

-- ============================================================================
-- Details Expansion
-- ============================================================================

function Dashboard:toggle_expand(row)
    row.expanded = not row.expanded
    self:refresh_for_tab()
end

function Dashboard:add_detail(row, text)
    local det = {
        name = row.name .. "::detail_" .. tostring(#row.details + 1),
        is_detail = true,
        expanded = false,
        mark_id = nil,
        elements = {
            name = self.elements.TextElement.new("detail", "  " .. text),
        },
    }
    det.build_segments = function()
        return self:build_segments_for_row(det)
    end

    table.insert(row.details, det)
    return det
end

function Dashboard:expand_details(row)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end
    if row.expanded then
        return
    end
    local l = self:bufline(row)
    if not l then
        return
    end

    local elements = row.elements
    local details = {
        string.format("   ├─ Status: %s", elements.status_two:render()),
        string.format("   ├─ Stage: %s", elements.stage_two:render()),
        string.format("   ├─ Install Time: %s", elements.install_duration:render() or "0"),
        string.format("   ├─ Config Time: %s", elements.config_duration:render() or "0"),
        string.format("   ├─ Path: %s", elements.path:render()),
    }

    if elements.stage.value == "lazy" and elements.lazy and elements.lazy.render_detailed then
        table.insert(details, string.format("   ├─ Trigger: %s", elements.lazy:render_detailed()))
    end
    table.insert(
        details,
        string.format(
            "   └─ Deps: %s",
            (#elements.deps:render_buttons() > 0 and elements.deps:render_buttons_joined() or "none")
        )
    )

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1, false, details)
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })

    row.expanded = true
    row.details_count = #details
end

function Dashboard:collapse_details(row)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end
    if not row.expanded then
        return
    end

    local l = self:bufline(row)
    if not l then
        return
    end

    local count = row.details_count or 0
    if count > 0 then
        vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
        vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1 + count, false, {})
        vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    end

    row.expanded = false
    row.details_count = 0
end

function Dashboard:get_row_at_line(buffer_line)
    local line_0 = buffer_line - 1
    for _, row in ipairs(self.rows) do
        local row_line = self:bufline(row)
        if row_line then
            if line_0 == row_line then
                return row
            end
            if row.expanded and row.details_count then
                if line_0 > row_line and line_0 <= (row_line + row.details_count) then
                    return row
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- Selection System
-- ============================================================================

function Dashboard:init_selection()
    self.selected_rows = {}
    self.selection_mode = false
end

function Dashboard:toggle_selection_mode()
    self.selection_mode = not self.selection_mode
    if not self.selection_mode then
        self:clear_selection()
    end
    self:render_selection_indicator()
end

function Dashboard:toggle_row_selection(row)
    if not row then
        return
    end

    if self.selected_rows[row.name] then
        self.selected_rows[row.name] = nil
    else
        self.selected_rows[row.name] = row
    end

    self:render_row_selection(row)
end

function Dashboard:clear_selection()
    for name, _ in pairs(self.selected_rows) do
        local row = self.rows_by_name[name]
        if row then
            self:render_row_selection(row)
        end
    end
    self.selected_rows = {}
end

function Dashboard:get_selected_pack_names()
    local names = {}
    for name, _ in pairs(self.selected_rows) do
        table.insert(names, name)
    end
    return names
end

function Dashboard:render_row_selection(row)
    if not row or not row.mark_id then
        return
    end

    local pos = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, self.ns_rows, row.mark_id, {})
    if not pos or not pos[1] then
        return
    end

    local line = pos[1]
    local is_selected = self.selected_rows[row.name] ~= nil

    if is_selected then
        vim.api.nvim_buf_set_extmark(self.content_buf, self.ns_selection, line, 0, {
            line_hl_group = "Visual",
            priority = 100,
        })
    else
        vim.api.nvim_buf_clear_namespace(self.content_buf, self.ns_selection, line, line + 1)
    end
end

function Dashboard:render_selection_indicator()
    if not (self.header_buf and vim.api.nvim_buf_is_valid(self.header_buf)) then
        return
    end

    local indicator = ""
    if self.selection_mode then
        local count = vim.tbl_count(self.selected_rows)
        indicator = string.format("  [SELECTION MODE: %d selected]", count)
    end

    vim.api.nvim_buf_set_extmark(self.header_buf, self.ns_ui, 0, 0, {
        virt_text = { { indicator, "WarningMsg" } },
        virt_text_pos = "eol",
    })
end

-- ============================================================================
-- Pack Operations
-- ============================================================================

function Dashboard:delete_packs(pack_names)
    if not pack_names or #pack_names == 0 then
        vim.notify("No packs selected for deletion", vim.log.levels.WARN)
        return
    end

    local pack_list = table.concat(pack_names, ", ")
    local confirm_msg = string.format("Delete %d pack(s)?\n%s\n\nType 'yes' to confirm:", #pack_names, pack_list)

    vim.ui.input({
        prompt = confirm_msg,
    }, function(input)
        if input ~= "yes" then
            vim.notify("Deletion cancelled", vim.log.levels.INFO)
            return
        end

        vim.notify(string.format("Deleting %d pack(s)...", #pack_names), vim.log.levels.INFO)

        for _, name in ipairs(pack_names) do
            local ok, err = pcall(vim.pack.delete, { name })

            if ok then
                vim.notify(string.format("✓ Deleted: %s", name), vim.log.levels.INFO)

                local row = self:find(name)
                if row then
                    self:apply_update_to_row(row, {
                        status = "deleted",
                        message = "Deleted",
                    })
                    self:update_row(name)
                end
            else
                vim.notify(string.format("✗ Failed to delete %s: %s", name, tostring(err)), vim.log.levels.ERROR)
            end
        end

        self:clear_selection()
        vim.notify("Deletion complete", vim.log.levels.INFO)
    end)
end

function Dashboard:update_packs(pack_names, opts)
    opts = opts or {}

    if not pack_names or #pack_names == 0 then
        vim.notify("No packs selected for update", vim.log.levels.WARN)
        return
    end

    if not opts.force then
        local pack_list = table.concat(pack_names, ", ")
        local confirm_msg = string.format("Update %d pack(s)?\n%s\n\nType 'yes' to confirm:", #pack_names, pack_list)

        vim.ui.input({
            prompt = confirm_msg,
        }, function(input)
            if input ~= "yes" then
                vim.notify("Update cancelled", vim.log.levels.INFO)
                return
            end

            self:_execute_updates(pack_names, opts)
        end)
    else
        self:_execute_updates(pack_names, opts)
    end
end

function Dashboard:_execute_updates(pack_names, opts)
    vim.notify(string.format("Updating %d pack(s)...", #pack_names), vim.log.levels.INFO)

    for _, name in ipairs(pack_names) do
        local row = self:find(name)
        if row then
            self:apply_update_to_row(row, {
                status = "updating",
                message = "Updating...",
            })
            self:update_row(name)
        end

        vim.schedule(function()
            local update_opts = vim.tbl_extend("force", opts, {})
            local ok, err = pcall(vim.pack.update, { name }, update_opts)

            if ok then
                vim.notify(string.format("✓ Updated: %s", name), vim.log.levels.INFO)

                if row then
                    self:apply_update_to_row(row, {
                        status = "loaded",
                        message = "Updated",
                    })
                    self:update_row(name)
                end
            else
                vim.notify(string.format("✗ Failed to update %s: %s", name, tostring(err)), vim.log.levels.ERROR)

                if row then
                    self:apply_update_to_row(row, {
                        status = "failed",
                        message = "Update failed",
                    })
                    self:update_row(name)
                end
            end
        end)
    end

    self:clear_selection()
    vim.notify("Update complete", vim.log.levels.INFO)
end

function Dashboard:update_all_packs(opts)
    opts = opts or {}

    local confirm_msg = "Update ALL packs?\n\nType 'yes' to confirm:"

    vim.ui.input({
        prompt = confirm_msg,
    }, function(input)
        if input ~= "yes" then
            vim.notify("Update cancelled", vim.log.levels.INFO)
            return
        end

        vim.notify("Updating all packs...", vim.log.levels.INFO)

        for _, row in ipairs(self.rows) do
            self:apply_update_to_row(row, {
                status = "updating",
                message = "Updating...",
            })
            self:update_row(row.name)
        end

        vim.schedule(function()
            local ok, err = pcall(vim.pack.update, opts)

            if ok then
                vim.notify("✓ All packs updated successfully", vim.log.levels.INFO)

                for _, row in ipairs(self.rows) do
                    self:apply_update_to_row(row, {
                        status = "loaded",
                        message = "Updated",
                    })
                    self:update_row(row.name)
                end
            else
                vim.notify(string.format("✗ Failed to update all packs: %s", tostring(err)), vim.log.levels.ERROR)
            end
        end)
    end)
end

-- ============================================================================
-- Row Updates & Batching
-- ============================================================================

function Dashboard:apply_update_to_row(row, data)
    local elems = row.elements
    local changed = false

    if data.status then
        if elems.status and elems.status:update(data.status) then
            changed = true
        end
        if elems.status_two and elems.status_two:update(data.status) then
            changed = true
        end
    end

    if data.message and data.message ~= "" then
        if elems.message and elems.message:update(data.message) then
            changed = true
        end
    elseif data.status then
        local status_messages = {
            ready = "Loaded",
            loaded = "Loaded",
            installed = "Installed",
            installing = "Installing…",
            configuring = "Configuring…",
            failed = "Failed",
            disabled = "Disabled",
            lazy = "Lazy",
            updating = "Updating…",
            deleted = "Deleted",
        }
        local msg = status_messages[data.status]
        if msg and elems.message and elems.message:update(msg) then
            changed = true
        end
    end

    if data.install_duration and elems.install_duration then
        if elems.install_duration:update(data.install_duration) then
            changed = true
        end
    end

    if data.config_duration and elems.config_duration then
        if elems.config_duration:update(data.config_duration) then
            changed = true
        end
    end

    if data.stage then
        if elems.stage and elems.stage:update(data.stage) then
            changed = true
        end
        if elems.stage_two and elems.stage_two:update(data.stage) then
            changed = true
        end
    end

    return changed
end

function Dashboard:update_row(name)
    local row = self:find(name)
    if not row then
        return
    end

    self:schedule_row_update(name, {})
end

function Dashboard:update_row_immediate(name)
    local now = vim.loop.now()
    local min_interval = Dashboard.UPDATE_CONFIG.min_render_interval_ms

    local last_render = self.last_render_times.rows[name] or 0
    local time_since_last = now - last_render

    if time_since_last < min_interval then
        return
    end

    local row = self.rows_by_name[name]
    if not row then
        return
    end

    if not row.mark_id then
        return
    end

    local pos = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, self.ns_rows, row.mark_id, {})
    if not pos then
        return
    end

    local line = pos[1]

    vim.api.nvim_buf_clear_namespace(self.content_buf, self.ns_content, line, line + 1)
    self:render_row_at(line, row)

    self.last_render_times.rows[name] = now
end

function Dashboard:schedule_row_update(row_name, update_data)
    self.pending_row_updates[row_name] = update_data

    if not self.debounce_timers.batch then
        self.debounce_timers.batch = vim.fn.timer_start(Dashboard.UPDATE_CONFIG.batch_debounce_ms, function()
            self:process_update_batch()
            self.debounce_timers.batch = nil
        end)
    end
end

function Dashboard:process_update_batch()
    if not self.is_valid then
        self.pending_row_updates = {}
        return
    end

    if self.update_batch.processing then
        return
    end

    local updates_to_process = {}
    for name, data in pairs(self.pending_row_updates) do
        table.insert(updates_to_process, {
            name = name,
            data = data,
        })
    end
    self.pending_row_updates = {}

    if #updates_to_process == 0 then
        return
    end

    self.update_batch.processing = true

    local chunk_size = Dashboard.UPDATE_CONFIG.max_batch_size
    local index = 1

    local function process_chunk()
        if index > #updates_to_process then
            self.update_batch.processing = false
            self:schedule_footer_update()
            return
        end

        local end_index = math.min(index + chunk_size - 1, #updates_to_process)

        vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })

        for i = index, end_index do
            local update = updates_to_process[i]
            local row = self:find(update.name)

            if row then
                self:apply_update_to_row(row, update.data)
                self:update_row_immediate(update.name)
            end
        end

        vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })

        index = end_index + 1

        vim.defer_fn(process_chunk, Dashboard.UPDATE_CONFIG.batch_interval_ms)
    end

    vim.schedule(process_chunk)
end

function Dashboard:batch_update_lines(row_updates)
    if not self:is_valid() then
        return
    end
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })

    for _, row in ipairs(row_updates) do
        self:update_row(row.name)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:schedule_footer_update()
end

function Dashboard:cleanup_smooth_updates()
    for timer_type, timer_id in pairs(self.debounce_timers) do
        if timer_id then
            vim.fn.timer_stop(timer_id)
        end
    end

    self.pending_row_updates = {}
    self.update_batch = { queue = {}, processing = false }
    self.debounce_timers = {}
end

-- ============================================================================
-- Pack Comparison Display
-- ============================================================================

function Dashboard:display_pack_comparison(pack_name)
    local manager = self.container:resolve("manager")
    local utils = self.container:resolve("utils")

    local width = vim.o.columns
    local height = vim.o.lines
    local win_height = math.floor(height * 0.80)
    local win_width = math.floor(width * 0.60)
    local inner_width = win_width - 4

    local pack = manager.packs[pack_name]
    if not pack then
        utils.safe_notify(string.format("[Sage] Pack not found: %s", pack_name), vim.log.levels.ERROR)
        return
    end

    local ok_native, n_pack = pcall(function()
        return pack:get_native()
    end)
    if not ok_native then
        n_pack = nil
    end

    local function get_field(root, path)
        if not root or not path then
            return nil
        end
        local keys = split_by_period(path)
        return getTableValue(root, keys)
    end

    local function value_to_string(v)
        local t = type(v)
        if v == nil then
            return "nil"
        elseif t == "string" then
            return v
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        elseif t == "table" then
            return vim.inspect(v)
        else
            return "<" .. t .. ">"
        end
    end

    local function get_pack_buf_win()
        local row = math.floor((height - win_height) / 2)
        local col = math.floor((width - win_width) / 2)

        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            width = win_width,
            height = win_height,
            row = row,
            col = col,
            style = "minimal",
            border = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
            zindex = 100,
        })

        return buf, win
    end

    local function add_side_by_side_section(lines, title, fields)
        table.insert(lines, "")
        if title and title ~= "" then
            table.insert(lines, title)
        end

        local label_col = 14
        local value_col = math.floor((inner_width - label_col - 5) / 2)

        local header = string.format(
            "%-" .. label_col .. "s %-" .. value_col .. "s | %-" .. value_col .. "s",
            "FIELD",
            "SAGE",
            "vim.pack"
        )
        table.insert(lines, header)
        table.insert(lines, string.rep("─", inner_width))

        for _, f in ipairs(fields) do
            local s_val = f.sage and get_field(pack, f.sage) or nil
            local n_val = f.native and get_field(n_pack, f.native) or nil

            local s_str = value_to_string(s_val)
            local n_str = value_to_string(n_val)

            if #s_str > value_col then
                s_str = s_str:sub(1, value_col - 1) .. "…"
            end
            if #n_str > value_col then
                n_str = n_str:sub(1, value_col - 1) .. "…"
            end

            local row = string.format(
                "%-" .. label_col .. "s %-" .. value_col .. "s | %-" .. value_col .. "s",
                f.label or "",
                s_str,
                n_str
            )
            table.insert(lines, row)
        end
    end

    local function get_diff_lines(fields)
        local diff = {}
        for _, f in ipairs(fields) do
            if f.sage and f.native and n_pack ~= nil then
                local s_val = get_field(pack, f.sage)
                local n_val = get_field(n_pack, f.native)
                if s_val ~= n_val then
                    table.insert(diff, {
                        label = f.label,
                        sage = value_to_string(s_val),
                        native = value_to_string(n_val),
                    })
                end
            end
        end
        if #diff == 0 then
            return { "", "No differences on the tracked fields 🎉" }
        end

        local lines = { "", "Diff (only mismatches):" }
        table.insert(lines, string.rep("─", inner_width))
        local label_col = 14
        local value_col = math.floor((inner_width - label_col - 5) / 2)

        for _, d in ipairs(diff) do
            local s_str = d.sage
            local n_str = d.native
            if #s_str > value_col then
                s_str = s_str:sub(1, value_col - 1) .. "…"
            end
            if #n_str > value_col then
                n_str = n_str:sub(1, value_col - 1) .. "…"
            end

            local row = string.format(
                "%-" .. label_col .. "s %-" .. value_col .. "s | %-" .. value_col .. "s",
                d.label or "",
                s_str,
                n_str
            )
            table.insert(lines, row)
        end

        return lines
    end

    local function get_pack_content()
        local lines = {}

        local header_text = string.format("Pack: %s", pack_name)
        local header_padding = math.floor((inner_width - #header_text - 2) / 2)

        table.insert(lines, "╓" .. string.rep("═", inner_width - 2) .. "╖")
        table.insert(
            lines,
            "║ "
                .. string.rep(" ", header_padding)
                .. header_text
                .. string.rep(" ", inner_width - header_padding - #header_text - 3)
                .. "║"
        )
        table.insert(lines, "╚" .. string.rep("═", inner_width - 2) .. "╝")
        table.insert(lines, "")
        table.insert(lines, "SAGE_PACK (sage.packs[name])  📦  VIM_PACK (vim.pack.get)")
        table.insert(lines, "")

        local core_fields = {
            { label = "name", sage = "name", native = "spec.name" },
            { label = "enabled", sage = "specs.normalize.data.enabled", native = nil },
            { label = "active", sage = "specs.vim.active", native = "active" },
            { label = "installed", sage = "installed", native = nil },
            { label = "loaded", sage = "loaded", native = nil },
            { label = "status", sage = "status", native = nil },
            { label = "path", sage = "specs.vim.path", native = "path" },
            { label = "rev", sage = "specs.vim.rev", native = "rev" },
            { label = "tags", sage = "specs.vim.tags", native = "tags" },
            { label = "branches", sage = "specs.vim.branches", native = "branches" },
        }

        add_side_by_side_section(lines, "Core", core_fields)

        local spec_fields = {
            { label = "src", sage = "specs.normalize.src", native = "spec.src" },
            { label = "version", sage = "specs.normalize.version", native = "spec.version" },
            { label = "stage", sage = "specs.normalize.data.stage", native = "spec.data.stage" },
            { label = "config", sage = "specs.normalize.data.config", native = "spec.data.config" },
            { label = "priority", sage = "specs.normalize.data.priority", native = "spec.data.priority" },
            { label = "depends", sage = "specs.normalize.data.depends", native = "spec.data.depends" },
            { label = "init", sage = "specs.normalize.data.on.init", native = "spec.data.on.init" },
            { label = "post", sage = "specs.normalize.data.on.post", native = "spec.data.on.post" },
            { label = "before", sage = "specs.normalize.data.on.before", native = "spec.data.on.before" },
            { label = "after", sage = "specs.normalize.data.on.after", native = "spec.data.on.after" },
        }

        add_side_by_side_section(lines, "Lazy", spec_fields)

        local lazy_fields = {
            { label = "Events ~Lazy~", sage = "specs.normalize.data.on.events", native = "spec.data.on.events" },
            { label = "Cmds ~Lazy~", sage = "specs.normalize.data.on.cmds", native = "spec.data.on.cmds" },
            { label = "Fts ~Lazy~", sage = "specs.normalize.data.on.fts", native = "spec.data.on.fts" },
            { label = "Keys ~Lazy~", sage = "specs.normalize.data.on.keys", native = "spec.data.on.keys" },
        }

        add_side_by_side_section(lines, "", lazy_fields)

        local all_for_diff = {}
        for _, f in ipairs(core_fields) do
            table.insert(all_for_diff, f)
        end
        for _, f in ipairs(spec_fields) do
            table.insert(all_for_diff, f)
        end
        for _, f in ipairs(lazy_fields) do
            table.insert(all_for_diff, f)
        end
        local diff_lines = get_diff_lines(all_for_diff)
        for _, l in ipairs(diff_lines) do
            table.insert(lines, l)
        end

        table.insert(lines, "")
        local close_text = "Press 'q' to close"
        local close_padding = math.floor((inner_width - #close_text) / 2)
        table.insert(lines, string.rep("─", close_padding + 3) .. close_text .. string.rep("─", close_padding + 4))

        local padded = {}
        for _, l in ipairs(lines) do
            local content_padding = math.max(0, math.floor((inner_width - vim.fn.strdisplaywidth(l)) / 2))
            table.insert(padded, string.rep(" ", content_padding) .. l)
        end

        return padded
    end

    local buf, win = get_pack_buf_win()
    local lines = get_pack_content()

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "sage", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end, { buffer = buf, noremap = true, silent = true, desc = "Close comparison window" })

    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end, { buffer = buf, noremap = true, silent = true, desc = "Close comparison window" })
end

-- ============================================================================
-- Initialization
-- ============================================================================

-- function Dashboard:init(container, elements, icons, opts)
--     self.opts = opts or {}
--     self.tabs = {
--         { id = "all", label = "All" },
--         { id = "loaded", label = "Loaded" },
--         { id = "not_loaded", label = "Not Loaded" },
--         { id = "lazy", label = "Lazy" },
--         { id = "now", label = "Now" },
--         { id = "later", label = "Later" },
--         { id = "failed", label = "Failed" },
--         { id = "disabled", label = "Disabled" },
--     }
--     self.active_tab_index = 1
--     self.rows = {}
--     self.rows_by_name = {}
--     self.header_buf = nil
--     self.header_win = nil
--     self.content_buf = nil
--     self.content_win = nil
--     self.footer_buf = nil
--     self.footer_win = nil
--     self.autocmd_ids = {}
--
--     self:init_selection()
--     self:init_smooth_updates()
--
--     self.ns_rows = vim.api.nvim_create_namespace("SageDashboardRows")
--     self.ns_content = vim.api.nvim_create_namespace("SageDashboardContent")
--     self.ns_buttons = vim.api.nvim_create_namespace("SageDashboardButtons")
--     self.ns_ui = vim.api.nvim_create_namespace("SageUI")
--     self.ns_footer = vim.api.nvim_create_namespace("SageDashboardFooter")
--     self.ns_background = vim.api.nvim_create_namespace("SageBackground")
--     self.ns_text = vim.api.nvim_create_namespace("SageText")
--     self.ns_overlay = vim.api.nvim_create_namespace("SageOverlay")
--     self.ns_status = vim.api.nvim_create_namespace("SageStatus")
--     self.ns_selection = vim.api.nvim_create_namespace("SageDashboardSelection")
--
--     self.last_stats = nil
--     self.header_height = 4
--     self.footer_height = 6
--     self.is_valid = false
--     self.should_track = true
--     self.render_timer = nil
--     self._footer_timer = nil
--     self.autocmd_ids = {}
--
--     self.config = {
--         lock_windows = opts.lock_windows ~= false,
--         auto_focus = opts.auto_focus ~= false,
--         debounce_ms = opts.debounce_ms or 200,
--         footer_debounce_ms = 150,
--         row_debounce_ms = 100,
--         batch_debounce_ms = 200,
--         batch_interval_ms = 50,
--         max_batch_size = 10,
--         min_render_interval_ms = 16,
--     }
--
--     self.container = container
--     self.elements = elements
--     self.icons = icons
--
--     self.bus = self.container:resolve("bus")
--     self.manager = self.container:resolve("manager")
--     self.utils = self.container:resolve("utils")
--     self.logger = self.container:resolve("logger")
--
--     self:setup_footer_debounced()
--
--     -- Highlights
--     vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
--     vim.api.nvim_set_hl(0, "SageHeaderBorder", { link = "FloatBorder", default = true })
--     vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
--     vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })
--     vim.api.nvim_set_hl(0, "SageRowNormal", { link = "Normal", default = true })
--     vim.api.nvim_set_hl(0, "SageRowAlt", { link = "CursorLine", default = true })
--     vim.api.nvim_set_hl(0, "SageRowHover", { link = "Visual", default = true })
--     vim.api.nvim_set_hl(0, "SageRowExpanded", { link = "PmenuSel", default = true })
--     vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
--     vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
--     vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
--     vim.api.nvim_set_hl(0, "SageRowWaiting", { link = "DiagnosticWarn", default = true })
--     vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })
--     vim.api.nvim_set_hl(0, "SageStatusCreated", { fg = "#7aa2f7", italic = true })
--     vim.api.nvim_set_hl(0, "SageStatusLoaded", { fg = "#9ece6a", bold = true })
--     vim.api.nvim_set_hl(0, "SageStatusFailed", { fg = "#f7768e", underline = true })
--     vim.api.nvim_set_hl(0, "SageLazyBracket", { fg = "#bb9af7" })
--     vim.api.nvim_set_hl(0, "SageLazyIcon", { fg = "#bb9af7" })
--     vim.api.nvim_set_hl(0, "SageLazyLabel", { fg = "#bb9af7" })
--     vim.api.nvim_set_hl(0, "SageLazyValue", { fg = "#bb9af7" })
--     vim.api.nvim_set_hl(0, "SageLink", { fg = "#6495ed", underline = true })
--     vim.api.nvim_set_hl(0, "SageMessage", { link = "DiagnosticHint", default = true })
--     vim.api.nvim_set_hl(0, "SageTaskProgress", { link = "DiagnosticInfo", default = true })
--     vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })
--     vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })
--     vim.api.nvim_set_hl(0, "SageDependency", { link = "Underlined", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerCommand", { link = "Function", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerFiletype", { link = "Type", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerEvent", { link = "Keyword", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerKeymap", { link = "Special", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerAfter", { link = "String", default = true })
--     vim.api.nvim_set_hl(0, "SageTriggerBefore", { link = "String", default = true })
--     vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
--     vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
--     vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })
--     vim.api.nvim_set_hl(0, "SagePackOnlyUs", { fg = "#00ff00" })
--
--     vim.api.nvim_create_autocmd("ColorScheme", {
--         pattern = "*",
--         callback = function()
--             vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
--             vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
--             vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })
--             vim.api.nvim_set_hl(0, "SageTaskProgress", { link = "DiagnosticInfo", default = true })
--             vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })
--             vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })
--             vim.api.nvim_set_hl(0, "SageMessage", { link = "DiagnosticHint", default = true })
--             vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
--             vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
--             vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
--             vim.api.nvim_set_hl(0, "SageRowWaiting", { link = "DiagnosticWarn", default = true })
--             vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })
--             vim.api.nvim_set_hl(0, "SageStatusCreated", { fg = "#7aa2f7", italic = true })
--             vim.api.nvim_set_hl(0, "SageStatusLoaded", { fg = "#9ece6a", bold = true })
--             vim.api.nvim_set_hl(0, "SageStatusFailed", { fg = "#f7768e", underline = true })
--             vim.api.nvim_set_hl(0, "SageLazyBracket", { fg = "#bb9af7" })
--             vim.api.nvim_set_hl(0, "SageLazyIcon", { fg = "#bb9af7" })
--             vim.api.nvim_set_hl(0, "SageLazyLabel", { fg = "#bb9af7" })
--             vim.api.nvim_set_hl(0, "SageLazyValue", { fg = "#bb9af7" })
--             vim.api.nvim_set_hl(0, "SageLink", { fg = "#6495ed", underline = true })
--             vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
--             vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
--             vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })
--         end,
--         desc = "Reapply Sage dashboard highlights on colorscheme change",
--     })
--
--     -- User commands
--     vim.api.nvim_create_user_command("SageOpen", function()
--         local manager = self.manager
--         local dashboard = manager.container:resolve("dashboard")
--         dashboard:open()
--     end, { desc = "Open Sage dashboard" })
--
--     vim.api.nvim_create_user_command("SageClose", function()
--         local manager = self.manager
--         local dashboard = manager.container:resolve("dashboard")
--         dashboard:close()
--     end, { desc = "Close Sage dashboard" })
--
--     vim.api.nvim_create_user_command("SageToggle", function()
--         local dashboard = self.manager.container:resolve("dashboard")
--         if dashboard.is_open then
--             dashboard:close()
--         else
--             dashboard:open()
--         end
--     end, { desc = "Toggle Sage dashboard" })
--
--     vim.api.nvim_create_user_command("SageReload", function()
--         local Loader = self.manager.container:resolve("loader")
--         Loader:close_all()
--         Dashboard:close()
--         vim.notify("Sage: loaders and dashboard cleaned up.", vim.log.levels.INFO)
--     end, { desc = "Reload Sage loaders and dashboard" })
--
--     vim.api.nvim_create_user_command("SageCleanup", function()
--         vim.api.nvim_exec_autocmds("VimLeavePre", {})
--     end, { desc = "Trigger Sage cleanup" })
--
--     vim.api.nvim_create_user_command("SageDebugLazy", function(c_opts)
--         local pack_name = c_opts.args
--         local row = Dashboard:find(pack_name)
--
--         if not row then
--             vim.notify("Pack not found: " .. pack_name, vim.log.levels.ERROR)
--             return
--         end
--
--         local info = {
--             stage = row.stage.value,
--             has_lazy = row.lazy ~= nil,
--             lazy_info = row.lazy and row.lazy:get_info() or "no lazy element",
--             trigger_data = row.lazy and row.lazy.trigger_data or "none",
--         }
--         print(vim.inspect(info))
--     end, { nargs = 1, desc = "Debug lazy element for a pack" })
-- end
--
function Dashboard:init_smooth_updates()
    self.pending_row_updates = {}
    self.pending_footer_update = false

    self.debounce_timers = {
        footer = nil,
        batch = nil,
    }

    self.last_render_times = {
        footer = 0,
        rows = {},
    }

    self.update_batch = {
        queue = {},
        processing = false,
    }

    self.frame_limiter = {
        last_frame = 0,
        pending_renders = {},
    }
end

function Dashboard.new()
    -- Redirect to singleton
    return Dashboard.get_instance()
end

return Dashboard
