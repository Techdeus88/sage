vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    once = true,
    callback = function()
        local start_time = _G.SageGlobal.start
        local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
        local api = require("sage.api")
        api:track_event("vimenter", time_duration)
    end,
})

vim.api.nvim_create_autocmd("UiEnter", {
    pattern = "*",
    once = true,
    callback = function()
        local start_time = _G.SageGlobal.start
        local time_duration = string.format("%.2f", (vim.loop.hrtime() - start_time) / 1e6)
        local api = require("sage.api")
        api:track_event("uienter", time_duration)
    end,
})

vim.api.nvim_create_autocmd("PackChangedPre", {
    group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
    callback = function(event)
        local kind = event.data.kind
        local spec = event.data.spec
        local name = spec.name
        local sage_manager = require("sage.manager")
        local Pack = sage_manager.packs[name]

        if not Pack then
            return -- Pack not in our system, skip
        end

        local n_spec = Pack.specs.normalize

        if kind == "install" then
            local confirmed = vim.fn.confirm("Install plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
            if not confirmed then
                error("Install cancelled for " .. n_spec.name)
            end
            Pack:set_status("installing")
        elseif kind == "delete" then
            local confirmed = vim.fn.confirm("Delete plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
            if not confirmed then
                error("Deletion cancelled for " .. n_spec.name)
            end
            Pack:set_status("deleting")
        elseif kind == "update" then
            local confirmed = vim.fn.confirm("Update plugin " .. n_spec.name .. "?", "&Yes\n&No", 2) == 1
            if not confirmed then
                error("Update cancelled for " .. n_spec.name)
            end
            Pack:set_status("updating")
        end
    end,
})

vim.api.nvim_create_autocmd("PackChanged", {
    group = vim.api.nvim_create_augroup("SageLoader", { clear = true }),
    callback = function(ev)
        local kind = ev.data.kind
        local spec = ev.data.spec
        local pack_path = ev.data.path
        local name = spec.name
        local sage_manager = require("sage.manager")
        local Pack = sage_manager.packs[name]

        if not Pack then
            return -- Pack not in our system, skip
        end

        local n_spec = Pack.specs.normalize
        local Event = require("sage.core.bus")

        if kind == "install" then
            Pack:set_path(pack_path)
            vim.notify(string.format("✓ Installed %s", n_spec.name), vim.log.levels.INFO)
            -- NOTE: Build handling moved to install_activate_batch for consistency
            -- Manual builds should be run separately or as part of pack config

        elseif kind == "update" then
            Pack:set_status("updated")
            vim.notify(string.format("✓ Updated %s", n_spec.name), vim.log.levels.INFO)
            Event.emit("pack:updated", {
                name = name,
                status = "updated",
                pack = Pack,
            })

        elseif kind == "delete" then
            Pack:set_status("deleted")
            vim.notify(string.format("✓ Deleted %s", n_spec.name), vim.log.levels.INFO)
            Event.emit("pack:deleted", {
                name = name,
                status = "deleted",
                pack = Pack,
            })
        end
    end,
})


vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Cleanup all loaders and dashboard before exit",
    callback = function()
        local ok1, loader = pcall(require, "sage.core.loader")
        if ok1 and loader and loader.close_all then
            pcall(function()
                loader.close_all()
            end)
        end

        local ok2, dashboard = pcall(require, "sage.ui.dashboard")
        if ok2 and dashboard and dashboard.close then
            pcall(function()
                dashboard:close()
            end)
        end

        local ok3, Event = pcall(require, "sage.core.bus")
        if ok3 and Event and Event.clear then
            pcall(function()
                Event.clear()
            end)
        end

        vim.notify("Sage cleanup complete before exit", vim.log.levels.INFO)
    end,
})
