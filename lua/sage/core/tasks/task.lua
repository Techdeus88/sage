-- ============================================================================
-- task.lua (Fixed)
-- ============================================================================

local task = {}
task.__index = task

function task.new(spec)
    local self = setmetatable({}, task)

    -- Prefer explicit id, fall back to name
    self.id = spec.id or spec.name
    self.name = spec.name or spec.id

    self.fn = spec.fn -- function to execute
    self.condition = spec.condition or function()
        return true
    end
    self.required = spec.required ~= false -- default true
    self.status = "pending" -- pending | running | success | failed | skipped
    self.duration = 0
    self.started_at = nil
    self.ended_at = nil
    self.error = nil
    self.depends = spec.depends or {} -- other task ids that must complete first
    self.retry_count = 0
    self.max_retries = spec.max_retries or 0

    return self
end

function task:can_run(pack)
    if not pack then
        return false, "pack is nil"
    end

    -- check if condition is met
    local ok, condition_result = pcall(self.condition, pack)
    if not ok or not condition_result then
        return false, "condition not met"
    end

    -- check if depends are satisfied
    for _, dep_id in ipairs(self.depends) do
        -- FIXED: Added nil check for lifecycle
        if not pack.lifecycle then
            return false, "pack has no lifecycle"
        end

        local dep_task = pack.lifecycle:get_task(dep_id)
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
    self.duration = (self.ended_at - self.started_at) / 1e6 -- ms

    if ok then
        self.status = "success"
        return true, result
    else
        self.error = result
    end
end

return task
