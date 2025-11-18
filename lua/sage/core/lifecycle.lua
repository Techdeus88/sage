-- ============================================================================
-- Pack Lifecycle management and implementation
-- ============================================================================
local PackLifecycle = {}
PackLifecycle.__index = PackLifecycle

function PackLifecycle.new(pack)
    local self = setmetatable({}, PackLifecycle)
    self.pack = pack
    self.tasks = {}
    self.status = "idle"
    self.progress = 0
    return self
end

function PackLifecycle:add_task(task)
    table.insert(self.tasks, task)
end

function PackLifecycle:get_task(name_or_stage)
    for _, task in ipairs(self.tasks) do
        if task.name == name_or_stage or task.stage == name_or_stage then
            return task
        end
    end
    return nil
end

function PackLifecycle:run_all(ctx)
    self.status = "running"
    local total = #self.tasks
    local completed = 0

    for _, task in ipairs(self.tasks) do
        task:run(ctx)
        completed = completed + 1
        self.progress = math.floor((completed / total) * 100)
        vim.schedule(function()
            self:update_ui()
        end)
    end

    self.status = self:is_success() and "success" or "failed"
    self:update_ui(true)
end

function PackLifecycle:run_task(name_or_stage, ctx)
    local task = self:get_task(name_or_stage)
    if not task then
        vim.notify(
            string.format("No task found for '%s' in pack '%s'", name_or_stage, self.pack.name),
            vim.log.levels.WARN
        )
        return false
    end

    self.status = "running"
    task:run(ctx)

    -- recalc progress
    local total = #self.tasks
    local completed = 0
    for _, t in ipairs(self.tasks) do
        if t.status == "success" or t.status == "failed" then
            completed = completed + 1
        end
    end
    self.progress = math.floor((completed / total) * 100)

    self.status = self:is_success() and "success" or "running"
    self:update_ui()
    return true
end

function PackLifecycle:is_success()
    for _, t in ipairs(self.tasks) do
        if t.status == "failed" then
            return false
        end
    end
    return true
end

function PackLifecycle:update_ui(final)
    local ui = require("sage.ui.dashboard")
    ui:update_pack_progress(self.pack, self.progress, self.status, final)
end

return PackLifecycle
