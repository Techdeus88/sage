
-- ============================================================================
-- Task definition
-- sage/core/tasks/task.lua
-- ============================================================================

local task = {}
task.__index = task

function task.new(spec)
    local self = setmetatable({}, task)

    -- Prefer explicit id, fall back to name
    self.id   = spec.id or spec.name
    self.name = spec.name or spec.id

    self.fn        = spec.fn                               -- function to execute
    self.condition = spec.condition or function() return true end
    self.required  = spec.required ~= false                -- default true
    self.status    = "pending"                             -- pending | running | success | failed | skipped
    self.duration  = 0
    self.started_at = nil
    self.ended_at   = nil
    self.error      = nil
    self.depends    = spec.depends or {}                   -- other task ids that must complete first
    self.retry_count = 0
    self.max_retries = spec.max_retries or 0

    return self
end

function task:can_run(pack)
    -- check if condition is met
    if not self.condition(pack) then
        return false, "condition not met"
    end

    -- check if depends are satisfied
    for _, dep_id in ipairs(self.depends) do
        local dep_task = pack.lifecycle and pack.lifecycle:get_task(dep_id)
        if not dep_task or dep_task.status ~= "success" then
            return false, "waiting for dependency: " .. dep_id
        end
    end

    return true, "ready"
end

function task:run(pack)
    self.status = "running"
    self.started_at = vim.loop.hrtime()

    local ok, result = pcall(self.fn, pack)

    self.ended_at = vim.loop.hrtime()
    self.duration = (self.ended_at - self.started_at) / 1e6  -- ms

    if ok then
        self.status = "success"
        return true, result
    else
        self.error = result

        -- retry logic
        if self.retry_count < self.max_retries then
            self.retry_count = self.retry_count + 1
            self.status = "pending"
            return false, string.format("retrying (%d/%d)", self.retry_count, self.max_retries)
        end

        self.status = "failed"
        return false, result
    end
end

function task:skip(reason)
    self.status = "skipped"
    self.error = reason or "condition not met"
end

return task
