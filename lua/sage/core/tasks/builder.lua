
-- ============================================================================
-- FILE 3: sage/core/tasks/builder.lua (FIXED)
-- ============================================================================

local TaskBuilder = {}

function TaskBuilder.create_default_tasks()
    local Task = require("sage.core.tasks.task")
    local tasks = {}

    -- ============================================================================
    -- Task 1: Validate Spec (runs immediately)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "validate",
            name = "Validate Spec",
            required = true,
            condition = function(p)
                -- ✅ Always runs (no pack.installed check)
                return true
            end,
            fn = function(p)
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

    -- ============================================================================
    -- Task 2: Install Check (blocks until pack.installed = true)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "install",
            name = "Install",
            required = true,
            condition = function(p)
                -- ✅ CRITICAL: Block until installed
                return p and p.installed == true
            end,
            fn = function(p)
                if not p or not p.installed then
                    error("Pack not installed yet")
                end
                -- Installation already done by Manager
                return true
            end,
        })
    )

    -- ============================================================================
    -- Task 3: Build (conditional, after install)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "build",
            name = "Build",
            required = false,
            condition = function(p)
                return p
                    and p.installed == true
                    and p.specs
                    and p.specs.normalize
                    and p.specs.normalize.data.build ~= nil
            end,
            fn = function(p)
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local spec = p.specs.normalize
                local build = spec.data.build

                if build and type(build) == "string" then
                    local path = p:get_path()
                    if not path then
                        error("Pack path not available")
                    end

                    -- Execute build command
                    vim.notify(string.format("Building %s...", spec.name), vim.log.levels.INFO)
                    local result = vim.system(vim.split(build, " "), { cwd = path }):wait()
                    
                    if result.code ~= 0 then
                        error(string.format("Build failed with code %d: %s", result.code, result.stderr or ""))
                    end
                    
                    vim.notify(string.format("Build successful for %s", spec.name), vim.log.levels.INFO)
                end
                return true
            end,
        })
    )

    -- ============================================================================
    -- Task 4: Before Hook (conditional, after install)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "before_hook",
            name = "Before Hook",
            required = false,
            condition = function(p)
                return p
                    and p.installed == true
                    and p.specs
                    and p.specs.normalize
                    and p.specs.normalize.data.before ~= nil
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

    -- ============================================================================
    -- Task 5: Configure (required, after install)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "config",
            name = "Configure",
            required = true,
            condition = function(p)
                -- ✅ Config runs if pack is installed AND has config function
                return p
                    and p.installed == true
                    and p.specs
                    and p.specs.normalize
                    and p.specs.normalize.data.config ~= nil
            end,
            fn = function(p)
                if not p or not p.specs or not p.specs.normalize then
                    error("Pack spec is invalid")
                end

                local config = p.specs.normalize.data.config
                if type(config) == "function" then
                    -- ✅ This is where user config runs
                    local start_time = vim.loop.hrtime()
                    config()
                    local duration = (vim.loop.hrtime() - start_time) / 1e6
                    
                    -- Store config timing
                    p.times = p.times or {}
                    p.times.config_duration = string.format("%.2f", duration)
                end
                return true
            end,
        })
    )

    -- ============================================================================
    -- Task 6: After Hook (conditional, after config)
    -- ============================================================================
    table.insert(
        tasks,
        Task.new({
            id = "after_hook",
            name = "After Hook",
            required = false,
            condition = function(p)
                return p
                    and p.installed == true
                    and p.specs
                    and p.specs.normalize
                    and p.specs.normalize.data.after ~= nil
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

-- ============================================================================
-- TASK LIFECYCLE: Only for custom tasks
-- ============================================================================
function TaskBuilder.create_custom_tasks(spec)
    local tasks = {}
    
    -- Build task (if specified)
    if spec.data.build then
        table.insert(tasks, Task.new({
            id = "build",
            name = "Build",
            required = true,
            fn = function(pack)
                local path = pack:get_path()
                local build_cmd = spec.data.build
                
                local result = vim.system(
                    vim.split(build_cmd, " "),
                    { cwd = path }
                ):wait()
                
                if result.code ~= 0 then
                    error("Build failed: " .. (result.stderr or ""))
                end
            end
        }))
    end
    
    -- Before hook
    if spec.data.before then
        table.insert(tasks, Task.new({
            id = "before",
            name = "Before Hook",
            required = false,
            fn = spec.data.before
        }))
    end
    
    -- After hook  
    if spec.data.after then
        table.insert(tasks, Task.new({
            id = "after",
            name = "After Hook",
            required = false,
            fn = spec.data.after
        }))
    end
    
    return tasks
end
    
return TaskBuilder