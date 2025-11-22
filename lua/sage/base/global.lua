local init = function()
    if global == nil and _G.SageGlobal == nil then
        global = {
            start = vim.loop.hrtime(),
            plugins_path = vim.fn.stdpath("data") .. "/site/pack/opt",
            plugin_path = function(name)
                return string.format("%s/%s", SageGlobal.plugins_path, name)
            end,
        }

        _G.SageGlobal = global
    end
end

return { init = init }
