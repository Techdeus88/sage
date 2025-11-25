-- ============================================================================
-- LOGGER SERVICE - Fixed and Event-Integrated
-- ============================================================================
local Logger = {}
Logger.__index = Logger
Logger._singleton = nil

Logger.LEVELS = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }
Logger.LEVEL_NAMES = { [0] = "TRACE", [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR", [5] = "FATAL" }
local ns_id = vim.api.nvim_create_namespace("sage-log")

function Logger.new(opts)
    local self = setmetatable({}, Logger)
    self.logs = {}
    self.log_counter = 0
    self.max_log = (opts and opts.max_log) or 1000
    self.level = (opts and opts.level) or "INFO"
    self.log_buf = nil
    self.log_win = nil
    self.last_rendered_index = 0
    self.bus = nil -- Will be set after container is initialized
    return self
end

function Logger:get_instance(opts)
    if not Logger._singleton then
        Logger._singleton = Logger.new(opts)
    end
    return Logger._singleton
end

function Logger:set_bus(bus)
    self.bus = bus
end

function Logger:log_event(level, source, msg)
    self.log_counter = self.log_counter + 1
    self.logs = self.logs or {}

    local date = os.date("%H:%M:%S")
    local src = string.format("[%s] ", source)
    local entry = {
        text = string.format("%s %-40s %s", date, src, msg),
        index = self.log_counter,
        level = level,
        source = source,
        timestamp = vim.loop.hrtime(),
    }

    table.insert(self.logs, entry)

    -- Remove old logs if we exceed max
    if #self.logs > self.max_log then
        table.remove(self.logs, 1)
        self.last_rendered_index = math.max(0, self.last_rendered_index - 1)
    end

    -- Emit to event bus
    if self.bus then
        self.bus.emit("logger:log", {
            level = level,
            source = source,
            message = msg,
            timestamp = vim.loop.hrtime(),
        })
    end

    self:render_logs()
end

function Logger:render_logs()
    if not (self.log_buf and vim.api.nvim_buf_is_valid(self.log_buf)) then
        return
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.log_buf })

    for _, item in ipairs(self.logs or {}) do
        if item.index > self.last_rendered_index then
            local lnum = vim.api.nvim_buf_line_count(self.log_buf)
            local width = math.max(3, #tostring(self.log_counter))
            local idx = string.format("[%0" .. width .. "d]", item.index)
            local line_text = string.format("%s %s", idx, item.text)

            vim.api.nvim_buf_set_lines(self.log_buf, -1, -1, false, { line_text })
            self.last_rendered_index = item.index
        end
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = self.log_buf })

    if self.log_win and vim.api.nvim_win_is_valid(self.log_win) then
        local line_count = vim.api.nvim_buf_line_count(self.log_buf)
        vim.api.nvim_win_set_cursor(self.log_win, { line_count, 0 })
    end
end

function Logger:open_log_window()
    if
        self.log_buf
        and vim.api.nvim_buf_is_valid(self.log_buf)
        and self.log_win
        and vim.api.nvim_win_is_valid(self.log_win)
    then
        return
    end

    if not self.log_buf or not vim.api.nvim_buf_is_valid(self.log_buf) then
        self.log_buf = vim.api.nvim_create_buf(false, true)
        self.last_rendered_index = 0

        vim.bo[self.log_buf].buftype = "nofile"
        vim.bo[self.log_buf].bufhidden = "wipe"
        vim.bo[self.log_buf].swapfile = false
        vim.bo[self.log_buf].modifiable = false
    end

    if not self.log_win or not vim.api.nvim_win_is_valid(self.log_win) then
        vim.cmd("botright split SageLog")
        self.log_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(self.log_win, self.log_buf)
        vim.api.nvim_win_set_height(self.log_win, 20)

        -- Add close keymap to the log buffer
        vim.keymap.set("n", "q", function()
            self:close_log_window()
        end, { buffer = self.log_buf, silent = true, desc = "Close log window" })

        vim.keymap.set("n", "<Esc>", function()
            self:close_log_window()
        end, { buffer = self.log_buf, silent = true, desc = "Close log window" })
    end

    self:render_logs()
end

function Logger:close_log_window()
    if self.log_win and vim.api.nvim_win_is_valid(self.log_win) then
        vim.api.nvim_win_close(self.log_win, true)
        self.log_win = nil
    end
end

function Logger:clear_logs()
    self.logs = {}
    self.log_counter = 0
    self.last_rendered_index = 0

    if self.log_buf and vim.api.nvim_buf_is_valid(self.log_buf) then
        vim.api.nvim_set_option_value("modifiable", true, { buf = self.log_buf })
        vim.api.nvim_buf_set_lines(self.log_buf, 0, -1, false, {})
        vim.api.nvim_set_option_value("modifiable", false, { buf = self.log_buf })
    end
end

function Logger:trace(source, message)
    self:log_event(self.LEVELS.TRACE, source, message)
end

function Logger:debug(source, message)
    self:log_event(self.LEVELS.DEBUG, source, message)
end

function Logger:info(source, message)
    self:log_event(self.LEVELS.INFO, source, message)
end

function Logger:warn(source, message)
    self:log_event(self.LEVELS.WARN, source, message)
end

function Logger:error(source, message)
    self:log_event(self.LEVELS.ERROR, source, message)
end

function Logger:fatal(source, message)
    self:log_event(self.LEVELS.FATAL, source, message)
end

function Logger:echo_message(level, source, msg)
    local hl_map = {
        [self.LEVELS.TRACE] = "Comment",
        [self.LEVELS.DEBUG] = "Comment",
        [self.LEVELS.INFO] = "Identifier",
        [self.LEVELS.WARN] = "WarningMsg",
        [self.LEVELS.ERROR] = "ErrorMsg",
        [self.LEVELS.FATAL] = "ErrorMsg",
    }

    local hl_group = hl_map[level] or "None"
    local full_msg = string.format("[%s] %s: %s", self.LEVEL_NAMES[level], source, msg)

    vim.api.nvim_echo({ { full_msg, hl_group } }, true, {})
end

function Logger:get_logs(limit)
    limit = limit or 1000
    local start_idx = math.max(1, #self.logs - limit + 1)
    local recent = {}
    for i = start_idx, #self.logs do
        table.insert(recent, vim.deepcopy(self.logs[i]))
    end
    return recent
end

return Logger
