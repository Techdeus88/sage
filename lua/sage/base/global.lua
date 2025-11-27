local init_global = function()
    local global = {
        config = require("sage.config"),
        start = vim.loop.hrtime(),
        plugins_path = vim.fn.stdpath("data") .. "/site/pack/opt",
        plugin_path = function(name)
            return string.format("%s/%s", Sage.plugins_path, name)
        end,
        sage_debug = vim.env.SAGE_DEBUG == 1,
    }

    _G.Sage = global
end

return { init = init_global }
