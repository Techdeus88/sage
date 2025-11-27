-- ============================================================================
-- FILE 1: sage/core/tasks/system.lua (FIXED)
-- ============================================================================

local TaskSystem = {}
TaskSystem.__index = TaskSystem

-- Module-level dependencies
local bus = nil
local logger = nil

-- Track wired packs
local wired_packs = setmetatable({}, { __mode = "k" })

function TaskSystem.init(deps)
    bus = deps.bus
    logger = deps.logger
end

function TaskSystem.wire_pack(pack)
    if not pack then
        return
    end
    if wired_packs[pack] then
        return
    end
    
    wired_packs[pack] = true
    
    local name = pack:get_name()

    local TaskBuilder = require("sage.core.tasks.builder")
    local TaskLifecycle = require("sage.core.tasks.lifecycle")

    -- Create lifecycle if not exists
    if not pack.lifecycle then
        pack.lifecycle = TaskLifecycle.new(pack)
    end

    -- Add default tasks
    local tasks = TaskBuilder.create_default_tasks()
    for _, task in ipairs(tasks) do
        pack.lifecycle:add_task(task)
    end

    pack._task_event_listeners = pack._task_event_listeners or {}

    -- ✅ FIX: Listen to pack:install:finish to trigger lifecycle
    -- This is the ONLY place lifecycle should start
    if bus then
        local install_listener = bus.on("pack:install:finish", function(data)
            if not pack or not pack.specs or not pack.specs.normalize then
                return
            end

            if data.name == pack.specs.normalize.name then
                -- ✅ CRITICAL: Mark as installed
                pack.installed = true
                
                -- ✅ Start lifecycle NOW (after installation)
                vim.schedule(function()
                    if pack.lifecycle and not pack.lifecycle.started then
                        pack.lifecycle.started = true
                        pack.lifecycle:run_next()
                    end
                end)
            end
        end)
        table.insert(pack._task_event_listeners, { event = "pack:install:finish", id = install_listener })
    end

    if logger then
        logger:debug("TaskSystem", string.format("Wired pack '%s'", name))
    end
end

function TaskSystem.unwire_pack(pack)
    if not pack or not pack._task_event_listeners then
        return
    end

    if bus and type(bus.off) == "function" then
        for _, listener in ipairs(pack._task_event_listeners) do
            pcall(function()
                bus.off(listener.event, listener.id)
            end)
        end
    end

    pack._task_event_listeners = {}
    wired_packs[pack] = nil

    if logger then
        logger:debug("TaskSystem", string.format("Unwired pack '%s'", pack:get_name()))
    end
end

return TaskSystem