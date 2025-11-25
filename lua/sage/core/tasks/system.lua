-- ============================================================================
-- system.lua
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

    -- Listen to pack events
    if bus then
        local install_listener = bus.on("pack:install:finish", function(data)
            if not pack or not pack.specs or not pack.specs.normalize then
                return
            end

            if data.name == pack.specs.normalize.name then
                pack.installed = true
                vim.schedule(function()
                    if pack.lifecycle then
                        pack.lifecycle:run_next()
                    end
                end)
            end
        end)
        table.insert(pack._task_event_listeners, { event = "pack:install:finish", id = install_listener })

        local config_listener = bus.on("pack:config:finish", function(data)
            if not pack or not pack.specs or not pack.specs.normalize then
                return
            end

            if data.name == pack.specs.normalize.name then
                pack.loaded = true
                vim.schedule(function()
                    if pack.lifecycle then
                        pack.lifecycle:run_next()
                    end
                end)
            end
        end)
        table.insert(pack._task_event_listeners, { event = "pack:config:finish", id = config_listener })
    end

    if logger then
        logger:debug("TaskSystem", string.format("Wired pack '%s'", pack:get_name()))
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