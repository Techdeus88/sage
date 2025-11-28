-- ui_renderer.lua

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(bus, dm, render_queue)
    local self =  setmetatable({}, Renderer)
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
    local index = #self.r_packs
    local delay = index * 50

    -- schedule a staggered render update
    self.queue:push(function()
        vim.defer_fn(function()
            self:render_pack_created(data)
        end, delay)
    end)
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
end

return Renderer
