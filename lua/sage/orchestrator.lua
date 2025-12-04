-- ============================================================================
-- FILE: core/orchestrator.lua
-- Initialization Orchestrator - Controls startup sequence - SINGLETON
-- ============================================================================
local Orchestrator = {}
Orchestrator.__index = Orchestrator

-- ============================================================================
-- SINGLETON INSTANCE
-- ============================================================================
local _instance = nil

function Orchestrator.get_instance(opts)
    if not _instance then
        _instance = setmetatable({}, Orchestrator)
        _instance:_init_defaults(opts or {})
    end
    return _instance
end

function Orchestrator.new(opts)
    -- Legacy compatibility: redirect to singleton
    return Orchestrator.get_instance(opts)
end

-- ============================================================================
-- INITIALIZATION DEFAULTS
-- ============================================================================
function Orchestrator:_init_defaults(opts)
    self.opts = opts
    self.initialized = false

    self.temp_logs = {}
    self.first_access = true

    -- Core services
    self.container = nil
    self.bus = nil
    self.logger = nil
    self.manager = nil
    self.api = nil
    self.metrics = nil
    self.loader = nil
    self.ui = nil
    self.utils = nil
    self.dashboard = nil
    self.command = nil
    self.dm = nil
    self.db = nil
    self.renderer = nil
end

-- ============================================================================
-- RESET (for testing/reinitialization)
-- ============================================================================
function Orchestrator:reset()
    self:log("Orchestrator", "Resetting orchestrator state")

    -- Clean up existing instances
    if self.dashboard and self.dashboard.is_open then
        self.dashboard:close()
    end

    -- Reset to defaults
    self:_init_defaults(self.opts)
end

-- ============================================================================
-- CORE INITIALIZATION METHODS
-- ============================================================================

function Orchestrator:init_base()
    require("sage.base.global").init()
    require("sage.base.notify").init()

    local Logger = require("sage.base.logger")
    self.logger = Logger:get_instance(self.opts)
    self.container:register("logger", function()
        return self.logger
    end, { lazy = false })

    local Utils = require("sage.base.utils")
    Utils.init(self.container)
    self.utils = Utils

    self.container:register("utils", function()
        return Utils
    end, { lazy = false })

    self:log("Orchestrator", "Base initialized (global, base, logger & utils)")
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
    self.bus = EventBus

    self.bus:init(self.container)
    self.container:register("bus", function()
        return self.bus
    end, { lazy = false })
    self:log("Orchestrator", "EventBus initialized")
end

function Orchestrator:init_manager()
    if not self.logger or not self.bus then
        error("Logger, Metrics must be initialized before manager")
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
    self:log("Orchestrator", "SageDep registered")
end

function Orchestrator:init_metrics()
    if not self.bus or not self.logger then
        error("Bus, Logger must be initialized before metrics")
    end
    local SageMetrics = require("sage.core.metrics")

    self.metrics = SageMetrics:get_singleton(self.container)

    self.container:register("metrics", function()
        return self.metrics
    end, { lazy = false })
    self:log("Orchestrator", "SageMetrics registered")
end

function Orchestrator:init_ui()
    if not self.manager or not self.bus then
        error("Manager, Bus must be initialized before UI")
    end

    local Dashboard = require("sage.ui.dashboard")
    local SageElements = require("sage.ui.elements")
    local SageIcons = require("sage.ui.icons")
    local dm = require("sage.ui.manager")
    local SageRenderer = require("sage.ui.renderer")
    local SageRenderQueue = require("sage.ui.render_queue")

    self.dm = dm.new(self.opts)
    self.db = Dashboard.get_instance()
    self.renderer = SageRenderer.new(self.bus, self.dm, SageRenderQueue)

    -- Wire the strategy object
    self.dm.dashboard = self.db

    -- Initialize the dashboard ONLY ONCE
    if not self.db.initialized then
        self.db:init(self.container, SageElements, SageIcons, self.opts)
    end

    self.manager:initialize(self.renderer)

    self.container:register("dashboard", function()
        return Dashboard.get_instance()
    end, { lazy = false })

    self.container:register("dashboard_manager", function()
        return self.dm
    end, { lazy = true })

    self:log("Orchestrator", "SageDashboard w/ manager registered")
end

function Orchestrator:init_loader()
    if not self.bus or not self.logger then
        error("Bus, and Logger must be initialized before loader")
    end

    local Loader = require("sage.core.loader")
    self.loader = Loader.new(self.container, self.opts)

    self.container:register("loader", function()
        return self.loader
    end)
    self:log("Orchestrator", "Loader initialized")
end

function Orchestrator:init_command()
    if not self.container then
        error("Container must initialize before command")
    end
    self.command = require("sage.base.command")
    self.command.init(self.container)

    self:log("Orchestrator", "Command/s initialized")
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

    self:log("Orchestrator", "TaskSystem registered and initialized")
end

function Orchestrator:init_public()
    if not self.bus or not self.manager or not self.logger or not self.metrics then
        error("Bus, Manager, Logger and Metrics must initialize before public api")
    end

    local SageCommands = require("sage.commands")
    self.commands = SageCommands

    local SageAPI = require("sage.api")
    self.api = SageAPI.new(self.container)

    self.container:register("api", function()
        return self.api
    end, { lazy = false })

    self.container:register("commands", function()
        return self.commands
    end)

    self.command:setup_commands()

    self:log("Orchestrator", "SageAPI (public) registered")
end

-- ============================================================================
-- MAIN INITIALIZATION ENTRY POINT
-- ============================================================================

function Orchestrator:execute_initialization()
    if self.initialized then
        self:log("Orchestrator", "Already initialized, skipping")
        return
    end

    self:log("Orchestrator", "Initialization starting")

    self:init_container()
    self:init_base()
    self:init_bus()
    self:init_manager()
    self:init_ui()
    self:init_pack()
    self:init_deps()
    self:init_metrics()
    self:init_loader()
    self:init_command()
    -- self:init_task()
    self:init_public()

    self.initialized = true
    self:log("Orchestrator", "Initialization complete")
end

-- ============================================================================
-- LOGGING (with temp log buffering)
-- ============================================================================

function Orchestrator:dump_temp_logs()
    if self.first_access then
        for _, log in pairs(self.temp_logs) do
            self.logger:debug(log.source, log.msg)
        end
        -- Reset temp logs
        self.temp_logs = {}
        return true
    end
    return false
end

function Orchestrator:log(source, msg)
    -- Use vim.notify if logger not ready
    if self.logger then
        if self.first_access then
            local ok, _ = pcall(function()
                self:dump_temp_logs()
            end)
            if not ok then
                error("Temp log dump errored")
            end
            -- Set first access to false
            self.first_access = false
            assert(vim.tbl_count(self.temp_logs) == 0, "Temp Logs did not reset!")
        end
        self.logger:debug(source, msg)
    else
        local curr_log_num = vim.tbl_count(self.temp_logs) + 1
        local log = { source = source, msg = msg }

        if not self.temp_logs[curr_log_num] then
            self.temp_logs[curr_log_num] = log
        end
    end
end

return Orchestrator

