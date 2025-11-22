local init = function()
    if global == nil and _G.SageGlobal == nil then
        global = {
            sage_start = vim.loop.hrtime(),
            sage_plugins = vim.fn.stdpath("data") .. "/site/pack/opt",
        }

        _G.SageGlobal = global
    end
end

return { init = init }
