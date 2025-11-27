-- ============================================================================
-- builder.lua (Fixed)
-- ============================================================================

local TaskBuilder = {}

function TaskBuilder.create_default_tasks()
    local Task = require("sage.core.tasks.task")
    local tasks = {}

    -- Task 1: Validate spec
    table.insert(
        tasks,
        Task.new({
            id = "validate",
            name = "Validate Spec",
            required = true,
            fn = function(p)
                -- FIXED: Added nil checks
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack or spec is invalid")
                end
                local spec = p.specs.normalize
                if not spec.name or spec.name == "" then
                    error("Pack name is required")
                end
                if not spec.src or spec.src == "" then
                    error("Pack source is required")
                end
                return true
            end,
        })
    )

    -- Task 2: Install (only if not installed)
    table.insert(
        tasks,
        Task.new({
            id = "install",
            name = "Install",
            required = true,
            -- depends = { "validate" },
            condition = function(p)
                return p and p.installed
            end,
            fn = function(p)
                -- Manager is responsible for actually installing.
                -- Here we just assert that it happened.
                if not p or not p.installed then
                    error("Installation did not complete")
                end
                -- p:set_installed(true)
                return true
            end,
        })
    )

    -- Task 3: Build (conditional)
    table.insert(
        tasks,
        Task.new({
            id = "build",
            name = "Build",
            required = false,
            -- depends = { "install" },
            condition = function(p)
                return p and p.specs and p.specs.normalize and p.specs.normalize.data.build ~= nil
            end,
            fn = function(p)
                -- FIXED: Added nil checks
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local commands = require("sage.commands")
                local spec = p.specs.normalize
                local build = spec.data.build

                if build then
                    local path = Sage.plugin_path(spec.name)
                    commands.build(spec, path)
                end
                return true
            end,
        })
    )

    -- Task 4: Pre-config hook
    table.insert(
        tasks,
        Task.new({
            id = "before_hook",
            name = "Before Hook",
            required = false,
            -- depends = { "install" },
            condition = function(p)
                return p and p.enabled and p.specs and p.specs.normalize and p.specs.normalize.data.before ~= nil
            end,
            fn = function(p)
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local before = p.specs.normalize.data.before
                if type(before) == "function" then
                    before()
                end
                return true
            end,
        })
    )

    -- Task 5: Configure (NOW REQUIRED)
    table.insert(
        tasks,
        Task.new({
            id = "config",
            name = "Configure",
            required = true, -- CHANGED: Config is now REQUIRED
            -- depends = { "install" },
            condition = function(p)
                -- Config task runs if pack has a config function
                return p and p.enabled and p.specs and p.specs.normalize and p.specs.normalize.data.config ~= nil
            end,
            fn = function(p)
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local config = p.specs.normalize.data.config
                if type(config) == "function" then
                    -- This is where the actual config function runs
                    -- NOT in the Loader!
                    config()
                end
                return true
            end,
        })
    )

    -- Task 6: Post-config hook
    table.insert(
        tasks,
        Task.new({
            id = "after_hook",
            name = "After Hook",
            required = false,
            -- depends = { "config" },
            condition = function(p)
                return p and p.enabled and p.specs and p.specs.normalize and p.specs.normalize.data.after ~= nil
            end,
            fn = function(p)
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local after = p.specs.normalize.data.after
                if type(after) == "function" then
                    after()
                end
                return true
            end,
        })
    )

    return tasks
end

return TaskBuilder
