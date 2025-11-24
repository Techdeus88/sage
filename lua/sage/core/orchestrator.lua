-- ============================================================================
-- FILE: core/orchestrator.lua
-- Initialization Orchestrator - Controls startup sequence
-- ============================================================================
local Orchestrator = {}
Orchestrator.__index = Orchestrator

function Orchestrator.new(opts)
    local self = setmetatable({}, Orchestrator)
    self.opts = opts or {}
    self.container = nil
    self.bus = nil
    self.logger = nil
    self.manager = nil
    self.stats = nil
    self.loader = nil
    self.ui = nil
    self.initialized = false
    return self
end

function Orchestrator:init_base()
    require("sage.base.global")
    -- require("sage.core.notify").init()
    -- require("sage.core.windows")
    require("sage.base.command")
end

function Orchestrator:init_container()
    local Container = require("sage.core.container")
    self.container = Container.get_instance()
    self.container:register("orchestrator", function()
        return self
    end)

    self:log("Orchestrator", "Container initialized")
end

function Orchestrator:init_bus()
    if not self.container then
        error("Container must be initialized first")
    end
    local EventBus = require("sage.core.bus")
    -- local EventBridge = require("sage.services.event.bridge")

    self.bus = EventBus
    -- self.bus.attach_bridge(EventBridge.new())

    self.container:register("bus", function()
        return self.bus
    end, { lazy = false })
    self:log("Orchestrator", "Event bus initialized")
end

function Orchestrator:init_logger()
     if not self.bus then
         error("Bus must be initialized before logger")
     end
     local Logger = require("sage.base.logger")
     self.logger = Logger:get_instance()
     self.logger:set_bus(self.bus)
     self.container:register("logger", function()
         return self.logger
     end, { lazy = false })
     self:log("Orchestrator", "Logger initialized")
end

function Orchestrator:init_utils()
    local Utils = require("sage.base.utils")
    self.container:register("utils", function()
        return Utils
    end)
    self:log("Orchestrator", "Utils initialized")
end

function Orchestrator:init_manager()
    if not self.logger then
        error("Logger must be initialized before manager")
    end
    local SageManager = require("sage.manager")
    self.manager = SageManager.new(self.container)
    self.container:register("manager", function()
        return self.manager
    end, { lazy = false })
    self:log("Orchestrator", "Manager initialized")
end

function Orchestrator:init_pack()
    local SagePack = require("sage.core.pack")
    self.container:register("pack", function()
        return SagePack
    end)
    self:log("Orchestrator", "SagePack registered")
end

-- function Orchestrator:init_deps()
--     local Deps = require("sage.services.deps")
--     self.container:register("deps", function()
--         return Deps
--     end)
--     self:log("Orchestrator", "Deps registered")
-- end
--
function Orchestrator:init_stats()
    if not self.manager then
        error("Manager must be initialized before stats")
    end
    local SageApi = require("sage.api")
    self.api = SageApi:new(self.container)
    self.container:register("api", function()
        return self.api
    end, { lazy = false })
    self:log("Orchestrator", "Stats initialized and listening")
end

function Orchestrator:init_ui()
    if not self.manager then
        error("Manager must be initialized before UI")
    end

    local bufnr = vim.api.nvim_create_buf(false, true)

    local SageDashboard = require("sage.ui.dashboard")
    self.dashboard = SageDashboard
    self.container:register("dashboard", function()
        return self.dashboard
    end, { lazy = false })
    self:log("Orchestrator", "UI initialized")

    if not self.dashboard then
        error("UI must be initialized before renderer")
    end
end

function Orchestrator:init_loader()
    if not self.manager or not self.bus or not self.logger then
        error("Manager, Bus, and Logger must be initialized before loader")
    end
    local Loader = require("sage.core.loader")
    self.loader = Loader.new(self.container)
    self.container:register("loader", function()
        return self.loader
    end)
    self:log("Orchestrator", "Loader initialized")
end

function Orchestrator:init_task()
    if not self.manager or not self.bus or not self.logger then
        error("Manager, Bus, and Logger must be initialized before loader")
    end
    local TaskBuilder = require("sage.core.tasks.builder")
    local TaskLifecycle = require("sage.core.tasks.lifecycle")
    local TaskSystem = require("sage.core.tasks.system")
    self.coordinator = TaskLifecycle.new(self.container)
    self.container:register("task_coordinator", function()
        return self.coordinator
    end, { lazy = false })
    self:log("Orchestrator", "Task coordinator initialized")
end

function Orchestrator:execute_initialization()
    if self.initialized then
        self:log("Orchestrator", "Already initialized, skipping")
        return
    end

    self:log("Orchestrator", "Starting initialization sequence")
    self:init_base()
    self:init_container()
    self:init_bus()
    self:init_logger()
    self:init_utils()
    self:init_pack()
    -- self:init_deps()
    self:init_manager()
    self:init_stats()
    self:init_ui()
    self:init_loader()
    self:init_task()

    self.initialized = true
    self:log("Orchestrator", "Initialization complete")
end

function Orchestrator:log(source, msg)
    -- Use vim.notify if logger not ready
    if self.logger then
        self.logger:debug(source, msg)
    else
        -- vim.api.nvim_echo({ { source, msg }}, false, {})
    end
end

return Orchestrator
