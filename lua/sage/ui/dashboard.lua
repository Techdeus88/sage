local width_percentage = 0.8
local height_percentage = 0.8

local function center_text(text, width)
    local text_width = vim.fn.strdisplaywidth(text) -- Use display width for proper unicode handling
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
Dashboard.tabs = {
    { id = "all", label = "All" },
    { id = "loaded", label = "Loaded" },
    { id = "not_loaded", label = "Not Loaded" },
    { id = "lazy", label = "Lazy" },
    { id = "now", label = "Now" },
    { id = "later", label = "Later" },
    { id = "failed", label = "Failed" },
    { id = "disabled", label = "Disabled" },
}
Dashboard.active_tab_index = 1
Dashboard.rows = {}
Dashboard.header_buf = nil
Dashboard.header_win = nil
Dashboard.content_buf = nil
Dashboard.content_win = nil
Dashboard.footer_buf = nil
Dashboard.footer_win = nil
Dashboard.autocmd_ids = {}
Dashboard.ns_rows = vim.api.nvim_create_namespace("SageDashboardRows")
Dashboard.ns_buttons = vim.api.nvim_create_namespace("SageDashboardButtons")
Dashboard.ns_ui = vim.api.nvim_create_namespace("SageUI")
Dashboard.ns_footer = vim.api.nvim_create_namespace("SageDashboardFooter")
Dashboard.rows_by_name = {}
Dashboard.last_stats = nil
Dashboard.header_height = 4
Dashboard.footer_height = 6
Dashboard.queue = { data = {}, first = 1, last = 0 }

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

    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("filetype", "sage", { buf = buf })
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
        vim.api.nvim_set_option_value("indentexpr", "", { buf = buf })
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
        border = { "╭", "─", "╮", "│", "", "", "", "│" },
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
        border = { "├", "─", "┤", "│", "╰", "─", "╯", "│" },
    })

    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.header_win })
    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.content_win })
    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.footer_win })

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

    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            local winleave_id = vim.api.nvim_create_autocmd("WinLeave", {
                callback = function()
                    local current = vim.api.nvim_get_current_win()
                    local is_dashboard = current == self.header_win
                        or current == self.content_win
                        or current == self.footer_win

                    if not is_dashboard and self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                        vim.schedule(function()
                            pcall(vim.api.nvim_set_current_win, self.content_win)
                        end)
                    end
                end,
            })
            table.insert(self.autocmd_ids, winleave_id)
        end
    end
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

local function get_value(name, key, level)
    local specs = require("sage.config").specs
    local pack
    local n_pack

    for _, spec in ipairs(specs) do
        if spec.name == name then
            pack = spec
            n_pack = vim.pack.get({name})[1]
        end
    end

    if level == 1 then
        local pack_value = pack[key]
        local n_pack_value = n_pack[key]
    end

    return pack_value, n_pack_value
end

local function format_table_value(key, val, val_type, indent, max_length)
    indent = string.rep(" ", indent or 1)

    local tbl_key = tostring(key):upper()
    local prefix = indent .. tbl_key .. " -> "
    local f_value = nil

    if val_type == "string" then
        f_value = string.format("%s [%s]", prefix, val)
    end
    if val_type == "number" then
        f_value = string.format("%s [%s]", prefix, string.format("%.0f", val))
    end
    if val_type == "boolean" then
        if val then
            f_value = string.format("%s [%s]", prefix, "true")
        else
            f_value = string.format("%s [%s]", prefix, "false")
        end
    end
    if val_type == "function" then
        f_value = string.format("%s [%s]", prefix, "<function>")
    end
    if val_type == "userdata" then
        f_value = string.format("%s [%s]", prefix, "<userdata>")
    end

    return f_value
end

local function format_table(name, lines, tbl_order, indent, max_length, num_tables)
    lines = lines or {}
    max_length = max_length or 10
    indent = indent or 0

    if not tbl or indent > max_length then
        return lines
    end

    for _, key in tbl_order.order do
        local p_value, n_value = get_value(tbl_order.name, key, tbl_order.level)
        local f_value = format_table_value(p_value)
        table.insert(lines, f_value)
    end
    
    return lines
end

function Dashboard:display_pack_comparison(pack_name)
    local manager = self.container:resolve("manager")
    local utils = self.container:resolve("utils")
    local pack = manager.packs[pack_name]

    if not pack then
        utils.safe_notify(string.format("[%s] Pack not found", pack_name), vim.log.levels.ERROR)
        return
    end

    local n_pack = pack:get_native()

    if not n_pack then
        utils.safe_notify(string.format("[%s] Failed to get native pack", pack_name), vim.log.levels.ERROR)
        return
    end

    local width = vim.o.columns
    local height = vim.o.lines
    local win_height = math.floor(height * 0.80)
    local win_width = math.floor(width * 0.60)
    local row = math.floor((height - win_height) / 2)
    local col = math.floor((width - win_width) / 2)

    -- Calculate inner width (accounting for borders and padding)
    local inner_width = win_width - 4 -- 2 for padding, 2 for borders

    local lines = {}

    -- Header box
    local header_text = string.format("Pack: %s", pack_name)
    local header_padding = math.floor((inner_width - #header_text - 2) / 2) -- -2 for border chars

    table.insert(lines, "╔" .. string.rep("═", inner_width - 2) .. "╗" ..
        "║ "
            .. string.rep(" ", header_padding)
            .. header_text
            .. string.rep(" ", inner_width - header_padding - #header_text - 3)
            .. "║"

    )
    table.insert(lines, "╚" .. string.rep("═", inner_width - 2) .. "╝")
    table.insert(lines, "")

    -- Content
    local content_lines = { "SAGE_PACK (sage.packs.name) 📦 VIM_PACK (vim.pack.get)" }
    local top_spec = { 
        name = pack_name, 
        order = {"name", "src", "active", "installed", "loaded", "version", "status"}, 
        level = 1 
    }
    content_lines = vim.list_extend(content_lines, format_table(pack_name, content_lines, top_spec, 0, 8, 1))
    for _, content_text in ipairs(content_lines) do
        local content_padding = math.floor((inner_width - vim.fn.strdisplaywidth(content_text)) / 2)
        table.insert(lines, string.rep(" ", content_padding) .. content_text)
    end

    table.insert(lines, string.rep("─", inner_width))
    table.insert(lines, "")

    -- Close instruction box
    local close_text = "Press 'q' to close this buffer"
    local close_padding = math.floor((inner_width - #close_text) / 2)
    table.insert(lines, "┌" .. string.rep("─", inner_width - 2) .. "┐")
    table.insert(
        lines,
        "│"
            .. string.rep(" ", close_padding)
            .. close_text
            .. string.rep(" ", inner_width - close_padding - #close_text - 2)
            .. "│"
    )
    table.insert(lines, "└" .. string.rep("─", inner_width - 2) .. "┘")

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        style = "minimal",
        border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
        zindex = 100,
    })

    -- Add padding to each line
    local padded_lines = {}
    for _, line in ipairs(lines) do
        table.insert(padded_lines, "  " .. line) -- Add consistent left padding
    end
    o

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "sage", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

    -- Add close keymaps
    vim.keymap.set("n", "q", function()
        vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, noremap = true, silent = true, desc = "Close comparison window" })

    vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, noremap = true, silent = true, desc = "Close comparison window" })
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

    vim.api.nvim_buf_clear_namespace(self.header_buf, Dashboard.ns_ui, 0, -1)

    local col = 0
    local tab_text = table.concat(tab_line, "")
    local padding = math.floor((win_width - #tab_text) / 2)

    for i, tab in ipairs(self.tabs) do
        local text = (i == self.active_tab_index) and string.format(" [%s] ", tab.label)
            or string.format("  %s  ", tab.label)

        local hl = (i == self.active_tab_index) and "SageTabActive" or "SageTab"

        -- Fixed: Properly use nvim_buf_set_extmark with hl_group
        vim.api.nvim_buf_set_extmark(self.header_buf, Dashboard.ns_ui, 1, padding + col, {
            end_col = padding + col + #text,
            hl_group = hl,
        })

        col = col + #text
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.header_buf })
end

-- ============================================================================
-- Tab Filtering
-- ============================================================================
function Dashboard:refresh_for_tab()
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end
    local Manager = self.manager

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    local filter = self.tabs[self.active_tab_index].id

    local function matches(row)
        if filter == "all" then
            return true
        end
        if filter == "loaded" or filter == "configured" or filter == "ready" then
            return row.status.value == "loaded" or row.status.value == "ready"
        end
        if filter == "not_loaded" then
            local pack = self.manager.packs[row.name]

            return pack.loaded == false
                or row.status.value == "installing"
                or row.status.value == "installed"
                or row.status.value == "created"
        end
        if filter == "lazy" then
            return row.stage.value == "lazy"
        end
        if filter == "failed" then
            return row.status.value == "failed"
        end
        if filter == "now" then
            return row.stage.value == "now"
        end
        if filter == "later" then
            return row.stage.value == "later"
        end
        if filter == "disabled" then
            return row.stage.value == "disabled"
        end
        return true
    end

    local line = 0
    local has_matches = false

    for _, row in ipairs(self.rows) do
        if matches(row) then
            has_matches = true
            self:_ensure_lines(line)

            row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, {
                id = row.mark_id,
                right_gravity = true,
            })

            self:update_line(row)
            line = line + 1

            if row.expanded and row.details_count then
                self:expand_details(row)
                line = line + row.details_count
            end
        end
    end

    -- Show message if no packs match the filter
    if not has_matches then
        local no_packs_msg = string.format("No packs found for filter: %s", filter)
        vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, { "", "  " .. no_packs_msg, "" })
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:render_header()
    self:render_footer()
end
-- ============================================================================
-- Footer Rendering
-- ============================================================================
function Dashboard:get_stats()
    local stats = {
        total = 0,
        loaded = 0,
        not_loaded = 0,
        lazy = 0,
        failed = 0,
        disabled = 0,
    }

    for _, row in ipairs(self.rows) do
        stats.total = stats.total + 1
        local status = row.status.value
        local stage = row.stage.value

        if status == "failed" then
            stats.failed = stats.failed + 1
        elseif status == "loaded" or status == "configured" or status == "ready" then
            stats.loaded = stats.loaded + 1
        elseif status == "lazy" or stage == "lazy" then
            stats.lazy = stats.lazy + 1
        elseif status == "disabled" or stage == "disabled" then
            stats.disabled = stats.disabled + 1
            stats.not_loaded = stats.not_loaded + 1
        elseif status == "installing" or status == "installed" or status == "created" then
            stats.not_loaded = stats.not_loaded + 1
        end
    end

    return stats
end

function Dashboard:setup_debounced_footer()
    self._footer_timer = nil
    self._footer_pending = false
end

function Dashboard:update_footer_debounced()
    if self._footer_timer then
        vim.fn.timer_stop(self._footer_timer)
    end

    local delay = (self.config and self.config.debounce_ms) or 50

    self._footer_timer = vim.fn.timer_start(delay, function()
        if self._footer_pending then
            self:update_footer_if_changed()
            self._footer_pending = false
        end
    end)

    self._footer_pending = true
end

function Dashboard:render_footer()
    if not (self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf)) then
        return
    end

    local win_width = vim.api.nvim_win_get_width(self.footer_win)
    local stats = self:get_stats()

    local ok, sage_metrics = pcall(require, "sage.metrics")
    local total_duration = 0
    if ok and sage_metrics and type(sage_metrics.get_event) == "function" then
        total_duration = sage_metrics:get_event("uienter") or 0
    end

    local progress_pct = stats.total > 0 and ((stats.loaded + stats.lazy + stats.disabled) / stats.total * 100) or 0
    local bar_width = math.floor(win_width * 0.6)
    local filled = math.floor(bar_width * (progress_pct / 100))
    local empty = bar_width - filled
    local progress_bar = string.rep("█", filled) .. string.rep("░", empty)

    local footer_lines = {
        "",
        center_text(
            string.format(
                "[%d/%d] %s %.0f%%",
                (stats.loaded + stats.lazy + stats.disabled),
                stats.total,
                progress_bar,
                progress_pct
            ),
            win_width
        ),
        "",
        center_text(
            string.format(
                "Loaded: %d  • Lazy: %d  • Failed: %d  • Disabled: %d  • Total Duration: %sms",
                stats.loaded,
                stats.lazy,
                stats.failed,
                stats.disabled,
                total_duration
            ),
            win_width
        ),
        center_text(
            "Press 'r' to refresh  •  'q' to quit  •  '<CR>' to toggle details  •  '<Tab>' to switch tabs",
            win_width
        ),
        "",
    }

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.footer_buf })
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, footer_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.footer_buf })

    vim.api.nvim_buf_clear_namespace(self.footer_buf, Dashboard.ns_footer, 0, -1)
    vim.api.nvim_buf_add_highlight(self.footer_buf, Dashboard.ns_footer, "SageFooterProgress", 1, 0, -1)
    vim.api.nvim_buf_add_highlight(self.footer_buf, Dashboard.ns_footer, "SageFooterStats", 3, 0, -1)
    vim.api.nvim_buf_add_highlight(self.footer_buf, Dashboard.ns_footer, "SageFooterHelp", 4, 0, -1)
end

function Dashboard:update_footer_if_changed()
    local stats = self:get_stats()
    local stats_str = vim.inspect(stats)

    if self.last_stats ~= stats_str then
        self.last_stats = stats_str
        vim.api.nvim_buf_set_option(self.footer_buf, "modifiable", true)
        self:render_footer()
    end
end

-- ============================================================================
-- Content Buffer Management
-- ============================================================================
function Dashboard:bufline(row)
    if not row.mark_id then
        return nil
    end
    local pos = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, Dashboard.ns_rows, row.mark_id, {})
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

        vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
        vim.api.nvim_buf_set_lines(self.content_buf, lc, lc, false, blanks)
        vim.api.nvim_buf_set_option(self.content_buf, "modifiable", false)
    end
end

-- ============================================================================
-- Pack Management
-- ============================================================================
function Dashboard:add_pack(data)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end
    local icons = self.icons
    local elem = self.elements
    local utils = self.utils

    local Pack = data.pack
    local n_spec = Pack.specs.normalize
    local name = data.name
    local stage = data.stage
    local status = data.status
    local message = data.message

    if self.rows_by_name[name] then
        local existing_row = self.rows_by_name[name]
        existing_row.status:update(status)
        existing_row.message:update(message)
        self:update_line(existing_row)
        return
    end

    local on = n_spec.data.on or {}

    -- Debug: Check if 'on' has any data
    if not next(on) then
        vim.notify(string.format("[DEBUG] Pack %s has no lazy trigger data", name), vim.log.levels.WARN)
    end

    local trigger_data = (n_spec.data.on and next(n_spec.data.on)) and n_spec.data.on or nil

    local row = {
        name = name,
        status_two = elem.StatusElement.new("status", status, "icon_text"),
        status = elem.StatusElement.new("status", status, "icon"),
        stage = elem.StageElement.new("stage", stage, "icon", {
            stage = { now = icons.now, later = icons.later, lazy = icons.lazy, disabled = icons.disabled },
        }),
        stage_two = elem.StageElement.new("stage_two", stage, "icon_text", {
            stage = { now = icons.now, later = icons.later, lazy = icons.lazy, disabled = icons.disabled },
        }),
        -- task_progress = elem.TaskProgressElement.new("task_progress", Pack:get_task_progress()),
        install_duration = elem.DurationElement.new("install_duration", Pack.times.install_duration),
        config_duration = elem.DurationElement.new("config_duration", Pack.times.config_duration),
        message = elem.TextElement.new("message", message),
        deps = elem.ListElement.new("deps", utils.get_dep_names(n_spec.data.depends or {})),
        lazy = elem.LazyElement.new("lazy", trigger_data),
        error = elem.TextElement.new("error", ""),
    }

    self.rows_by_name[name] = row
    table.insert(self.rows, row)

    local index = #self.rows
    local line = index - 1

    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
    self:_ensure_lines(line)

    row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, {
        right_gravity = true,
    })

    self:update_line(row)
end

-- ============================================================================
-- Line Updating
-- ============================================================================
function Dashboard:update_line(row)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    local ns = Dashboard.ns_buttons
    local l = self:bufline(row)
    if not l then
        return
    end
    local icons = self.icons

    self:_ensure_lines(l)

    local install = row.install_duration:render() or "0"
    local config = row.config_duration:render() or "0"
    local install_button = string.format("[%s %s]", icons.install or "󰚰", install)
    local config_button = string.format("[%s %s]", icons.config or "󰒓", config)

    local deps_buttons = row.deps:render_buttons()
    local message_text = row.message:render()
    local deps_text = (#deps_buttons > 0) and (table.concat(deps_buttons, " ")) or ""
    local error_text = row.error ~= nil and row.error

    -- In dashboard.lua, update_line function around line 520:
    local lazy_text = ""
    local info = ""
    local lazy_trigger_type = ""

    -- Only render lazy triggers if pack is in lazy stage AND has lazy data
    if row.stage.value == "lazy" and row.lazy then
        local lazy_info = row.lazy:get_info()

        -- Debug: Check what we're trying to render
        if lazy_info.type == "none" or lazy_info.count == 0 then
            vim.notify(
                string.format("[DEBUG] Pack %s is lazy but has no trigger data: %s", row.name, vim.inspect(lazy_info)),
                vim.log.levels.WARN
            )
        else
            lazy_text = row.lazy:render()
            info = lazy_info
            lazy_trigger_type = info.type
        end
    end

    local task_text = ""
    if row.task_progress then
        task_text = row.task_progress:render()
    end

    local line_text = string.format(
        "%s %s %-5s %s %s %s %s %s %s",
        row.status:render(),
        row.name,
        row.stage:render(),
        task_text,
        install_button,
        config_button,
        message_text,
        deps_text,
        lazy_text,
        error_text
    )

    local padded = add_padding_to_line(line_text, 1)

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    local current_line = vim.api.nvim_buf_get_lines(self.content_buf, l, l + 1, false)[1] or ""
    vim.api.nvim_buf_set_text(self.content_buf, l, 0, l, #current_line, { padded })
    vim.api.nvim_buf_clear_namespace(self.content_buf, ns, l, l + 1)

    local function highlight_button(button_text, hl_group, priority)
        priority = priority or 100
        local s = padded:find(button_text, 1, true)
        if s then
            vim.api.nvim_buf_set_extmark(self.content_buf, ns, l, s - 1, {
                end_col = s - 1 + #button_text,
                hl_group = hl_group,
                priority = priority,
            })
        end
    end

    highlight_button(install_button, "SageButton", 100)
    highlight_button(config_button, "SageButton", 100)

    if task_text ~= "" then
        highlight_button(task_text, "SageTaskProgress", 105)
    end

    if lazy_text ~= "" then
        local type_hl_map = {
            cmds = "SageTriggerCommand",
            fts = "SageTriggerFiletype",
            events = "SageTriggerEvent",
            keys = "SageTriggerKeymap",
            after = "SageTriggerAfter",
            before = "SageTriggerBefore",
        }
        local hl = type_hl_map[lazy_trigger_type] or "SageLazyTrigger"
        highlight_button(lazy_text, hl, 110)
    end

    for _, dep in ipairs(deps_buttons) do
        highlight_button(dep, "SageDependency", 100)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:update_footer_debounced()
end

function Dashboard:update_line_internal(row)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    local ns = Dashboard.ns_buttons
    local l = self:bufline(row)
    if not l then
        return
    end

    self:_ensure_lines(l)

    local icons = self.icons
    local install = row.install_duration:render() or "0"
    local config = row.config_duration:render() or "0"
    local install_button = string.format("[%s %s]", icons.install or "󰚰", install)
    local config_button = string.format("[%s %s]", icons.config or "󰒓", config)

    local deps_buttons = row.deps:render_buttons()
    local deps_text = (#deps_buttons > 0) and (table.concat(deps_buttons, " ")) or ""

    local lazy_text = ""
    local lazy_trigger_type = nil
    if row.stage.value == "lazy" and row.lazy then
        lazy_text = row.lazy:render()
        local info = row.lazy:get_info()
        lazy_trigger_type = info.type
    end

    local message_text = row.message:render()
    local task_text = ""
    if row.task_progress then
        task_text = row.task_progress:render()
    end

    local line_text = string.format(
        "%s %s %-5s %s %s %s %s %s %s",
        row.status:render(),
        row.name,
        row.stage:render(),
        task_text,
        install_button,
        config_button,
        deps_text,
        lazy_text,
        message_text
    )

    local padded = add_padding_to_line(line_text, 1)
    local current_line = vim.api.nvim_buf_get_lines(self.content_buf, l, l + 1, false)[1] or ""

    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
    vim.api.nvim_buf_set_text(self.content_buf, l, 0, l, #current_line, { padded })
    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", false)

    vim.api.nvim_buf_clear_namespace(self.content_buf, ns, l, l + 1)

    local function highlight_button(button_text, hl_group, priority)
        priority = priority or 100
        local s = padded:find(button_text, 1, true)
        if s then
            vim.api.nvim_buf_set_extmark(self.content_buf, ns, l, s - 1, {
                end_col = s - 1 + #button_text,
                hl_group = hl_group,
                priority = priority,
            })
        end
    end

    highlight_button(install_button, "SageButton", 100)
    highlight_button(config_button, "SageButton", 100)

    if task_text ~= "" then
        highlight_button(task_text, "SageTaskProgress", 105)
    end

    if lazy_text ~= "" then
        local type_hl_map = {
            cmds = "SageTriggerCommand",
            fts = "SageTriggerFiletype",
            events = "SageTriggerEvent",
            keys = "SageTriggerKeymap",
            after = "SageTriggerAfter",
            before = "SageTriggerBefore",
        }
        local hl = type_hl_map[lazy_trigger_type] or "SageLazyTrigger"
        highlight_button(lazy_text, hl, 110)
    end

    for _, dep in ipairs(deps_buttons) do
        highlight_button(dep, "SageDependency", 100)
    end
end

function Dashboard:find(name)
    return self.rows_by_name[name]
end

-- ============================================================================
-- Sorting
-- ============================================================================
function Dashboard:resort_rows()
    table.sort(self.rows, function(a, b)
        local status_a = a.status.value or "not_loaded"
        local status_b = b.status.value or "not_loaded"
        local sa = STATUS_ORDER[status_a] or 999
        local sb = STATUS_ORDER[status_b] or 999

        if sa ~= sb then
            return sa < sb
        end

        local stage_a = a.stage.value or "now"
        local stage_b = b.stage.value or "now"
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

    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    for i, row in ipairs(self.rows) do
        local line = i - 1

        self:_ensure_lines(line)

        if row.mark_id then
            pcall(vim.api.nvim_buf_del_extmark, self.content_buf, Dashboard.ns_rows, row.mark_id)
        end

        row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, {
            right_gravity = true,
        })

        self:update_line_internal(row)
    end
end

-- ============================================================================
-- Details Expansion
-- ============================================================================

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

    local details = {
        string.format("   ├─ Status: %s", row.status_two:render()),
        string.format("   ├─ Stage: %s", row.stage_two:render()),
        string.format("   ├─ Install Time: %s", row.install_duration:render() or "0"),
        string.format("   ├─ Config Time: %s", row.config_duration:render() or "0"),
    }

    -- Add lazy trigger details for lazy stage packs
    if row.stage.value == "lazy" and row.lazy and row.lazy.render_detailed then
        table.insert(details, string.format("   ├─ Trigger: %s", row.lazy:render_detailed()))
    end
    table.insert(
        details,
        string.format(
            "   └─ Deps: %s",
            (#row.deps:render_buttons() > 0 and row.deps:render_buttons_joined() or "none")
        )
    )

    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1, false, details)
    vim.api.nvim_buf_set_option(self.content_buf, "modifiable", false)

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
        vim.api.nvim_buf_set_option(self.content_buf, "modifiable", true)
        vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1 + count, false, {})
        vim.api.nvim_buf_set_option(self.content_buf, "modifiable", false)
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

-- Helper to adjust color brightness (optional)
function Dashboard:adjust_color(color, factor)
    if type(color) == "string" then
        color = tonumber(color:sub(2), 16)
    end

    -- Use safe bitwise operations for Lua 5.1 compatibility
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

-- ============================================================================
-- Keymaps
-- ============================================================================
-- In dashboard.lua, replace the setup_keymaps function:
-- In dashboard.lua, setup_keymaps function:
function Dashboard:setup_keymaps()
    local Utils = self.utils
    local Manager = self.manager
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    -- Disable insert mode in all buffers
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.keymap.set("n", "i", "<Nop>", { buffer = buf, silent = true })
        vim.keymap.set("n", "a", "<Nop>", { buffer = buf, silent = true })
    end

    -- Tab navigation - set on ALL buffers with proper self reference
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.keymap.set("n", "<Tab>", function()
            self.active_tab_index = (self.active_tab_index % #self.tabs) + 1
            self:refresh_for_tab() -- Use self, not Dashboard

            -- Ensure focus is on content window after tab switch
            if self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                pcall(vim.api.nvim_set_current_win, self.content_win)
            end
        end, { buffer = buf, silent = true, desc = "Next tab" })

        vim.keymap.set("n", "<S-Tab>", function()
            self.active_tab_index = (self.active_tab_index - 2 + #self.tabs) % #self.tabs + 1
            self:refresh_for_tab() -- Use self, not Dashboard

            -- Ensure focus is on content window after tab switch
            if self.content_win and vim.api.nvim_win_is_valid(self.content_win) then
                pcall(vim.api.nvim_set_current_win, self.content_win)
            end
        end, { buffer = buf, silent = true, desc = "Previous tab" })
    end

    vim.keymap.set("n", "<A-CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = self:get_row_at_line(cursor[1])

        if not row then
            vim.notify("No pack selected", vim.log.levels.WARN)
            return
        end

        self:display_pack_comparison(row.name)
    end, { buffer = self.content_buf, silent = true, desc = "Show pack comparison" })

    vim.keymap.set("n", "r", function()
        vim.notify("Refreshing dashboard...", vim.log.levels.INFO)
        vim.schedule(function()
            self:close()
            self:open()
        end)
    end, { buffer = self.content_buf, desc = "Refresh dashboard" })

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
end
-- ============================================================================
-- Window Management
-- ============================================================================
function Dashboard:open()
    if (not self.event_listeners or #self.event_listeners == 0) and self.bus then
        self:listen()
        self:sync_all_packs()
    end
    if
        self.header_win
        and vim.api.nvim_win_is_valid(self.header_win)
        and self.content_win
        and vim.api.nvim_win_is_valid(self.content_win)
    then
        pcall(vim.api.nvim_set_current_win, self.content_win)
        return
    end

    local ok, err = pcall(function()
        self:create_three_pane_layout()
        self:render_header()
        self:render_footer()
        self:setup_keymaps()
    end)

    if not ok then
        vim.notify("Failed to open dashboard: " .. tostring(err), vim.log.levels.ERROR)
    end
end

function Dashboard:close()
    -- Unregister event listeners first
    -- self:unlisten()
    self.is_open = false

    if self.render_timer and not self.render_timer:is_closing() then
        self.render_timer:close() -- ← REQUIRED!
        self.render_timer = nil
    end

    -- Stop any pending timers
    if self._footer_timer then
        vim.fn.timer_stop(self._footer_timer)
        self._footer_timer = nil
    end

    -- Cleanup autocmds
    for _, id in ipairs(self.autocmd_ids) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmd_ids = {}

    -- Close windows and buffers
    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
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

-- Event Handlers
-- ============================================================================
function Dashboard:listen()
    local Bus = self.bus
    -- Store listener IDs for cleanup
    self.event_listeners = {}

    local function register(event_name, handler)
        local id = Bus.on(event_name, function(data)
            local ok, err = pcall(handler, data)
            if not ok then
                vim.notify(
                    string.format("Dashboard event handler error [%s]: %s", event_name, err),
                    vim.log.levels.ERROR
                )
            end
        end)
        table.insert(self.event_listeners, { event = event_name, id = id })
    end

    local function get_manager()
        return self.container:resolve("manager")
    end

    register("pack:created", function(data)
        self:add_pack(data)
    end)

    register("pack:all_created", function()
        vim.schedule(function()
            self:sync_all_packs()
            self:render_footer()
        end)
    end)

    register("pack:install:start", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        -- row.status:update(data.status)
        -- row.status_two:update(data.status)
        row.message:update(data.message)
        self:update_line(row)
    end)

    register("pack:install:finish", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        -- row.status:update(data.status)
        -- row.status_two:update(data.status)
        row.message:update(data.message)
        row.install_duration:update(data.install_duration or 0)
        self:update_line(row)
    end)

    register("pack:load:start", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.message:update(data.message)
        self:update_line(row)
    end)

    register("pack:load:complete", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.message:update(data.message)
        self:update_line(row)
        self:resort_rows()
    end)

    register("pack:config:start", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        -- row.status:update(data.status)
        -- row.status_two:update(data.status)
        row.message:update(data.message)
        self:update_line(row)
    end)

    register("pack:config:finish", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        -- row.status:update(data.status)
        -- row.status_two:update(data.status)
        row.message:update(data.message)
        row.config_duration:update(data.config_duration or 0)
        self:update_line(row)
    end)

    -- register("pack:lazy", function(data)
    --     local row = self:find(data.name)
    --     if not row then
    --         return
    --     end
    --
    --     row.status:update(data.status)
    --     row.status_two:update(data.status)
    --     row.message:update(data.message)
    --
    --     -- Only update if we have valid trigger data
    --     if row.lazy and data.trigger and next(data.trigger) ~= nil then
    --         row.lazy:update(data.trigger)
    --     end
    --     -- Don't update if data.trigger is nil - keep existing data
    --
    --     self:update_line(row)
    -- end)

    register("pack:failed", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.error:update(data.error)
        row.message:update("✖ " .. (data.reason or "Unknown error"))
        self:update_line(row)
    end)

    register("pack:complete", function()
        vim.schedule(function()
            self:resort_rows()
            vim.defer_fn(function()
                self:focus_content_window()
            end, 50)
        end)
    end)

    register("pack:status:change", function(data)
        local row = self:find(data.name)
        if not row or data.new_status == "created" then
            return
        end
        row.status:update(data.new_status)
        row.status_two:update(data.new_status)

        row.message:update(string.format("%s", data.new_status:upper()))
        self:update_line(row)
    end)

    register("pack:task:start", function(data)
        local Manager = get_manager()
        local row = self:find(data.name)
        if not row then
            return
        end
        local pack = Manager.packs[data.name]
        if pack then
            row.task_progress:update(pack:get_task_progress())
        end
        row.message:update(string.format("Running task: %s", data.task))
        self:update_line(row)
    end)

    register("pack:task:complete", function(data)
        local Manager = get_manager()
        local row = self:find(data.name)
        if not row then
            return
        end
        local pack = Manager.packs[data.name]
        if pack then
            row.task_progress:update(pack:get_task_progress())
        end
        if data.status == "success" then
            row.message:update(string.format("✓ %s", data.task))
        elseif data.status == "failed" then
            row.message:update(string.format("✗ %s: %s", data.task, data.error or "failed"))
        end
        self:update_line(row)
    end)

    register("pack:lifecycle:complete", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.message:update("All tasks complete")
        self:update_line(row)
    end)
end

function Dashboard:unlisten()
    if not self.event_listeners then
        return
    end
    local Bus = self.bus

    for _, listener in ipairs(self.event_listeners) do
        -- Try multiple patterns for event cleanup based on common event bus APIs
        local ok = pcall(function()
            if type(Bus.off) == "function" then
                -- Pattern 1: Event.off(event_name, id)
                Bus.off(listener.event, listener.id)
            elseif type(Bus.remove) == "function" then
                -- Pattern 2: Event.remove(event_name, id)
                Event.remove(listener.event, listener.id)
            elseif type(Bus.unsubscribe) == "function" then
                -- Pattern 3: Event.unsubscribe(id)
                Bus.unsubscribe(listener.id)
            end
        end)

        if not ok then
            vim.notify(string.format("Failed to unregister event listener: %s", listener.event), vim.log.levels.WARN)
        end
    end

    self.event_listeners = {}
end

-- ============================================================================
-- Window Focus Management
-- ============================================================================
function Dashboard:focus_content_window()
    if not (self.content_win and vim.api.nvim_win_is_valid(self.content_win)) then
        return
    end

    -- Set focus to content window
    pcall(vim.api.nvim_set_current_win, self.content_win)

    -- Move cursor to first pack (line 1, column 0)
    pcall(vim.api.nvim_win_set_cursor, self.content_win, { 1, 0 })

    -- Ensure the window is in view
    vim.cmd("redraw")
end

function Dashboard:focus_first_pack()
    if not (self.content_win and vim.api.nvim_win_is_valid(self.content_win)) then
        return
    end

    -- Find the first visible row
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
        pcall(vim.api.nvim_win_set_cursor, self.content_win, { line + 1, 0 }) -- +1 because cursor is 1-based
    else
        self:focus_content_window()
    end
end

function Dashboard:is_valid()
    return self.content_buf
        and vim.api.nvim_buf_is_valid(self.content_buf)
        and self.content_win
        and vim.api.nvim_win_is_valid(self.content_win)
end

-- ============================================================================
-- Batch update optimization
-- ============================================================================
function Dashboard:batch_update_lines(row_updates)
    if not self:is_valid() then
        return
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })

    for _, row in ipairs(row_updates) do
        self:update_line_internal(row)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:update_footer_debounced()
end

function Dashboard:sync_all_packs()
    if not self.manager or not self.manager.packs then
        return
    end

    for name, pack in pairs(self.manager.packs) do
        if not self.rows_by_name[name] then
            self:add_pack({
                name = name,
                pack = pack,
                stage = (pack.stage and pack.stage.value) or "now",
                status = (pack.status and pack.status.value) or "not_loaded",
                message = (pack.message and pack.message.value) or "",
            })
        end
    end

    self:resort_rows()
end
-- ============================================================================
-- Initialization
-- ============================================================================
function Dashboard:init(container, elements, icons, opts)
    opts = opts or {}

    self.render_timer = nil -- ✅ Initialize
    self._footer_timer = nil
    self.autocmd_ids = {}
    -- Allow disabling window lock
    self.config = {
        lock_windows = opts.lock_windows ~= false, -- default true
        auto_focus = opts.auto_focus ~= false, -- default true
        debounce_ms = opts.debounce_ms or 50,
    }

    self.container = container
    self.elements = elements
    self.icons = icons

    self.bus = self.container:resolve("bus")
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")

    self:listen()
    self:setup_debounced_footer()
    self:sync_all_packs()

    -- ========================================================================
    -- BASE UI HIGHLIGHTS
    -- ========================================================================
    vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
    vim.api.nvim_set_hl(0, "SageHeaderBorder", { link = "FloatBorder", default = true })

    -- ========================================================================
    -- TAB HIGHLIGHTS
    -- ========================================================================
    vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
    vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })

    -- ========================================================================
    -- ROW HIGHLIGHTS (Background colors based on status)
    -- ========================================================================
    vim.api.nvim_set_hl(0, "SageRowNormal", { link = "Normal", default = true })
    vim.api.nvim_set_hl(0, "SageRowAlt", { link = "CursorLine", default = true })
    vim.api.nvim_set_hl(0, "SageRowHover", { link = "Visual", default = true })
    vim.api.nvim_set_hl(0, "SageRowExpanded", { link = "PmenuSel", default = true })

    -- Status-based row colors
    vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
    vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
    vim.api.nvim_set_hl(0, "SageRowWaiting", { link = "DiagnosticWarn", default = true })
    vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })

    vim.api.nvim_set_hl(0, "SageMessage", { link = "DiagnosticHint", default = true })
    vim.api.nvim_set_hl(0, "SageTaskProgress", { link = "DiagnosticInfo", default = true })
    -- ========================================================================
    -- BUTTON HIGHLIGHTS (Interactive elements)
    -- ========================================================================

    -- Timing buttons [󰇚 12.5ms] [󰒓 8.3ms]
    vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })

    -- Lazy trigger buttons [󰘳 cmd: Telescope] [󰈔 ft: lua]
    vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })

    -- Dependency buttons [dep_name]
    vim.api.nvim_set_hl(0, "SageDependency", { link = "Underlined", default = true })

    -- ========================================================================
    -- TRIGGER TYPE SPECIFIC HIGHLIGHTS
    -- ========================================================================
    vim.api.nvim_set_hl(0, "SageTriggerCommand", { link = "Function", default = true })
    vim.api.nvim_set_hl(0, "SageTriggerFiletype", { link = "Type", default = true })
    vim.api.nvim_set_hl(0, "SageTriggerEvent", { link = "Keyword", default = true })
    vim.api.nvim_set_hl(0, "SageTriggerKeymap", { link = "Special", default = true })
    vim.api.nvim_set_hl(0, "SageTriggerAfter", { link = "String", default = true })
    vim.api.nvim_set_hl(0, "SageTriggerBefore", { link = "String", default = true })

    -- ========================================================================
    -- FOOTER HIGHLIGHTS
    -- ========================================================================
    vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
    vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })

    -- ========================================================================
    -- -- COLORSCHEME AUTOCMD (Reapply on colorscheme change)
    -- -- ========================================================================
    vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "*",
        callback = function()
            vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
            vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
            vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })
            vim.api.nvim_set_hl(0, "SageTaskProgress", { link = "DiagnosticInfo", default = true })
            vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })
            vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })
            vim.api.nvim_set_hl(0, "SageMessage", { link = "DiagnosticHint", default = true })
            vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
            vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
            vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
            vim.api.nvim_set_hl(0, "SageRowWaiting", { link = "DiagnosticWarn", default = true })
            vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })
            vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
            vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
            vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })
        end,
        desc = "Reapply Sage dashboard highlights on colorscheme change",
    })
    --
    -- ========================================================================
    -- USER COMMANDS (Don't create :Sage here to avoid circular dependency)
    -- ========================================================================

    vim.api.nvim_create_user_command("SageOpen", function()
        local manager = require("sage.manager")
        local dashboard = manager.container:resolve("dashboard")
        dashboard:open()
    end, { desc = "Open Sage dashboard" })

    vim.api.nvim_create_user_command("SageClose", function()
        local manager = require("sage.manager")
        local dashboard = manager.container:resolve("dashboard")
        dashboard:close()
    end, { desc = "Close Sage dashboard" })

    vim.api.nvim_create_user_command("SageToggle", function()
        local manager = require("sage.manager")
        local dashboard = manager.container:resolve("dashboard")
        if dashboard.is_open then
            dashboard:close()
        else
            dashboard:open()
        end
    end, { desc = "Toggle Sage dashboard" })

    vim.api.nvim_create_user_command("SageReload", function()
        require("sage.core.loader"):close_all()
        Dashboard:close()
        vim.notify("Sage: loaders and dashboard cleaned up.", vim.log.levels.INFO)
    end, { desc = "Reload Sage loaders and dashboard" })

    vim.api.nvim_create_user_command("SageCleanup", function()
        vim.api.nvim_exec_autocmds("VimLeavePre", {})
    end, { desc = "Trigger Sage cleanup" })

    vim.api.nvim_create_user_command("SageDebugLazy", function(opts)
        local pack_name = opts.args
        local row = Dashboard:find(pack_name)

        if not row then
            vim.notify("Pack not found: " .. pack_name, vim.log.levels.ERROR)
            return
        end

        local info = {
            stage = row.stage.value,
            has_lazy = row.lazy ~= nil,
            lazy_info = row.lazy and row.lazy:get_info() or "no lazy element",
            trigger_data = row.lazy and row.lazy.trigger_data or "none",
        }
        print(vim.inspect(info))
    end, { nargs = 1, desc = "Debug lazy element for a pack" })
end

return Dashboard
