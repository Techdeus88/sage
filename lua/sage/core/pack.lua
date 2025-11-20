local utils = require("sage.base.utils")

local Pack = {}
Pack.__index = Pack

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
    self.specs["user"] = spec
    self.specs["normalize"] = {}

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

function Pack:set_path(path)
    if path ~= nil then
        self.path = path
    end
end

function Pack:get_name()
    return self.specs.normalize.name or ""
end

function Pack:set_active(active)
    if active ~= nil then
        self.active = active
    end
end

function Pack:set_rev(rev)
    if rev ~= nil then
        self.rev = rev
    end
end

function Pack:set_branches(branches)
    if branches ~= nil then
        self.branches = vim.tbl_extend("force", self.branches, branches)
    end
    return self.branches
end

function Pack:set_tags(tags)
    if tags ~= nil then
        self.tags = vim.tbl_extend("force", self.tags, tags)
    end
    return self.tags
end

function Pack:get_path()
    if self.path ~= "" then
        return self.path
    end
end

function Pack:set_stage(stage)
    self.stage = stage
    return self
end

function Pack:get_stage()
    return self.stage
end

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
    local curr_status = self.status
    if curr_status ~= status then
        self.status = status
        return true, self.status
    end
    return false, self.status
end

function Pack:get_status()
    return self.status
end

function Pack:get_native()
    local name = self:get_name()
    local n_ok, res_pack_list = pcall(vim.pack.get, { name })

    if not n_ok then
        vim.notify(string.format("[%s] Pack not found", pack_name), vim.log.levels.ERROR)
    end

    local n_pack = res_pack_list[1]
    if n_pack then
        return n_pack
    end
end

return Pack
