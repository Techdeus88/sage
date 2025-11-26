local Metrics = {}

Metrics.__index = Metrics
Metrics._singleton = nil

function Metrics.get_singleton(container)
    if Metrics._singleton == nil then
        Metrics._singleton = Metrics.new(container)
    end

    return Metrics._singleton
end

function Metrics.new(container)
    local self = setmetatable({}, Metrics)

    self.container = container
    self.manager = self.container:resolve("manager")
    self.utils = self.container:resolve("utils")

    self.stats = {}
    self.stats.times = {}
    self.stats.times.events = {}
    self.stats.times.loads = {}

    return self
end

function Metrics:track_event(event, value)
    if self.stats.times.events then
        self.stats.times.events[event] = value
    end
    return true, string.format("Event %s tracked with value %s", event, value)
end

function Metrics:get_stats()
    local Packs = self.manager:get_packs()

    self.stats["counted"] = 0
    self.stats["loaded"] = 0
    self.stats["failed"] = 0

    for name, pack in pairs(Packs) do
        self.stats["counted"] = self.stats["counted"] + 1
        if not pack.loaded then
            self.stats["failed"] = self.stats["failed"] + 1
        else
            self.stats["loaded"] = self.stats["loaded"] + 1
        end
        self.stats["times"][name] = pack.times
    end
    return self.stats
end

function Metrics:get_status()
    local Packs = self.manager.packs
    local status = {}
    for name, pack in pairs(Packs) do
        status[name] = {
            status = pack.status,
            stage = pack.stage,
            installed = pack.installed,
            failed = pack.failed,
            times = pack.times,
            specs = pack.specs,
        }
    end
    return status
end

function Metrics:get_config()
    local Packs = self.manager.packs
    local config = {}
    for name, pack in pairs(Packs) do
        config[name] = {
            status = pack.status,
            stage = pack.stage,
            installed = pack.installed,
            failed = pack.failed,
            times = pack.times,
            specs = pack.specs,
            data = pack.specs.normalize.data,
        }
    end
    return config
end

function Metrics:get_vim_info(pack_name)
    local vim_pack = vim.pack.get({ name = pack_name })
    return vim_pack
end

function Metrics:get_event(event)
    if self["stats"] and self["stats"].times.events[event] ~= nil then
        return self.stats.times.events[event]
    end
end

function Metrics:get_stage_lists()
    local Manager = self.manager
    local Utils = self.utils
    local Packs = Manager.packs
    local all_packs = vim.tbl_values(Packs)
    local sorted = Utils.sort_packs(all_packs)

    return sorted
end

return Metrics
