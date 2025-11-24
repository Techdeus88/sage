local M = {}

M.queue = {}
M.ready = false
M._timer = nil
M._check = nil

-- Internal notify that queues if not ready
local function _notify(msg, level, opts)
    if M.ready then
        vim.notify(msg, level, opts)
    else
        table.insert(M.queue, vim.F.pack_len(msg, level, opts))
    end
end

-- Start the delay mechanism
function M.init()
    if M._timer then
        return
    end -- prevent double init

    local orig = vim.notify
    M._timer = vim.uv.new_timer()
    M._check = vim.uv.new_check()

    local function flush()
        M._timer:stop()
        M._check:stop()
        M.ready = true

        vim.schedule(function()
            for _, notif in ipairs(M.queue) do
                vim.notify(vim.F.unpack_len(notif))
            end
            M.queue = {}
        end)
    end

    -- Check if user's notification system loaded
    M._check:start(function()
        if vim.notify ~= orig then
            flush()
        end
    end)

    -- Fallback after 500ms
    M._timer:start(500, 0, flush)
end

-- Public API for sage to use
function M.notify(msg, level, opts)
    vim.schedule(function()
        _notify(msg, level, opts)
    end)
end

-- Allow users to manually mark ready (advanced use)
function M.mark_ready()
    if not M.ready then
        M._timer:stop()
        M._check:stop()
        M.ready = true
    end
end

return M
