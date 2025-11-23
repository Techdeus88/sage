
-- ============================================================================
-- Task Builder - Creates standard task sets for packs
-- sage/core/tasks/builder.lua
-- ============================================================================

local TaskBuilder = {}

function TaskBuilder.create_default_tasks(pack)
    local Task = require("sage.core.tasks.task")
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
            -- Manager is responsible for actually installing.
            -- Here we just assert that it happened.
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

return TaskBuilder
