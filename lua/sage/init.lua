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
    local _, config = pcall(require, "sage.base.config")
    local _, dashboard = pcall(require, "sage.ui.dashboard")
    local _, manager = pcall(require, "sage.manager")


    local merged_opts = vim.tbl_deep_extend("force", config, opts)

    merged_opts.sage = {
        start = vim.loop.hrtime(),
    }

    pcall(require, "sage.base.command")

    -- Call init safely
    local d_ok, _ = pcall(function()
        dashboard:init(merged_opts.dashboard)
    end)

    if not d_ok then
        vim.notify("sage.ui.dashboard missing `init` method", vim.log.levels.ERROR)
    end

    -- Run packs safely
    pcall(function()
        manager:run_packs(merged_opts)
    end)
end

return M
