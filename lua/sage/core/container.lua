-- ============================================================================
-- file: container.lua
-- dependency injection SageContainer (singleton)
-- ============================================================================
local SageContainer = {}
SageContainer.__index = SageContainer
SageContainer._singleton = nil

---get or create the singleton container instance
---@return SageContainer
function SageContainer.get_instance()
    if not SageContainer._singleton then
        SageContainer._singleton = SageContainer.new()
    end
    return SageContainer._singleton
end

---create a new container
---@return SageContainer
function SageContainer.new()
    local self = setmetatable({}, SageContainer)
    self._services = {}
    self._factories = {}
    self._options = {}
    return self
end

---register a service
---@param name string service name
---@param factory function factory function that creates the service
---@param options? table options like { lazy = true }
function SageContainer:register(name, factory, options)
    options = options or {}
    self._factories[name] = factory
    self._options[name] = options

    if not options.lazy then
        self._services[name] = factory(self)
    end
end

---resolve a service by name
---@param name string service name
---@return any
function SageContainer:resolve(name)
    if self._services[name] then
        return self._services[name]
    end

    if self._factories[name] then
        self._services[name] = self._factories[name](self)
        return self._services[name]
    end

    error(string.format("service '%s' not registered in container", name))
end

---check if a service is registered
---@param name string service name
---@return boolean
function SageContainer:has(name)
    return self._factories[name] ~= nil or self._services[name] ~= nil
end

---get all registered services
---@return table services metadata
function SageContainer:get_services()
    local result = {}
    for name, _ in pairs(self._factories) do
        result[name] = {
            cached = self._services[name] ~= nil,

            lazy = self._options[name] and self._options[name].lazy or false,
        }
    end
    return result
end

---clear all instances (useful for testing)
function SageContainer:clear()
    self._services = {}
end

---reset the singleton (useful for testing)
function SageContainer.reset()
    SageContainer._singleton = nil
end

---create a scoped container with overrides
function SageContainer:scope(overrides)
    local scoped = SageContainer.new()
    for k, v in pairs(self._services) do
        scoped._services[k] = v
    end
    for k, v in pairs(overrides or {}) do
        scoped._services[k] = v
    end
    return scoped
end

return SageContainer
