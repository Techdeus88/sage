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
-- local function setup_monitoring(bus) end

local function setup_orchestrator(opts)
    local Orchestrator = require("sage.orchestrator")
    local orchestrator = Orchestrator.new(opts)
    orchestrator:execute_initialization()
    return orchestrator
end

function M.setup(opts)
    local config = require("sage.config")
    config.setup(opts)

    local orchestrator = setup_orchestrator(config.opts)
    -- Run packs safely
    pcall(function()
        orchestrator.manager:run_packs()
    end)
end

return M
