local Pack = {}
Pack.__index = Pack

local bus = nil
local utils = nil

function Pack.init(deps)
    bus = deps.bus
    utils = deps.utils
end

function Pack.new(n_spec)
    local self = setmetatable({}, Pack)

    self.name = n_spec.name
    self.failed = false
    self.installed = false
    self.lifecycle = nil -- will be set later by the manager / lifecycle code
    self.loaded = false
    self.status = "idle"
    self.times = {
        install_duration = 0,
        config_duration = 0,
    }

    local v_spec = {
        active = false,
        branches = {},
        path = "",
        rev = "",
        tags = {},
    }

    self.specs = {}
    self.specs.normalize = n_spec
    self.specs.vim = v_spec

    return self
end

-- ---------------------------------------------------------------------------
-- Simple setters / getters
-- ---------------------------------------------------------------------------

function Pack:set_path(path)
    if path ~= nil then
        self.specs.vim.path = path
    end
end

function Pack:get_name()
    return self.name
end

function Pack:set_active(active)
    if active ~= nil then
        self.specs.vim.active = active
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
        self.specs.vim.rev = rev
    end
end

function Pack:set_branches(branches)
    if branches ~= nil then
        self.specs.vim.branches = branches
    end
end

function Pack:get_native_vim_pack()
    local ok, v_spec_wrapped = pcall(vim.pack.get, { self.name })
    local v_spec = v_spec_wrapped[1]
    v_spec.spec = nil
    if ok then
        return v_spec
    end
end

function Pack:merge_native_with_sage()
    local v_spec = self:get_native_vim_pack()
    self:set_path(v_spec.path)
    self:set_branches(v_spec.branches)
    self:set_active(v_spec.active)
    self:set_rev(v_spec.rev)
    self:set_tags(v_spec.tags)

    -- local SageVSpec = self.specs.vim
    -- local merged_v_spec = vim.tbl_deepextend("force", SageVSpec, v_spec)
    -- self.specs.vim = merged_v_spec
end

function Pack:set_tags(tags)
    if tags ~= nil then
        self.specs.vim.tags = tags
    end
end

function Pack:set_stage(stage)
    self.specs.normalize.data.stage = stage
    return self
end

function Pack:get_stage()
    return self.specs.normalize.data.stage
end

function Pack:get_path()
    if self.path ~= "" then
        return self.specs.vim.path
    end
    return nil
end

function Pack:set_status(new_status)
    local pack_name = self:get_name()
    local curr_status = self:get_status()

    if curr_status ~= new_status then
        self.status = new_status

        if bus then
            bus.emit("pack:status:update", {
                name = pack_name,
                prev_status = curr_status,
                status = new_status,
            })
        end
    end
    return self.status
end

function Pack:get_status()
    return self.status
end

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Integration with vim.pack
--{
-- active  = boolean,           -- added via vim.pack.add() this session
--path    = string,            -- plugin path on disk
-- rev     = string,            -- git revision
-- branches = { ... }?,         -- optional
-- tags     = { ... }?,         -- optional
--   spec    = {
--   src     = string,          -- git URL
--  name    = string,          -- plugin name
--  version = string|VersionRange|nil,
--  data    = any,             -- arbitrary user data
-- },
-- }

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

    if type(res_pack_list[1]) ~= "table" or #res_pack_list == 0 then
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
