-- render_queue.lua
local RenderQueue = {}
RenderQueue.__index = RenderQueue

function RenderQueue.new()
    local self = setmetatable({}, RenderQueue)
    self.queue = {}
    self.scheduled = false
    self.locked = false
    return self
end

function RenderQueue:push(fn, ...)
    assert(type(fn) == "function", "RenderQueue:push(fn) requires function")

    table.insert(self.queue, { fn = fn, args = { ... } })

    if not self.scheduled then
        self.scheduled = true
        vim.schedule(function()
            self:flush()
        end)
    end
end

function RenderQueue:flush()
    if self.locked then
        return
    end
    self.locked = true

    -- take current queue, reset to empty
    local jobs = self.queue
    self.queue = {}
    self.scheduled = false

    for _, job in ipairs(jobs) do
        local ok, err = pcall(job.fn, unpack(job.args))
        if not ok then
            vim.notify("RenderQueue error: " .. tostring(err), vim.log.levels.ERROR)
        end
    end

    self.locked = false

    -- if more were pushed during flush, run again
    if #self.queue > 0 then
        self:flush()
    end
end

return RenderQueue
