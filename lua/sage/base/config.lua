return {
	dashboard = "smart", -- simple or manual -> when to load the SageUI Dashboard
	directory = "plugins", -- starting point ->  aka directory to load packs from
    force = false,
    confirm = true,
	strategy = "vimenter", -- delay or idle  -> startegies to decide how to load later stage packs
    check_interval = 100, -- interval time   -> How often the timer checks the idle time of the user
	delay_ms = 1000, -- delay time           -> How long the timer waits before loading the later staged packs
    idle_time_ms = 1000, -- idle time        -> How long the user is idle before loading the later staged packs
    lock_windows = true,
    auto_focus = true,
}
