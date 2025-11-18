local Task = {}
Task.__index = Task

function Task.new(name, fn)
    local self = setmetatable({}, Task)
    self.name = name
    self.fn = fn
    self.status = "idle"   -- idle | running | success | failed
    self.duration = 0
    self.started_at = nil
    self.ended_at = nil
    return self
end

function Task:run(ctx)
    self.status = "running"
    self.started_at = vim.loop.hrtime()
    local ok, err = pcall(self.fn, ctx)
    self.ended_at = vim.loop.hrtime()
    self.duration = (self.ended_at - self.started_at) / 1e6 -- ms
    if ok then
        self.status = "success"
    else
        self.status = "failed"
        self.error = err
    end
end

return Task
