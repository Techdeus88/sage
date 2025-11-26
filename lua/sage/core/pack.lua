local Pack = {}
Pack.__index = Pack

local bus = nil
local utils = nil

function Pack.init(deps)
    bus = deps.bus
    utils = deps.utils
end

function Pack.new(spec)
    local self = setmetatable({}, Pack)

    local src = spec.src or spec[1]
    local name = spec.name or utils.extract_name(src)
    local priority = spec.priority or 100
    local config = spec.config
    local before = spec.before
    local after = spec.after
    local build = spec.build
    local depends = spec.depends
    local version = spec.version
    local on = spec.on

    local prefix = "https://github.com/"
    local disabled = spec.enabled ~= nil and spec.enabled == false
    local stage = self:determine_stage(spec)
    local beg_status = "idle"

    self.enabled = not disabled
    self.lifecycle = nil -- will be set later by the manager / lifecycle code

    self.stage = stage
    self.status = beg_status
    self.priority = priority

    self.loaded = false
    self.installed = false
    self.failed = false
    self.times = {
        install_duration = 0,
        config_duration = 0,
    }

    -- vim.pack specific
    self.active = false
    self.path = ""
    self.rev = ""
    self.branches = {}
    self.tags = {}

    self.specs = {}
    self.specs.user = spec
    self.specs.normalize = {}

    local n_spec = self.specs.normalize

    n_spec.src = prefix .. src
    n_spec.name = name
    n_spec.version = version
    n_spec.data = {}
    n_spec.data.stage = stage
    n_spec.data.source = src
    n_spec.data.depends = depends
    n_spec.data.before = before
    n_spec.data.config = config
    n_spec.data.after = after
    n_spec.data.on = on
    n_spec.data.build = build

    return self
end

-- ---------------------------------------------------------------------------
-- Simple setters / getters
-- ---------------------------------------------------------------------------

function Pack:set_path(path)
    if path ~= nil then
        self.path = path
    end
end

function Pack:get_name()
    return self.specs.normalize.name
end

function Pack:set_active(active)
    if active ~= nil then
        self.active = active
    end
end

function Pack:set_installed(is_installed)
    if is_installed ~= nil then
        self.installed = is_installed
    end
end

function Pack:get_installed()
    return self.installed
end

function Pack:set_rev(rev)
    if rev ~= nil then
        self.rev = rev
    end
end

function Pack:set_branches(branches)
    if branches ~= nil then
        self.branches = vim.tbl_extend("force", self.branches or {}, branches)
    end
end

function Pack:set_tags(tags)
    if tags ~= nil then
        self.tags = vim.tbl_extend("force", self.tags or {}, tags)
    end
end

function Pack:set_stage(stage)
    self.stage = stage
    return self
end

function Pack:get_stage()
    return self.stage
end

function Pack:get_path()
    if self.path ~= "" then
        return self.path
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Stage / status
-- ---------------------------------------------------------------------------

function Pack:determine_stage(spec)
    if utils.is_not_enabled(spec) then
        return "disabled"
    end

    local on = spec.on
    if
        on ~= nil
        and (
            on.before ~= nil
            or on.after ~= nil
            or on.events ~= nil
            or on.event ~= nil
            or on.fts ~= nil
            or on.ft ~= nil
            or on.cmds ~= nil
            or on.cmd ~= nil
            or on.keys ~= nil
        )
    then
        return "lazy"
    end

    if on ~= nil and on.stage == "now" then
        return "now"
    end

    return "later"
end

function Pack:set_status(status)
    local pack_name = self:get_name()
    local curr_status = self.status
    local delay_status = 300

    if curr_status ~= status then
        self.status = status
        if bus then
            vim.schedule(function()
                vim.defer_fn(function()
                    bus.emit("pack:status:change", {
                        name = pack_name,
                        prev_status = curr_status,
                        new_status = status,
                    })
                end, delay_status)
            end)
        end
        return true, self.status
    end
    return false, self.status
end

function Pack:get_status()
    return self.status
end

-- ---------------------------------------------------------------------------
-- Integration with vim.pack
-- ---------------------------------------------------------------------------

function Pack:get_native()
    local name = self:get_name()
    if name == "" then
        return nil
    end

    local ok, res_pack_list = pcall(vim.pack.get, { name })
    if not ok then
        vim.notify(string.format("[Sage] Pack not found for name '%s'", name), vim.log.levels.ERROR)
        return nil
    end

    if type(res_pack_list) ~= "table" or #res_pack_list == 0 then
        return nil
    end

    return res_pack_list[1]
end

-- ---------------------------------------------------------------------------
-- Lifecycle helpers
-- ---------------------------------------------------------------------------

function Pack:get_task_progress()
    -- lifecycle will be set to an object elsewhere which implements :get_progress()
    if not self.lifecycle or type(self.lifecycle.get_progress) ~= "function" then
        return {
            total = 0,
            completed = 0,
            required_completed = 0,
            required_total = 0,
            percentage = 0,
        }
    end

    return self.lifecycle:get_progress()
end

return Pack
