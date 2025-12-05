return {
    -- Base icons
    base = {
        plugin = "",
        pack = "",
        keys = "",
        setup = "",
        config = "",
        global = "",
        error = "",
        warn = "",
        hint = "󰌵",
        info = "",
        file = "󰈙",
        other = "",
    },

    -- Status icons
    status = {
        loaded = "●",
        not_loaded = "○",
        failed = "✗",
        installing = "󰇚",
        configuring = "󰒓",
        disabled = "󰪎",
        waiting = "󰔟",
        runtime = " ",
    },

    -- Stage icons
    stage = {
        now = "",
        later = "󰔠",
        lazy = "󰒲",
        disabled = "󰟢",
    },

    -- Trigger type icons
    trigger = {
        event = "",
        filetype = "󰈔", -- File icon for filetypes
        ft = "",
        cmd = " ",
        keys = " ",
        command = " ",
        keymap = "󰌓", -- Keyboard for keymaps
    },

    -- Dependency icons
    depends = {
        depends = "",
        after = "󰁔",
        before = "󰁒",
    },

    -- Timing icons
    timers = {
        install = "󰇚", -- Download/install
        duration = "󱎫", -- Clock/timer
    },

    -- UI nav elements
    navigation = {
        expand = "└─",
        collapse = "├─",
        separator = "•",
        arrow_right = "",
        arrow_down = "",
        setup = "󰒓", -- Config/setup
    },

    -- Progress
    progress = {
        full = "█",
        empty = "░",
    },
}
