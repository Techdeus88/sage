local core = require("sage.ui.core")
local Event = require("sage.core.bus")
local icons = require("sage.ui.icons")
local utils = require("sage.base.utils")

local width_percentage = 0.9
local height_percentage = 0.9

local function center_text(text, width)
    local padding = math.floor((width - #text) / 2)
    return string.rep(" ", padding) .. text
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

-- Separate buffers and windows for each pane
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

-- Pane heights
Dashboard.header_height = 4
Dashboard.footer_height = 6

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

    -- Calculate heights
    local content_height = win_height - self.header_height - self.footer_height

    -- Create buffers
    self.header_buf = vim.api.nvim_create_buf(false, true)
    self.content_buf = vim.api.nvim_create_buf(false, true)
    self.footer_buf = vim.api.nvim_create_buf(false, true)

    -- Set buffer options for all
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
        vim.api.nvim_buf_set_option(buf, "filetype", "sage")
        vim.api.nvim_buf_set_option(buf, "modifiable", true)
        vim.api.nvim_buf_set_option(buf, "indentexpr", "")

        vim.b[buf].miniindentscope_disable = true
        vim.b[buf].indent_blankline_enabled = false
        vim.b[buf].snacks_indent_disable = true
    end

    -- Header window (top)
    self.header_win = vim.api.nvim_open_win(self.header_buf, false, {
        relative = "editor",
        width = win_width,
        height = self.header_height,
        row = row,
        col = col,
        style = "minimal",
        border = { "╭", "─", "╮", "│", "", "", "", "│" },
    })

    -- Content window (middle, scrollable)
    self.content_win = vim.api.nvim_open_win(self.content_buf, true, {
        relative = "editor",
        width = win_width,
        height = content_height,
        row = row + self.header_height,
        col = col,
        style = "minimal",
        border = { "", "", "", "│", "", "", "", "│" },
    })

    -- Footer window (bottom)
    self.footer_win = vim.api.nvim_open_win(self.footer_buf, false, {
        relative = "editor",
        width = win_width,
        height = self.footer_height,
        row = row + self.header_height + content_height,
        col = col,
        style = "minimal",
        border = { "├", "─", "┤", "│", "╰", "─", "╯", "│" },
    })

    -- Set window options
    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.header_win })
    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.content_win })
    vim.api.nvim_set_option_value("winhighlight", "Normal:SageUIWindow", { win = self.footer_win })

    vim.api.nvim_win_set_option(self.content_win, "cursorline", true)
    vim.api.nvim_win_set_option(self.content_win, "scrolloff", 3)

    -- Focus content window
    pcall(vim.api.nvim_set_current_win, self.content_win)

    self:lock_windows()
    self:setup_close_keymaps()
end

function Dashboard:lock_windows()
    -- Prevent leaving the dashboard windows
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
            vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
                noremap = true,
                silent = true,
                nowait = true,
                callback = function()
                    self:close()
                end,
            })
        end
    end
end

-- ============================================================================
-- Header Rendering (Static after initial render)
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

    local header_lines = {
        "",
        rendered_tabs,
        "",
        "",
    }

    vim.api.nvim_buf_set_lines(self.header_buf, 0, -1, false, header_lines)

    -- Clear and add highlights
    vim.api.nvim_buf_clear_namespace(self.header_buf, Dashboard.ns_ui, 0, -1)

    local col = 0
    local tab_text = table.concat(tab_line, "")
    local padding = math.floor((win_width - #tab_text) / 2)

    for i, tab in ipairs(self.tabs) do
        local text = (i == self.active_tab_index) and string.format(" [%s] ", tab.label)
            or string.format("  %s  ", tab.label)

        local hl = (i == self.active_tab_index) and "SageTabActive" or "SageTab"

        vim.api.nvim_buf_add_highlight(self.header_buf, Dashboard.ns_ui, hl, 1, padding + col, padding + col + #text)
        col = col + #text
    end

    -- Make header read-only
    vim.api.nvim_buf_set_option(self.header_buf, "modifiable", true)
end

-- ============================================================================
-- Footer Rendering (Updates only when stats change)
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

function Dashboard:render_footer()
    if not (self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf)) then
        return
    end

    local win_width = vim.api.nvim_win_get_width(self.footer_win)
    local stats = self:get_stats()

    local ui_enter_time = "0.00ms"
    local ok, sage_api = pcall(require, "sage.api")
    if ok then
        ui_enter_time = sage_api:get_event("uienter")
    end

    -- Calculate progress
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
                "Loaded: %d  • Lazy: %d  • Failed: %d  •  Disabled: %d  • Total Duration: %sms",
                stats.loaded,
                stats.lazy,
                stats.failed,
                stats.disabled,
                ui_enter_time
            ),
            win_width
        ),
        center_text(
            "Press 'r' to refresh  •  'q' to quit  •  '<CR>' to toggle details •  '<Tab>' to switch tabs",
            win_width
        ),
        "",
    }

    vim.api.nvim_buf_set_option(self.footer_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, footer_lines)

    -- Add highlights
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
        vim.api.nvim_buf_set_lines(self.content_buf, lc, lc, false, blanks)
    end
end

function Dashboard:add_padding_to_line(line, padding)
    padding = padding or 1
    local pad = string.rep(" ", padding)
    return string.format("%s%s%s", pad, line, pad)
end

-- ============================================================================
-- Pack Management (Get stage from the event's data object OR from the spec's on.stage opt)
-- ============================================================================
function Dashboard:add_pack(data)
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

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

    local _, elem = pcall(require, "sage.ui.core")

    local row = {
        name = name,
        status = elem.StatusElement.new("status", status, "icon"),
        status_two = elem.StatusElement.new("status", status, "icon_text"),
        stage = elem.StageElement.new("stage", stage, "icon", {
            stage = { now = icons.now, later = icons.later, lazy = icons.lazy, disabled = icons.disabled },
        }),
        stage_two = elem.StageElement.new("stage_two", stage, "icon_text", {
            stage = { now = icons.now, later = icons.later, lazy = icons.lazy, disabled = icons.disabled },
        }),
        deps = elem.ListElement.new("deps", utils.get_dep_names(n_spec.data.depends or {})),
        install_duration = elem.DurationElement.new("install_duration", Pack.times.install_duration),
        config_duration = elem.DurationElement.new("config_duration", Pack.times.config_duration),
        message = elem.TextElement.new("message", message),
        lazy = elem.LazyElement.new("lazy", on),
    }

    self.rows_by_name[name] = row
    table.insert(self.rows, row)

    local index = #self.rows
    local line = index - 1 -- 0-based

    self:_ensure_lines(line)

    row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, {
        right_gravity = true,
    })

    self:update_line(row)
end

-- ============================================================================
-- UPDATE_LINE WITH GRANULAR TRIGGER HIGHLIGHTING
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

    self:_ensure_lines(l)

    -- Build line components
    local install = row.install_duration:render() or "0"
    local config = row.config_duration:render() or "0"
    local install_button = string.format("[%s %s]", icons.install or "󰇚", install)
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

    -- Build complete line
    local line_text = string.format(
        "%s %-25s %s %s %s %s %s %s",
        row.status:render(),
        row.name,
        row.stage:render(),
        row.message:render(),
        install_button,
        config_button,
        deps_text,
        lazy_text
    )
    local padded = self:add_padding_to_line(line_text, 1)

    -- Update buffer text
    local current_line = vim.api.nvim_buf_get_lines(self.content_buf, l, l + 1, false)[1] or ""
    vim.api.nvim_buf_set_text(self.content_buf, l, 0, l, #current_line, { padded })

    -- Clear old highlights
    vim.api.nvim_buf_clear_namespace(self.content_buf, ns, l, l + 1)

    -- Helper function to highlight buttons
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

    -- Highlight timing buttons (priority 100)
    highlight_button(install_button, "SageButton", 100)
    highlight_button(config_button, "SageButton", 100)

    -- Highlight lazy trigger button with type-specific highlight (priority 110)
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

    -- Highlight dependency buttons (priority 100)
    for _, dep in ipairs(deps_buttons) do
        highlight_button(dep, "SageDependency", 100)
    end

    -- Update footer
    vim.defer_fn(function()
        self:update_footer_if_changed()
    end, 100)
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

        self:update_line(row)
    end

    self:render_footer()
end

-- ============================================================================
-- Tab Filtering (FIXED: Added "now" and "later" filters)
-- ============================================================================
function Dashboard:refresh_for_tab()
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    local filter = self.tabs[self.active_tab_index].id

    local function matches(row)
        if filter == "all" then
            return true
        end
        if filter == "loaded" or filter == "configured" or filter == "ready" then
            return row.status.value == "loaded"
        end
        if filter == "not_loaded" then
            return row.status.value == "not_loaded"
                or row.status.value == "installing"
                or row.status.value == "installed"
                or row.status.value == "created"
        end
        if filter == "lazy" then
            return row.stage.value == "lazy" or row.status.value == "lazy" -- FIXED: Filter by stage, not status
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
    for _, row in ipairs(self.rows) do
        if matches(row) then
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

    self:render_header()
    self:render_footer()
end

-- ============================================================================
-- Details Expansion
-- ============================================================================
function Dashboard:display_pack_comparison(pack_name)
    local manager = require("sage.manager")
    local pack = manager:get_pack(pack_name)
    local n_pack = pack:get_native()

    if not pack or not n_pack then
        vim.notify(string.format("[%s] Failed to retrieve pack data", pack_name), vim.log.levels.ERROR)
        return
    end

    -- Build content lines
    local lines = {}
    table.insert(lines, "╔════════════════════════════════════════╗")
    table.insert(lines, string.format("║  Sage Pack: %s", pack_name .. string.rep(" ", 35 - #pack_name) .. "║"))
    table.insert(lines, "╚════════════════════════════════════════╝")
    table.insert(lines, "")

    -- Pack (Manager) section
    table.insert(lines, "📦 PACK (Manager)")
    table.insert(lines, string.rep("─", 40))
    if pack then
        table.insert(lines, format_table(pack))
    else
        table.insert(lines, "  (nil)")
    end
    table.insert(lines, "")

    -- N_Pack (vim.pack) section
    table.insert(lines, "📦 N_PACK (vim.pack.get)")
    table.insert(lines, string.rep("─", 40))
    if n_pack then
        table.insert(lines, format_table(n_pack))
    else
        table.insert(lines, "  (nil)")
    end
    table.insert(lines, "")

    -- Summary
    table.insert(lines, "━" .. string.rep("━", 38) .. "━")
    table.insert(lines, "Press 'q' to close this buffer")

    -- Use snacks.nvim scratch buffer
    local Snacks = require("snacks")
    Snacks.scratch({
        file = pack_name,
        ft = "lua",
        width = 80,
        height = 40,
        opts = {
            relative = "editor",
            style = "float",
            border = "rounded",
        },
    })

    -- Get the buffer and set content
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Set close keymap
    vim.keymap.set("n", "q", function()
        vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, noremap = true, silent = true })
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

    local details = {
        string.format("   ├─ Status: %s", row.status_two:render()),
        string.format("   ├─ Stage: %s", row.stage_two:render()),
        string.format("   ├─ Install Time: %s", row.install_duration:render() or "0"),
        string.format("   ├─ Config Time: %s", row.config_duration:render() or "0"),
    }

    -- FIXED: Add lazy trigger details for lazy stage packs
    if row.stage.value == "lazy" and row.lazy_trigger then
        table.insert(details, string.format("   ├─ Trigger: %s", row.lazy_trigger:render_detailed()))
    end

    table.insert(
        details,
        string.format(
            "   └─ Deps: %s",
            (#row.deps:render_buttons() > 0 and row.deps:render_buttons_joined() or "none")
        )
    )

    vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1, false, details)

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
        vim.api.nvim_buf_set_lines(self.content_buf, l + 1, l + 1 + count, false, {})
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
-- Keymaps
-- ============================================================================
function Dashboard:setup_keymaps()
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        return
    end

    vim.keymap.set("n", "i", "<Nop>", { buffer = self.header_buf, silent = true })
    vim.keymap.set("n", "i", "<Nop>", { buffer = self.content_buf, silent = true })
    vim.keymap.set("n", "i", "<Nop>", { buffer = self.footer_buf, silent = true })
    vim.keymap.set("n", "a", "<Nop>", { buffer = self.header_buf, silent = true })
    vim.keymap.set("n", "a", "<Nop>", { buffer = self.content_buf, silent = true })
    vim.keymap.set("n", "a", "<Nop>", { buffer = self.footer_buf, silent = true })

    vim.keymap.set("n", "<Tab>", function()
        Dashboard.active_tab_index = (Dashboard.active_tab_index % #Dashboard.tabs) + 1
        Dashboard:refresh_for_tab()
    end, { buffer = self.content_buf, silent = true, desc = "Next tab" })

    vim.keymap.set("n", "<S-Tab>", function()
        Dashboard.active_tab_index = (Dashboard.active_tab_index - 2 + #Dashboard.tabs) % #Dashboard.tabs + 1
        Dashboard:refresh_for_tab()
    end, { buffer = self.content_buf, silent = true, desc = "Previous tab" })

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
            return
        end

        if row.expanded then
            self:collapse_details(row)
        else
            self:expand_details(row)
        end
    end, { buffer = self.content_buf, desc = "Toggle pack details" })

    vim.keymap.set("n", "<S-CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = self:get_row_at_line(cursor[1])

        if not row then
            return
        end

        self:display_pack_comparison(row.name.value)
    end, { buffer = self.content_buf, desc = "Toggle SagePack details" })
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
        pcall(vim.api.nvim_set_current_win, self.content_win)
        return
    end

    local ok, err = pcall(function()
        self:create_three_pane_layout()
        self:render_header()
        self:render_footer()
        self:listen()
        self:setup_keymaps()
    end)

    if not ok then
        vim.notify("Failed to open dashboard: " .. tostring(err), vim.log.levels.ERROR)
    end
end

function Dashboard:close()
    for _, id in ipairs(self.autocmd_ids) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    self.autocmd_ids = {}

    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
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
end

-- ============================================================================
-- Event Handlers (FIXED: Removed duplicate notifications)
-- ============================================================================
function Dashboard:listen()
    Event.on("pack:created", function(data)
        self:add_pack(data)
    end)

    Event.on("pack:all_created", function(data)
        vim.schedule(function()
            self:render_footer()
        end)
    end)

    Event.on("pack:install:start", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update(data.message)
        self:update_line(row)
    end)

    Event.on("pack:install:finish", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update(data.message)
        row.install_duration:update(data.install_duration or 0)
        self:update_line(row)
    end)

    Event.on("pack:config:start", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update(data.message)
        self:update_line(row)
    end)

    Event.on("pack:config:finish", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update(data.message)
        row.config_duration:update(data.config_duration or 0)
        self:update_line(row)
        self:resort_rows()
    end)
    -- FIXED: Removed duplicate vim.notify calls
    Event.on("pack:lazy", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update(data.message)

        -- Only update lazy trigger if it exists
        if row.lazy_trigger and data.trigger then
            row.lazy_trigger:update(data.trigger)
        end

        self:update_line(row)
        -- self:resort_rows()
    end)

    Event.on("pack:failed", function(data)
        local row = self:find(data.name)
        if not row then
            return
        end
        row.status:update(data.status)
        row.status_two:update(data.status)
        row.message:update("✖ " .. (data.reason or "Unknown error"))
        self:update_line(row)
    end)

    Event.on("pack:complete", function()
        vim.schedule(function()
            self:resort_rows()
            -- After everything is complete, focus content window
            vim.defer_fn(function()
                self:focus_content_window()
            end, 50)
        end)
    end)
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

-- ============================================================================
-- Initialization
-- ============================================================================
function Dashboard:init(opts)
    opts = opts or {}

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
    -- vim.api.nvim_create_autocmd("ColorScheme", {
    -- 	pattern = "*",
    -- 	callback = function()
    -- 		vim.api.nvim_set_hl(0, "SageUIWindow", { link = "NormalFloat", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageTabActive", { link = "TabLineSel", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageTab", { link = "TabLine", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageRowLoaded", { link = "DiagnosticOk", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageRowFailed", { link = "DiagnosticError", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageRowLazy", { link = "DiagnosticInfo", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageRowWaiting", { link = "DiagnosticWarn", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageRowDisabled", { link = "Comment", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageFooterProgress", { link = "Title", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageFooterStats", { link = "String", default = true })
    -- 		vim.api.nvim_set_hl(0, "SageFooterHelp", { link = "Comment", default = true })
    -- 	end,
    -- 	desc = "Reapply Sage dashboard highlights on colorscheme change",
    -- })
    --
    -- ========================================================================
    -- USER COMMANDS (Don't create :Sage here to avoid circular dependency)
    -- ========================================================================
    vim.api.nvim_create_user_command("SageReload", function()
        require("sage.core.loader").close_all()
        Dashboard:close()
        vim.notify("Sage: loaders and dashboard cleaned up.", vim.log.levels.INFO)
    end, { desc = "Reload Sage loaders and dashboard" })

    vim.api.nvim_create_user_command("SageCleanup", function()
        vim.api.nvim_exec_autocmds("VimLeavePre", {})
    end, { desc = "Trigger Sage cleanup" })
end

-- Helper to adjust color brightness (optional)
function Dashboard:adjust_color(color, factor)
    if type(color) == "string" then
        color = tonumber(color:sub(2), 16)
    end

    local r = math.floor(bit.rshift(color, 16) * (1 + factor))
    local g = math.floor(bit.band(bit.rshift(color, 8), 0xFF) * (1 + factor))
    local b = math.floor(bit.band(color, 0xFF) * (1 + factor))

    r = math.min(255, math.max(0, r))
    g = math.min(255, math.max(0, g))
    b = math.min(255, math.max(0, b))

    return string.format("#%02x%02x%02x", r, g, b)
end

return Dashboard
