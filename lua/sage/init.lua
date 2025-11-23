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
    pcall(require, "sage.base.global")
    pcall(require, "sage.base.command")
    local _, config = pcall(require, "sage.base.config")
    local _, dashboard = pcall(require, "sage.ui.dashboard")
    local _, manager = pcall(require, "sage.manager")

    local merged_opts = vim.tbl_deep_extend("force", config, opts)

    -- Call init safely
    local d_ok, err = pcall(function()
        dashboard:init({
            lock_windows = true,
            auto_focus = true,
        })
    end)

    if not d_ok then
        vim.notify("sage.ui.dashboard missing `:init` method" .. vim.inspect(err), vim.log.levels.ERROR)
    end

    -- Run packs safely
    pcall(function()
        manager:run_packs(merged_opts)
   end)
end

return M
