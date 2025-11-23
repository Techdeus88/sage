-- ============================================================================
-- system.lua (Fixed)
-- ============================================================================

local TaskSystem = {}
TaskSystem.__index = TaskSystem

-- Optional: track wired packs so we don't double-wire
local wired_packs = setmetatable({}, { __mode = "k" }) -- weak keys (pack -> true)

-- ============================================================================
-- Integration with Manager
-- ============================================================================
function TaskSystem.wire_pack(pack)
    if not pack then
        return
    end

    -- Avoid wiring the same pack multiple times
    if wired_packs[pack] then
        return
    end
    wired_packs[pack] = true

    local TaskBuilder = require("sage.core.tasks.builder")
    local TaskLifecycle = require("sage.core.tasks.lifecycle")
    local Event = require("sage.core.bus")

    -- Create lifecycle if not exists
    if not pack.lifecycle then
        pack.lifecycle = TaskLifecycle.new(pack)
    end

    -- Add default tasks
    local tasks = TaskBuilder.create_default_tasks(pack)
    for _, task in ipairs(tasks) do
        pack.lifecycle:add_task(task)
    end

    -- FIXED: Store event listener IDs for potential cleanup
    pack._task_event_listeners = pack._task_event_listeners or {}

    -- Listen to pack events and advance tasks
    local install_listener = Event.on("pack:install:finish", function(data)
        -- FIXED: Added validation checks
        if not pack or not pack.specs or not pack.specs.normalize then
            return
        end

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
    table.insert(pack._task_event_listeners, { event = "pack:install:finish", id = install_listener })

    local config_listener = Event.on("pack:config:finish", function(data)
        -- FIXED: Added validation checks
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

-- FIXED: Added cleanup function
function TaskSystem.unwire_pack(pack)
    if not pack or not pack._task_event_listeners then
        return
    end

    local Event = require("sage.core.bus")

    for _, listener in ipairs(pack._task_event_listeners) do
        pcall(function()
            if type(Event.off) == "function" then
                Event.off(listener.event, listener.id)
            end
        end)
    end

    pack._task_event_listeners = {}
    wired_packs[pack] = nil
end

return TaskSystem
