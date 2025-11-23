
-- ============================================================================
-- TASK SYSTEM - Integrated with Pack Lifecycle
-- sage/core/task_system.lua
-- ============================================================================

local TaskSystem = {}
TaskSystem.__index = TaskSystem

-- Optional: track wired packs so we don't double-wire
local wired_packs = setmetatable({}, { __mode = "k" }) -- weak keys (pack -> true)

-- ============================================================================
-- Integration with Manager
-- ============================================================================
function TaskSystem.wire_pack(pack)
    -- Avoid wiring the same pack multiple times
    if wired_packs[pack] then
        return
    end
    wired_packs[pack] = true

    local TaskBuilder   = require("sage.core.tasks.builder")
    local TaskLifecycle = require("sage.core.tasks.lifecycle")
    local Event         = require("sage.core.bus")

    -- Create lifecycle if not exists
    if not pack.lifecycle then
        pack.lifecycle = TaskLifecycle.new(pack)
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
            -- run_next can do notifications, so keep it off fast event
            vim.schedule(function()
                if pack.lifecycle then
                    pack.lifecycle:run_next()
                end
            end)
        end
    end)

    Event.on("pack:config:finish", function(data)
        if data.name == pack.specs.normalize.name then
            pack.loaded = true
            vim.schedule(function()
                if pack.lifecycle then
                    pack.lifecycle:run_next()
                end
            end)
        end
    end)
end

return TaskSystem
