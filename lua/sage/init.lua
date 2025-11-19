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

function M.setup(opts)
    print("Setting up")
    print(vim.inspect(opts))
    local config = require("sage.base.config")
    local dashboard = require("sage.ui.dashboard")
    local manager = require("sage.manager")

    local merged_opts = vim.tbl_deep_extend("force", config, opts)

    merged_opts.sage = {
        start = vim.loop.hrtime(),
    }

    local c_ok, create_command = pcall(require, "sage.base.command")
    if not c_ok then
        return
    end
    create_command.setup(merged_opts.sage.start)
    create_command.run()

    -- Call init safely
    local d_ok, _ = pcall(function()
        dashboard:init(merged_opts.dashboard)
    end)

    if not d_ok then
        vim.notify("sage.ui.dashboard missing `init` method", vim.log.levels.ERROR)
    end

    -- Run packs safely
    local m_ok, _ = pcall(function()
        manager:run_packs(merged_opts)
    end)

    if not m_ok then
        vim.notify("sage.manager missing `run_packs` method", vim.log.levels.ERROR)
    end
end

return M
