local init_global = function()
    local global = {
        start = vim.loop.hrtime(),
        plugins_path = vim.fn.stdpath("data") .. "/site/pack/opt",
        plugin_path = function(name)
            return string.format("%s/%s", SageGlobal.plugins_path, name)
        end,
    }

    _G.SageGlobal = global
end

init_global()

