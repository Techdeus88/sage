-- ============================================================================
-- lifecycle.lua (Fixed)
-- ============================================================================
local Event = require("sage.core.bus")

local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(pack)
    local self = setmetatable({}, Lifecycle)
    self.pack = pack
    self.tasks = {}
    self.task_order = {} -- execution order
    self.current_task_index = 0
    self.completed = false
    return self
end

function Lifecycle:add_task(task)
    if not task or not task.id then
        return
    end
    self.tasks[task.id] = task
    table.insert(self.task_order, task.id)
end

function Lifecycle:get_task(task_id)
    return self.tasks[task_id]
end

function Lifecycle:get_next_runnable_task()
    for i = self.current_task_index + 1, #self.task_order do
        local task_id = self.task_order[i]
        local task = self.tasks[task_id]

        if task and task.status == "pending" then
            local can_run, reason = task:can_run(self.pack)
            if can_run then
                self.current_task_index = i
                return task
            elseif task.required then
                -- Required task can't run - we're blocked
                return nil, reason
            else
                -- Optional task can't run - skip it
                task:skip(reason)
            end
        end
    end

    return nil, "no more tasks"
end

function Lifecycle:run_next()
    local task, reason = self:get_next_runnable_task()

    if not task then
        -- Check if all required tasks are complete
        local all_required_done = true
        for _, task_id in ipairs(self.task_order) do
            local t = self.tasks[task_id]
            if t and t.required and t.status ~= "success" and t.status ~= "skipped" then
                all_required_done = false
                break
            end
        end

        if all_required_done and not self.completed then
            self.completed = true
            -- FIXED: Added nil check for pack
            if self.pack and self.pack.specs and self.pack.specs.normalize then
                vim.schedule(function()
                    Event.emit("pack:lifecycle:complete", {
                        name = self.pack.specs.normalize.name,
                        pack = self.pack,
                    })
                end)
            end
        end

        return false, reason
    end

    -- FIXED: Added nil check for pack before emitting
    if self.pack and self.pack.specs and self.pack.specs.normalize then
        -- Emit task start event (scheduled)
        vim.schedule(function()
            Event.emit("pack:task:start", {
                name = self.pack.specs.normalize.name,
                task = task.name,
                task_id = task.id,
                pack = self.pack,
            })
        end)
    end

    -- Run the task (synchronous for now)
    local ok, result = task:run(self.pack)

    -- FIXED: Added nil check for pack before emitting
    if self.pack and self.pack.specs and self.pack.specs.normalize then
        -- Emit task complete event (scheduled)
        vim.schedule(function()
            Event.emit("pack:task:complete", {
                name = self.pack.specs.normalize.name,
                task = task.name,
                task_id = task.id,
                status = task.status,
                duration = task.duration,
                error = task.error,
                pack = self.pack,
            })
        end)
    end

    -- Continue with next task if this one succeeded
    if ok then
        return self:run_next()
    end

    return false, result
end

function Lifecycle:get_progress()
    local total = 0
    local completed = 0
    local required_total = 0
    local required_completed = 0

    for _, task_id in ipairs(self.task_order) do
        local task = self.tasks[task_id]
        if task then
            total = total + 1

            if task.status == "success" or task.status == "skipped" then
                completed = completed + 1
            end

            if task.required then
                required_total = required_total + 1
                if task.status == "success" then
                    required_completed = required_completed + 1
                end
            end
        end
    end

    return {
        total = total,
        completed = completed,
        required_total = required_total,
        required_completed = required_completed,
        percentage = total > 0 and (completed / total * 100) or 0,
    }
end

return Lifecycle
