-- Version check with better error handling
local SAGE_NVIM_VERSION = vim.version()
if SAGE_NVIM_VERSION.major == 0 and SAGE_NVIM_VERSION.minor < 12 then
    vim.notify(
        "SAGE PLUGIN MANAGER requires Neovim >= 0.12.0 (current: "
            .. SAGE_NVIM_VERSION.major
            .. "."
            .. SAGE_NVIM_VERSION.minor
            .. ")",
        vim.log.levels.ERROR
    )
    return nil
end

local M = {}


-- ============================================================================
-- FILE:sage/init.lua
-- Main Sage initialization
-- ============================================================================
local function setup_monitoring(bus)
end

local function setup_container()
    return require("sage.core.container").get_instance()
end

local function setup_orchestrator(opts)
    local Orchestrator = require("sage.core.orchestrator")
    local orchestrator = Orchestrator.new(opts)
    orchestrator:execute_initialization()
    return orchestrator
end

function M.setup(opts)
    local SageDefaultConfig = require("sage.base.config")
    opts = vim.tbl_deep_extend("force", SageDefaultConfig, opts or {})
    
    local orchestrator = setup_orchestrator(opts)
     -- Extract services
    local container = orchestrator.container
    local logger = orchestrator.logger
    local manager = orchestrator.manager
    local dashboard = orchestrator.dashboard
    local loader = orchestrator.loader
    local bus = orchestrator.bus
    local coordinator = orchestrator.coordinator

    -- Call init safely
    local d_ok, err = pcall(function()
        dashboard:init({
            lock_windows = opts.lock_windows,
            auto_focus = opts.auto_focus
        })
    end)

    if not d_ok then
        vim.notify("sage.ui.dashboard missing `:init` method" .. vim.inspect(err), vim.log.levels.ERROR)
    end

    -- Run packs safely
    pcall(function()
        manager:run_packs(opts)
   end)
end

return M
