-- ui_renderer.lua

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(bus, dm, render_queue)
    local self = setmetatable({}, Renderer)
    self.bus = bus
    self.dm = dm
    self.queue = render_queue.new()
    self.r_packs = {} -- store pack info before rendering

    return self
end

-- called when pack:created happens
function Renderer:on_pack_created(data)
    -- store it (no UI)
    table.insert(self.r_packs, data)
    local index = #self.r_packs + math.random(1, 10)
    local delay = index * 25

    -- schedule a staggered render update
    self.queue:push(function()
        vim.defer_fn(function()
            self:render_pack_created(data)
        end, delay)
    end)
end

function Renderer:on_pack_updated(data)
    local row = self.dm.dashboard:find(data.name)
    local index = #self.r_packs + math.random(10, 20)
    local delay = index * 35
    if not row then
        return
    end
    vim.defer_fn(function()
        self:render_pack_updated(data)
    end, delay)
end

function Renderer:render_pack_updated(data)
    if self.dm.dashboard and self.dm.dashboard.update_line then
        self.dm.dashboard:update_line(data)
        self.dm.dashboard:resort_rows()
    end
end

-- the actual UI work (safe to do in scheduled tick)
function Renderer:render_pack_created(pack)
    if self.dm.dashboard and self.dm.dashboard.add_pack then
        self.dm.dashboard:add_pack(pack)
    end
end

-- registers all bus handlers
function Renderer:register_listeners()
    self.bus.on("pack:created", function(pack)
        self:on_pack_created(pack)
    end)

    self.bus.on("pack:config:start", function(data)
        self:on_pack_updated(data)
    end)
    self.bus.on("pack:config:finish", function(data)
        self:on_pack_updated(data)
    end)
    self.bus.on("pack:load:start", function(data)
        self:on_pack_updated(data)
    end)
    self.bus.on("pack:load:complete", function(data)
        self:on_pack_updated(data)
    end)
    self.bus.on("pack:install:start", function(data)
        self:on_pack_updated(data)
    end)
    self.bus.on("pack:install:finish", function(data)
        self:on_pack_updated(data)
    end)

    self.bus.on("pack:status:change", function(data)
        self:on_pack_updated(data)
    end)

    --         local row = self:find(data.name)
    --         if not row or data.new_status == "created" then
    --             return
    --         end
    --         row.status:update(data.new_status)
    --         row.status_two:update(data.new_status)
    --         self:update_line(row)
    --     end)

    --
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
    -- self.bus.on("pack:created", function(pack)
    --     self:on_pack_created(pack)
    -- end)
end

return Renderer
