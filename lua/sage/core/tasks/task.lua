-- ============================================================================
-- FILE 4: sage/core/tasks/task.lua (NO CHANGES NEEDED - Already Good!)
-- ============================================================================

local Task = {}
Task.__index = Task

-- Module-level dependencies
local bus = nil
local logger = nil

function Task.init(deps)
    bus = deps.bus
    logger = deps.logger
end

function Task.new(spec)
    local self = setmetatable({}, Task)

    self.id = spec.id or spec.name
    self.name = spec.name or spec.id
    self.fn = spec.fn
    self.condition = spec.condition or function() return true end
    self.required = spec.required ~= false
    self.status = "pending"
    self.duration = 0
    self.started_at = nil
    self.ended_at = nil
    self.error = nil
    self.depends = spec.depends or {}
    self.retry_count = 0
    self.max_retries = spec.max_retries or 0

    return self
end

function Task:can_run(pack)
    if not pack then
        return false, "pack is nil"
    end

    local ok, condition_result = pcall(self.condition, pack)
    if not ok or not condition_result then
        return false, "condition not met"
    end

    for _, dep_id in ipairs(self.depends) do
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

function Task:run(pack)
    self.status = "running"
    self.started_at = vim.loop.hrtime()

    if logger then
        logger:debug("Task", string.format("Running task '%s' for pack '%s'", self.name, pack:get_name()))
    end

    local ok, result = pcall(self.fn, pack)

    self.ended_at = vim.loop.hrtime()
    self.duration = (self.ended_at - self.started_at) / 1e6

    if ok then
        self.status = "success"
        if logger then
            logger:debug("Task", string.format("Task '%s' completed in %.2fms", self.name, self.duration))
        end
        return true, result
    else
        self.error = result
        self.status = "failed"
        if logger then
            logger:error("Task", string.format("Task '%s' failed: %s", self.name, tostring(result)))
        end
        return false, result
    end
end

function Task:skip(reason)
    self.status = "skipped"
    self.error = reason
    if logger then
        logger:debug("Task", string.format("Task '%s' skipped: %s", self.name, reason or "condition not met"))
    end
end

return Task