---@class Sage.Config.UserOpts
local M = {} ---@class Sage.Config

M.opts = { ---@class Sage.Config.Opts
    config_path = vim.fn.stdpath("config"),
    data_path = vim.fn.stdpath("data"),
    packages_rpath = "/site/pack/core/opt/",
    sage_rpath = "/site/pack/managers/start/sage/", -- ?
    plugins_rpath = "/lua/packs/", -- starting point ->  aka directory to load packs from

    add_opts = { confirm = false }, ---@type vim.pack.keyset.add
    update_opts = { force = true }, ---@type vim.pack.keyset.update

    strategy = "vimenter", -- delay or idle  -> startegies to decide how to load later stage packs
    check_interval = 100, -- interval time   -> How often the timer checks the idle time of the user
    delay_time_ms = 1000, -- delay time           -> How long the timer waits before loading the later staged packs
    idle_time_ms = 1000, -- idle time        -> How long the user is idle before loading the later staged packs

    --never, manual, errors, first, smart, startup, always
    dashboard = "smart",
    dashboard_auto_close = 2000,
    dashboard_threshold = 500,
    lock_windows = true,
    auto_focus = true,

    level = "INFO",
    max_log = 1000,

    install_timeout = 60000,
}

---@param opts? Sage.Config.UserOpts
function M.setup(opts)
    M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
