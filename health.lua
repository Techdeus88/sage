local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

local container = require("sage.core.container")
local default_config = require("sage.base.config")

local manager = require("sage.core.manager").new(container, default_config)

local function check_manager_health()
    local stats = manager:get_cleanup_stats()

    if stats.active_timers > 0 then
        print(string.format("Warning: %d active timers found", stats.active_timers))

        for _, pack_info in ipairs(stats.pack_list) do
            if pack_info.active_timers > 0 then
                print(string.format("  - %s: %d timers", pack_info.name, pack_info.active_timers))
            end
        end
    end

    return stats
end

function M.check()
    start("Sage")

    if vim.fn.has("nvim-0.12.0") == 1 then
        ok("Using Neovim >= 0.12.0")
    else
        error("Neovim >= 0.12.0 is required")
    end

    for _, cmd in ipairs({ "git", "rg", { "fd", "fdfind" }, "lazygit" }) do
        local name = type(cmd) == "string" and cmd or vim.inspect(cmd)
        local commands = type(cmd) == "string" and { cmd } or cmd
        ---@cast commands string[]
        local found = false

        for _, c in ipairs(commands) do
            if vim.fn.executable(c) == 1 then
                name = c
                found = true
            end
        end

        if found then
            ok(("`%s` is installed"):format(name))
        else
            warn(("`%s` is not installed"):format(name))
        end
    end

    check_manager_health()
end

return M
