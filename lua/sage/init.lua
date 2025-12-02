--- ============================================================================
-- FILE: init.lua
-- Sage Plugin Manager - Config-First Initialization
-- ============================================================================

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
-- Setup orchestrator with pre-configured specs
-- ============================================================================
local function setup_orchestrator(opts)
    local Orchestrator = require("sage.orchestrator")
    local orchestrator = Orchestrator.new(opts)
    orchestrator:execute_initialization()
    return orchestrator
end

-- ============================================================================
-- Main setup function
-- ============================================================================
function M.setup(opts)
    -- ✅ STEP 1: Setup config FIRST
    -- This loads, validates, and normalizes all specs
    local config = require("sage.config")
    config.setup(opts)

    -- ✅ At this point, config.specs contains all normalized specs
    -- No need for Manager to load/validate/normalize again!

    if vim.g.sage_debug then
        vim.notify(
            string.format("[Sage] Config ready with %d normalized specs", config.spec_count or 0),
            vim.log.levels.INFO
        )
    end

    -- ✅ STEP 2: Setup orchestrator with config opts
    -- Manager will use config.get_all_specs() to get pre-normalized specs
    local orchestrator = setup_orchestrator(config.opts)

    local log = orchestrator.logger:debug(
        "Config",
        string.format("Opts used in this session: %d key-value pairs", vim.tbl_count(config.opts))
    )
    orchestrator.logger:log_table("Config", config.opts, log)
    orchestrator.logger:debug("Config", string.format("Config normalized %d packages", #config.specs))

    -- ✅ STEP 3: Run packs safely
    local m_ok, err = pcall(function()
        orchestrator.manager:run_packs()
    end)
    if not m_ok then
        orchestrator.logger:debug(string.format("Primary method that kicks off process dailed - %s", vim.inspect(err)))
    end
end

return M
