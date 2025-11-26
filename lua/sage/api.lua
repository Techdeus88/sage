local API = {}

function API.new(container, manager)
    local self = setmetatable({}, API)

    self.container = container
    self.manager = manager
    self.utils = self.container:resolve("utils")

    self.stats = {}
    self.stats.times = {}
    self.stats.times.events = {}
    self.stats.times.loads = {}
    self.stats.times.installs = {}

    return self
end

function API:get_stage_lists()
    local Manager = self.manager
    local utils = self.utils
    local Packs = Manager.packs
    local all_packs = vim.tbl_values(Packs)
    local sorted = utils.sort_packs(all_packs)

    return sorted
end

function API:get_event(event)
    if self["stats"] and self["stats"].times.events[event] ~= nil then
        return self.stats.times.events[event]
    end
end

function API:get_stats()
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

return API
