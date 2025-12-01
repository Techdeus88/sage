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

    -- store updates that arrive before a row exists
    self.pending_updates = {}

    local logger = function(msg)
        if self.dm and self.dm.dashboard and self.dm.dashboard.debug_log then
            self.dm.dashboard:debug_log(msg, "renderer")
        end
    end
    self.debug_log = logger

    return self
end

-- ============================================================================
-- Pack Creation Rendering (staggered, with buffering for early updates)
-- ============================================================================
function Renderer:on_pack_created(data)
    self.created_count = self.created_count + 1
    local index = self.created_count

    -- Visible stagger: one new row every 65ms
    -- tweak this if you want faster/slower animation
    local delay = index * 65

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

    -- This creates/updates the row + extmark
    self.dm.dashboard:add_pack(data)

    -- If any updates arrived before creation, apply the latest now
    local pending = self.pending_updates[data.name]
    if pending then
        self.pending_updates[data.name] = nil
        local row = self.dm.dashboard:find(data.name)
        if row then
            -- Use dashboard's apply function
            if self.dm.dashboard.apply_update_to_row then
                self.dm.dashboard:apply_update_to_row(row, pending)
            else
                self:_apply_update_to_row(row, pending)
            end
            self.dm.dashboard:update_row(data.name)
        end
    end

    if self.dm.dashboard.is_ready then
        self.debug_log(string.format("Rendered pack --%s--", data.name))
    else
        self.debug_log(string.format("Tracked pack --%s-- (dashboard not open)", data.name))
    end
end
-- Pack Update Rendering (staggered, with buffering)
-- ============================================================================
function Renderer:on_pack_updated(data)
    self.update_count = self.update_count + 1
    local index = self.update_count

    -- Updates should feel quick but still visible
    local delay = index * 80

    self.queue:push(function()
        vim.defer_fn(function()
            self:render_pack_updated(data)
        end, delay)
    end)
end

function Renderer:_apply_update_to_row(row, data)
    local elems = row.elements

    if data.status then
        if elems.status then
            elems.status:update(data.status)
        end
        if elems.status_two then
            elems.status_two:update(data.status)
        end
    end

    if data.message and data.message ~= "" then
        if elems.message then
            elems.message:update(data.message)
        end
    elseif data.status then
        -- derive a friendly message from status when none is provided
        local status_messages = {
            ready = "Loaded",
            loaded = "Loaded",
            installed = "Installed",
            installing = "Installing…",
            configuring = "Configuring…",
            failed = "Failed",
            disabled = "Disabled",
            lazy = "Lazy",
        }
        local msg = status_messages[data.status]
        if msg and elems.message then
            elems.message:update(msg)
        end
    end

    if data.install_duration and elems.install_duration then
        elems.install_duration:update(data.install_duration)
    end

    if data.config_duration and elems.config_duration then
        elems.config_duration:update(data.config_duration)
    end

    if data.stage then
        if elems.stage then
            elems.stage:update(data.stage)
        end
        if elems.stage_two then
            elems.stage_two:update(data.stage)
        end
    end
end

function Renderer:render_pack_updated(data)
    if not self.dm.dashboard or not self.dm.dashboard.is_valid then
        return
    end

    local row = self.dm.dashboard:find(data.name)
    if not row then
        -- Row not created yet – remember the latest event for this pack
        self.pending_updates[data.name] = data
        self.debug_log(string.format("Queued update for %s (no row yet)", data.name))
        return
    end

    -- Use dashboard's apply function if available
    if self.dm.dashboard.apply_update_to_row then
        self.dm.dashboard:apply_update_to_row(row, data)
    else
        self:_apply_update_to_row(row, data)
    end

    -- Trigger re-render via update_row which checks dirty flags
    self.dm.dashboard:update_row(data.name)
    self.debug_log(string.format("Updated pack --%s--", data.name))
end

-- ============================================================================
-- registers all bus handlers
-- ============================================================================
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

    -- Failure events
    self.bus.on("pack:failed", function(data)
        self.debug_log(string.format("--Caught-- failed pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    -- Lazy / disabled events (if your bus emits them)
    self.bus.on("pack:lazy", function(data)
        self.debug_log(string.format("--Caught-- lazy pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)

    self.bus.on("pack:disabled", function(data)
        self.debug_log(string.format("--Caught-- disabled pack emit for %s", data.name))
        self:on_pack_updated(data)
    end)
end

-- ============================================================================
-- Cleanup
-- ============================================================================
function Renderer:cleanup()
    self.created_count = 0
    self.update_count = 0
    self.pending_updates = {}

    if self.queue then
        self.queue:flush()
    end
end

return Renderer