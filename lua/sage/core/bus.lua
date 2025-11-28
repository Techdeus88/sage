-- ============================================================================
-- Bus Dispatcher with deduplication
-- ============================================================================
local Bus = {}
Bus.__index = Bus

Bus.listeners = {}
Bus._next_id = 0
Bus.queue = {}
Bus.queued_items = {} -- Track what's already queued
Bus.logger = nil
Bus.utils = nil

function Bus:init(container)
    if not self.container then
        self.container = container
        self.logger = self.container:resolve("logger")
        self.utils = self.container:resolve("utils")
    end
end

--- Register a listener for an event
---@param event string
---@param callback function
---@return integer listener_id
function Bus.on(event, callback)
    if not Bus.listeners[event] then
        Bus.listeners[event] = {}
    end
    Bus._next_id = Bus._next_id + 1
    local id = Bus._next_id
    Bus.listeners[event][id] = callback
    return id
end

--- Emit an event
---@param event string
---@param data any
function Bus.emit(event, data)
    local listeners = Bus.listeners[event]
    if not listeners then
        return
    end
    for id, callback in pairs(listeners) do
        local ok, err = pcall(callback, data)
        if not ok then
            vim.schedule(function()
                vim.notify(string.format("Bus '%s' listener %d failed: %s", event, id, err), vim.log.levels.ERROR)
            end)
        end
    end
    Bus.log_event(event, data, Bus)
end

function Bus.log_event(event, data, self)
    self.logger:debug("Bus", string.format("%s -> triggered by %s -> with status %s", event, data.name, data.status))
end

--- Remove a listener by ID
---@param listener_id integer
function Bus.off(listener_id)
    for event, listeners in pairs(Bus.listeners) do
        if listeners[listener_id] then
            listeners[listener_id] = nil
            -- Clean up empty event tables
            if vim.tbl_isempty(listeners) then
                Bus.listeners[event] = nil
            end
            return true
        end
    end
    return false
end

--- Remove all listeners for an event (optional helper)
---@param event string
function Bus.clear(event)
    Bus.listeners[event] = nil
end

function Bus.add_to_queue(name, fn)
    -- Prevent duplicate queue entries
    if Bus.queued_items[name] then
        return -- Already queued
    end

    Bus.queued_items[name] = true
    table.insert(Bus.queue, { name = name, cb = fn })
end

function Bus:run_queue()
    while #Bus.queue > 0 do
        local item = table.remove(Bus.queue, 1)
        pcall(item.cb)
        -- Remove from tracking after execution
        Bus.queued_items[item.name] = nil
    end
end

function Bus:clear_queue()
    Bus.queue = {}
    Bus.queued_items = {}
end

return Bus
