return {
    config_path = vim.fn.stdpath("config"),
    data_path = vim.fn.stdpath("data"),
    packages_rpath = "/site/pack/core/opt/",
    unpack_rpath = "/site/pack/managers/start/unpack/", -- ?

    directory = "/lua/plugins", -- starting point ->  aka directory to load packs from
    add_opts = { confirm = false }, ---@type vim.pack.keyset.add
    update_opts = { force = true }, ---@type vim.pack.keyset.update

    strategy = "vimenter", -- delay or idle  -> startegies to decide how to load later stage packs
    check_interval = 100, -- interval time   -> How often the timer checks the idle time of the user
    delay_time_ms = 1000, -- delay time           -> How long the timer waits before loading the later staged packs
    idle_time_ms = 1000, -- idle time        -> How long the user is idle before loading the later staged packs

    dashboard = "smart", -- simple or manual -> when to load the SageUI Dashboard
    lock_windows = true,
    auto_focus = true,

    level = "INFO",
    max_log = 1000,

    install_timeout = 60000,
}
