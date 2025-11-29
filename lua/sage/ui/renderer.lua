-- ui_renderer.lua

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(bus, dm, render_queue)
    local self = setmetatable({}, Renderer)
    self.bus = bus
    self.dm = dm
    self.queue = render_queue.new()

    -- Track rendering state
    self.created_count = 0
    self.update_count = 0

    local logger = function(msg)
        self.dm.dashboard:debug_log(msg, "renderer")
    end
    self.debug_log = logger

    return self
end

-- ============================================================================
-- Pack Creation Rendering
-- ============================================================================
function Renderer:on_pack_created(data)
    self.created_count = self.created_count + 1
    local index = self.created_count

    -- Stagger by 10ms per pack for smooth rendering
    -- 32 packs = 320ms total stagger time
    local delay = index * 10

    self.queue:push(function()
        vim.defer_fn(function()
            self:render_pack_created(data)
        end, delay)
    end)
end

function Renderer:render_pack_created(data)
    if not self.dm.dashboard or not self.dm.dashboard.add_pack then
        return
    end
    -- Always add pack data (doesn't require windows)
    self.dm.dashboard:add_pack(data)

    -- Logging only if we actually rendered
    if self.dm.dashboard.is_ready then
        self.debug_log(string.format("Rendered pack --%s--", data.name))
    else
        self.debug_log(string.format("Tracked pack --%s-- (dashboard not open)", data.name))
    end
end
-- ============================================================================
-- Pack Update Rendering
-- ============================================================================
function Renderer:on_pack_updated(data)
    self.update_count = self.update_count + 1

    -- Updates should be faster - only 5ms delay
    local delay = 5

    self.queue:push(function()
        vim.defer_fn(function()
            self:render_pack_updated(data)
        end, delay)
    end)
end

function Renderer:render_pack_updated(data)
    if not self.dm.dashboard or not self.dm.dashboard.is_valid then
        return
    end

    local row = self.dm.dashboard:find(data.name)
    if not row then
        -- Pack doesn't exist yet, might be rendering out of order
        self.debug_log(string.format("Row not found for update: %s", data.name))
        return
    end

    -- Update the row based on event type
    if data.status then
        row.status:update(data.status)
        row.status_two:update(data.status)
    end

    if data.message then
        row.message:update(data.message)
    end

    if data.install_duration then
        row.install_duration:update(data.install_duration)
    end

    if data.config_duration then
        row.config_duration:update(data.config_duration)
    end

    self.dm.dashboard:update_line(row)
    self.debug_log(string.format("Updated pack --%s-- to render", data.name))
end

-- registers all bus handlers
function Renderer:register_listeners()
    -- Pack creation - only happens once per pack
    self.bus.on("pack:created", function(pack)
        self.debug_log(string.format("--Caught-- created pack emit for %s", pack.name))
        self:on_pack_created(pack)
    end)

    -- Install events
    self.bus.on("pack:install:start", function(data)
        self.debug_log(string.format("--Caught-- install:start pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    self.bus.on("pack:install:finish", function(data)
        self.debug_log(string.format("--Caught-- install:finish pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Load events
    self.bus.on("pack:load:start", function(data)
        self.debug_log(string.format("--Caught-- load:start pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    self.bus.on("pack:load:complete", function(data)
        self.debug_log(string.format("--Caught-- load:complete pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Config events
    self.bus.on("pack:config:start", function(data)
        self.debug_log(string.format("--Caught-- config:start pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    self.bus.on("pack:config:finish", function(data)
        self.debug_log(string.format("--Caught-- config:finish pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Status changes
    self.bus.on("pack:status:change", function(data)
        self.debug_log(string.format("--Caught-- status:change pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Lazy packs
    self.bus.on("pack:lazy", function(data)
        self.debug_log(string.format("--Caught-- lazy pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Failed packs
    self.bus.on("pack:failed", function(data)
        self.debug_log(string.format("--Caught-- failed pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- All packs created - trigger resort
    self.bus.on("pack:all_created", function(data)
        self.debug_log("--Caught-- all_created pack emit")

        -- Wait for all renders to complete before resorting
        local total_delay = self.created_count * 10 + 100

        vim.defer_fn(function()
            if self.dm.dashboard and self.dm.dashboard.is_valid then
                self.dm.dashboard:resort_rows()
                self.dm.dashboard:render_footer()
                self.dm.dashboard:focus_content_window()
            end
        end, total_delay)
    end)
end
-- ============================================================================
-- Cleanup
-- ============================================================================
function Renderer:cleanup()
    self.created_count = 0
    self.update_count = 0

    -- Flush any pending renders
    if self.queue then
        self.queue:flush()
    end
end

return Renderer
