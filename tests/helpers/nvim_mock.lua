-- Mock implementation of Neovim API for testing
local M = {}

-- Track created buffers and windows
local buffers = {}
local windows = {}
local extmarks = {}
local buf_id_counter = 1
local win_id_counter = 1
local extmark_id_counter = 1

function M.create_vim_mock()
    local vim_mock = {
        api = {
            -- Buffer functions
            nvim_create_buf = function(listed, scratch)
                local buf_id = buf_id_counter
                buf_id_counter = buf_id_counter + 1
                buffers[buf_id] = {
                    id = buf_id,
                    lines = {},
                    options = {},
                    vars = {},
                    extmarks = {},
                    namespaces = {},
                }
                return buf_id
            end,

            nvim_buf_is_valid = function(buf)
                return buffers[buf] ~= nil
            end,

            nvim_buf_set_lines = function(buf, start, end_line, strict, lines)
                if not buffers[buf] then
                    error("Invalid buffer: " .. buf)
                end
                buffers[buf].lines = lines
            end,

            nvim_buf_get_lines = function(buf, start, end_line, strict)
                if not buffers[buf] then
                    return {}
                end
                return buffers[buf].lines
            end,

            nvim_buf_line_count = function(buf)
                if not buffers[buf] then
                    return 0
                end
                return #buffers[buf].lines
            end,

            nvim_buf_set_extmark = function(buf, ns_id, line, col, opts)
                if not buffers[buf] then
                    error("Invalid buffer: " .. buf)
                end

                local id = opts and opts.id or extmark_id_counter
                if not opts or not opts.id then
                    extmark_id_counter = extmark_id_counter + 1
                end

                if not buffers[buf].extmarks[ns_id] then
                    buffers[buf].extmarks[ns_id] = {}
                end

                buffers[buf].extmarks[ns_id][id] = {
                    id = id,
                    line = line,
                    col = col,
                    opts = opts or {},
                }

                return id
            end,

            nvim_buf_get_extmark_by_id = function(buf, ns_id, id, opts)
                if not buffers[buf] or not buffers[buf].extmarks[ns_id] then
                    return nil
                end
                local mark = buffers[buf].extmarks[ns_id][id]
                if not mark then
                    return nil
                end
                return { mark.line, mark.col }
            end,

            nvim_buf_del_extmark = function(buf, ns_id, id)
                if buffers[buf] and buffers[buf].extmarks[ns_id] then
                    buffers[buf].extmarks[ns_id][id] = nil
                end
            end,

            nvim_buf_clear_namespace = function(buf, ns_id, line_start, line_end)
                if buffers[buf] and buffers[buf].extmarks[ns_id] then
                    buffers[buf].extmarks[ns_id] = {}
                end
            end,

            nvim_buf_set_var = function(buf, name, value)
                if not buffers[buf] then
                    error("Invalid buffer: " .. buf)
                end
                buffers[buf].vars[name] = value
            end,

            nvim_buf_delete = function(buf, opts)
                buffers[buf] = nil
            end,

            nvim_buf_set_text = function(buf, start_row, start_col, end_row, end_col, replacement)
                if not buffers[buf] then
                    error("Invalid buffer: " .. buf)
                end
                -- Simplified implementation
                if not buffers[buf].lines[start_row + 1] then
                    buffers[buf].lines[start_row + 1] = ""
                end
                buffers[buf].lines[start_row + 1] = replacement[1] or ""
            end,

            -- Window functions
            nvim_open_win = function(buf, enter, config)
                local win_id = win_id_counter
                win_id_counter = win_id_counter + 1
                windows[win_id] = {
                    id = win_id,
                    buf = buf,
                    config = config,
                    options = {},
                }
                return win_id
            end,

            nvim_win_is_valid = function(win)
                return windows[win] ~= nil
            end,

            nvim_win_close = function(win, force)
                windows[win] = nil
            end,

            nvim_win_get_width = function(win)
                if not windows[win] then
                    return 80
                end
                return windows[win].config.width or 80
            end,

            nvim_win_get_height = function(win)
                if not windows[win] then
                    return 24
                end
                return windows[win].config.height or 24
            end,

            nvim_win_get_cursor = function(win)
                return { 1, 0 }
            end,

            nvim_win_set_cursor = function(win, pos)
                -- Mock implementation
            end,

            nvim_set_current_win = function(win)
                -- Mock implementation
            end,

            nvim_get_current_win = function()
                return 1
            end,

            -- Option functions
            nvim_set_option_value = function(name, value, opts)
                local target = opts.buf or opts.win
                if opts.buf and buffers[target] then
                    buffers[target].options[name] = value
                elseif opts.win and windows[target] then
                    windows[target].options[name] = value
                end
            end,

            nvim_get_option_value = function(name, opts)
                local target = opts.buf or opts.win
                if opts.buf and buffers[target] then
                    return buffers[target].options[name]
                elseif opts.win and windows[target] then
                    return windows[target].options[name]
                end
            end,

            -- Namespace functions
            nvim_create_namespace = function(name)
                return #extmarks + 1
            end,

            -- Highlight functions
            nvim_set_hl = function(ns_id, name, val)
                -- Mock implementation
            end,

            -- Autocmd functions
            nvim_create_autocmd = function(event, opts)
                return math.random(1000, 9999)
            end,

            nvim_del_autocmd = function(id)
                -- Mock implementation
            end,

            nvim_exec_autocmds = function(event, opts)
                -- Mock implementation
            end,

            -- User command functions
            nvim_create_user_command = function(name, command, opts)
                -- Mock implementation
            end,
        },

        fn = {
            strdisplaywidth = function(str)
                return #str
            end,
            timer_start = function(delay, callback)
                return math.random(1000, 9999)
            end,
            timer_stop = function(id)
                -- Mock implementation
            end,
        },

        keymap = {
            set = function(mode, lhs, rhs, opts)
                -- Mock implementation
            end,
        },

        log = {
            levels = {
                DEBUG = 0,
                INFO = 1,
                WARN = 2,
                ERROR = 3,
            },
        },

        o = {
            columns = 120,
            lines = 40,
        },

        uv = {
            new_timer = function()
                return {
                    start = function() end,
                    stop = function() end,
                    close = function() end,
                    is_closing = function()
                        return false
                    end,
                }
            end,
        },

        schedule = function(fn)
            fn()
        end,

        schedule_wrap = function(fn)
            return fn
        end,

        defer_fn = function(fn, delay)
            fn()
        end,

        notify = function(msg, level)
            -- Mock implementation
        end,

        cmd = function(command)
            -- Mock implementation
        end,

        inspect = function(obj)
            return tostring(obj)
        end,

        tbl_count = function(tbl)
            local count = 0
            for _ in pairs(tbl) do
                count = count + 1
            end
            return count
        end,
    }

    return vim_mock
end

-- Helper to reset mocks
function M.reset()
    buffers = {}
    windows = {}
    extmarks = {}
    buf_id_counter = 1
    win_id_counter = 1
    extmark_id_counter = 1
end

-- Helper to get internal state for assertions
function M.get_buffers()
    return buffers
end

function M.get_windows()
    return windows
end

function M.get_buffer_extmarks(buf, ns_id)
    if buffers[buf] and buffers[buf].extmarks[ns_id] then
        return buffers[buf].extmarks[ns_id]
    end
    return {}
end

return M
