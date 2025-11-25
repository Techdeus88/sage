-- ============================================================================
-- FILE: core/orchestrator.lua
-- Initialization Orchestrator - Controls startup sequence
-- ============================================================================
local Orchestrator = {}
Orchestrator.__index = Orchestrator

function Orchestrator.new(opts)
    local self = setmetatable({}, Orchestrator)
    self.opts = opts or {}
    self.initialized = false

    self.container = nil
    self.bus = nil
    self.logger = nil
    self.manager = nil
    self.api = nil
    self.loader = nil
    self.ui = nil
    self.dashboard = nil

    return self
end

function Orchestrator:init_base()
    require("sage.base.global").init()
    require("sage.base.notify").init()
    local Utils = require("sage.base.utils")

    self.container:register("utils", function()
        return Utils
    end)

    self:log("Orchestrator", "Base initialized (global, base & utils)")
end

function Orchestrator:init_container()
    local Container = require("sage.core.container")
    self.container = Container.get_instance()
    self.container:register("orchestrator", function()
        return self
    end)
    self:log("Orchestrator", "Container initialized")
end

function Orchestrator:init_command()
    if not self.container then
        error("Container must be initialized first")
    end
    if not self.bus or not self.api or not self.loader or not self.dashboard then
        error("Bus, API, Loader, and Dashboard must be initialized before commands")
    end
    local cmd = require("sage.base.command")
    cmd.init(self.container)

    self:log("Orchestrator", "Commands initialized")
end

function Orchestrator:init_bus()
    if not self.container then
        error("Container must be initialized first")
    end

    local EventBus = require("sage.core.bus")
    self.bus = EventBus

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
    self.logger = Logger:get_instance(self.opts)
    self.logger:set_bus(self.bus)
    self.container:register("logger", function()
        return self.logger
    end, { lazy = false })
    self:log("Orchestrator", "Logger initialized")
end

function Orchestrator:init_manager()
    if not self.logger then
        error("Logger must be initialized before manager")
    end
    local SageManager = require("sage.core.manager")
    self.manager = SageManager.new(self.container, self.opts)
    self.container:register("manager", function()
        return self.manager
    end, { lazy = false })
    self:log("Orchestrator", "Manager initialized")
end

function Orchestrator:init_pack()
    local SagePack = require("sage.core.pack")
    -- Initialize Pack dependencies once
    SagePack.init({
        bus = self.bus,
        utils = self.container:resolve("utils"),
    })
    
    self.container:register("pack", function()
        return SagePack
    end)
    self:log("Orchestrator", "SagePack registered")
end

function Orchestrator:init_deps()
    local Deps = require("sage.core.dep")
    self.container:register("deps", function()
        return Deps
    end)
    self:log("Orchestrator", "Deps registered")
end

function Orchestrator:init_api()
    if not self.manager then
        error("Manager must be initialized before api & stats")
    end
    local SageApi = require("sage.api")
    self.api = SageApi.new(self.container)
    self.container:register("api", function()
        return self.api
    end, { lazy = false })
    self:log("Orchestrator", "Sage API initialized and listening")
end

function Orchestrator:init_ui()
    if not self.manager or not self.bus then
        error("Manager, Bus must be initialized before UI")
    end
    -- Dashboard is a singleton table, not a class with .new()
    local SageDashboard = require("sage.ui.dashboard")
    local SageElements = require("sage.ui.elements")
    local SageIcons = require("sage.ui.icons")

    -- Dashboard is the instance itself, not a class
    self.dashboard = SageDashboard

    self.container:register("dashboard", function()
        return self.dashboard
    end, { lazy = false })

    self:log("Orchestrator", "UI initialized")

    -- Initialize the dashboard with options
    self.dashboard:init(self.container, SageElements, SageIcons, {
        lock_windows = self.opts.lock_windows,
        auto_focus = self.opts.auto_focus,
    })

    self:log("Orchestrator", "Dashboard initialized with options")
end

function Orchestrator:init_loader()
    if not self.bus or not self.logger then
        error("Bus, and Logger must be initialized before loader")
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
        error("Manager, Bus, & Logger must initialize before tasks")
    end

    local Task = require("sage.core.tasks.task")
    local TaskBuilder = require("sage.core.tasks.builder")
    local TaskLifecycle = require("sage.core.tasks.lifecycle")
    local TaskSystem = require("sage.core.tasks.system")

    -- Initialize all task modules with dependencies
    Task.init({
        bus = self.bus,
        logger = self.logger,
    })
    
    TaskLifecycle.init({
        bus = self.bus,
        logger = self.logger,
    })
    
    TaskSystem.init({
        bus = self.bus,
        logger = self.logger,
    })

    -- Register in container
    self.container:register("task", function()
        return Task
    end)
    
    self.container:register("task_builder", function()
        return TaskBuilder
    end)
    
    self.container:register("task_lifecycle", function()
        return TaskLifecycle
    end)
    
    self.container:register("task_system", function()
        return TaskSystem
    end)

    self:log("Orchestrator", "Task system initialized with dependencies")
end

function Orchestrator:execute_initialization()
    if self.initialized then
        self:log("Orchestrator", "Already initialized, skipping")
        return
    end

    self:log("Orchestrator", "Initialization starting")

    self:init_container()
    self:init_base()
    self:init_bus()
    self:init_logger()
    self:init_pack()
    self:init_deps()
    self:init_manager()
    self:init_loader()
    self:init_api()
    self:init_ui()
    self:init_command()
    self:init_task()

    self.initialized = true
    self:log("Orchestrator", "Initialization complete")
end

function Orchestrator:log(source, msg)
    -- Use vim.notify if logger not ready
    if self.logger then
        self.logger:debug(source, msg)
    else
        vim.notify(string.format("%s %s", source, msg), vim.log.levels.DEBUG, { title = "Sage" })
        -- vim.api.nvim_echo({ { string.format("[%s] %s", source, msg) } }, false, {})
    end
end

return Orchestrator
