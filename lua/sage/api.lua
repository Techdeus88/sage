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

return API
