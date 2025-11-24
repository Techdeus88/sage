local Api = {}
Api.__index = Api
Api._singleton = nil

function Api.new(container)
    local self = setmetatable({}, Api)

    self.stats = {}
    self.stats.times = {}
    self.stats.times.events = {}
    self.stats.times.loads = {}

    return self
end

function Api:get_singleton()
    if self._singleton == nil then
        self._singleton = Api.new()
    end
    return self._singleton
end

function Api:get_stats()
    local Packs = require("sage.manager").packs
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

function Api:get_status()
    local Packs = require("sage.manager").Packs
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

function Api:get_config()
    local Packs = require("sage.manager").Packs
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
end

function Api:get_vim_info(pack_name)
    local vim_pack = vim.pack.get({ name = pack_name })
    return vim_pack
end

function Api:track_event(event, value)
    if self.stats.times.events then
        self.stats.times.events[event] = value
    end
    return true
end

function Api:get_event(event)
    if self.stats.times.events[event] ~= nil then
        return self.stats.times.events[event]
    end
    return nil
end

function Api.get_stage_lists()
    local Manager = require("sage.manager")
    local Packs = Manager.packs
    local all_packs = vim.tbl_values(Packs)
    local sorted = require("sage.base.utils").sort_packs(all_packs)

    return sorted
end

return Api:get_singleton()
