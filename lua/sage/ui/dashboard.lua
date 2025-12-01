local height_percentage = 0.8
local width_percentage = 0.8

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
Dashboard.__index = Dashboard

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

    -- Configure buffers to prevent premature closure
    for _, buf in ipairs({ self.header_buf, self.content_buf, self.footer_buf }) do
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("filetype", "sage", { buf = buf })
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
        vim.api.nvim_set_option_value("indentexpr", "", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf }) -- Add this

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

    for _, win in ipairs({ self.header_win, self.content_win, self.footer_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            -- These windows should not be easily closed
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

---@param window_name string
function Dashboard:get_window(window_name)
    local name_map = { header = self.header_win, content = self.content_win, footer = self.footer_win }
    return name_map[window_name]
end

function Dashboard:lock_windows()
    if not self.config or self.config.lock_windows == false then
        return
    end

    -- Store window IDs for validation
    local dashboard_windows = {
        header = self.header_win,
        content = self.content_win,
        footer = self.footer_win,
    }

    -- Prevent leaving dashboard windows
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
                                -- Content window is gone, close everything
                                self:close()
                            end
                        end)
                    end
                end,
            })
            table.insert(self.autocmd_ids, winleave_id)
        end
    end

    -- Guard against any window being closed individually
    local close_guard_id = vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(args)
            local closed_win = tonumber(args.match)

            -- Check if any of our windows closed
            for name, win_id in pairs(dashboard_windows) do
                if closed_win == win_id then
                    vim.schedule(function()
                        -- One window closed, close them all
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

    -- Periodic check to ensure all windows are still valid
    self.window_check_timer = vim.uv.new_timer()
    self.window_check_timer:start(
        1000,
        1000,
        vim.schedule_wrap(function()
            -- Check if any window is missing
            local header_valid = self.header_win and vim.api.nvim_win_is_valid(self.header_win)
            local content_valid = self.content_win and vim.api.nvim_win_is_valid(self.content_win)
            local footer_valid = self.footer_win and vim.api.nvim_win_is_valid(self.footer_win)

            if not (header_valid and content_valid and footer_valid) then
                -- One or more windows are invalid, close everything
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

local function getTableValue(t, keys)
    local current = t
    for _, key in ipairs(keys) do
        if type(current) == "table" and current[key] ~= nil then
            current = current[key]
        else
            return nil -- Key not found or not a table
        end
    end
    return current
end

local function split_by_period(str)
    local result = {}
    -- Pattern matches any character (.), zero or more times (*), that is not (^) a period (.)
    -- The non-greedy quantifier (?) ensures it matches the shortest possible sequence.
    for part in str:gmatch("([^.]*)") do
        if part ~= "" then -- Avoid adding empty strings if there are consecutive periods or a period at the start/end
            table.insert(result, part)
        end
    end
    return result
end

-- Compare a Sage pack to native vim.pack info (Neovim 0.12)
function Dashboard:display_pack_comparison(pack_name)
    local manager = self.container:resolve("manager")
    local utils = self.container:resolve("utils")

    local width = vim.o.columns
    local height = vim.o.lines
    local win_height = math.floor(height * 0.80)
    local win_width = math.floor(width * 0.60)
    local inner_width = win_width - 4 -- 2 borders + 2 padding

    local pack = manager.packs[pack_name]
    if not pack then
        utils.safe_notify(string.format("[Sage] Pack not found: %s", pack_name), vim.log.levels.ERROR)
        return
    end

    -- Native vim.pack view (usually wraps vim.pack.get())
    local ok_native, n_pack = pcall(function()
        return pack:get_native()
    end)
    if not ok_native then
        n_pack = nil
    end

    -- Small helper: get nested value (uses your existing helpers)
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
            border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
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
        local value_col = math.floor((inner_width - label_col - 5) / 2) -- 5 ≈ " | " + margin

        -- Header
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
                -- Simple ~= comparison is usually enough for these scalars
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

        -- Header box
        local header_text = string.format("Pack: %s", pack_name)
        local header_padding = math.floor((inner_width - #header_text - 2) / 2) -- -2 for border chars

        table.insert(lines, "╔" .. string.rep("═", inner_width - 2) .. "╗")
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

        -- Core pack-level fields
        local core_fields = {
            { label = "name", sage = "name", native = "spec.name" },
            { label = "enabled", sage = "enabled", native = nil },
            { label = "active", sage = "active", native = "active" },
            { label = "installed", sage = "installed", native = nil },
            { label = "loaded", sage = "loaded", native = nil },
            { label = "status", sage = "status", native = nil },
            { label = "path", sage = "path", native = "path" },
            { label = "rev", sage = nil, native = "rev" },
        }

        add_side_by_side_section(lines, "Core", core_fields)

        -- Spec-level fields (Sage normalize vs vim.pack.Spec)
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

        -- Spec-level fields (Sage normalize vs vim.pack.Spec)
        local lazy_fields = {
            { label = "Events ~Lazy~", sage = "specs.normalize.data.on.events", native = "spec.data.on.events" },
            { label = "Cmds ~Lazy~", sage = "specs.normalize.data.on.cmds", native = "spec.data.on.cmds" },
            { label = "Fts ~Lazy~", sage = "specs.normalize.data.on.fts", native = "spec.data.on.fts" },
            { label = "Keys ~Lazy~", sage = "specs.normalize.data.on.keys", native = "spec.data.on.keys" },
        }

        add_side_by_side_section(lines, "", lazy_fields)

        -- Diff section (only mismatched fields where both sides exist)
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

        -- Horizontal padding
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

    ------------------------------------------------------------
    -- 1. Resolve active filter
    ------------------------------------------------------------
    local filter_id = self.tabs[self.active_tab_index].id

    local function matches(row)
        local status = row.elements.status and row.elements.status.value
        local stage  = row.elements.stage and row.elements.stage.value
        local pack   = self.manager.packs[row.name]

        if filter_id == "all" then
            return true
        end

        if filter_id == "loaded" then
            return status == "loaded" or status == "ready" or status == "configured"
        end

        if filter_id == "not_loaded" then
            return (pack and pack.loaded == false)
                or status == "installing"
                or status == "installed"
                or status == "created"
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

    ------------------------------------------------------------
    -- 2. Clear all content
    ------------------------------------------------------------
    vim.api.nvim_buf_clear_namespace(self.content_buf, Dashboard.ns_rows, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.content_buf, Dashboard.ns_content, 0, -1)
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {})

    ------------------------------------------------------------
    -- 3. Render only matching rows
    ------------------------------------------------------------
    local line = 0
    local has_matches = false

    for _, row in ipairs(self.rows) do
        if matches(row) then
            has_matches = true
            ----------------------------------------------------
            -- Allocate a blank buffer line for this row
            ----------------------------------------------------

            vim.api.nvim_buf_set_lines(self.content_buf, line, line, false, { "" })


            ----------------------------------------------------
            -- Assign or move the row extmark (position only)
            ----------------------------------------------------
            row.mark_id = vim.api.nvim_buf_set_extmark(
                self.content_buf,
                Dashboard.ns_rows,
                line,
                0,
                {
                    id = row.mark_id,
                    right_gravity = false,
                }
            )

            ----------------------------------------------------
            -- Render row virt_text (stable, correct)
            ----------------------------------------------------
            self:render_row(row)

            ----------------------------------------------------
            -- Expanded detail rows
            ----------------------------------------------------
            if row.expanded and row.details then
                for _, detail_row in ipairs(row.details) do
                    line = line + 1
                    vim.api.nvim_buf_set_lines(self.content_buf, line, line, false, { "" })

                    detail_row.mark_id = vim.api.nvim_buf_set_extmark(
                        self.content_buf,
                        Dashboard.ns_rows,
                        line,
                        0,
                        {
                            id = detail_row.mark_id,
                            right_gravity = false,
                        }
                    )

                    self:render_row(detail_row)
                end
            end

            line = line + 1
        end
    end

    ------------------------------------------------------------
    -- 4. Handle empty-filter result
    ------------------------------------------------------------
    if not has_matches then
        vim.api.nvim_buf_set_lines(self.content_buf, 0, -1, false, {
            "",
            "  No packs in category: " .. filter_id,
            "",
        })
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    ------------------------------------------------------------
    -- 5. Re-render header & footer (tab label etc)
    ------------------------------------------------------------
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
        local status = row.elements.status.value

        if status == "failed" then
            stats.failed = stats.failed + 1
        elseif status == "loaded" or status == "configured" or status == "ready" then
            stats.loaded = stats.loaded + 1
        elseif status == "lazy" then
            stats.lazy = stats.lazy + 1
        elseif status == "disabled" then
            stats.disabled = stats.disabled + 1
            stats.not_loaded = stats.not_loaded + 1
        elseif
            status == "installing"
            or status == "installed"
            or status == "created"
            or status == "idle"
            or status == "configuring"
        then
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

    -- Highlight line 1 (progress bar)
    local line1_text = footer_lines[2]
    if line1_text and #line1_text > 0 then
        vim.api.nvim_buf_set_extmark(self.footer_buf, Dashboard.ns_footer, 1, 0, {
            end_col = #line1_text,
            hl_group = "SageFooterProgress",
        })
    end

    -- Highlight line 3 (stats)
    local line3_text = footer_lines[4]
    if line3_text and #line3_text > 0 then
        vim.api.nvim_buf_set_extmark(self.footer_buf, Dashboard.ns_footer, 3, 0, {
            end_col = #line3_text,
            hl_group = "SageFooterStats",
        })
    end

    -- Highlight line 4 (help)
    local line4_text = footer_lines[5]
    if line4_text and #line4_text > 0 then
        vim.api.nvim_buf_set_extmark(self.footer_buf, Dashboard.ns_footer, 4, 0, {
            end_col = #line4_text,
            hl_group = "SageFooterHelp",
        })
    end
end

function Dashboard:update_footer_if_changed()
    local stats = self:get_stats()
    local stats_str = vim.inspect(stats)

    if self.last_stats ~= stats_str then
        self.last_stats = stats_str
        vim.api.nvim_set_option_value("modifiable", true, self.footer_buf)
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

        vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
        vim.api.nvim_buf_set_lines(self.content_buf, lc, lc, false, blanks)
        vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    end
end

-- ============================================================================
-- Pack Management
-- ============================================================================
function Dashboard:add_pack(data)
    local icons = self.icons
    local elem = self.elements
    local utils = self.utils

    local Pack = data.pack
    if not Pack then
        return
    end

    local n_spec = Pack.specs.normalize
    local name = data.name
    local stage = data.stage
    local status = data.status
    local message = data.message
    local path = data.path or ""

    local trigger_data = (n_spec.data.on and next(n_spec.data.on)) and n_spec.data.on or nil

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
        name = name,
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

    local row = self.rows_by_name[name]
    if not row then
        row = {
            name = name,
            elements = row_elements,
            mark_id = nil,
            index = #self.rows + 1
        }

        self.rows_by_name[name] = row
        table.insert(self.rows, row)
    else
        self:update_row(row.name)
    end

    -- If buffer / window isn't ready yet, just track the data.
    if not (self.content_buf and vim.api.nvim_buf_is_valid(self.content_buf)) then
        if self.debug_log then
            self:debug_log(string.format("Tracked pack %s (UI not ready)", name))
        end
        return
    end
    self:render_row(row)
end

function Dashboard:render_row(row)
    -- 1. Ensure row position tracking exists (only if mark_id is nil)
    if not row.mark_id then
        local index = row.index
        local line = index - 1
        vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
        self:_ensure_lines(line)

        row.mark_id =
            vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, { right_gravity = true })
    end

    -- 2. Get current line position
    local current_line = vim.api.nvim_buf_get_extmark_by_id(self.content_buf, Dashboard.ns_rows, row.mark_id, {})[1]

    -- 3. Clear old content
    vim.api.nvim_buf_clear_namespace(self.content_buf, Dashboard.ns_content, current_line, current_line + 1)

    -- 4. Build render order
    local elements = row.elements
    local render_order = {
        elements.status,
        elements.name and { text = elements.name, hl_group = "Normal" } or nil,
        elements.stage,
        elements.lazy,
        elements.install_duration,
        elements.config_duration,
        elements.deps,
        elements.message,
        elements.error,
    }

    -- 5. Render
    local virt_text = {}

    for _, elem in ipairs(render_order) do
        if elem then
            if type(elem) == "table" and elem.text then
                table.insert(virt_text, { elem.text, elem.hl_group or "Normal" })
                table.insert(virt_text, { " ", "Normal" })
            elseif type(elem) == "table" and elem.render_with_hl then
                local render_data = elem:render_with_hl()

                if render_data[1] and render_data[1].text then
                    for _, segment in ipairs(render_data) do
                        table.insert(virt_text, { segment.text, segment.hl_group })
                    end
                else
                    if render_data.text and render_data.text ~= "" then
                        table.insert(virt_text, { render_data.text, render_data.hl_group })
                    end
                end

                table.insert(virt_text, { " ", "Normal" })
            end
        end
    end

    -- Remove trailing space
    if #virt_text > 0 and virt_text[#virt_text][1] == " " then
        table.remove(virt_text)
    end

    -- 6. Set extmark
    if #virt_text > 0 then
        vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_content, current_line, 0, {
            virt_text = virt_text,
            virt_text_pos = "eol",
        })
        self:debug_log(string.format("Rendered %d segments for %s at line %d", #virt_text, row.name, current_line))
    else
        self:debug_log(string.format("No content to render for %s", row.name))
    end
end

function Dashboard:update_row(row_name)
    local row = self:find(row_name)
    if not row then
        self:debug_log(string.format("update_row: row not found for %s", row_name))
        return
    end

    -- Check if any element is dirty
    local needs_update = false
    local elems = row.elements

    for key, elem in pairs(elems) do
        if type(elem) == "table" and elem.is_dirty and elem:is_dirty() then
            needs_update = true
            self:debug_log(string.format("Element %s is dirty for %s", key, row_name))
            break
        end
    end

    if needs_update then
        self:debug_log(string.format("Re-rendering row %s", row_name))
        self:render_row(row)

        -- Mark elements clean
        for _, elem in pairs(elems) do
            if type(elem) == "table" and elem.mark_clean then
                elem:mark_clean()
            end
        end
    end
end

function Dashboard:find(name)
    return self.rows_by_name[name]
end

-- Update the renderer helper to apply updates correctly
function Dashboard:apply_update_to_row(row, data)
    local elems = row.elements

    if data.status then
        if elems.status then
            elems.status:update(data.status)
        end
        if elems.status_two then
            elems.status_two:update(data.status)
        end
    end

    if data.message and data.message ~= "" then
        if elems.message then
            elems.message:update(data.message)
        end
    elseif data.status then
        -- derive a friendly message from status when none is provided
        local status_messages = {
            ready = "Loaded",
            loaded = "Loaded",
            installed = "Installed",
            installing = "Installing…",
            configuring = "Configuring…",
            failed = "Failed",
            disabled = "Disabled",
            lazy = "Lazy",
        }
        local msg = status_messages[data.status]
        if msg and elems.message then
            elems.message:update(msg)
        end
    end

    if data.install_duration and elems.install_duration then
        elems.install_duration:update(data.install_duration)
    end

    if data.config_duration and elems.config_duration then
        elems.config_duration:update(data.config_duration)
    end

    if data.stage and elems.stage then
        elems.stage:update(data.stage)
        if elems.stage_two then
            elems.stage_two:update(data.stage)
        end
    end
end

-- Clear all content rendering (keeps position tracking)
function Dashboard:clear_content()
    vim.api.nvim_buf_clear_namespace(self.content_buf, Dashboard.ns_content, 0, -1)
end

-- Full re-render
function Dashboard:refresh()
    self:clear_content()
    for _, row in ipairs(self.rows) do
        self:render_row(row)
    end
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
    local deps_text = (#deps_buttons > 0) and (table.concat(deps_buttons, " ")) or ""

    local message_text = row.message:render()
    local error_text = row.error ~= nil and row.error:render()

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
    self:debug_log(string.format("update_line hit by %s", row.name))
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

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.content_buf })
    vim.api.nvim_buf_set_text(self.content_buf, l, 0, l, #current_line, { padded })
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })

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
        local status_a = a.elements.status.value or "not_loaded"
        local status_b = b.elements.status.value or "not_loaded"
        local sa = STATUS_ORDER[status_a] or 999
        local sb = STATUS_ORDER[status_b] or 999

        if sa ~= sb then
            return sa < sb
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
            pcall(vim.api.nvim_buf_del_extmark, self.content_buf, Dashboard.ns_rows, row.mark_id)
        end

        row.mark_id = vim.api.nvim_buf_set_extmark(self.content_buf, Dashboard.ns_rows, line, 0, {
            right_gravity = true,
        })

        self:render_row(row)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
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

    local elements = row.elements
    local details = {
        string.format("   ├─ Status: %s", elements.status_two:render()),
        string.format("   ├─ Stage: %s", elements.stage_two:render()),
        string.format("   ├─ Install Time: %s", elements.install_duration:render() or "0"),
        string.format("   ├─ Config Time: %s", elements.config_duration:render() or "0"),
        string.format("   ├─ Path: %s", elements.path:render()),
    }

    -- Add lazy trigger details for lazy stage packs
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
    if
        self.header_win
        and vim.api.nvim_win_is_valid(self.header_win)
        and self.content_win
        and vim.api.nvim_win_is_valid(self.content_win)
    then
        self:focus_first_pack()
        return
    end

    self.is_ready = true
    self.is_open = true

    local ok, err = pcall(function()
        self:create_three_pane_layout()
    end)

    if not ok then
        vim.notify("Failed to open dashboard: " .. tostring(err), vim.log.levels.ERROR)
        self.is_open = false
        return
    end

    -- FIX: Call rebuild_display ONCE, not in a loop
    self:debug_log(string.format("Rendering %d tracked packs", vim.tbl_count(self.rows_by_name)))
    self:rebuild_display()

    self:render_header()
    self:render_footer()
    self:setup_keymaps()
end

function Dashboard:close()
    self.is_open = false

    -- Stop window check timer
    if self.window_check_timer and not self.window_check_timer:is_closing() then
        self.window_check_timer:close()
        self.window_check_timer = nil
    end

    if self.render_timer and not self.render_timer:is_closing() then
        self.render_timer:close()
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

    -- Close windows and buffers (as a unit)
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
        self:update_row(row.name)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.content_buf })
    self:update_footer_debounced()
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
-- Initialization
-- ============================================================================
function Dashboard:init(container, elements, icons, opts)
    self.opts = opts or {}
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
    self.rows = {}
    self.rows_by_name = {}
    self.header_buf = nil
    self.header_win = nil
    self.content_buf = nil
    self.content_win = nil
    self.footer_buf = nil
    self.footer_win = nil
    self.autocmd_ids = {}
    self.ns_rows = vim.api.nvim_create_namespace("SageDashboardRows")
    self.ns_content = vim.api.nvim_create_namespace("SageDashboardContent")
    self.ns_buttons = vim.api.nvim_create_namespace("SageDashboardButtons")
    self.ns_ui = vim.api.nvim_create_namespace("SageUI")
    self.ns_footer = vim.api.nvim_create_namespace("SageDashboardFooter")
    self.ns_background = vim.api.nvim_create_namespace("SageBackground") -- Priority 50
    self.ns_text = vim.api.nvim_create_namespace("SageText") -- Priority 100
    self.ns_buttons = vim.api.nvim_create_namespace("SageButtons") -- Priority 150
    self.ns_status = vim.api.nvim_create_namespace("SageStatus") -- Priority 200
    self.ns_overlay = vim.api.nvim_create_namespace("SageOverlay") -- Priority 250
    self.last_stats = nil
    self.header_height = 4
    self.footer_height = 6
    self.is_valid = false
    self.should_track = true
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
    self.logger = self.container:resolve("logger")

    self:setup_debounced_footer()

    -- ========================================================================
    -- BASE UI HIGHLIGHTS
    -- =======================================================================
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
    vim.api.nvim_set_hl(0, "SageStatusCreated", { fg = "#7aa2f7", italic = true })
    vim.api.nvim_set_hl(0, "SageStatusLoaded", { fg = "#9ece6a", bold = true })
    vim.api.nvim_set_hl(0, "SageStatusFailed", { fg = "#f7768e", underline = true })
    vim.api.nvim_set_hl(0, "SageLazyBracket", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyIcon", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyLabel", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyValue", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLink", { fg = "#6495ed", underline = true })
    vim.api.nvim_set_hl(0, "SageMessage", { link = "DiagnosticHint", default = true })
    vim.api.nvim_set_hl(0, "SageTaskProgress", { link = "DiagnosticInfo", default = true })
    vim.api.nvim_set_hl(0, "SageStatusCreated", { fg = "#7aa2f7", italic = true })
    vim.api.nvim_set_hl(0, "SageStatusLoaded", { fg = "#9ece6a", bold = true })
    vim.api.nvim_set_hl(0, "SageStatusFailed", { fg = "#f7768e", underline = true })
    vim.api.nvim_set_hl(0, "SageLazyBracket", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyIcon", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyLabel", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLazyValue", { fg = "#bb9af7" })
    vim.api.nvim_set_hl(0, "SageLink", { fg = "#6495ed", underline = true })

    -- ========================================================================
    -- BUTTON HIGHLIGHTS (Interactive elements)
    -- ========================================================================

    -- Timing buttons [󰇚 12.5ms] [󰒓 8.3ms]
    vim.api.nvim_set_hl(0, "SageButton", { link = "Underlined", default = true })

    -- Lazy trigger buttons [󰘳 cmd: Telescope] [󰈔 ft: lua]
    vim.api.nvim_set_hl(0, "SageLazyTrigger", { link = "DiagnosticInfo", default = true })

    -- Dependency buttons [dep_name]
    vim.api.nvim_set_hl(0, "SageDependency", { link = "Underlined", default = true })

    -- ====
    -- Sage Pack Info Details
    -- ====
    vim.api.nvim_set_hl(0, "SagePackOnlyUs", { fg = "#00ff00" })
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
            vim.api.nvim_set_hl(0, "SageStatusCreated", { fg = "#7aa2f7", italic = true })
            vim.api.nvim_set_hl(0, "SageStatusLoaded", { fg = "#9ece6a", bold = true })
            vim.api.nvim_set_hl(0, "SageStatusFailed", { fg = "#f7768e", underline = true })
            vim.api.nvim_set_hl(0, "SageLazyBracket", { fg = "#bb9af7" })
            vim.api.nvim_set_hl(0, "SageLazyIcon", { fg = "#bb9af7" })
            vim.api.nvim_set_hl(0, "SageLazyLabel", { fg = "#bb9af7" })
            vim.api.nvim_set_hl(0, "SageLazyValue", { fg = "#bb9af7" })
            vim.api.nvim_set_hl(0, "SageLink", { fg = "#6495ed", underline = true })
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
        local manager = self.manager
        local dashboard = manager.container:resolve("dashboard")
        dashboard:open()
    end, { desc = "Open Sage dashboard" })

    vim.api.nvim_create_user_command("SageClose", function()
        local manager = self.manager
        local dashboard = manager.container:resolve("dashboard")
        dashboard:close()
    end, { desc = "Close Sage dashboard" })

    vim.api.nvim_create_user_command("SageToggle", function()
        local dashboard = self.manager.container:resolve("dashboard")
        if dashboard.is_open then
            dashboard:close()
        else
            dashboard:open()
        end
    end, { desc = "Toggle Sage dashboard" })

    vim.api.nvim_create_user_command("SageReload", function()
        local Loader = self.manager.container:resolve("loader")
        Loader:close_all()
        Dashboard:close()
        vim.notify("Sage: loaders and dashboard cleaned up.", vim.log.levels.INFO)
    end, { desc = "Reload Sage loaders and dashboard" })

    vim.api.nvim_create_user_command("SageCleanup", function()
        vim.api.nvim_exec_autocmds("VimLeavePre", {})
    end, { desc = "Trigger Sage cleanup" })

    vim.api.nvim_create_user_command("SageDebugLazy", function(c_opts)
        local pack_name = c_opts.args
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

function Dashboard:debug_log(msg, sub_source)
    sub_source = sub_source or ""
    self.logger:debug("Dashboard-" .. sub_source, msg)
end

return Dashboard
