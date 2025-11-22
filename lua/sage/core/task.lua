-- ============================================================================
-- TASK SYSTEM - Integrated with Pack Lifecycle
-- task_system.lua - Place this in sage/core/task_system.lua
-- ============================================================================
local Event = require("sage.core.bus")

local TaskSystem = {}
TaskSystem.__index = TaskSystem

-- ============================================================================
-- Task Definition
-- ============================================================================
local Task = {}
Task.__index = Task

function Task.new(spec)
    local self = setmetatable({}, Task)
    self.id = spec.name  -- unique identifier
    self.name = spec.name
    self.fn = spec.fn  -- function to execute
    self.condition = spec.condition or function() return true end  -- when to run
    self.required = spec.required ~= false  -- default true
    self.status = "pending"  -- pending | running | success | failed | skipped
    self.duration = 0
    self.started_at = nil
    self.ended_at = nil
    self.error = nil
    self.depends = spec.depends or {}  -- other task IDs that must complete first
    self.retry_count = 0
    self.max_retries = spec.max_retries or 0
    return self
end

function Task:can_run(pack)
    -- Check if condition is met
    if not self.condition(pack) then
        return false, "condition not met"
    end

    -- Check if depends are satisfied
    for _, dep_id in ipairs(self.depends) do
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

    local ok, result = pcall(self.fn, pack)

    self.ended_at = vim.loop.hrtime()
    self.duration = (self.ended_at - self.started_at) / 1e6  -- ms

    if ok then
        self.status = "success"
        return true, result
    else
        self.error = result

        -- Retry logic
        if self.retry_count < self.max_retries then
            self.retry_count = self.retry_count + 1
            self.status = "pending"
            return false, string.format("retrying (%d/%d)", self.retry_count, self.max_retries)
        end

        self.status = "failed"
        return false, result
    end
end

function Task:skip(reason)
    self.status = "skipped"
    self.error = reason or "condition not met"
end

-- ============================================================================
-- Lifecycle - Manages task execution for a pack
-- ============================================================================
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(pack)
    local self = setmetatable({}, Lifecycle)
    self.pack = pack
    self.tasks = {}
    self.task_order = {}  -- execution order
    self.current_task_index = 0
    self.completed = false
    return self
end

function Lifecycle:add_task(task)
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

        if task.status == "pending" then
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
            if t.required and t.status ~= "success" and t.status ~= "skipped" then
                all_required_done = false
                break
            end
        end

        if all_required_done then
            self.completed = true
            vim.schedule(function()
                Event.emit("pack:lifecycle:complete", {
                    name = self.pack.specs.normalize.name,
                    pack = self.pack,
                })
            end)
        end

        return false, reason
    end

    -- Emit task start event (scheduled)
    vim.schedule(function()
        Event.emit("pack:task:start", {
            name = self.pack.specs.normalize.name,
            task = task.name,
            task_id = task.id,
            pack = self.pack,
        })
    end)

    -- Run the task
    local ok, result = task:run(self.pack)

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

    return {
        total = total,
        completed = completed,
        required_total = required_total,
        required_completed = required_completed,
        percentage = total > 0 and (completed / total * 100) or 0,
    }
end

-- ============================================================================
-- Task Builder - Creates standard task sets for packs
-- ============================================================================
local TaskBuilder = {}

function TaskBuilder.create_default_tasks(pack)
    local tasks = {}

    -- Task 1: Validate spec
    table.insert(tasks, Task.new({
        id = "validate",
        name = "Validate Spec",
        required = true,
        fn = function(p)
            local spec = p.specs.normalize
            if not spec.name or spec.name == "" then
                error("Pack name is required")
            end
            if not spec.src or spec.src == "" then
                error("Pack source is required")
            end
            return true
        end,
    }))

    -- Task 2: Install (only if not installed)
    table.insert(tasks, Task.new({
        id = "install",
        name = "Install",
        required = true,
        depends = { "validate" },
        condition = function(p)
            return not p.installed
        end,
        fn = function(p)
            -- This will be triggered by the manager's install flow
            -- Just verify it happened
            if not p.installed then
                error("Installation did not complete")
            end
            return true
        end,
    }))

    -- Task 3: Build (conditional)
    table.insert(tasks, Task.new({
        id = "build",
        name = "Build",
        required = false,
        depends = { "install" },
        condition = function(p)
            return p.specs.normalize.data.build ~= nil
        end,
        fn = function(p)
            local build = p.specs.normalize.data.build
            if type(build) == "string" then
                vim.cmd(build)
            elseif type(build) == "function" then
                build()
            end
            return true
        end,
    }))

    -- Task 4: Pre-config hook
    table.insert(tasks, Task.new({
        id = "before_hook",
        name = "Before Hook",
        required = false,
        depends = { "install" },
        condition = function(p)
            return p.specs.normalize.data.before ~= nil
        end,
        fn = function(p)
            local before = p.specs.normalize.data.before
            if type(before) == "function" then
                before()
            end
            return true
        end,
    }))

    -- Task 5: Configure
    table.insert(tasks, Task.new({
        id = "config",
        name = "Configure",
        required = false,
        depends = { "install", "before_hook" },
        condition = function(p)
            return p.specs.normalize.data.config ~= nil
        end,
        fn = function(p)
            local config = p.specs.normalize.data.config
            if type(config) == "function" then
                config()
            end
            return true
        end,
    }))

    -- Task 6: Post-config hook
    table.insert(tasks, Task.new({
        id = "after_hook",
        name = "After Hook",
        required = false,
        depends = { "config" },
        condition = function(p)
            return p.specs.normalize.data.after ~= nil
        end,
        fn = function(p)
            local after = p.specs.normalize.data.after
            if type(after) == "function" then
                after()
            end
            return true
        end,
    }))

    return tasks
end

-- ============================================================================
-- Integration with Manager
-- ============================================================================
function TaskSystem.wire_pack(pack)
    -- Create lifecycle if not exists
    if not pack.lifecycle then
        pack.lifecycle = Lifecycle.new(pack)
    end

    -- Add default tasks
    local tasks = TaskBuilder.create_default_tasks(pack)
    for _, task in ipairs(tasks) do
        pack.lifecycle:add_task(task)
    end

    -- Listen to pack events and advance tasks
    Event.on("pack:install:finish", function(data)
        if data.name == pack.specs.normalize.name then
            pack.installed = true
            vim.schedule(function()
                pack.lifecycle:run_next()
            end)
        end
    end)

    Event.on("pack:config:finish", function(data)
        if data.name == pack.specs.normalize.name then
            pack.loaded = true
            vim.schedule(function()
                pack.lifecycle:run_next()
            end)
        end
    end)
end

-- ============================================================================
-- Add task progress to pack object
-- ============================================================================
function TaskSystem.add_methods_to_pack(Pack)
    function Pack:get_task_progress()
        if not self.lifecycle then
            return { total = 0, completed = 0, percentage = 0 }
        end
        return self.lifecycle:get_progress()
    end

    function Pack:get_current_task()
        if not self.lifecycle then
            return nil
        end

        local task, _ = self.lifecycle:get_next_runnable_task()
        return task
    end

    function Pack:run_tasks()
        if not self.lifecycle then
            return false, "no lifecycle"
        end

        return self.lifecycle:run_next()
    end
end

return {
    Task = Task,
    Lifecycle = Lifecycle,
    TaskBuilder = TaskBuilder,
    TaskSystem = TaskSystem,
}
