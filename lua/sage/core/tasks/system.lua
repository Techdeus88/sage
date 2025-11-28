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

-- Wire lifecycle ONLY if there are custom tasks
function TaskSystem.wire_pack(pack)
    local TaskBuilder = require("sage.core.tasks.builder")
    local spec = pack.specs.normalize
    local tasks = TaskBuilder.create_custom_tasks(spec)
    
    if #tasks == 0 then
        return -- No custom tasks, no lifecycle needed
    end
    
    -- Create lifecycle
    pack.lifecycle = Lifecycle.new(pack)
    for _, task in ipairs(tasks) do
        pack.lifecycle:add_task(task)
    end
    
    -- Start lifecycle AFTER pack is loaded
    local listener = bus.on("pack:loaded", function(data)
        if data.name == pack.name then
            pack.lifecycle:run_next()
        end
    end)
    
    pack._task_listeners = { listener }
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