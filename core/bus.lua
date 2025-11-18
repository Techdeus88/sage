-- ============================================================================
-- Event Dispatcher with deduplication
-- ============================================================================
local Event = {}
Event.__index = Event

Event.listeners = {}
Event._next_id = 0
Event.queue = {}
Event.queued_items = {} -- Track what's already queued

--- Register a listener for an event
---@param event string
---@param callback function
---@return integer listener_id
function Event.on(event, callback)
    if not Event.listeners[event] then
        Event.listeners[event] = {}
    end
    Event._next_id = Event._next_id + 1
    local id = Event._next_id
    Event.listeners[event][id] = callback
    return id
end

--- Emit an event
---@param event string
---@param data any
function Event.emit(event, data)
    local listeners = Event.listeners[event]
    if not listeners then
        return
    end
    for id, callback in pairs(listeners) do
        local ok, err = pcall(callback, data)
        if not ok then
            vim.schedule(function()
                vim.notify(string.format("Event '%s' listener %d failed: %s", event, id, err), vim.log.levels.ERROR)
            end)
        end
    end
end

--- Remove a listener by ID
---@param listener_id integer
function Event.off(listener_id)
    for event, listeners in pairs(Event.listeners) do
        if listeners[listener_id] then
            listeners[listener_id] = nil
            -- Clean up empty event tables
            if vim.tbl_isempty(listeners) then
                Event.listeners[event] = nil
            end
            return true
        end
    end
    return false
end

--- Remove all listeners for an event (optional helper)
---@param event string
function Event.clear(event)
    Event.listeners[event] = nil
end

function Event.add_to_queue(name, fn)
    -- Prevent duplicate queue entries
    if Event.queued_items[name] then
        return -- Already queued
    end

    Event.queued_items[name] = true
    table.insert(Event.queue, { name = name, cb = fn })
end

function Event:run_queue()
    while #Event.queue > 0 do
        local item = table.remove(Event.queue, 1)
        pcall(item.cb)
        -- Remove from tracking after execution
        Event.queued_items[item.name] = nil
    end
end

function Event:clear_queue()
    Event.queue = {}
    Event.queued_items = {}
end

return Event
